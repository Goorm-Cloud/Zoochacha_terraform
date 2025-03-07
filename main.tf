terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

# VPC 모듈
module "vpc" {
  source = "./vpc"
}

# EKS 모듈
module "eks" {
  source = "./eks"
  
  depends_on = [
    module.vpc
  ]
}

# Jenkins 모듈
module "jenkins" {
  source = "./jenkins"

  depends_on = [
    module.eks
  ]
} 