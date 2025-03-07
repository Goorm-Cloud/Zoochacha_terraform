#!/bin/bash

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 각 모듈의 배포 상태 확인
check_terraform_state() {
    local dir=$1
    if [ -f "$dir/terraform.tfstate" ]; then
        resources=$(cat "$dir/terraform.tfstate" | grep '"type":' | wc -l)
        if [ $resources -gt 0 ]; then
            return 0 # 리소스가 존재함
        fi
    fi
    return 1 # 리소스가 없음
}

# Terraform 초기화 및 적용
apply_terraform() {
    local dir=$1
    log_info "Deploying $dir..."
    
    cd $dir
    if [ $? -ne 0 ]; then
        log_error "$dir 디렉토리로 이동 실패"
        return 1
    fi

    ../terraform-lock.sh init
    if [ $? -ne 0 ]; then
        log_error "$dir terraform init 실패"
        return 1
    fi

    ../terraform-lock.sh apply -auto-approve
    if [ $? -ne 0 ]; then
        log_error "$dir terraform apply 실패"
        return 1
    fi

    cd ..
    log_info "$dir 배포 완료"
    return 0
}

# Terraform 삭제
destroy_terraform() {
    local dir=$1
    log_info "Destroying $dir..."
    
    cd $dir
    if [ $? -ne 0 ]; then
        log_error "$dir 디렉토리로 이동 실패"
        return 1
    fi

    ../terraform-lock.sh destroy -auto-approve
    if [ $? -ne 0 ]; then
        log_error "$dir terraform destroy 실패"
        return 1
    fi

    cd ..
    log_info "$dir 삭제 완료"
    return 0
}

# 메인 배포 함수
deploy() {
    # VPC 배포
    if ! check_terraform_state "vpc"; then
        apply_terraform "vpc"
        if [ $? -ne 0 ]; then
            log_error "VPC 배포 실패"
            return 1
        fi
    else
        log_warn "VPC가 이미 배포되어 있습니다"
    fi

    # EKS 배포
    if ! check_terraform_state "eks"; then
        apply_terraform "eks"
        if [ $? -ne 0 ]; then
            log_error "EKS 배포 실패"
            return 1
        fi
    else
        log_warn "EKS가 이미 배포되어 있습니다"
    fi

    # Jenkins 배포
    if ! check_terraform_state "jenkins"; then
        apply_terraform "jenkins"
        if [ $? -ne 0 ]; then
            log_error "Jenkins 배포 실패"
            return 1
        fi
    else
        log_warn "Jenkins가 이미 배포되어 있습니다"
    fi

    log_info "모든 리소스 배포 완료"
}

# 메인 삭제 함수
destroy() {
    # Jenkins 삭제
    if check_terraform_state "jenkins"; then
        destroy_terraform "jenkins"
        if [ $? -ne 0 ]; then
            log_error "Jenkins 삭제 실패"
            return 1
        fi
    else
        log_warn "Jenkins가 이미 삭제되어 있습니다"
    fi

    # EKS 삭제
    if check_terraform_state "eks"; then
        destroy_terraform "eks"
        if [ $? -ne 0 ]; then
            log_error "EKS 삭제 실패"
            return 1
        fi
    else
        log_warn "EKS가 이미 삭제되어 있습니다"
    fi

    # VPC 삭제
    if check_terraform_state "vpc"; then
        destroy_terraform "vpc"
        if [ $? -ne 0 ]; then
            log_error "VPC 삭제 실패"
            return 1
        fi
    else
        log_warn "VPC가 이미 삭제되어 있습니다"
    fi

    log_info "모든 리소스 삭제 완료"
}

# 명령어 처리
case "$1" in
    "deploy")
        deploy
        ;;
    "destroy")
        destroy
        ;;
    *)
        echo "사용법: $0 {deploy|destroy}"
        exit 1
        ;;
esac 