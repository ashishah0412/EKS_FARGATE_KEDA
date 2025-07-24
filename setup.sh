#!/bin/bash
set -e

APP_NAME="hello-python"
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="$APP_NAME"
CLUSTER_NAME="hello-keda-cluster"
NAMESPACE="python-app"

echo "1. Creating ECR Repo..."
aws ecr create-repository --repository-name $ECR_REPO --region $AWS_REGION || true

echo "2. Building Docker Image..."
docker build -t $APP_NAME ./app

echo "3. Tagging and Pushing Image to ECR..."
docker tag $APP_NAME:latest $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO

echo "4. Creating EKS Cluster with Fargate..."
eksctl create cluster \
  --name $CLUSTER_NAME \
  --region $AWS_REGION \
  --fargate \
  --version 1.29 \
  --fargate-profile-name fargate-profile \
  --without-nodegroup

echo "5. Creating Namespace for App..."
kubectl apply -f k8s/namespace.yaml

echo "6. Creating Fargate Profile (auto done by eksctl), verifying..."
kubectl get fargateprofiles -n kube-system

echo "7. Replacing ECR image URI in deployment..."
sed "s|<YOUR_ECR_IMAGE_URI>|$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO|g" k8s/deployment.yaml > k8s/deployment-final.yaml

echo "8. Deploying Python App..."
kubectl apply -f k8s/deployment-final.yaml
kubectl apply -f k8s/service.yaml

echo "9. Installing KEDA..."
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda --namespace keda --create-namespace

echo "10. Deploying KEDA ScaledObject..."
kubectl apply -f k8s/keda-scaler.yaml

echo "✅ Setup Complete. Use 'kubectl get svc -n $NAMESPACE' to find LoadBalancer URL."
