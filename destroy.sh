#!/bin/bash

# AWS 프로필 설정
export AWS_PROFILE=zoochacha

# 볼륨 삭제 함수
delete_volumes() {
    echo "EBS 볼륨 삭제 시작..."
    volumes=$(aws ec2 describe-volumes --filters "Name=availability-zone,Values=ap-northeast-2a,ap-northeast-2c" --query 'Volumes[*].[VolumeId,State]' --output text)
    if [ ! -z "$volumes" ]; then
        echo "$volumes" | while read -r volume_id state; do
            if [ "$state" = "available" ]; then
                aws ec2 delete-volume --volume-id $volume_id
                echo "볼륨 $volume_id 삭제 요청됨"
            else
                echo "볼륨 $volume_id는 $state 상태라 삭제할 수 없습니다"
            fi
        done
    else
        echo "삭제할 볼륨이 없습니다"
    fi
}

# 스냅샷 삭제 함수
delete_snapshots() {
    echo "EBS 스냅샷 삭제 시작..."
    snapshots=$(aws ec2 describe-snapshots --owner-ids self --query 'Snapshots[*].[SnapshotId,State]' --output text)
    if [ ! -z "$snapshots" ]; then
        echo "$snapshots" | while read -r snapshot_id state; do
            if [ "$state" = "completed" ]; then
                aws ec2 delete-snapshot --snapshot-id $snapshot_id
                echo "스냅샷 $snapshot_id 삭제 요청됨"
            else
                echo "스냅샷 $snapshot_id는 $state 상태라 삭제할 수 없습니다"
            fi
        done
    else
        echo "삭제할 스냅샷이 없습니다"
    fi
}

# AMI 삭제 함수
delete_amis() {
    echo "AMI 삭제 시작..."
    amis=$(aws ec2 describe-images --owners self --query 'Images[*].[ImageId,Name]' --output text)
    if [ ! -z "$amis" ]; then
        echo "$amis" | while read -r image_id name; do
            aws ec2 deregister-image --image-id $image_id
            echo "AMI $image_id ($name) 삭제 요청됨"
        done
    else
        echo "삭제할 AMI가 없습니다"
    fi
}

# EKS PVC/PV 삭제 함수
delete_eks_storage() {
    echo "EKS 스토리지 리소스 삭제 시작..."
    
    # EKS 클러스터가 있는지 확인
    if aws eks describe-cluster --name zoochacha-eks-cluster &>/dev/null; then
        echo "EKS 클러스터가 발견되었습니다. 스토리지 리소스 삭제를 시작합니다..."
        
        # kubeconfig 업데이트
        aws eks update-kubeconfig --name zoochacha-eks-cluster --region ap-northeast-2
        
        # 모든 네임스페이스의 PVC 삭제
        echo "모든 네임스페이스의 PVC 삭제 중..."
        for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
            echo "네임스페이스 $ns의 PVC 삭제 중..."
            kubectl delete pvc --all -n $ns --force --grace-period=0 2>/dev/null || true
        done
        
        # PV 삭제
        echo "모든 PV 삭제 중..."
        kubectl delete pv --all --force --grace-period=0 2>/dev/null || true
        
        # EKS 관련 볼륨 보존
        echo "EKS 관련 볼륨 보존 중..."
        volumes=$(aws ec2 describe-volumes --filters "Name=tag:kubernetes.io/cluster/zoochacha-eks-cluster,Values=owned" --query 'Volumes[*].[VolumeId,State,Tags[?Key==`Name`].Value|[0]]' --output text)
        if [ ! -z "$volumes" ]; then
            echo "$volumes" | while read -r volume_id state name; do
                if [ "$state" = "available" ]; then
                    # 볼륨 태그 변경 (보존용)
                    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
                    NEW_NAME="preserved-${name:-$volume_id}-${TIMESTAMP}"
                    echo "볼륨 $volume_id ($name) 보존 중..."
                    
                    # 기존 EKS 태그 제거
                    aws ec2 delete-tags --resources $volume_id --tags Key=kubernetes.io/cluster/zoochacha-eks-cluster
                    
                    # 새로운 보존 태그 추가
                    aws ec2 create-tags --resources $volume_id --tags \
                        Key=Name,Value=$NEW_NAME \
                        Key=Preserved,Value=true \
                        Key=PreservedAt,Value=$TIMESTAMP \
                        Key=OriginalName,Value="${name:-$volume_id}"
                    
                    echo "볼륨 $volume_id ($name)이 $NEW_NAME로 보존됨"
                else
                    echo "EKS 볼륨 $volume_id ($name)는 $state 상태라 보존할 수 없습니다"
                fi
            done
        fi
        
        echo "EKS 스토리지 리소스 삭제 완료"
    else
        echo "EKS 클러스터가 이미 삭제되었거나 존재하지 않습니다"
    fi
}

# Jenkins EC2 백업 및 삭제
echo "Creating backup of Jenkins EC2..."
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=zoochacha-jenkins-server" --query 'Reservations[].Instances[?State.Name==`running`][].InstanceId' --output text)
if [ ! -z "$INSTANCE_ID" ]; then
    # AMI 생성
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    AMI_NAME="zoochacha-jenkins-backup-${TIMESTAMP}"
    echo "Creating AMI: ${AMI_NAME}..."
    AMI_ID=$(aws ec2 create-image --instance-id $INSTANCE_ID --name "$AMI_NAME" --description "Backup of Jenkins server before termination" --no-reboot --output text)
    echo "Waiting for AMI creation to complete..."
    aws ec2 wait image-available --image-ids $AMI_ID
    echo "AMI created successfully: ${AMI_ID}"

    # Jenkins EC2 삭제
    echo "Destroying Jenkins EC2..."
    cd jenkins-ec2
    terraform init
    terraform destroy -auto-approve
    if [ $? -ne 0 ]; then
        echo "Failed to destroy Jenkins EC2. Please check the error and try again."
        exit 1
    fi
    cd ..
else
    echo "Jenkins EC2 instance not found."
fi

# EKS 스토리지 리소스 삭제 (클러스터가 살아있는 동안)
delete_eks_storage

# EKS 클러스터 삭제
echo "Destroying EKS Cluster..."
cd eks
terraform init
terraform destroy -var="vpc_id=vpc-06ef01a5470e9b2cc" \
  -var='private_subnet_ids=["subnet-06b7d8b981f1d7202","subnet-0f5542bd677ba353a"]' \
  -var='public_subnet_ids=["subnet-01e58ed6299ed550f","subnet-0ffeae540d824b39e"]' \
  -auto-approve
if [ $? -ne 0 ]; then
    echo "Failed to destroy EKS cluster. Please check the error and try again."
    exit 1
fi
cd ..

# 일반 볼륨, 스냅샷, AMI 삭제
delete_volumes
delete_snapshots
delete_amis

# VPC 삭제
echo "Destroying VPC..."
cd vpc
terraform init
terraform destroy -auto-approve
if [ $? -ne 0 ]; then
    echo "Failed to destroy VPC. Please check the error and try again."
    exit 1
fi
cd ..

# DynamoDB는 prevent_destroy 설정이 되어 있어 수동으로 삭제해야 함
echo "Note: DynamoDB table 'terraform-lock' has prevent_destroy enabled."
echo "To delete it, you need to:"
echo "1. Remove the prevent_destroy setting from dynamodb/main.tf"
echo "2. Run: cd dynamodb && terraform init && terraform destroy"

echo "Infrastructure destruction completed (except DynamoDB)."

# 백업 정보 출력
echo "Backup AMI ID: ${AMI_ID}"
echo "Backup AMI Name: ${AMI_NAME}" 