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

    ../terraform-lock.sh init
    if [ $? -ne 0 ]; then
        log_error "$dir terraform init 실패"
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

# EKS 노드 그룹 삭제 함수
delete_eks_nodegroup() {
    log_info "EKS 노드 그룹 삭제 시작..."
    aws eks delete-nodegroup \
        --cluster-name zoochacha-eks-cluster \
        --nodegroup-name zoochacha-node-group-large

    log_info "노드 그룹 삭제 완료 대기 중..."
    while true; do
        if ! aws eks describe-nodegroup \
            --cluster-name zoochacha-eks-cluster \
            --nodegroup-name zoochacha-node-group-large 2>/dev/null; then
            log_info "노드 그룹이 성공적으로 삭제되었습니다"
            break
        fi
        log_warn "노드 그룹이 아직 삭제 중입니다. 30초 후 다시 확인합니다"
        sleep 30
    done
}

# EKS 클러스터 삭제 함수
delete_eks_cluster() {
    log_info "EKS 클러스터 삭제 시작..."
    aws eks delete-cluster --name zoochacha-eks-cluster

    log_info "EKS 클러스터 삭제 완료 대기 중..."
    while true; do
        if ! aws eks describe-cluster --name zoochacha-eks-cluster 2>/dev/null; then
            log_info "EKS 클러스터가 성공적으로 삭제되었습니다"
            break
        fi
        log_warn "EKS 클러스터가 아직 삭제 중입니다. 30초 후 다시 확인합니다"
        sleep 30
    done
}

# EKS 로드밸런서 삭제 함수
delete_eks_loadbalancers() {
    log_info "EKS 로드밸런서 삭제 시작..."
    elbs=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[*].LoadBalancerArn' --output text)
    if [ ! -z "$elbs" ]; then
        for elb in $elbs; do
            aws elbv2 delete-load-balancer --load-balancer-arn $elb
            log_info "로드밸런서 $elb 삭제 요청됨"
        done
        log_info "로드밸런서 삭제 완료 대기 중..."
        sleep 30
    else
        log_warn "삭제할 로드밸런서가 없습니다"
    fi
}

# 보안 그룹 삭제 함수
delete_security_groups() {
    log_info "보안 그룹 삭제 시작..."
    vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=zoochacha-eks-vpc" --query 'Vpcs[0].VpcId' --output text)
    if [ ! -z "$vpc_id" ]; then
        sgs=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
        if [ ! -z "$sgs" ]; then
            for sg in $sgs; do
                aws ec2 delete-security-group --group-id $sg || true
                log_info "보안 그룹 $sg 삭제 시도"
            done
        fi
    fi
}

# NAT Gateway 삭제 함수
delete_nat_gateways() {
    log_info "NAT Gateway 삭제 시작..."
    vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=zoochacha-eks-vpc" --query 'Vpcs[0].VpcId' --output text)
    if [ ! -z "$vpc_id" ]; then
        nat_gateways=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc_id" --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text)
        if [ ! -z "$nat_gateways" ]; then
            for nat in $nat_gateways; do
                aws ec2 delete-nat-gateway --nat-gateway-id $nat
                log_info "NAT Gateway $nat 삭제 요청됨"
            done
            log_info "NAT Gateway 삭제 완료 대기 중..."
            sleep 60
        else
            log_warn "삭제할 NAT Gateway가 없습니다"
        fi
    fi
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

    # Jenkins EC2 배포
    if ! check_terraform_state "jenkins-ec2"; then
        apply_terraform "jenkins-ec2"
        if [ $? -ne 0 ]; then
            log_error "Jenkins EC2 배포 실패"
            return 1
        fi
    else
        log_warn "Jenkins EC2가 이미 배포되어 있습니다"
    fi

    log_info "모든 리소스 배포 완료"
}

# 메인 삭제 함수
destroy() {
    # Jenkins EC2 삭제
    if check_terraform_state "jenkins-ec2"; then
        destroy_terraform "jenkins-ec2"
        if [ $? -ne 0 ]; then
            log_error "Jenkins EC2 삭제 실패"
            return 1
        fi
        log_info "Jenkins EC2 삭제 완료 대기 중..."
        sleep 30
    else
        log_warn "Jenkins EC2가 이미 삭제되어 있습니다"
    fi

    # EKS 관련 리소스 삭제
    if check_terraform_state "eks"; then
        # 1. 로드밸런서 삭제
        delete_eks_loadbalancers
        sleep 30

        # 2. 노드 그룹 삭제
        delete_eks_nodegroup
        sleep 30

        # 3. EKS 클러스터 삭제
        delete_eks_cluster
        sleep 60

        # 4. Terraform 상태 파일 정리
        destroy_terraform "eks"
        if [ $? -ne 0 ]; then
            log_error "EKS Terraform 상태 정리 실패"
            return 1
        fi
    else
        log_warn "EKS가 이미 삭제되어 있습니다"
    fi

    # VPC 관련 리소스 삭제
    if check_terraform_state "vpc"; then
        # 1. NAT Gateway 삭제
        delete_nat_gateways

        # 2. 보안 그룹 삭제
        delete_security_groups
        sleep 30

        # 3. VPC 삭제
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