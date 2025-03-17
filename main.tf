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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    command     = "aws"
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}

# VPC 모듈
module "vpc" {
  source = "./vpc"
}

# EKS 모듈
module "eks" {
  source             = "./eks"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
}

data "aws_secretsmanager_secret" "jenkins_password" {
  name = "jenkins-admin-password"
}

data "aws_secretsmanager_secret_version" "jenkins_password" {
  secret_id = data.aws_secretsmanager_secret.jenkins_password.id
}

# Jenkins 모듈
module "jenkins-ec2" {
  source                  = "./jenkins-ec2"
  vpc_id                 = module.vpc.vpc_id
  subnet_id              = module.vpc.public_subnet_ids[0]
  cluster_name           = module.eks.cluster_name
  jenkins_admin_password = data.aws_secretsmanager_secret_version.jenkins_password.secret_string
}

# EIP 연결을 위한 null_resource
resource "null_resource" "jenkins_provisioner" {
  depends_on = [aws_eip_association.jenkins_test, local_file.jenkins_test_private_key]

  # 인스턴스 생성 후 백업 스크립트 복사
  provisioner "file" {
    source      = "${path.module}/../jenkins-backup.sh"
    destination = "/home/ubuntu/jenkins-backup.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(local_file.jenkins_test_private_key.filename)
      host        = aws_eip.jenkins_test.public_ip
    }
  }

  # 백업 스크립트 권한 설정
  provisioner "remote-exec" {
    inline = ["chmod +x /home/ubuntu/jenkins-backup.sh"]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(local_file.jenkins_test_private_key.filename)
      host        = aws_eip.jenkins_test.public_ip
    }
  }
} 