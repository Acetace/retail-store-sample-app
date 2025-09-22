# infrastructure/main.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}

# Create a VPC with public & private subnets, NAT gateways, etc.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "project-bedrock-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
}

# Create an EKS cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.3"

  cluster_name    = "project-bedrock-cluster"
  cluster_version = "1.28"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # IAM Role for the EKS cluster itself
  iam_role_name = "project-bedrock-cluster-role"

  # Enable public endpoint access (CORRECT WAY)
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true
  
  # Optional: Restrict public access to specific CIDRs if desired
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

  # IAM Role for the worker nodes (EC2 instances)
  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 2
      desired_size = 1

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
    }
  }
}

# Create a read-only IAM user for developers
resource "aws_iam_user" "dev_readonly" {
  name = "dev-readonly-user"
}

# Create a policy that allows read-only EKS access
resource "aws_iam_policy" "eks_readonly" {
  name        = "EKS-ReadOnlyAccess"
  description = "Policy for read-only access to EKS cluster"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

# Attach the policy to the user
resource "aws_iam_user_policy_attachment" "dev_readonly_eks" {
  user       = aws_iam_user.dev_readonly.name
  policy_arn = aws_iam_policy.eks_readonly.arn
}

# Generate an access key/secret for the user
resource "aws_iam_access_key" "dev_readonly" {
  user = aws_iam_user.dev_readonly.name
}

# Output the credentials and cluster name (will be shown after 'terraform apply')
output "dev_user_access_key" {
  value = aws_iam_access_key.dev_readonly.id
}

output "dev_user_secret_key" {
  value     = aws_iam_access_key.dev_readonly.secret
  sensitive = true # Marks this output as sensitive in the console
}

output "cluster_name" {
  value = module.eks.cluster_name
}
