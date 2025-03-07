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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# EKS 클러스터 정보 참조
data "terraform_remote_state" "eks" {
  backend = "local"

  config = {
    path = "../eks/terraform.tfstate"
  }
}

# Kubernetes 프로바이더 설정
provider "kubernetes" {
  config_path = "~/.kube/config"
}

# Helm 프로바이더 설정
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# AWS Secrets Manager에 Jenkins 관리자 비밀번호 참조
data "aws_secretsmanager_secret" "jenkins_admin_password" {
  name = var.secret_name
}

# 안전한 랜덤 패스워드 생성
resource "random_password" "jenkins_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Jenkins 네임스페이스 생성
resource "kubernetes_namespace" "jenkins" {
  metadata {
    name = var.namespace
  }
}

# Jenkins Helm 차트 배포
resource "helm_release" "jenkins" {
  name       = "jenkins"
  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  version    = var.jenkins_version
  namespace  = kubernetes_namespace.jenkins.metadata[0].name

  values = [
    file("${path.module}/values.yaml")
  ]

  set {
    name  = "controller.admin.username"
    value = "zoochacha"
  }

  set {
    name  = "controller.admin.password"
    value = random_password.jenkins_password.result
  }

  set {
    name  = "controller.containerEnv[0].name"
    value = "JAVA_OPTS"
  }

  set {
    name  = "controller.containerEnv[0].value"
    value = "-Xmx1024m -Xms512m -XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:MaxGCPauseMillis=100 -XX:+UseStringDeduplication"
  }

  set {
    name  = "controller.serviceType"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.image.tag"
    value = var.jenkins_image_tag
  }

  depends_on = [
    kubernetes_namespace.jenkins,
  ]
}

# AWS Secrets Manager에서 시크릿 가져오기
data "aws_secretsmanager_secret" "github_token" {
  name = "github-token"
}

data "aws_secretsmanager_secret_version" "github_token" {
  secret_id = data.aws_secretsmanager_secret.github_token.id
}

data "aws_secretsmanager_secret" "webhook_secret" {
  name = "github-webhook-secret"
}

data "aws_secretsmanager_secret_version" "webhook_secret" {
  secret_id = data.aws_secretsmanager_secret.webhook_secret.id
}

data "aws_secretsmanager_secret" "discord_webhook" {
  name = "jenkins-discord-webhook"
}

data "aws_secretsmanager_secret_version" "discord_webhook" {
  secret_id = data.aws_secretsmanager_secret.discord_webhook.id
} 