# 프로바이더 설정 제거
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC 상태 참조
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket  = "zoochacha-permanent-store"
    key     = "terraform/state/vpc/terraform.tfstate"
    region  = "ap-northeast-2"
  }
}

# 기존 IAM 역할 참조
data "aws_iam_role" "eks_cluster_role" {
  name = "zoochacha-eks-cluster-role"
}

data "aws_iam_role" "eks_node_group_role" {
  name = "zoochacha-eks-node-group-role"
}

# EKS Cluster
resource "aws_eks_cluster" "this" {
  name     = "zoochacha-eks-cluster"
  role_arn = data.aws_iam_role.eks_cluster_role.arn
  bootstrap_self_managed_addons = false

  vpc_config {
    subnet_ids = concat(data.terraform_remote_state.vpc.outputs.private_subnet_ids, data.terraform_remote_state.vpc.outputs.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  tags = {
    Name = "zoochacha-eks-cluster"
  }
}

# IAM 정책 연결
resource "aws_iam_role_policy_attachment" "eks_node_group_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = data.aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = data.aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = data.aws_iam_role.eks_node_group_role.name
}

# 노드 그룹
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "zoochacha-node-group-medium"
  node_role_arn   = data.aws_iam_role.eks_node_group_role.arn
  subnet_ids      = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  instance_types  = ["t3.medium"]
  disk_size      = 20

  scaling_config {
    desired_size = 3
    max_size     = 4
    min_size     = 1
  }

  update_config {
    max_unavailable_percentage = 50
  }

  depends_on = [
    aws_eks_cluster.this,
    aws_iam_role_policy_attachment.eks_node_group_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry
  ]
}