provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}
 
locals {
  cluster_name = "education-eks-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "amex-vpc"
  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

# S3 reead only IAM policy 
# Defining the IAM policy inline for time saving
#  A separate JSON file s3-access-policy.json is inclded for assignment requirement
# Also included ECR Permissions in that json file even though Docker Hub is used for images in case future need of ECR image pulling
data "aws_iam_policy_document" "s3_read_only" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::your-static-assets-bucket-name/*"]
  }
}

resource "aws_iam_policy" "s3_read_policy" {
  name        = "S3ReadOnlyPolicy-${module.eks.cluster_name}"
  description = "Read-only access to S3 bucket for static assets"
  policy      = data.aws_iam_policy_document.s3_read_only.json
}

module "irsa_httpbin" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "HttpbinIRSA-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [aws_iam_policy.s3_read_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:default:httpbin-sa"]
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.5"

  cluster_name    = local.cluster_name
  cluster_version = "1.31"

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"
  }

  eks_managed_node_groups = {
    one = {
      name            = "node-group-1"
      instance_types  = ["t3.small"]
      min_size        = 1
      max_size        = 1
      desired_size    = 1
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

resource "kubernetes_service_account" "httpbin" {
  metadata {
    name      = "httpbin-sa"
    namespace = "default"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.irsa_httpbin.iam_role_arn
    }
  }
}

resource "kubernetes_deployment" "httpbin" {
  metadata {
    name      = "httpbin"
    namespace = "default"
    labels = {
      app = "httpbin"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "httpbin"
      }
    }

    template {
      metadata {
        labels = {
          app = "httpbin"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.httpbin.metadata[0].name

        container {
          name  = "httpbin"
          image = "kennethreitz/httpbin"

          port {
            container_port = 80
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "httpbin" {
  metadata {
    name = "httpbin"
  }

  spec {
    selector = {
      app = "httpbin"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "LoadBalancer"
  }
}