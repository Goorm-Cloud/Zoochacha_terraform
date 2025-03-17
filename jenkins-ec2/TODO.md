# Jenkins 운영 환경 마이그레이션 TODO

## SSH 키 변경
- [ ] `zoochacha-test-jenkins-server.pem` → `zoochacha-jenkins-server.pem`로 변경
- [ ] 모든 provisioner의 private_key 경로 업데이트
- [ ] 새 키 파일 권한 설정 (chmod 600)

## 포트 설정
- [ ] Jenkins 웹 포트: 8081 → 8080
- [ ] JNLP 에이전트 포트: 50001 → 50000
- [ ] 보안 그룹 인바운드 규칙 업데이트

## 인프라 설정 검토
- [ ] 인스턴스 타입 적절성 검토
- [ ] EBS 볼륨 크기 검토
- [ ] 백업 보관 기간 정책 검토

## 보안 설정
- [ ] Jenkins 관리자 비밀번호 정책 검토
- [ ] IAM 역할 권한 범위 검토
- [ ] 보안 그룹 접근 제한 검토

## 파일 수정 필요 위치
1. `main.tf`의 provisioner 블록들
2. `user_data` 스크립트 내 포트 설정
3. 보안 그룹 인바운드 규칙

## 주의사항
- 운영 환경 마이그레이션 전 반드시 현재 설정 백업
- 키 페어는 AWS 콘솔에서 미리 생성 필요
- 운영 환경 배포 전 테스트 환경에서 충분한 검증 필요 