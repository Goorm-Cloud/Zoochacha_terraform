# Jenkins EC2 서버 배포 및 관리

## 개요
이 모듈은 Jenkins 서버를 AWS EC2 인스턴스로 배포하고 관리하는 Terraform 코드입니다.

## 주요 기능
- Jenkins 서버 자동 배포
- S3 버킷을 통한 설정 파일 관리
- 자동 백업 기능
- AMI를 통한 재해 복구 기능

## 백업 및 복구 메커니즘

### 1. 설정 백업
- Jenkins 설정 파일은 자동으로 S3에 백업됩니다.
- 백업은 평일 저녁 10시에 자동 실행되며 `zoochacha-permanent-store` 버킷에 저장됩니다.
- 백업 스크립트: `/usr/local/bin/jenkins-backup.sh`

### 2. AMI 백업
- EC2 인스턴스의 AMI가 매주 일요일 새벽 2시에 자동 생성됩니다.
- 최신 3개의 AMI만 유지되며 이전 AMI는 자동 삭제됩니다.
- AMI 생성 스크립트: `/home/ubuntu/jenkins-create-ami.sh`

### 3. 복구 방법
- 배포 실패 또는 재해 발생 시 복구 AMI를 사용하여 Jenkins 서버를 복구할 수 있습니다.

#### AMI를 사용한 복구
```bash
# 복구 AMI를 사용하여 재배포
terraform apply -var="use_recovery_ami=true"
```

#### 특정 AMI를 사용한 복구
```bash
# 특정 AMI ID를 사용하여 재배포
terraform apply -var="recovery_ami_id=ami-1234567890abcdef0"
```

## 주의사항
- AMI 복구 방식은 설정 파일만 복구하는 방식보다 빠르고 안정적입니다.
- 테라폼 apply 시 기존 젠킨스 인스턴스는 종료됩니다. 중요한 데이터는 사전에 백업되어야 합니다. 