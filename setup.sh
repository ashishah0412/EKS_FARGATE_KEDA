#!/bin/bash

set -e

AWS_REGION="us-east-1"
CLUSTER_NAME="hello-keda-cluster"
ECR_REPO="hello-python"
NAMESPACE="python-app"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest"

echo "🔐 1. Checking or creating ECR repo..."
if ! aws ecr describe-repositories --repository-names $ECR_REPO --region $AWS_REGION >/dev/null 2>&1; then
  aws ecr create-repository --repository-name $ECR_REPO --region $AWS_REGION
  echo "✅ ECR repository created: $ECR_REPO"
else
  echo "✅ ECR repository already exists."
fi

echo "🔑 2. Authenticating Docker to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

echo "🔨 3. Preparing Docker buildx..."
docker buildx create --name multiarch-builder --use >/dev/null 2>&1 || docker buildx use multiarch-builder

echo "🐳 4. Building and pushing Docker image for linux/amd64..."
docker buildx build \
  --platform linux/amd64 \
  -t $ECR_URI \
  -f app/Dockerfile \
  ./app \
  --push

echo "☸️ 5. Checking if EKS cluster exists..."
if ! eksctl get cluster --name $CLUSTER_NAME --region $AWS_REGION >/dev/null 2>&1; then
  echo "⏳ Creating EKS Fargate cluster..."
  eksctl create cluster \
    --name $CLUSTER_NAME \
    --region $AWS_REGION \
    --version 1.29 \
    --fargate \
    --without-nodegroup
else
  echo "✅ EKS cluster already exists."
fi

echo "🔗 6. Enabling OIDC provider for cluster..."
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --region $AWS_REGION \
  --approve || echo "⚠️ OIDC might already be associated."

echo "🔍 7. Checking/creating namespace..."
kubectl get ns $NAMESPACE >/dev/null 2>&1 || kubectl create namespace $NAMESPACE

echo "🛡️ 8. Creating Fargate profile for namespace (if not exists)..."
if ! eksctl get fargateprofile --cluster $CLUSTER_NAME --region $AWS_REGION | grep $NAMESPACE >/dev/null 2>&1; then
  eksctl create fargateprofile \
    --cluster $CLUSTER_NAME \
    --region $AWS_REGION \
    --name python-fargate \
    --namespace $NAMESPACE \
    --labels "env=python"
else
  echo "✅ Fargate profile already exists for namespace $NAMESPACE"
fi

echo "📦 9. Installing or upgrading KEDA..."
helm repo add kedacore https://kedacore.github.io/charts || true
helm repo update
helm upgrade --install keda kedacore/keda --namespace keda --create-namespace

echo "📝 10. Preparing final deployment manifest..."
sed "s|<YOUR_ECR_IMAGE_URI>|$ECR_URI|g" k8s/deployment.yaml > k8s/deployment-final.yaml

echo "🚀 11. Deploying app and scaler..."
kubectl apply -f k8s/deployment-final.yaml
kubectl apply -f k8s/keda-scaler.yaml

echo "✅ 12. Verifying pods..."
kubectl get pods -n $NAMESPACE
kubectl get pods -n keda

echo "🌐 To test your app locally, run:"
echo "kubectl port-forward -n $NAMESPACE deployment/hello-python 5000:5000"
echo "curl http://localhost:5000"
