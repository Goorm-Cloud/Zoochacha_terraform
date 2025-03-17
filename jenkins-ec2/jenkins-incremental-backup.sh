#!/bin/bash    # 증분 백업용으로 미리 만들어둠.. 사용할지는 미지수

# 변수 설정
BUCKET_NAME="zoochacha-permanent-store"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/jenkins_backup_${TIMESTAMP}"
CONFIG_DIR="${BACKUP_DIR}/config"
JENKINS_HOME="/var/lib/jenkins"
JENKINS_CLI="/home/ubuntu/jenkins-cli.jar"
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
JENKINS_URL="http://$PRIVATE_IP:8080"  # 테스트 서버는 8081로 변경 필요
JENKINS_USER="zoochacha"
JENKINS_PASSWORD="1111"
HASH_FILE="/var/lib/jenkins/.backup_hash"
LAST_FULL_BACKUP_FILE="/var/lib/jenkins/.last_full_backup"

# 백업 유형 확인 함수
need_full_backup() {
    # 마지막 전체 백업 날짜 확인
    if [ ! -f "$LAST_FULL_BACKUP_FILE" ]; then
        return 0  # 파일이 없으면 전체 백업 필요
    fi
    
    last_backup=$(cat "$LAST_FULL_BACKUP_FILE")
    today=$(date +%Y%m%d)
    
    # 한 달이 지났는지 확인 (100은 대략 한 달)
    if [ $((($today - $last_backup) >= 100)) -eq 1 ]; then
        return 0  # 전체 백업 필요
    fi
    return 1  # 전체 백업 불필요
}

# 설정 파일 변경 확인 함수
config_changed() {
    local file="$1"
    local current_hash=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
    local stored_hash=""
    
    if [ -f "$HASH_FILE" ]; then
        stored_hash=$(grep "^${file}:" "$HASH_FILE" 2>/dev/null | cut -d: -f2)
    fi
    
    if [ "$current_hash" != "$stored_hash" ]; then
        echo "${file}:${current_hash}" >> "$HASH_FILE.tmp"
        return 0  # 변경됨
    fi
    echo "${file}:${stored_hash}" >> "$HASH_FILE.tmp"
    return 1  # 변경 없음
}

# 백업 디렉토리 생성
mkdir -p "${CONFIG_DIR}"

# Jenkins 서비스 상태 확인
if ! systemctl is-active --quiet jenkins; then
    echo "Jenkins is not running. Starting Jenkins..."
    systemctl start jenkins
    sleep 30
fi

if need_full_backup; then
    echo "=== Starting Full Backup ==="
    
    # Jenkins 중지
    systemctl stop jenkins
    
    # 전체 백업
    cd "${JENKINS_HOME}"
    tar -czf "${BACKUP_DIR}/jenkins_full_${TIMESTAMP}.tar.gz" \
        --exclude='*.log' \
        --exclude='*.tmp' \
        --exclude='war' \
        .
    
    # 현재 날짜를 마지막 전체 백업 날짜로 저장
    date +%Y%m%d > "$LAST_FULL_BACKUP_FILE"
    
    # S3에 업로드
    aws s3 cp "${BACKUP_DIR}/jenkins_full_${TIMESTAMP}.tar.gz" \
        "s3://${BUCKET_NAME}/jenkins/backup/full/jenkins_full_${TIMESTAMP}.tar.gz"
    
    # 최신 전체 백업 링크 업데이트
    aws s3 cp "${BACKUP_DIR}/jenkins_full_${TIMESTAMP}.tar.gz" \
        "s3://${BUCKET_NAME}/jenkins/backup/full/latest.tar.gz"
    
    # Jenkins 재시작
    systemctl start jenkins
    
    echo "Full backup completed: s3://${BUCKET_NAME}/jenkins/backup/full/jenkins_full_${TIMESTAMP}.tar.gz"
else
    echo "=== Starting Incremental Backup ==="
    
    # 증분 백업 대상 디렉토리/파일
    BACKUP_TARGETS=(
        # 중요 설정 파일
        "config.xml"
        "credentials.xml"
        "secrets/master.key"
        "secrets/hudson.util.Secret"
        "identity.key.enc"
        "secret.key"
        # Job 관련 파일
        "jobs/*/config.xml"
        "jobs/*/builds/lastSuccessfulBuild"
        "jobs/*/builds/lastStableBuild"
        "jobs/*/workspace"
        # 플러그인 설정
        "plugins/*.jpi"
        "plugins/*.hpi"
        # 사용자 설정
        "users/*/config.xml"
        # Configuration as Code
        "casc_configs/*.yaml"
    )
    
    # 변경된 파일만 백업
    for target in "${BACKUP_TARGETS[@]}"; do
        find "${JENKINS_HOME}" -path "${JENKINS_HOME}/${target}" -type f | while read file; do
            if config_changed "$file"; then
                rel_path=${file#${JENKINS_HOME}/}
                dir_path=$(dirname "${BACKUP_DIR}/${rel_path}")
                mkdir -p "$dir_path"
                cp "$file" "${BACKUP_DIR}/${rel_path}"
            fi
        done
    done
    
    # 플러그인 목록 추출
    echo "Extracting plugin list..."
    curl -s -u "${JENKINS_USER}:${JENKINS_PASSWORD}" "${JENKINS_URL}/pluginManager/api/json?depth=1" | \
        python3 -c "import sys, json; print('\n'.join(p['shortName'] for p in json.load(sys.stdin)['plugins']))" > "${CONFIG_DIR}/plugins.txt" || \
        echo "Failed to extract plugin list"
    
    # 변경된 파일이 있는 경우에만 S3에 업로드
    if [ -n "$(ls -A ${BACKUP_DIR})" ]; then
        cd "${BACKUP_DIR}"
        tar -czf "jenkins_incremental_${TIMESTAMP}.tar.gz" .
        
        aws s3 cp "jenkins_incremental_${TIMESTAMP}.tar.gz" \
            "s3://${BUCKET_NAME}/jenkins/backup/incremental/jenkins_incremental_${TIMESTAMP}.tar.gz"
        
        echo "Incremental backup completed: s3://${BUCKET_NAME}/jenkins/backup/incremental/jenkins_incremental_${TIMESTAMP}.tar.gz"
    else
        echo "No changes detected, skipping incremental backup"
    fi
fi

# 해시 파일 업데이트
if [ -f "$HASH_FILE.tmp" ]; then
    mv "$HASH_FILE.tmp" "$HASH_FILE"
fi

# 임시 디렉토리 정리
rm -rf "${BACKUP_DIR}"

echo "=== Backup process completed! ===" 