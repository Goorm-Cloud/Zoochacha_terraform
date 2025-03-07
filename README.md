# Zoochacha Terraform 프로젝트

이 프로젝트는 AWS에 VPC, EKS 클러스터, Jenkins EC2를 자동으로 배포하는 Terraform 코드를 포함하고 있습니다.

## 사전 요구사항

- AWS CLI가 설치되어 있어야 합니다.
- AWS 자격 증명이 구성되어 있어야 합니다.
- Terraform이 설치되어 있어야 합니다.
- kubectl이 설치되어 있어야 합니다.
- SSH 키 페어가 ~/.ssh/id_rsa와 ~/.ssh/id_rsa.pub에 있어야 합니다.

## 디렉토리 구조

```
zoochacha_terraform/
├── vpc/                # VPC 관련 Terraform 코드
├── eks/                # EKS 클러스터 관련 Terraform 코드
├── jenkins-ec2/        # Jenkins EC2 관련 Terraform 코드
├── terraform-lock.sh   # Terraform 중복 실행 방지 스크립트
├── deploy.sh           # 전체 배포/삭제 자동화 스크립트
└── README.md           # 이 문서
```

## 실행 방법

### 1. 스크립트 실행 권한 부여

```bash
chmod +x terraform-lock.sh deploy.sh
```

### 2. 전체 인프라 배포

다음 명령어를 실행하면 VPC, EKS, Jenkins EC2가 순차적으로 배포됩니다:

```bash
./deploy.sh deploy
```

배포 순서:
1. VPC 생성
2. EKS 클러스터 생성
3. Jenkins EC2 배포

### 3. 전체 인프라 삭제

다음 명령어를 실행하면 모든 리소스가 역순으로 삭제됩니다:

```bash
./deploy.sh destroy
```

삭제 순서:
1. Jenkins EC2 삭제
2. EKS 클러스터 삭제
3. VPC 삭제

## Jenkins 접속 방법

Jenkins EC2 배포가 완료되면 다음과 같이 접속할 수 있습니다:

1. Jenkins URL 확인:
```bash
cd jenkins-ec2
terraform output jenkins_url
```

2. 초기 관리자 비밀번호 확인:
```bash
ssh -i ~/.ssh/id_rsa ubuntu@$(terraform output -raw jenkins_public_ip) 'sudo cat /var/lib/jenkins/secrets/initialAdminPassword'
```

## 주의사항

- 각 단계별로 이전 단계가 성공적으로 완료되어야 다음 단계로 진행됩니다.
- 배포 중 오류가 발생하면 즉시 중단됩니다.
- 이미 배포된 리소스는 자동으로 건너뜁니다.
- 삭제는 배포의 역순으로 진행됩니다.
- Jenkins EC2 인스턴스에는 Docker, kubectl, AWS CLI가 자동으로 설치됩니다.

## 로그 메시지

스크립트는 다음과 같은 색상으로 구분된 로그 메시지를 출력합니다:

- 🟢 녹색: 정보 메시지 (성공)
- 🟡 노란색: 경고 메시지 (건너뜀)
- 🔴 빨간색: 오류 메시지 (실패)

## 문제 해결

### 중복 실행 오류

"Terraform이 이미 실행 중입니다" 메시지가 표시되는 경우:
1. 실제로 다른 터미널에서 실행 중인지 확인
2. 실행 중이 아니라면 `.terraform-lock` 파일을 수동으로 삭제

### EKS 클러스터 접속 문제

EKS 클러스터 배포 후 접속이 안 되는 경우:
```bash
aws eks update-kubeconfig --name zoochacha-eks-cluster --region ap-northeast-2
```

### Jenkins EC2 접속 문제

SSH 접속이 안 되는 경우:
1. 보안 그룹 규칙 확인
2. SSH 키 권한 확인 (600)
3. 인스턴스 상태 및 네트워크 설정 확인

## 라이선스

MIT License 