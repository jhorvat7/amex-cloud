# Amex Terraform EKS Project

URL: http://a39628b5472884a8888b317a1d04afe0-546242512.us-east-1.elb.amazonaws.com/#/Dynamic_data

This project provisions an Amazon EKS cluster and its resources using Terraform.. It includes modules for VPC, IAM roles, and eks configurations to deploy and manage a simple container for httpbin. Uses an ALB for securing traffic and private vpc subnets with NAT Gateway for security.

- **EKS Cluster**: Provisions an Amazon EKS cluster with managed node groups.
- **VPC**: Creates a VPC with public and private subnets and NAT GATEWAY.
- **IAM Roles**: Configures IAM roles for service accounts (IRSA) and policies for S3 and ECR access.
- **Kubernetes Resources**: Deploys Kubernetes service accounts and workloads like `httpbin`.
- No public IPs are assigned to worker nodes.
- All external traffic is handled by the ALB.
- The application does not have direct access to the internet except via NAT.
- An IAM policy is defined inline for IRSA and also provided as a separate JSON file (`s3-access-policy.json`) as required by the assignment. 