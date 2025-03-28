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

    terraform init
    if [ $? -ne 0 ]; then
        log_error "$dir terraform init 실패"
        return 1
    fi

    terraform apply -auto-approve
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

    terraform init
    if [ $? -ne 0 ]; then
        log_error "$dir terraform init 실패"
        return 1
    fi

    terraform destroy -auto-approve
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

# VPC 생성 완료 확인 함수
wait_for_vpc() {
    log_info "VPC 생성 완료 대기 중..."
    while true; do
        vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=zoochacha-vpc" --query 'Vpcs[0].VpcId' --output text)
        if [ "$vpc_id" != "None" ] && [ ! -z "$vpc_id" ]; then
            # 서브넷 확인
            subnet_count=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'length(Subnets)' --output text)
            if [ "$subnet_count" -eq 4 ]; then
                # 보안 그룹 확인
                sg_id=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Name,Values=zoochacha-eks-sg" --query 'SecurityGroups[0].GroupId' --output text)
                if [ "$sg_id" != "None" ] && [ ! -z "$sg_id" ]; then
                    log_info "VPC와 모든 관련 리소스가 준비되었습니다"
                    return 0
                fi
            fi
        fi
        log_warn "VPC 또는 관련 리소스가 아직 준비되지 않았습니다. 10초 후 다시 확인합니다"
        sleep 10
    done
}

# EKS 클러스터 상태 확인 함수
wait_for_eks_cluster() {
    log_info "EKS 클러스터 상태 확인 중..."
    
    # 클러스터가 이미 ACTIVE 상태인지 확인
    if aws eks describe-cluster --name zoochacha-eks-cluster --query 'cluster.status' --output text 2>/dev/null | grep -q ACTIVE; then
        log_info "EKS 클러스터가 이미 ACTIVE 상태입니다"
        return 0
    fi

    # 새로 생성된 경우에만 대기
    log_info "EKS 클러스터 생성 시작... 초기 8분 30초 대기"
    sleep 510  # 8분 30초 = 510초
    
    log_info "EKS 클러스터 생성 완료 대기 중..."
    while true; do
        if aws eks describe-cluster --name zoochacha-eks-cluster --query 'cluster.status' --output text 2>/dev/null | grep -q ACTIVE; then
            log_info "EKS 클러스터가 성공적으로 생성되었습니다"
            return 0
        fi
        log_warn "EKS 클러스터가 아직 생성 중입니다. 10초 후 다시 확인합니다"
        sleep 10
    done
}

# EKS 노드 준비 상태 체크 함수
wait_for_eks_nodes() {
    log_info "EKS 노드 준비 상태 확인 중..."
    while true; do
        NODE_STATUS=$(kubectl get nodes --no-headers 2>/dev/null | grep -v "NotReady" | grep "Ready" | wc -l)
        if [ "$NODE_STATUS" -ge 2 ]; then
            log_info "노드가 모두 Ready 상태입니다"
            
            # 시스템 파드 상태도 확인
            PENDING_PODS=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep "Pending" | wc -l)
            if [ "$PENDING_PODS" -eq 0 ]; then
                log_info "모든 시스템 파드가 정상 실행 중입니다"
                return 0
            fi
        fi
        log_warn "노드 또는 시스템 파드 준비 대기 중... (30초마다 확인)"
        sleep 30
    done
}

# IAM 역할 삭제 함수
delete_iam_roles() {
    log_info "IAM 역할 삭제 시작..."
    
    # EKS 노드 그룹 IAM 역할 정책 디태치
    log_info "노드 그룹 IAM 역할 정책 디태치 중..."
    aws iam detach-role-policy --role-name zoochacha-eks-node-group-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy || true
    aws iam detach-role-policy --role-name zoochacha-eks-node-group-role --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy || true
    aws iam detach-role-policy --role-name zoochacha-eks-node-group-role --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly || true
    
    # EBS CSI 드라이버 IAM 역할 정책 디태치
    log_info "EBS CSI IAM 역할 정책 디태치 중..."
    aws iam detach-role-policy --role-name zoochacha-eks-ebs-csi-role --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy || true
    
    # EKS 클러스터 IAM 역할 정책 디태치
    log_info "클러스터 IAM 역할 정책 디태치 중..."
    aws iam detach-role-policy --role-name zoochacha-eks-cluster-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy || true
    
    sleep 10
    
    # IAM 역할 삭제
    log_info "IAM 역할 삭제 중..."
    aws iam delete-role --role-name zoochacha-eks-node-group-role || true
    aws iam delete-role --role-name zoochacha-eks-ebs-csi-role || true
    aws iam delete-role --role-name zoochacha-eks-cluster-role || true
    
    log_info "IAM 역할 삭제 완료"
}

# DynamoDB 테이블 생성 확인 함수
wait_for_dynamodb_table() {
    log_info "DynamoDB 테이블 생성 확인 중..."
    while true; do
        TABLE_STATUS=$(aws dynamodb describe-table --table-name terraform-lock --query 'Table.TableStatus' --output text 2>/dev/null)
        if [ "$TABLE_STATUS" == "ACTIVE" ]; then
            log_info "DynamoDB 테이블이 성공적으로 생성되었습니다"
            return 0
        fi
        log_warn "DynamoDB 테이블이 아직 준비되지 않았습니다. 10초 후 다시 확인합니다"
        sleep 10
    done
}

# Metric Server 설치 함수
install_metric_server() {
    log_info "Metric Server 설치 중..."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    
    # Metric Server Pod가 Ready 상태가 될 때까지 대기
    log_info "Metric Server 준비 상태 확인 중..."
    while true; do
        if kubectl get deployment metrics-server -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q "1"; then
            log_info "Metric Server가 성공적으로 설치되었습니다"
            return 0
        fi
        log_warn "Metric Server가 아직 준비되지 않았습니다. 10초 후 다시 확인합니다"
        sleep 10
    done
}

# 배포 함수
deploy() {
    log_info "인프라 배포 시작"

    # 0. DynamoDB 테이블 생성 (가장 먼저)
    log_info "DynamoDB 상태 잠금 테이블 생성"
    cd vpc
    terraform init
    terraform apply -target=aws_dynamodb_table.terraform_lock -auto-approve
    cd ..
    
    # DynamoDB 테이블 생성 완료 확인
    wait_for_dynamodb_table

    # 1. VPC 배포 (기본 인프라)
    apply_terraform "vpc"
    wait_for_vpc
    
    # 2. Jenkins EC2 배포 (VPC만 의존)
    apply_terraform "jenkins-ec2"
    
    # 3. EKS 배포 (VPC 의존)
    apply_terraform "eks"
    wait_for_eks_cluster
    
    # kubeconfig 업데이트 (EKS 배포 직후 필요)
    update_kubeconfig
    
    # EKS 노드 준비 상태 확인
    wait_for_eks_nodes
    
    # Metric Server 설치 (EKS 노드 준비 직후)
    install_metric_server
    
    # 4. Basic Infra 배포 (VPC, EKS 의존)
    apply_terraform "zoochacha-basic-infra"
    
    # 5. Log Monitoring 배포 (EKS 노드 의존)
    apply_terraform "log-monitoring"

    # 최종 상태 확인
    check_nodes_status

    log_info "인프라 배포 완료"
}

# 삭제 함수
destroy() {
    log_info "인프라 삭제 시작"

    # 1. Log Monitoring 삭제 (가장 먼저 제거)
    destroy_terraform "log-monitoring"

    # 2. Basic Infra 삭제 (EKS 의존성)
    destroy_terraform "zoochacha-basic-infra"

    # 3. EKS 관련 리소스 삭제
    delete_eks_loadbalancers
    delete_eks_nodegroup
    delete_eks_cluster
    delete_iam_roles
    destroy_terraform "eks"

    # 4. Jenkins EC2 삭제 (독립적으로 삭제 가능)
    destroy_terraform "jenkins-ec2"

    # 5. VPC 관련 리소스 삭제 (마지막에 삭제)
    delete_nat_gateways
    delete_security_groups
    destroy_terraform "vpc"

    log_info "인프라 삭제 완료"
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