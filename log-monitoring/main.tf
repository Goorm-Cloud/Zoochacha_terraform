terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
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

# 현재 모니터링 EC2의 AMI ID
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "image-id"
    values = ["ami-0035b9cafde7aeb38"]
  }

  owners = ["self"]
}

# VPC 데이터 소스
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# 서브넷 데이터 소스
data "aws_subnet" "selected" {
  id = var.subnet_id
}

# Elasticsearch 보안 그룹
resource "aws_security_group" "elasticsearch" {
  name        = "${var.name_prefix}-elasticsearch-sg"
  description = "Security group for Elasticsearch"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 9300
    to_port     = 9300
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-elasticsearch-sg"
    }
  )
}

# Kibana 보안 그룹
resource "aws_security_group" "kibana" {
  name        = "${var.name_prefix}-kibana-sg"
  description = "Security group for Kibana"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5601
    to_port     = 5601
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-kibana-sg"
    }
  )
}

# Grafana 보안 그룹
resource "aws_security_group" "grafana" {
  name        = "${var.name_prefix}-grafana-sg"
  description = "Security group for Grafana"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-grafana-sg"
    }
  )
}

# SSH 접근을 위한 보안 그룹
resource "aws_security_group" "ssh" {
  name        = "${var.name_prefix}-ssh-sg"
  description = "Security group for SSH access"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr_blocks
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-ssh-sg"
    }
  )
}

# IAM 역할 데이터 소스
data "aws_iam_role" "efk_role" {
  name = "${var.name_prefix}-role"
}

# IAM 인스턴스 프로파일 데이터 소스
data "aws_iam_instance_profile" "efk_profile" {
  name = var.instance_profile_name
}

# EC2 인스턴스
resource "aws_instance" "efk" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  vpc_security_group_ids = [
    aws_security_group.elasticsearch.id,
    aws_security_group.kibana.id,
    aws_security_group.grafana.id,
    aws_security_group.ssh.id
  ]

  iam_instance_profile = data.aws_iam_instance_profile.efk_profile.name

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y apt-transport-https ca-certificates wget gnupg2 lsb-release

              # Elasticsearch 설치
              wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
              echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-8.x.list
              apt-get update
              apt-get install -y elasticsearch

              # Elasticsearch 설정
              cat > /etc/elasticsearch/elasticsearch.yml << 'EOL'
              cluster.name: efk-cluster
              node.name: node-1
              network.host: 0.0.0.0
              discovery.type: single-node
              xpack.security.enabled: true
              xpack.security.http.ssl.enabled: false
              EOL

              # Elasticsearch 비밀번호 설정
              ELASTIC_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${var.secret_manager_arn} --query SecretString --output text)
              echo "ELASTIC_PASSWORD=$ELASTIC_PASSWORD" | tee -a /etc/environment

              # Elasticsearch 시작
              systemctl daemon-reload
              systemctl enable elasticsearch
              systemctl start elasticsearch

              # Elasticsearch가 완전히 시작될 때까지 대기
              while ! curl -s http://localhost:9200 > /dev/null; do
                sleep 10
              done

              # Kibana 설치
              apt-get install -y kibana

              # Kibana 설정
              cat > /etc/kibana/kibana.yml << EOL
              server.host: 0.0.0.0
              elasticsearch.hosts: ["http://localhost:9200"]
              elasticsearch.username: kibana_system
              elasticsearch.password: $ELASTIC_PASSWORD
              EOL

              # Kibana 시작
              systemctl enable kibana
              systemctl start kibana

              # FluentD 설치
              curl -L https://toolbelt.treasuredata.com/sh/install-ubuntu-focal-td-agent4.sh | sh

              # FluentD elasticsearch 플러그인 설치
              td-agent-gem install fluent-plugin-elasticsearch

              # FluentD 설정
              cat > /etc/td-agent/td-agent.conf << EOL
              <source>
                @type forward
                port 24224
                bind 0.0.0.0
              </source>

              <match **>
                @type elasticsearch
                host localhost
                port 9200
                user elastic
                password $ELASTIC_PASSWORD
                logstash_format true
                logstash_prefix fluentd
                include_timestamp true
                flush_interval 5s
              </match>
              EOL

              # FluentD 시작
              systemctl enable td-agent
              systemctl start td-agent
              EOF

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-efk"
    }
  )
}

# FluentD DaemonSet을 위한 네임스페이스 생성
resource "kubernetes_namespace" "logging" {
  metadata {
    name = "logging"
  }
}

# FluentD ConfigMap
resource "kubernetes_config_map" "fluentd" {
  metadata {
    name      = "fluentd-config"
    namespace = kubernetes_namespace.logging.metadata[0].name
  }

  data = {
    "fluent.conf" = <<-EOT
      <source>
        @type tail
        path /var/log/containers/*.log
        pos_file /var/log/fluentd-containers.log.pos
        tag kubernetes.*
        read_from_head true
        <parse>
          @type json
          time_key time
          time_type string
          time_format %Y-%m-%dT%H:%M:%S.%NZ
          keep_time_key true
        </parse>
      </source>

      <filter kubernetes.**>
        @type kubernetes_metadata
        @id filter_kube_metadata
        kubernetes_url "#{ENV['KUBERNETES_URL']}"
        bearer_token_file /var/run/secrets/kubernetes.io/serviceaccount/token
        ca_file /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      </filter>

      <match kubernetes.**>
        @type elasticsearch
        host ${aws_instance.efk.private_ip}
        port 9200
        user elastic
        password ${var.elastic_password}
        logstash_format true
        logstash_prefix fluentd
        include_timestamp true
        flush_interval 5s
      </match>
    EOT
  }
}

# FluentD ServiceAccount
resource "kubernetes_service_account" "fluentd" {
  metadata {
    name      = "fluentd"
    namespace = kubernetes_namespace.logging.metadata[0].name
  }
}

# FluentD ClusterRole
resource "kubernetes_cluster_role" "fluentd" {
  metadata {
    name = "fluentd"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "namespaces"]
    verbs      = ["get", "list", "watch"]
  }
}

# FluentD ClusterRoleBinding
resource "kubernetes_cluster_role_binding" "fluentd" {
  metadata {
    name = "fluentd"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.fluentd.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.fluentd.metadata[0].name
    namespace = kubernetes_namespace.logging.metadata[0].name
  }
}

# FluentD DaemonSet
resource "kubernetes_daemon_set" "fluentd" {
  metadata {
    name      = "fluentd"
    namespace = kubernetes_namespace.logging.metadata[0].name
    labels = {
      app = "fluentd"
    }
  }

  spec {
    selector {
      match_labels = {
        app = "fluentd"
      }
    }

    template {
      metadata {
        labels = {
          app = "fluentd"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.fluentd.metadata[0].name
        containers {
          name  = "fluentd"
          image = "fluent/fluentd-kubernetes-daemonset:v1.16-debian-elasticsearch7-1"
          env {
            name  = "KUBERNETES_URL"
            value = "https://kubernetes.default.svc"
          }
          env {
            name  = "ELASTIC_PASSWORD"
            value = var.elastic_password
          }
          volume_mounts {
            name       = "varlog"
            mount_path = "/var/log"
          }
          volume_mounts {
            name       = "varlibdockercontainers"
            mount_path = "/var/lib/docker/containers"
            read_only  = true
          }
          volume_mounts {
            name       = "config"
            mount_path = "/fluentd/etc"
          }
        }
        volumes {
          name = "varlog"
          host_path {
            path = "/var/log"
            type = "DirectoryOrCreate"
          }
        }
        volumes {
          name = "varlibdockercontainers"
          host_path {
            path = "/var/lib/docker/containers"
            type = "DirectoryOrCreate"
          }
        }
        volumes {
          name = "config"
          config_map {
            name = kubernetes_config_map.fluentd.metadata[0].name
            items {
              key  = "fluent.conf"
              path = "fluent.conf"
            }
          }
        }
      }
    }
  }
} 