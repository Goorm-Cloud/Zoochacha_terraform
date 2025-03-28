#!/bin/bash

# 에러 발생시 스크립트 중단
set -e

echo "🚀 Starting infrastructure destruction..."

# 1. Helm releases 삭제
echo "📦 Removing Helm releases..."
helm uninstall zoochacha-manifest -n zoochacha || true
helm uninstall ingress-nginx -n ingress-nginx || true
sleep 5

# 2. Kubernetes 리소스 정리
echo "🧹 Cleaning up Kubernetes resources..."
kubectl delete namespace zoochacha || true
kubectl delete namespace argocd || true
kubectl delete namespace ingress-nginx || true
kubectl delete clusterrole zoochacha-installer || true
kubectl delete clusterrolebinding zoochacha-installer || true
kubectl delete serviceaccount zoochacha-installer -A || true
kubectl delete crd applications.argoproj.io || true
kubectl delete crd applicationsets.argoproj.io || true
kubectl delete crd appprojects.argoproj.io || true
sleep 5

# 3. Terraform 모듈 삭제 (역순)
echo "🏗️  Removing Terraform modules..."

# zoochacha-basic-infra 삭제
echo "Removing zoochacha-basic-infra..."
cd zoochacha-basic-infra
terraform destroy -auto-approve -lock=false
cd ..

# log-monitoring 삭제
echo "Removing log-monitoring..."
cd log-monitoring
terraform destroy -auto-approve -lock=false -var="elastic_password=temp1234"
cd ..

# jenkins-ec2 삭제
echo "Removing jenkins-ec2..."
cd jenkins-ec2
terraform destroy -auto-approve -lock=false -var="pub_sub1_id=$(cd ../vpc && terraform output -raw public_subnet_1_id)"
cd ..

# eks 삭제
echo "Removing EKS cluster..."
cd eks
terraform destroy -auto-approve -lock=false
cd ..

# vpc 삭제
echo "Removing VPC..."
cd vpc
terraform destroy -auto-approve -lock=false
cd ..

echo "✅ Infrastructure destruction completed!" 