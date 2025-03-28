# 프로바이더 설정
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
  version  = "1.32"

  vpc_config {
    subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids
    security_group_ids = [data.terraform_remote_state.vpc.outputs.eks_sg_id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name = "zoochacha-eks-cluster"
  }
}

# EKS 클러스터 IAM 정책 연결
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = data.aws_iam_role.eks_cluster_role.name
}

# EBS CSI Driver용 IRSA 설정
data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_eks_cluster.this.identity[0].oidc[0].issuer]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
  }
}

# EBS CSI Driver용 역할 참조
data "aws_iam_role" "ebs_csi_role" {
  name = "zoochacha-eks-ebs-csi-role"
}

# VPC CNI 애드온
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"
  addon_version = "v1.19.3-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_node_group.this]
}

# CoreDNS 애드온
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"
  addon_version = "v1.11.4-eksbuild.2"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  service_account_role_arn = data.aws_iam_role.eks_cluster_role.arn

  depends_on = [aws_eks_addon.vpc_cni]
}

# kube-proxy 애드온
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"
  addon_version = "v1.32.0-eksbuild.2"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_addon.coredns]
}

# EBS CSI 드라이버 애드온
resource "aws_eks_addon" "aws_ebs_csi_driver" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "aws-ebs-csi-driver"
  addon_version = "v1.41.0-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  service_account_role_arn = data.aws_iam_role.ebs_csi_role.arn

  depends_on = [
    aws_eks_addon.kube_proxy
  ]
}

# 노드 그룹 IAM 정책 연결
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

# Launch template for EKS nodes
resource "aws_launch_template" "eks_nodes" {
  name = "zoochacha-eks-nodes"
  
  user_data = base64encode(<<-EOF
    #!/bin/bash
    /etc/eks/bootstrap.sh ${aws_eks_cluster.this.name}
    hostnamectl set-hostname zoochacha-workernode-$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "zoochacha-workernode"
    }
  }
}

# EKS 노드 그룹
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "zoochacha-eks-node-group"
  node_role_arn   = data.aws_iam_role.eks_node_group_role.arn
  subnet_ids      = data.terraform_remote_state.vpc.outputs.private_subnet_ids

  scaling_config {
    desired_size = 3
    max_size     = 5
    min_size     = 3
  }

  instance_types = ["t3.medium"]

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry
  ]

  tags = {
    Name = "zoochacha-eks-node-group"
  }
}