terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# EKS 클러스터 정보 가져오기
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

# EKS 클러스터 상태 확인을 위한 locals
locals {
  eks_ready = data.aws_eks_cluster.this.status == "ACTIVE"
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.this.name]
    command     = "aws"
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.this.name]
      command     = "aws"
    }
  }
}

# Helm 차트 설치
resource "helm_release" "basic_infra" {
  count = local.eks_ready ? 1 : 0

  name       = "basic-infra"
  chart      = var.helm_chart_path
  version    = var.helm_chart_version
  create_namespace = false
} 