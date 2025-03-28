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
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
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

  name             = "basic-infra"
  chart           = var.helm_chart_path
  version         = var.helm_chart_version
  create_namespace = false
  namespace       = "zoochacha"

  # nginx 차트 설정
  set {
    name  = "nginx.enabled"
    value = "true"
  }

  set {
    name  = "nginx.image.repository"
    value = "nginx"
  }

  set {
    name  = "nginx.image.tag"
    value = "1.25.3"
  }

  set {
    name  = "nginx.replicaCount"
    value = "2"
  }

  set {
    name  = "nginx.service.type"
    value = "ClusterIP"
  }

  set {
    name  = "nginx.service.port"
    value = "80"
  }

  set {
    name  = "nginx.ingress.enabled"
    value = "true"
  }

  set {
    name  = "nginx.ingress.className"
    value = "nginx"
  }

  set {
    name  = "nginx.ingress.hosts[0].host"
    value = "zoochacha.online"
  }

  set {
    name  = "nginx.ingress.hosts[0].paths[0].path"
    value = "/"
  }

  set {
    name  = "nginx.ingress.hosts[0].paths[0].pathType"
    value = "Prefix"
  }

  # nginxProxy 설정
  set {
    name  = "nginxProxy.replicaCount"
    value = "2"
  }

  set {
    name  = "nginxProxy.image.repository"
    value = "nginx"
  }

  set {
    name  = "nginxProxy.image.tag"
    value = "1.25.3"
  }

  set {
    name  = "nginxProxy.image.pullPolicy"
    value = "Always"
  }

  # nginxProxy configMap 설정
  set {
    name  = "nginxProxy.configMap.extraConfig"
    value = "{}"
  }

  # hooks 설정
  set {
    name  = "hooks.enabled"
    value = "true"
  }

  set {
    name  = "hooks.preInstall.enabled"
    value = "true"
  }

  set {
    name  = "hooks.postInstall.enabled"
    value = "true"
  }

  # rbac 설정
  set {
    name  = "rbac.serviceAccountName"
    value = "zoochacha-installer"
  }

  # certManager 설정
  set {
    name  = "certManager.enabled"
    value = "false"
  }

  # nginx 서버 블록 설정
  set {
    name  = "nginx.serverBlock"
    value = <<-EOT
      server {
        listen 0.0.0.0:8080;
        
        location / {
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          
          proxy_pass http://map-server.zoochacha.svc.cluster.local:8002;
        }
        
        location /admin {
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          
          proxy_pass http://admin-server.zoochacha.svc.cluster.local:8001;
        }
      }
    EOT
  }

  # 글로벌 설정
  set {
    name  = "global.environment"
    value = "production"
  }

  set {
    name  = "global.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "global.domain"
    value = "zoochacha.com"
  }

  set {
    name  = "global.namespaces.nginx"
    value = "zoochacha"
  }

  # 리소스 설정
  set {
    name  = "resources.nginx.requests.cpu"
    value = "200m"
  }

  set {
    name  = "resources.nginx.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "resources.nginx.limits.cpu"
    value = "500m"
  }

  set {
    name  = "resources.nginx.limits.memory"
    value = "512Mi"
  }
}

# Ingress Controller 설치
resource "helm_release" "ingress_nginx" {
  count = local.eks_ready ? 1 : 0

  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.9.1"
  namespace        = "ingress-nginx"
  create_namespace = true

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-cross-zone-load-balancing-enabled"
    value = "true"
  }

  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }

  set {
    name  = "controller.autoscaling.enabled"
    value = "true"
  }

  set {
    name  = "controller.autoscaling.minReplicas"
    value = "2"
  }

  set {
    name  = "controller.autoscaling.maxReplicas"
    value = "5"
  }
}

# Karpenter Helm 차트 설치
resource "helm_release" "karpenter" {
  count = local.eks_ready ? 1 : 0

  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "v0.35.0"
  namespace        = "karpenter"
  create_namespace = true

  set {
    name  = "settings.aws.defaultInstanceProfile"
    value = "KarpenterNodeInstanceProfile-zoochacha"
  }

  set {
    name  = "settings.aws.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "settings.aws.clusterEndpoint"
    value = data.aws_eks_cluster.this.endpoint
  }

  set {
    name  = "settings.aws.interruptionQueueName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/KarpenterControllerRole-${var.cluster_name}"
  }

  set {
    name  = "controller.env[0].name"
    value = "CLUSTER_NAME"
  }

  set {
    name  = "controller.env[0].value"
    value = var.cluster_name
  }

  set {
    name  = "controller.env[1].name"
    value = "CLUSTER_ENDPOINT"
  }

  set {
    name  = "controller.env[1].value"
    value = data.aws_eks_cluster.this.endpoint
  }
}

# Karpenter Provisioner 설정
resource "kubectl_manifest" "karpenter_provisioner" {
  count = local.eks_ready ? 1 : 0

  depends_on = [helm_release.karpenter]

  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1alpha5
    kind: Provisioner
    metadata:
      name: default
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["t3.medium", "t3.large", "c5.large", "c5.xlarge"]
      limits:
        resources:
          cpu: 100
          memory: 100Gi
      ttlSecondsAfterEmpty: 30
      ttlSecondsUntilExpired: 604800
      providerRef:
        name: default
  YAML
}

# Karpenter AWS Node Template 설정
resource "kubectl_manifest" "karpenter_aws_node_template" {
  count = local.eks_ready ? 1 : 0

  depends_on = [helm_release.karpenter]

  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1alpha1
    kind: AWSNodeTemplate
    metadata:
      name: default
    spec:
      amiFamily: AL2
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 50Gi
            volumeType: gp3
      instanceProfile: KarpenterNodeInstanceProfile-${var.cluster_name}
      securityGroupSelector:
        kubernetes.io/cluster/${var.cluster_name}: owned
      subnetSelector:
        Type: private
      tags:
        Environment: production
        KarpenerProvisionerName: default
      userData: |
        #!/bin/bash
        set -ex
        /etc/eks/bootstrap.sh ${var.cluster_name} \
          --container-runtime containerd \
          --kubelet-extra-args "--node-labels=karpenter.sh/provisioner-name=default,node.kubernetes.io/lifecycle=spot,eks.amazonaws.com/nodegroup=karpenter"
  YAML
}

# AWS 계정 ID 가져오기
data "aws_caller_identity" "current" {} 