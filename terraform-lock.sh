#!/bin/bash

LOCK_FILE=".terraform-lock"

# 이미 실행 중인지 확인
if [ -f "$LOCK_FILE" ]; then
    pid=$(cat "$LOCK_FILE")
    if ps -p "$pid" > /dev/null; then
        echo "에러: Terraform이 이미 실행 중입니다 (PID: $pid)"
        exit 1
    else
        # 프로세스가 없다면 오래된 잠금 파일 제거
        rm "$LOCK_FILE"
    fi
fi

# 현재 프로세스 ID로 잠금 파일 생성
echo $$ > "$LOCK_FILE"

# 종료 시 잠금 파일 제거
trap 'rm -f "$LOCK_FILE"' EXIT

# Terraform 명령어 실행
terraform "$@" 