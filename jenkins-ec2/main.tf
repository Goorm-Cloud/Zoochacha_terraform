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

# VPC 정보 가져오기 (기존 VPC 사용)
data "terraform_remote_state" "vpc" {
  backend = "local"

  config = {
    path = "../vpc/terraform.tfstate"
  }
}

# 보안 그룹 생성
resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-sg"
  description = "Security group for Jenkins server"
  vpc_id      = data.terraform_remote_state.vpc.outputs.eks-vpc-id

  # SSH 접속 허용
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Jenkins 웹 인터페이스 접속 허용
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # JNLP 에이전트 접속 허용
  ingress {
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 모든 아웃바운드 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jenkins-sg"
  }
}

# 키 페어 생성
resource "aws_key_pair" "jenkins_key" {
  key_name   = "jenkins-key"
  public_key = file("~/.ssh/id_rsa.pub")  # 로컬 머신의 SSH 공개 키 파일 경로
}

# EC2 인스턴스 생성
resource "aws_instance" "jenkins" {
  ami           = "ami-0c9c942bd7bf113a2"  # Ubuntu 22.04 AMI
  instance_type = "t3.medium"
  subnet_id     = "subnet-0829e5a585337a210"
  key_name      = aws_key_pair.jenkins_key.key_name

  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              # 시스템 업데이트
              apt-get update
              apt-get upgrade -y

              # Java 설치
              apt-get install -y openjdk-11-jdk

              # Jenkins 저장소 추가 및 설치
              curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
              echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
              apt-get update
              apt-get install -y jenkins

              # Jenkins 서비스 시작
              systemctl enable jenkins
              systemctl start jenkins

              # Docker 설치
              apt-get install -y apt-transport-https ca-certificates curl software-properties-common
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
              add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
              apt-get update
              apt-get install -y docker-ce docker-ce-cli containerd.io

              # Docker 서비스 시작 및 권한 설정
              systemctl enable docker
              systemctl start docker
              usermod -aG docker ubuntu
              usermod -aG docker jenkins

              # kubectl 설치
              curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
              chmod +x kubectl
              mv kubectl /usr/local/bin/

              # AWS CLI 설치
              apt-get install -y unzip
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              ./aws/install

              # Jenkins 서비스 재시작
              systemctl restart jenkins
              EOF

  tags = {
    Name = "jenkins-server"
  }
}

# Elastic IP 할당
resource "aws_eip" "jenkins" {
  instance = aws_instance.jenkins.id
  domain   = "vpc"
  
  tags = {
    Name = "jenkins-eip"
  }
}

# 출력 정의
output "jenkins_public_ip" {
  value = aws_eip.jenkins.public_ip
}

output "jenkins_url" {
  value = "http://${aws_eip.jenkins.public_ip}:8080"
} 