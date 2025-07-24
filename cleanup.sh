#!/bin/bash

set -e

AWS_REGION="us-east-1"
CLUSTER_NAME="hello-keda-cluster"
ECR_REPO="hello-python"
NAMESPACE="python-app"

# 1. Delete app and scaler
echo "1. Deleting application deployment and scaler..."
kubectl delete -f k8s/deployment-final.yaml || true
kubectl delete -f k8s/keda-scaler.yaml || true

# 2. Uninstall KEDA
echo "2. Uninstalling KEDA..."
helm uninstall keda -n keda || true
kubectl delete namespace keda --grace-period=0 --force || true

# Force remove finalizers if namespace is stuck
echo "🧼 Checking for stuck KEDA namespace..."
if kubectl get ns keda -o json 2>/dev/null | grep -q '"keda"'; then
  echo "⚠️  KEDA namespace may be stuck, attempting to remove finalizers..."
  kubectl get namespace keda -o json | jq '.spec.finalizers=[]' | kubectl replace --raw "/api/v1/namespaces/keda/finalize" -f - || true
fi

echo "⏳ Waiting for KEDA namespace to fully delete..."
timeout 60s bash -c 'until ! kubectl get ns keda &>/dev/null; do sleep 5; done' \
  && echo "✅ KEDA namespace deleted." \
  || echo "⚠️ KEDA namespace still terminating. Manual cleanup may be required."

# 3. Delete Fargate profile
echo "3. Deleting Fargate profile..."
if eksctl get fargateprofile --cluster $CLUSTER_NAME --region $AWS_REGION | grep $NAMESPACE >/dev/null 2>&1; then
  eksctl delete fargateprofile \
    --cluster $CLUSTER_NAME \
    --region $AWS_REGION \
    --name python-fargate
  echo "✅ Fargate profile deleted."
else
  echo "✅ No Fargate profile found for $NAMESPACE."
fi

# 4. Delete namespace
echo "4. Deleting Python app namespace..."
kubectl delete namespace $NAMESPACE --grace-period=0 --force || true

# Force remove finalizers if namespace is stuck
echo "🧼 Checking for stuck python-app namespace..."
if kubectl get ns $NAMESPACE -o json 2>/dev/null | grep -q "$NAMESPACE"; then
  echo "⚠️  $NAMESPACE namespace may be stuck, attempting to remove finalizers..."
  kubectl get namespace $NAMESPACE -o json | jq '.spec.finalizers=[]' | kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f - || true
fi

echo "⏳ Waiting for $NAMESPACE namespace to fully delete..."
timeout 60s bash -c "until ! kubectl get ns $NAMESPACE &>/dev/null; do sleep 5; done" \
  && echo "✅ Namespace $NAMESPACE deleted." \
  || echo "⚠️ Namespace $NAMESPACE still terminating. Manual cleanup may be required."

# 5. Delete EKS Cluster
echo "5. Deleting EKS Cluster..."
eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION || true

# 6. Delete ECR repo
echo "6. Deleting ECR repository..."
aws ecr delete-repository --repository-name $ECR_REPO --region $AWS_REGION --force || true

echo "🧹 Cleanup completed. Some manual cleanup may be required if namespaces were stuck."
