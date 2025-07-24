#!/bin/bash
set -e

APP_NAME="hello-python"
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CLUSTER_NAME="hello-keda-cluster"
NAMESPACE="python-app"

echo "1. Deleting KEDA Scaler..."
kubectl delete -f k8s/keda-scaler.yaml || true

echo "2. Uninstalling KEDA..."
helm uninstall keda -n keda || true
kubectl delete ns keda || true

echo "3. Deleting App Resources..."
kubectl delete -f k8s/deployment-final.yaml || true
kubectl delete -f k8s/service.yaml || true
kubectl delete ns $NAMESPACE || true

echo "4. Deleting EKS Cluster..."
eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION

echo "5. Deleting ECR Repo..."
aws ecr delete-repository --repository-name $APP_NAME --force --region $AWS_REGION

echo "✅ Cleanup Complete."
