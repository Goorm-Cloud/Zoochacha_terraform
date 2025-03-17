#!/bin/bash

function check_error() {
    if [ $? -ne 0 ]; then
        echo "Error: $1"
        exit 1
    fi
}

function wait_for_jenkins() {
    local jenkins_url="http://$1:8081"
    echo "Waiting for Jenkins to be available at $jenkins_url..."
    while ! curl -s -f "$jenkins_url" > /dev/null; do
        echo -n "."
        sleep 5
    done
    echo "Jenkins is available!"
}

case "$1" in
    "apply")
        # 1. 현재 디렉토리가 test-env인지 확인
        if [[ $(basename $(pwd)) != "test-env" ]]; then
            echo "Error: Please run this script from the test-env directory"
            exit 1
        fi

        # 2. 다른 테라폼 상태 파일 변경 방지
        export TF_WORKSPACE="test"

        # 3. 테라폼 초기화 및 적용
        terraform init
        check_error "Terraform initialization failed"

        terraform plan -out=tfplan
        check_error "Terraform plan failed"

        terraform apply tfplan
        check_error "Terraform apply failed"

        # 4. Jenkins URL 출력
        JENKINS_URL=$(terraform output -raw jenkins_test_url)
        echo "Jenkins test server is available at: $JENKINS_URL"
        
        # 5. Jenkins 서비스 대기
        JENKINS_IP=$(terraform output -raw jenkins_test_public_ip)
        wait_for_jenkins $JENKINS_IP
        ;;

    "destroy")
        # 1. 현재 디렉토리 확인
        if [[ $(basename $(pwd)) != "test-env" ]]; then
            echo "Error: Please run this script from the test-env directory"
            exit 1
        fi

        # 2. 다른 테라폼 상태 파일 변경 방지
        export TF_WORKSPACE="test"

        # 3. 테라폼 destroy 실행
        terraform destroy -auto-approve
        check_error "Terraform destroy failed"

        # 4. S3 백업 확인
        echo "Checking latest backup in S3..."
        aws s3 ls s3://zoochacha-permanent-store/jenkins/backup_config/latest.tar.gz

        echo "Usage: $0 {apply|destroy}"
        echo "  apply   - Create test Jenkins server"
        echo "  destroy - Destroy test Jenkins server and verify backup"
        exit 1
        ;;
esac 