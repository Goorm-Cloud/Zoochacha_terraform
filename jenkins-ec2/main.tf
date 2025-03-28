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
  backend = "s3"
  config = {
    bucket = "zoochacha-permanent-store"
    key    = "terraform/state/vpc/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# AWS 리전과 계정 ID 데이터 소스
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  prefix = data.terraform_remote_state.vpc.outputs.prefix
}

# 보안 그룹 생성
resource "aws_security_group" "jenkins_sg" {
  name        = "${local.prefix}-jenkins-sg"
  description = "Security group for Jenkins server"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  # SSH 접속 허용 (특정 IP에서만 접근 가능하도록 제한)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # TODO: 실제 운영 환경에서는 특정 IP로 제한 필요
    description = "Allow SSH access"
  }

  # Jenkins 웹 인터페이스 접속 허용 (8080 포트)
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # TODO: 실제 운영 환경에서는 특정 IP로 제한 필요
    description = "Allow Jenkins web access"
  }

  # JNLP 에이전트 접속 허용 (50000 포트)
  ingress {
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # TODO: 실제 운영 환경에서는 특정 IP로 제한 필요
    description = "Allow Jenkins JNLP access"
  }

  # 모든 아웃바운드 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${local.prefix}-jenkins-sg"
    Environment = "prod"
  }
}

# Jenkins 설정 파일들을 EC2로 복사
resource "aws_s3_bucket" "jenkins_config" {
  bucket = "${local.prefix}-jenkins-config"
  
  tags = {
    Name = "${local.prefix}-jenkins-config"
  }
}

# 백업 스크립트를 영구 저장소에 업로드
resource "aws_s3_object" "jenkins_backup_script" {
  bucket = "zoochacha-permanent-store"
  key    = "jenkins/scripts/jenkins-backup.sh"
  source = "jenkins-backup.sh"
}

resource "aws_s3_object" "jenkins_yaml" {
  bucket = aws_s3_bucket.jenkins_config.id
  key    = "jenkins.yaml"
  source = "jenkins.yaml"
}

resource "aws_s3_object" "plugins_txt" {
  bucket = aws_s3_bucket.jenkins_config.id
  key    = "plugins.txt"
  source = "plugins.txt"
}

# IAM 역할 및 인스턴스 프로파일 생성
resource "aws_iam_role" "jenkins_role" {
  name = "${local.prefix}-jenkins-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = "prod"
  }
}

resource "aws_iam_role_policy" "jenkins_s3_policy" {
  name = "${local.prefix}-jenkins-s3-policy"
  role = aws_iam_role.jenkins_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::zoochacha-permanent-store",
          "arn:aws:s3:::zoochacha-permanent-store/jenkins/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "${local.prefix}-jenkins-profile"
  role = aws_iam_role.jenkins_role.name
}

# EC2 인스턴스 생성
resource "aws_instance" "jenkins" {
  ami                  = var.use_recovery_ami ? var.recovery_ami_id : var.ami_id
  instance_type        = var.instance_type
  subnet_id            = data.terraform_remote_state.vpc.outputs.pub_sub1_id
  key_name             = var.key_name
  iam_instance_profile = aws_iam_instance_profile.jenkins_profile.name

  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]

  root_block_device {
    volume_size = 30  # TODO: 운영 환경에 맞게 볼륨 크기 조정 필요
    volume_type = "gp3"
    tags = {
      Name        = "${local.prefix}-jenkins-root-volume"
      Environment = "prod"
    }
  }

  user_data = <<-EOF
              #!/bin/bash
              # 시스템 업데이트 및 기본 설치
              apt-get update
              apt-get upgrade -y
              apt-get install -y openjdk-17-jdk awscli

              # Jenkins 저장소 추가 및 설치
              curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
              echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
              apt-get update
              apt-get install -y jenkins

              # Jenkins 서비스 시작
              systemctl start jenkins
              systemctl enable jenkins

              # 백업 스크립트 생성
              cat > /home/ubuntu/jenkins-backup.sh << 'EOSCRIPT'
              #!/bin/bash

              # 변수 설정
              BUCKET_NAME="zoochacha-permanent-store"
              TIMESTAMP=$(date +%Y%m%d_%H%M%S)
              BACKUP_DIR="/tmp/jenkins_backup_$TIMESTAMP"
              CONFIG_DIR="$BACKUP_DIR/config"
              JENKINS_HOME="/var/lib/jenkins"
              JENKINS_CLI="/home/ubuntu/jenkins-cli.jar"
              PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
              JENKINS_URL="http://$PRIVATE_IP:8080"
              JENKINS_USER="zoochacha"
              JENKINS_PASSWORD="1111"
              SOURCE_JENKINS_YAML="/home/ubuntu/jenkins.yaml"
              MAX_RETRIES=3
              RETRY_DELAY=300  # 5분 대기

              # 백업 함수 정의
              perform_backup() {
                  local attempt=$1
                  echo "Backup attempt $attempt of $MAX_RETRIES"

                  # 백업 디렉토리 생성
                  mkdir -p "$CONFIG_DIR"

                  # Jenkins 서비스 상태 확인
                  if ! systemctl is-active --quiet jenkins; then
                      echo "Jenkins is not running. Please start Jenkins first."
                      return 1
                  fi

                  echo "=== Starting Jenkins Backup Process ==="

                  # 중요 파일 존재 여부 확인
                  echo "Checking important files..."
                  for f in config.xml credentials.xml secrets/master.key secrets/hudson.util.Secret identity.key.enc secret.key; do
                      if [ ! -f "$JENKINS_HOME/$f" ]; then
                          echo "Warning: $f not found!"
                      fi
                  done

                  # 1. Jenkins 전체 백업 (workspace와 builds 포함)
                  echo "Backing up Jenkins home directory..."
                  cd "$JENKINS_HOME"
                  sudo tar -czf "$BACKUP_DIR/jenkins_home.tar.gz" \
                      --exclude='*.log' \
                      --exclude='*.tmp' \
                      --exclude='war' \
                      $(find . -name "config.xml") \
                      $(find . -name "credentials.xml") \
                      $(find . -name "*.xml") \
                      jobs/reservation_service \
                      jobs/zoochacha-admin-service-pipeline \
                      jobs/zoochacha-reservation-detail-service-pipeline \
                      workspace \
                      plugins \
                      secrets \
                      users \
                      .ssh \
                      .aws \
                      .groovy \
                      caches \
                      fingerprints \
                      logs \
                      updates \
                      userContent

                  # 2. 플러그인 목록 추출
                  echo "Extracting plugin list..."
                  sudo ls -1 "$JENKINS_HOME/plugins" | grep ".jpi$" | sed 's/\.jpi$//' > "$CONFIG_DIR/plugins.txt" || \
                      echo "Failed to extract plugin list"

                  # 3. Configuration as Code 설정 백업
                  echo "Backing up CasC configuration..."
                  if [ -f "$JENKINS_HOME/casc_configs/jenkins.yaml" ]; then
                      sudo cp "$JENKINS_HOME/casc_configs/jenkins.yaml" "$CONFIG_DIR/jenkins.yaml"
                  fi

                  # 소스 코드의 jenkins.yaml 백업
                  if [ -f "$SOURCE_JENKINS_YAML" ]; then
                      sudo cp "$SOURCE_JENKINS_YAML" "$CONFIG_DIR/jenkins.yaml.source"
                  fi

                  # 4. 중요 설정 파일 개별 백업
                  echo "Backing up critical configuration files..."
                  for f in config.xml credentials.xml hudson.model.UpdateCenter.xml jenkins.telemetry.Correlator.xml nodeMonitors.xml jenkins.model.JenkinsLocationConfiguration.xml hudson.plugins.git.GitTool.xml hudson.plugins.emailext.ExtendedEmailPublisher.xml; do
                      if [ -f "$JENKINS_HOME/$f" ]; then
                          sudo cp "$JENKINS_HOME/$f" "$CONFIG_DIR/"
                      fi
                  done

                  # 5. Job 설정 파일 백업
                  echo "Backing up job configurations..."
                  for job in "reservation_service" "zoochacha-admin-service-pipeline" "zoochacha-reservation-detail-service-pipeline"; do
                      if [ -d "$JENKINS_HOME/jobs/$job" ]; then
                          sudo mkdir -p "$CONFIG_DIR/jobs/$job"
                          sudo cp "$JENKINS_HOME/jobs/$job/config.xml" "$CONFIG_DIR/jobs/$job/" 2>/dev/null || true
                          # lastSuccessfulBuild와 lastStableBuild 정보 백업
                          if [ -d "$JENKINS_HOME/jobs/$job/builds" ]; then
                              sudo mkdir -p "$CONFIG_DIR/jobs/$job/builds"
                              sudo cp -r "$JENKINS_HOME/jobs/$job/builds/lastSuccessfulBuild" "$CONFIG_DIR/jobs/$job/builds/" 2>/dev/null || true
                              sudo cp -r "$JENKINS_HOME/jobs/$job/builds/lastStableBuild" "$CONFIG_DIR/jobs/$job/builds/" 2>/dev/null || true
                          fi
                      fi
                  done

                  # 6. 보안 관련 파일 백업
                  echo "Backing up security-related files..."
                  sudo mkdir -p "$CONFIG_DIR/secrets"
                  if [ -d "$JENKINS_HOME/secrets" ]; then
                      sudo cp -r "$JENKINS_HOME/secrets"/* "$CONFIG_DIR/secrets/" 2>/dev/null || true
                  fi

                  # 7. 사용자 설정 백업
                  echo "Backing up user configurations..."
                  if [ -d "$JENKINS_HOME/users" ]; then
                      sudo cp -r "$JENKINS_HOME/users" "$CONFIG_DIR/"
                  fi

                  # 8. 설정 파일들을 하나의 압축 파일로 만들기
                  echo "Creating backup archive..."
                  cd "$BACKUP_DIR"
                  sudo tar -czf "jenkins_backup_$TIMESTAMP.tar.gz" ./*

                  # S3로 업로드
                  echo "Uploading to S3..."
                  if sudo aws s3 cp "$BACKUP_DIR/jenkins_backup_$TIMESTAMP.tar.gz" \
                      "s3://$BUCKET_NAME/jenkins/backup_config/jenkins_backup_$TIMESTAMP.tar.gz"; then
                       
                      # 최신 백업 링크 업데이트
                      sudo aws s3 cp "$BACKUP_DIR/jenkins_backup_$TIMESTAMP.tar.gz" \
                          "s3://$BUCKET_NAME/jenkins/backup_config/latest.tar.gz"
                       
                      # 임시 디렉토리 정리
                      sudo rm -rf "$BACKUP_DIR"
                       
                      echo "=== Backup completed successfully! ==="
                      echo "Timestamp: $TIMESTAMP"
                      echo "Backup location:"
                      echo "- Backup: s3://$BUCKET_NAME/jenkins/backup_config/jenkins_backup_$TIMESTAMP.tar.gz"
                       
                      return 0
                  else
                      echo "Backup failed on attempt $attempt"
                      return 1
                  fi
              }

              # 백업 실행 (재시도 로직 포함)
              for ((i=1; i<=$MAX_RETRIES; i++)); do
                  if perform_backup $i; then
                      exit 0
                  else
                      if [ $i -lt $MAX_RETRIES ]; then
                          echo "Waiting $RETRY_DELAY seconds before next attempt..."
                          sleep $RETRY_DELAY
                      else
                          echo "All backup attempts failed"
                          exit 1
                      fi
                  fi
              done
              EOSCRIPT

              chmod +x /home/ubuntu/jenkins-backup.sh
              chown ubuntu:ubuntu /home/ubuntu/jenkins-backup.sh

              # 백업 스크립트를 /usr/local/bin으로 이동 및 권한 설정
              mv /home/ubuntu/jenkins-backup.sh /usr/local/bin/
              chmod +x /usr/local/bin/jenkins-backup.sh

              # Jenkins 로그 디렉토리 생성 및 권한 설정
              mkdir -p /var/log/jenkins
              chown jenkins:jenkins /var/log/jenkins

              # Cron 작업 설정 (평일 저녁 10시에 백업 실행)
              echo "0 22 * * 1-5 root /usr/local/bin/jenkins-backup.sh" | tee /etc/cron.d/jenkins-backup

              # 설정 파일 다운로드
              mkdir -p /var/lib/jenkins/casc_configs
              aws s3 cp s3://${aws_s3_bucket.jenkins_config.id}/jenkins.yaml /var/lib/jenkins/casc_configs/jenkins.yaml
              aws s3 cp s3://${aws_s3_bucket.jenkins_config.id}/plugins.txt /var/lib/jenkins/plugins.txt

              # 환경 변수 설정
              echo "JENKINS_ADMIN_PASSWORD=${var.jenkins_admin_password}" >> /etc/environment
              echo "JENKINS_URL=http://$PRIVATE_IP:8080" >> /etc/environment
              echo "CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs/jenkins.yaml" >> /etc/environment

              # 플러그인 설치
              JENKINS_HOME=/var/lib/jenkins
              JENKINS_WAR=/usr/share/java/jenkins.war
              JENKINS_UC=https://updates.jenkins.io
              
              while read plugin; do
                java -jar $JENKINS_WAR --plugin-download-directory=$JENKINS_HOME/plugins $plugin
              done < $JENKINS_HOME/plugins.txt

              # 권한 설정
              chown -R jenkins:jenkins /var/lib/jenkins

              # Jenkins 재시작
              systemctl restart jenkins

              # Terraform destroy 시 실행될 백업 스크립트 생성
              cat > /home/ubuntu/jenkins-destroy-backup.sh << 'EOSCRIPT'
              #!/bin/bash
              
              # Discord Webhook URL을 Secrets Manager에서 가져오기
              DISCORD_WEBHOOK_URL=$(aws secretsmanager get-secret-value --secret-id jenkins-discord-webhook --query SecretString --output text)
              
              # 현재 시간 가져오기
              CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
              
              # 백업 실행
              /home/ubuntu/jenkins-backup.sh
              BACKUP_RESULT=$?

              if [ $BACKUP_RESULT -eq 0 ]; then
                  # 백업 성공 시 Discord로 성공 메시지 전송
                  curl -H "Content-Type: application/json" -X POST -d '{
                      "embeds": [{
                          "title": "Jenkins 백업 성공",
                          "description": "Jenkins 서버의 백업이 성공적으로 완료되었습니다.",
                          "color": 3066993,
                          "fields": [
                              {
                                  "name": "상태",
                                  "value": "성공",
                                  "inline": true
                              },
                              {
                                  "name": "시간",
                                  "value": "'"$CURRENT_TIME"'",
                                  "inline": true
                              }
                          ],
                          "footer": {
                              "text": "Jenkins Backup System"
                          }
                      }]
                  }' $DISCORD_WEBHOOK_URL
                  exit 0
              else
                  # 백업 실패 시 Discord로 실패 메시지 전송
                  curl -H "Content-Type: application/json" -X POST -d '{
                      "embeds": [{
                          "title": "Jenkins 백업 실패",
                          "description": "Jenkins 서버의 백업이 실패하였습니다. 수동 확인이 필요합니다.",
                          "color": 15158332,
                          "fields": [
                              {
                                  "name": "상태",
                                  "value": "실패",
                                  "inline": true
                              },
                              {
                                  "name": "시간",
                                  "value": "'"$CURRENT_TIME"'",
                                  "inline": true
                              }
                          ],
                          "footer": {
                              "text": "Jenkins Backup System"
                          }
                      }]
                  }' $DISCORD_WEBHOOK_URL
                  exit 1
              fi
              EOSCRIPT

              chmod +x /home/ubuntu/jenkins-destroy-backup.sh
              chown ubuntu:ubuntu /home/ubuntu/jenkins-destroy-backup.sh
              EOF

  tags = {
    Name        = "${local.prefix}-jenkins-server"
    Environment = "prod"
  }
}

# Elastic IP 할당
resource "aws_eip" "jenkins" {
  domain = "vpc"

  tags = {
    Name        = "${local.prefix}-jenkins-eip"
    Environment = "prod"
  }
}

# EIP 연결
resource "aws_eip_association" "jenkins" {
  instance_id   = aws_instance.jenkins.id
  allocation_id = aws_eip.jenkins.id
}

# 출력 정의
output "jenkins_public_ip" {
  value       = aws_eip.jenkins.public_ip
  description = "Jenkins server public IP"
}

output "jenkins_url" {
  value       = "http://${aws_eip.jenkins.public_ip}:8080"
  description = "Jenkins server URL"
} 