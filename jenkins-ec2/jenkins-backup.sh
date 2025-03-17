#!/bin/bash

# 변수 설정
BUCKET_NAME="zoochacha-permanent-store"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/jenkins_backup_${TIMESTAMP}"
CONFIG_DIR="${BACKUP_DIR}/config"
JENKINS_HOME="/var/lib/jenkins"
JENKINS_CLI="/home/ubuntu/jenkins-cli.jar"
JENKINS_URL="http://localhost:8080"
JENKINS_USER="zoochacha"
JENKINS_PASSWORD="1111"  
SOURCE_JENKINS_YAML="/home/ubuntu/jenkins.yaml"

# 백업 디렉토리 생성
mkdir -p "${CONFIG_DIR}"
mkdir -p "${CONFIG_DIR}/secrets"

# Jenkins 서비스 상태 확인
if ! systemctl is-active --quiet jenkins; then
    echo "Jenkins is not running. Please start Jenkins first."
    exit 1
fi

echo "=== Starting Jenkins Backup Process ==="

# 중요 파일 존재 여부 확인
IMPORTANT_FILES=(
    "config.xml"
    "credentials.xml"
    "secrets/master.key"
    "secrets/hudson.util.Secret"
    "identity.key"
    "secret.key"
    "secrets/identity.key"
    "secret.key.not-so-secret"
)

echo "Checking important files..."
for file in "${IMPORTANT_FILES[@]}"; do
    if [ ! -f "${JENKINS_HOME}/${file}" ]; then
        echo "Warning: ${file} not found!"
    else
        echo "Found: ${file}"
        # 발견된 파일은 즉시 백업
        dir=$(dirname "${CONFIG_DIR}/${file}")
        mkdir -p "${dir}"
        sudo cp "${JENKINS_HOME}/${file}" "${CONFIG_DIR}/${file}"
        echo "Immediately backed up: ${file}"
    fi
done

# 1. Jenkins 전체 백업 (workspace와 builds 포함)
echo "Backing up Jenkins home directory..."
cd "${JENKINS_HOME}"
sudo tar -czf "${BACKUP_DIR}/jenkins_home.tar.gz" \
    --exclude='*.log' \
    --exclude='*.tmp' \
    --exclude='war' \
    $(find . -name "config.xml") \
    $(find . -name "credentials.xml") \
    $(find . -name "*.xml") \
    $(find . -name "identity.key") \
    $(find . -name "*.key") \
    $(find . -name "hudson.util.Secret") \
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
curl -s -u "${JENKINS_USER}:${JENKINS_PASSWORD}" "http://43.200.208.61:8080/pluginManager/api/json?depth=1" | \
    python3 -c "import sys, json; print('\n'.join(p['shortName'] for p in json.load(sys.stdin)['plugins']))" > "${CONFIG_DIR}/plugins.txt" || \
    echo "Failed to extract plugin list"

# 3. Configuration as Code 설정 백업
echo "Backing up CasC configuration..."
if [ -f "${JENKINS_HOME}/casc_configs/jenkins.yaml" ]; then
    sudo cp "${JENKINS_HOME}/casc_configs/jenkins.yaml" "${CONFIG_DIR}/jenkins.yaml"
fi

# 소스 코드의 jenkins.yaml 백업
if [ -f "${SOURCE_JENKINS_YAML}" ]; then
    sudo cp "${SOURCE_JENKINS_YAML}" "${CONFIG_DIR}/jenkins.yaml.source"
fi

# 4. 중요 설정 파일 개별 백업
echo "Backing up critical configuration files..."
CRITICAL_CONFIGS=(
    "config.xml"
    "credentials.xml"
    "hudson.model.UpdateCenter.xml"
    "jenkins.telemetry.Correlator.xml"
    "nodeMonitors.xml"
    "jenkins.model.JenkinsLocationConfiguration.xml"
    "hudson.plugins.git.GitTool.xml"
    "hudson.plugins.emailext.ExtendedEmailPublisher.xml"
    "identity.key"
    "secret.key"
    "secret.key.not-so-secret"
)

for file in "${CRITICAL_CONFIGS[@]}"; do
    if [ -f "${JENKINS_HOME}/${file}" ]; then
        dir=$(dirname "${CONFIG_DIR}/${file}")
        mkdir -p "${dir}"
        sudo cp "${JENKINS_HOME}/${file}" "${CONFIG_DIR}/${file}"
        echo "Copied ${file} to backup"
    else
        echo "Warning: Could not find ${file} for backup"
    fi
done

# 5. Job 설정 파일 백업
echo "Backing up job configurations..."
for job in "reservation_service" "zoochacha-admin-service-pipeline" "zoochacha-reservation-detail-service-pipeline"; do
    if [ -d "${JENKINS_HOME}/jobs/${job}" ]; then
        sudo mkdir -p "${CONFIG_DIR}/jobs/${job}"
        sudo cp "${JENKINS_HOME}/jobs/${job}/config.xml" "${CONFIG_DIR}/jobs/${job}/" 2>/dev/null || true
        # lastSuccessfulBuild와 lastStableBuild 정보 백업
        if [ -d "${JENKINS_HOME}/jobs/${job}/builds" ]; then
            sudo mkdir -p "${CONFIG_DIR}/jobs/${job}/builds"
            sudo cp -r "${JENKINS_HOME}/jobs/${job}/builds/lastSuccessfulBuild" "${CONFIG_DIR}/jobs/${job}/builds/" 2>/dev/null || true
            sudo cp -r "${JENKINS_HOME}/jobs/${job}/builds/lastStableBuild" "${CONFIG_DIR}/jobs/${job}/builds/" 2>/dev/null || true
        fi
    fi
done

# 6. 보안 관련 파일 백업
echo "Backing up security-related files..."
sudo mkdir -p "${CONFIG_DIR}/secrets"
if [ -d "${JENKINS_HOME}/secrets" ]; then
    # 전체 secrets 디렉토리 복사
    sudo cp -r "${JENKINS_HOME}/secrets"/* "${CONFIG_DIR}/secrets/" 2>/dev/null || true
    
    # 중요 파일 개별 확인 및 백업
    SECURITY_FILES=(
        "master.key"
        "hudson.util.Secret"
        "identity.key"
        "initialAdminPassword"
        "jenkins.model.Jenkins.crumbSalt"
    )
    
    for file in "${SECURITY_FILES[@]}"; do
        if [ -f "${JENKINS_HOME}/secrets/${file}" ]; then
            sudo cp "${JENKINS_HOME}/secrets/${file}" "${CONFIG_DIR}/secrets/"
            echo "Copied secrets/${file} to backup"
        else
            echo "Warning: Could not find secrets/${file} for backup"
        fi
    done
    
    # 루트 디렉토리의 identity.key도 확인
    if [ -f "${JENKINS_HOME}/identity.key" ]; then
        sudo cp "${JENKINS_HOME}/identity.key" "${CONFIG_DIR}/"
        echo "Copied identity.key from root directory to backup"
    fi
    
    # 루트 디렉토리의 secret.key도 확인
    if [ -f "${JENKINS_HOME}/secret.key" ]; then
        sudo cp "${JENKINS_HOME}/secret.key" "${CONFIG_DIR}/"
        echo "Copied secret.key from root directory to backup"
    fi
    
    # 루트 디렉토리의 secret.key.not-so-secret도 확인
    if [ -f "${JENKINS_HOME}/secret.key.not-so-secret" ]; then
        sudo cp "${JENKINS_HOME}/secret.key.not-so-secret" "${CONFIG_DIR}/"
        echo "Copied secret.key.not-so-secret from root directory to backup"
    fi
fi

# 7. 사용자 설정 백업
echo "Backing up user configurations..."
if [ -d "${JENKINS_HOME}/users" ]; then
    sudo cp -r "${JENKINS_HOME}/users" "${CONFIG_DIR}/"
    echo "Copied users directory to backup"
fi

# 8. credentials.xml 파일 특별 처리
echo "Checking for credentials.xml..."
if [ -f "${JENKINS_HOME}/credentials.xml" ]; then
    sudo cp "${JENKINS_HOME}/credentials.xml" "${CONFIG_DIR}/"
    echo "Copied credentials.xml to backup"
else
    # credentials.xml 파일 찾기
    CRED_FILES=$(sudo find "${JENKINS_HOME}" -name "credentials.xml" 2>/dev/null)
    if [ -n "${CRED_FILES}" ]; then
        for cred_file in ${CRED_FILES}; do
            rel_path=${cred_file#${JENKINS_HOME}/}
            dir=$(dirname "${CONFIG_DIR}/${rel_path}")
            mkdir -p "${dir}"
            sudo cp "${cred_file}" "${CONFIG_DIR}/${rel_path}"
            echo "Copied ${rel_path} to backup"
        done
    else
        echo "Warning: No credentials.xml files found in Jenkins home"
    fi
fi

# 9. 설정 파일들을 하나의 압축 파일로 만들기
echo "Creating backup archive..."
cd "${BACKUP_DIR}"
sudo tar -czf "jenkins_backup_${TIMESTAMP}.tar.gz" ./*

# 10. S3로 업로드
echo "Uploading to S3..."
# 통합된 백업 파일 업로드
if sudo aws s3 cp "${BACKUP_DIR}/jenkins_backup_${TIMESTAMP}.tar.gz" \
    "s3://${BUCKET_NAME}/jenkins/backup_config/jenkins_backup_${TIMESTAMP}.tar.gz"; then
    echo "Successfully uploaded backup to S3"
    
    # 최신 백업 링크 업데이트
    sudo aws s3 cp "${BACKUP_DIR}/jenkins_backup_${TIMESTAMP}.tar.gz" \
        "s3://${BUCKET_NAME}/jenkins/backup_config/latest.tar.gz"
else
    echo "Failed to upload backup to S3"
    exit 1
fi

# 11. 백업 파일 검증
echo "Verifying backup integrity..."
sudo aws s3 ls "s3://${BUCKET_NAME}/jenkins/backup_config/jenkins_backup_${TIMESTAMP}.tar.gz" || {
    echo "Backup verification failed!"
    exit 1
}

# 12. 임시 디렉토리 정리
echo "Cleaning up temporary files..."
sudo rm -rf "${BACKUP_DIR}"

echo "=== Backup completed successfully! ==="
echo "Timestamp: ${TIMESTAMP}"
echo "Backup location:"
echo "- Backup: s3://${BUCKET_NAME}/jenkins/backup_config/jenkins_backup_${TIMESTAMP}.tar.gz"

# 백업 파일 목록 출력
echo -e "\nBacked up files:"
aws s3 ls "s3://${BUCKET_NAME}/jenkins/backup_config/jenkins_backup_${TIMESTAMP}.tar.gz" 