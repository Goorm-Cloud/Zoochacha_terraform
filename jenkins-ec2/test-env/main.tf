terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }

  # 테스트 환경 상태 파일 분리
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC 정보 가져오기 (기존 VPC 사용)
data "terraform_remote_state" "vpc" {
  backend = "local"

  config = {
    path = "${path.module}/../../vpc/terraform.tfstate"
  }
}

locals {
  prefix = "${data.terraform_remote_state.vpc.outputs.prefix}-test"
}

# 보안 그룹 생성
resource "aws_security_group" "jenkins_test_sg" {
  name        = "${local.prefix}-jenkins-sg"
  description = "Security group for Jenkins test server"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  # SSH 접속 허용
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH access"
  }

  # Jenkins 웹 인터페이스 접속 허용 (테스트 환경은 8081 포트 사용)
  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow Jenkins web access"
  }

  # JNLP 에이전트 접속 허용 (테스트 환경은 50001 포트 사용)
  ingress {
    from_port   = 50001
    to_port     = 50001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
    Environment = "test"
  }
}

# IAM 역할 및 인스턴스 프로파일 생성
resource "aws_iam_role" "jenkins_test_role" {
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
    Environment = "test"
  }
}

resource "aws_iam_role_policy" "jenkins_test_s3_policy" {
  name = "${local.prefix}-jenkins-s3-policy"
  role = aws_iam_role.jenkins_test_role.id

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

resource "aws_iam_instance_profile" "jenkins_test_profile" {
  name = "${local.prefix}-jenkins-profile"
  role = aws_iam_role.jenkins_test_role.name
}

# 키 페어 생성
resource "tls_private_key" "jenkins_test_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# AWS 키 페어 생성
resource "aws_key_pair" "jenkins_test_key" {
  key_name   = "${local.prefix}-key"
  public_key = tls_private_key.jenkins_test_key.public_key_openssh

  tags = {
    Name        = "${local.prefix}-key"
    Environment = "test"
  }
}

# 프라이빗 키를 로컬에 저장
resource "local_file" "jenkins_test_private_key" {
  content         = tls_private_key.jenkins_test_key.private_key_pem
  filename        = pathexpand("~/.ssh/${local.prefix}-key.pem")
  file_permission = "0600"
}

# EC2 인스턴스 생성
resource "aws_instance" "jenkins_test" {
  ami                  = var.ami_id
  instance_type        = var.instance_type
  subnet_id            = data.terraform_remote_state.vpc.outputs.pub_sub1_id
  key_name             = aws_key_pair.jenkins_test_key.key_name
  iam_instance_profile = aws_iam_instance_profile.jenkins_test_profile.name

  vpc_security_group_ids = [aws_security_group.jenkins_test_sg.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    tags = {
      Name        = "${local.prefix}-jenkins-root-volume"
      Environment = "test"
    }
  }

  user_data = <<-EOT
#!/bin/bash
set -e

# 전역 변수 설정
JENKINS_HOME="/var/lib/jenkins"
JENKINS_PORT="8081"
JENKINS_CLI_JAR="/usr/local/bin/jenkins-cli.jar"
JENKINS_URL="http://localhost:$${JENKINS_PORT}"
S3_BUCKET="zoochacha-permanent-store"
JENKINS_USER="zoochacha"
JENKINS_PASSWORD="1111"
JENKINS_DIR_SUFFIX="4496553686384266030"
PASSWORD_HASH='$2a$10$DK0HHEJIWh.s5/QqxYZCp.zXL5oYlqJ1P6IFyP33tFhKf3UgS4Lge'
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/your-webhook-url"

# 로깅 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 디스코드 알림 함수
send_discord_notification() {
    local message="$1"
    local status="$2" # success, warning, error
    local color="0"
    
    case "$status" in
        "success") color="65280" ;; # 녹색
        "warning") color="16776960" ;; # 노란색
        "error") color="16711680" ;; # 빨간색
        *) color="0" ;; # 회색
    esac
    
    local payload='{
        "embeds": [{
            "title": "Jenkins 백업 복원 알림",
            "description": "'"$message"'",
            "color": '"$color"'
        }]
    }'
    
    curl -s -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK_URL" || true
}

# 에러 처리 함수
handle_error() {
    local error_msg=$1
    log "ERROR: $${error_msg}"
    # 에러 로그를 시스템 로그에 기록
    logger -t jenkins_setup "ERROR: $${error_msg}"
    # 디스코드 알림 전송
    send_discord_notification "오류 발생: $${error_msg}" "error"
    exit 1
}

# Jenkins 서비스 관리 함수
manage_jenkins_service() {
    local action=$1
    log "Jenkins service $${action}..."
    systemctl $${action} jenkins
}

# Jenkins 시작 대기 함수
wait_for_jenkins() {
    log "Waiting for Jenkins to start..."
    local max_attempts=30
    local attempt=0
    while ! curl -s $${JENKINS_URL} > /dev/null; do
        if [ $${attempt} -ge $${max_attempts} ]; then
            log "Jenkins failed to start after 5 minutes"
            return 1
        fi
        log "Waiting for Jenkins to start... $(( $${attempt} + 1 ))/$${max_attempts}"
        sleep 10
        attempt=$(( $${attempt} + 1 ))
    done
    return 0
}

# 보안 설정 업데이트 함수
update_security_settings() {
    local config_file=$1
    log "Updating security settings in $${config_file}..."
    cp $${config_file} $${config_file}.bak
    
    sed -i 's/<securityRealm class="[^"]*"\/>/<securityRealm class="hudson.security.HudsonPrivateSecurityRealm"><disableSignup>true<\/disableSignup><enableCaptcha>false<\/enableCaptcha><\/securityRealm>/' $${config_file}
    sed -i 's/<authorizationStrategy class="[^"]*"\/>/<authorizationStrategy class="hudson.security.FullControlOnceLoggedInAuthorizationStrategy"><denyAnonymousReadAccess>false<\/denyAnonymousReadAccess><\/authorizationStrategy>/' $${config_file}
    
    if ! grep -q "HudsonPrivateSecurityRealm\|FullControlOnceLoggedInAuthorizationStrategy" $${config_file}; then
        log "Security settings not properly applied, retrying..."
        return 1
    fi
    return 0
}

# CLI 로그인 테스트 함수
test_cli_login() {
    log "Testing Jenkins CLI login..."
    local max_attempts=30
    local attempt=0
    
    while [ $${attempt} -lt $${max_attempts} ]; do
        log "Attempting login $(( $${attempt} + 1 ))/$${max_attempts}"
        if java -jar $${JENKINS_CLI_JAR} -s $${JENKINS_URL} -auth $${JENKINS_USER}:$${JENKINS_PASSWORD} who-am-i; then
            log "CLI login successful"
            return 0
        fi
        sleep 10
        attempt=$(( $${attempt} + 1 ))
    done
    return 1
}

# 중요 파일 확인 함수
check_important_files() {
    log "Checking important Jenkins files..."
    local missing_files=()
    
    # 중요 파일 목록
    local important_files=(
        "config.xml"
        "secret.key"
        "secrets/master.key"
        "users/users.xml"
    )
    
    for file in "$${important_files[@]}"; do
        if [ ! -f "$${JENKINS_HOME}/$${file}" ]; then
            missing_files+=("$${file}")
            log "Missing important file: $${file}"
        else
            log "Found important file: $${file}"
        fi
    done
    
    if [ $${#missing_files[@]} -gt 0 ]; then
        log "WARNING: Some important files are missing: $${missing_files[*]}"
        return 1
    fi
    
    return 0
}

# 시스템 업데이트 및 필수 패키지 설치
log "Updating system and installing required packages..."
apt-get update
apt-get install -y openjdk-17-jdk python3-pip jq unzip

# AWS CLI v2 설치
log "Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

# Jenkins 설치
log "Installing Jenkins..."
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
apt-get update
apt-get install -y jenkins

# Jenkins 포트 설정
log "Configuring Jenkins port..."
sed -i "s/HTTP_PORT=8080/HTTP_PORT=$${JENKINS_PORT}/g" /etc/default/jenkins
sed -i "s/Environment=\"JENKINS_PORT=8080\"/Environment=\"JENKINS_PORT=$${JENKINS_PORT}\"/g" /lib/systemd/system/jenkins.service
systemctl daemon-reload

# S3에서 백업 복원
cd $${JENKINS_HOME}
LATEST_BACKUP=$(aws s3 ls s3://$${S3_BUCKET}/jenkins/backup_config/ --recursive | sort | tail -n 1 | awk '{print $4}')
if [ -z "$${LATEST_BACKUP}" ]; then
    log "No backup found, using default configuration"
    LATEST_BACKUP="jenkins/backup_config/latest.tar.gz"
fi

log "Using backup file: $${LATEST_BACKUP}"
if ! aws s3 cp "s3://$${S3_BUCKET}/$${LATEST_BACKUP}" latest.tar.gz; then
    handle_error "S3 백업 복원 실패 - 버킷: $${S3_BUCKET}, 파일: $${LATEST_BACKUP}"
fi

if [ -f latest.tar.gz ]; then
    manage_jenkins_service stop
    
    # 백업 복원
    log "Restoring backup..."
    mkdir -p backup
    mv latest.tar.gz backup/
    
    # 기존 파일 백업
    log "Backing up existing Jenkins files..."
    mkdir -p jenkins_original_backup
    if [ -d "$${JENKINS_HOME}" ]; then
        cp -r "$${JENKINS_HOME}"/* jenkins_original_backup/ 2>/dev/null || true
    fi
    
    # 기존 파일 정리
    log "Cleaning up existing Jenkins files..."
    find . -maxdepth 1 -not -name "backup" -not -name "jenkins_original_backup" -not -name "." -exec rm -rf {} \;
    
    # 백업 파일 압축 해제
    cd backup
    if ! tar -xzf latest.tar.gz; then
        handle_error "백업 파일 압축 해제 실패"
    fi
    
    # 백업 파일 내용 확인
    log "Checking backup contents..."
    find . -type f | sort
    
    # 백업 파일 복원
    cd ..
    if [ -d backup/config ]; then
        log "Restoring configuration files..."
        cp -r backup/config/* .
        
        # 중요 디렉토리 생성
        mkdir -p secrets users
        
        # 중요 파일 복원 확인
        if [ -f backup/config/secrets/master.key ]; then
            log "Restoring master.key..."
            cp backup/config/secrets/master.key secrets/
        else
            log "WARNING: master.key not found in backup"
        fi
        
        if [ -f backup/config/secret.key ]; then
            log "Restoring secret.key..."
            cp backup/config/secret.key .
        else
            log "WARNING: secret.key not found in backup"
        fi
        
        if [ -f backup/config/secret.key.not-so-secret ]; then
            log "Restoring secret.key.not-so-secret..."
            cp backup/config/secret.key.not-so-secret .
        fi
        
        if [ -d backup/config/users ]; then
            log "Restoring users directory..."
            cp -r backup/config/users/* users/
        else
            log "WARNING: users directory not found in backup"
        fi
        
        if [ -f backup/config/credentials.xml ]; then
            log "Restoring credentials.xml..."
            cp backup/config/credentials.xml .
        fi
        
        # identity.key 파일 복원
        if [ -f backup/config/identity.key ]; then
            log "Restoring identity.key..."
            cp backup/config/identity.key .
        elif [ -f backup/config/secrets/identity.key ]; then
            log "Restoring secrets/identity.key..."
            cp backup/config/secrets/identity.key secrets/
        else
            log "WARNING: identity.key not found in backup"
        fi
        
        # hudson.util.Secret 파일 복원
        if [ -f backup/config/secrets/hudson.util.Secret ]; then
            log "Restoring hudson.util.Secret..."
            cp backup/config/secrets/hudson.util.Secret secrets/
        else
            log "WARNING: hudson.util.Secret not found in backup"
        fi
    else
        log "WARNING: config directory not found in backup"
        send_discord_notification "백업 파일에서 config 디렉토리를 찾을 수 없습니다." "warning"
    fi
    
    # 백업 디렉토리 정리
    rm -rf backup
else
    log "Creating default configuration..."
    send_discord_notification "백업 파일이 없어 기본 설정을 사용합니다." "warning"
fi

# 사용자 설정
log "Configuring users..."
mkdir -p $${JENKINS_HOME}/users/$${JENKINS_USER}_$${JENKINS_DIR_SUFFIX}
cat > $${JENKINS_HOME}/users/$${JENKINS_USER}_$${JENKINS_DIR_SUFFIX}/config.xml << EOF
<?xml version='1.1' encoding='UTF-8'?>
<user>
    <version>10</version>
    <id>$${JENKINS_USER}</id>
    <fullName>$${JENKINS_USER}</fullName>
    <properties>
        <hudson.security.HudsonPrivateSecurityRealm_-Details>
            <passwordHash>#jbcrypt:$${PASSWORD_HASH}</passwordHash>
        </hudson.security.HudsonPrivateSecurityRealm_-Details>
    </properties>
</user>
EOF

# users.xml 업데이트
if [ -f $${JENKINS_HOME}/users/users.xml ]; then
    log "Updating users.xml..."
    # 중복 항목 제거
    grep -v '<string>admin</string>' $${JENKINS_HOME}/users/users.xml | \
    sed '/<entry>[ \t]*<\/entry>/d' > $${JENKINS_HOME}/users/users.xml.tmp
    
    # zoochacha 사용자 항목 추가 (이미 있는지 확인)
    if ! grep -q "<string>$${JENKINS_USER}</string>" $${JENKINS_HOME}/users/users.xml.tmp; then
        sed -i "/<idToDirectoryNameMap class=\"concurrent-hash-map\">/a \    <entry>\n      <string>$${JENKINS_USER}</string>\n      <string>$${JENKINS_USER}_$${JENKINS_DIR_SUFFIX}</string>\n    </entry>" $${JENKINS_HOME}/users/users.xml.tmp
    fi
    
    mv $${JENKINS_HOME}/users/users.xml.tmp $${JENKINS_HOME}/users/users.xml
fi

# 권한 설정
chown -R jenkins:jenkins $${JENKINS_HOME}

# 중요 파일 확인
if ! check_important_files; then
    log "WARNING: Some important files are missing, Jenkins may not start properly"
    send_discord_notification "중요 파일이 누락되어 Jenkins가 제대로 시작되지 않을 수 있습니다." "warning"
fi

# Jenkins 시작 및 설정 검증
manage_jenkins_service start
if ! wait_for_jenkins; then
    handle_error "Jenkins 시작 실패"
fi

# Jenkins CLI 다운로드 및 설정 검증
until wget -q -O $${JENKINS_CLI_JAR} $${JENKINS_URL}/jnlpJars/jenkins-cli.jar; do
    log "Waiting for Jenkins CLI to become available..."
    sleep 5
done

if test_cli_login; then
    log "Jenkins configuration successful"
    send_discord_notification "Jenkins 설정이 성공적으로 완료되었습니다." "success"
else
    handle_error "Jenkins configuration failed - CLI login test failed"
fi
EOT

  # 인스턴스 종료 시 대기 시간 및 상태 확인
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOF
      echo "Initiating instance termination process..."
      instance_id="${self.id}"
      
      # 연결된 EIP 해제 확인
      echo "Checking for associated EIP..."
      aws ec2 describe-addresses --filters "Name=instance-id,Values=$instance_id" | grep -q "AssociationId" && {
        echo "Waiting for EIP disassociation..."
        sleep 30
      }
      
      # 인스턴스 종료 전 상태 확인
      echo "Checking instance status..."
      aws ec2 describe-instance-status --instance-id $instance_id || true
      
      # 종료 대기
      echo "Waiting for instance to terminate..."
      sleep 60
    EOF
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${local.prefix}-jenkins-server"
    Environment = "test"
  }
}

# Elastic IP 할당
resource "aws_eip" "jenkins_test" {
  domain = "vpc"

  tags = {
    Name        = "${local.prefix}-jenkins-eip"
    Environment = "test"
  }
}

# EIP 연결
resource "aws_eip_association" "jenkins_test" {
  instance_id   = aws_instance.jenkins_test.id
  allocation_id = aws_eip.jenkins_test.id
}

# EIP 연결을 위한 null_resource
resource "null_resource" "jenkins_provisioner" {
  depends_on = [aws_eip_association.jenkins_test, local_file.jenkins_test_private_key]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(local_file.jenkins_test_private_key.filename)
    host        = aws_eip.jenkins_test.public_ip
  }

  provisioner "file" {
    source      = "${path.module}/../jenkins-backup.sh"
    destination = "/tmp/backup-jenkins.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv /tmp/backup-jenkins.sh /usr/local/bin/",
      "sudo chmod +x /usr/local/bin/backup-jenkins.sh"
    ]
  }
}

# EIP 연결 해제 및 삭제 제어
resource "null_resource" "eip_management" {
  triggers = {
    eip_id      = aws_eip.jenkins_test.id
    instance_id = aws_instance.jenkins_test.id
  }

  # EIP 연결 해제 시 대기 및 재시도
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOF
      eip_id="${self.triggers.eip_id}"
      instance_id="${self.triggers.instance_id}"
      
      echo "Checking EIP association status..."
      max_attempts=5
      attempt=1
      
      while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt to verify EIP disassociation..."
        aws ec2 describe-addresses --allocation-ids $eip_id | grep -q "AssociationId" || break
        echo "EIP still associated, waiting..."
        sleep 30
        attempt=$((attempt + 1))
      done
    EOF
  }
}

# 보안 그룹 삭제 제어
resource "null_resource" "security_group_management" {
  triggers = {
    sg_id = aws_security_group.jenkins_test_sg.id
  }

  # 보안 그룹 삭제 전 의존성 확인 및 대기
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOF
      sg_id="${self.triggers.sg_id}"
      
      echo "Checking security group dependencies..."
      max_attempts=5
      attempt=1
      
      while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt to check security group dependencies..."
        dependencies=$(aws ec2 describe-network-interfaces --filters "Name=group-id,Values=$sg_id" --query 'NetworkInterfaces[*].[NetworkInterfaceId]' --output text)
        
        if [ -z "$dependencies" ]; then
          echo "No dependencies found for security group"
          break
        else
          echo "Security group still has dependencies, waiting..."
          sleep 30
        fi
        
        attempt=$((attempt + 1))
      done
    EOF
  }
}

# IAM 역할 삭제 제어
resource "null_resource" "iam_role_management" {
  triggers = {
    role_name = aws_iam_role.jenkins_test_role.name
  }

  # IAM 역할 삭제 전 의존성 확인 및 대기
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOF
      role_name="${self.triggers.role_name}"
      
      echo "Checking IAM role dependencies..."
      max_attempts=5
      attempt=1
      
      while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt to check IAM role dependencies..."
        attached_policies=$(aws iam list-attached-role-policies --role-name $role_name --query 'AttachedPolicies[*].[PolicyArn]' --output text)
        instance_profiles=$(aws iam list-instance-profiles-for-role --role-name $role_name --query 'InstanceProfiles[*].[InstanceProfileName]' --output text)
        
        if [ -z "$attached_policies" ] && [ -z "$instance_profiles" ]; then
          echo "No dependencies found for IAM role"
          break
        else
          echo "IAM role still has dependencies, waiting..."
          sleep 20
        fi
        
        attempt=$((attempt + 1))
      done
    EOF
  }
}

# 전체 삭제 프로세스 제어
resource "null_resource" "deletion_controller" {
  depends_on = [
    aws_instance.jenkins_test,
    aws_eip.jenkins_test,
    aws_security_group.jenkins_test_sg,
    aws_iam_role.jenkins_test_role
  ]

  # 삭제 순서 및 상태 모니터링
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOF
      echo "Starting resource deletion process..."
      
      # 테라폼 상태 백업
      echo "Backing up Terraform state..."
      cp terraform.tfstate "terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)"
      
      # 리소스 삭제 순서 로깅
      echo "Resource deletion order:"
      echo "1. EIP Association"
      echo "2. EC2 Instance"
      echo "3. Security Group"
      echo "4. IAM Role and Instance Profile"
      echo "5. EIP"
      
      # 최종 상태 확인
      echo "Waiting for all resources to be deleted..."
      sleep 60
      
      echo "Deletion process completed"
    EOF
  }
}

# 상태 파일 백업
resource "null_resource" "state_backup" {
  triggers = {
    instance_id = aws_instance.jenkins_test.id
  }

  provisioner "local-exec" {
    command = "if [ -f terraform.tfstate ]; then cp terraform.tfstate terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S); else echo 'No terraform.tfstate file found, skipping backup'; fi"
  }
}

# 출력 정의
output "jenkins_test_public_ip" {
  value       = aws_eip.jenkins_test.public_ip
  description = "Jenkins test server public IP"
}

output "jenkins_test_url" {
  value       = "http://${aws_eip.jenkins_test.public_ip}:8081"
  description = "Jenkins test server URL"
} 