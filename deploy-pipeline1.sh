#!/bin/bash
set -eo pipefail

# --- Configuration Variables ---
AWS_ACCOUNT_ID="261358761679"   # Replace with your AWS Account ID
AWS_REGION="us-east-2"           # Replace with your AWS Region (e.g., us-east-2)
EKS_CLUSTER_NAME="hello-keda-cluster"  # Replace with your desired EKS cluster name
ECR_REPO_NAME="hello-keda-app"
IMAGE_TAG="latest"
K8S_NAMESPACE="hello-keda-app"
# External Secrets Version - VERIFY THIS MATCHES YOUR CLUSTER'S COMPATIBILITY!
# Using 0.9.1 if bundle.yaml is available, else use specific file URLs for older versions.
EXTERNAL_SECRETS_VERSION="0.9.1" # Using a version known to have bundle.yaml

# Paths to Kubernetes manifests
NAMESPACE_FILE="k8s/namespace.yml"
DEPLOYMENT_FILE="k8s/deployment.yml"
SERVICE_FILE="k8s/service.yml"
KEDA_SCALER_FILE="k8s/keda-scaler.yml"

# --- ECR Login and Docker Build/Push ---
echo "--- Docker Build and Push to ECR ---"
# Check if ECR repo exists, create if not
aws ecr describe-repositories --repository-names "${ECR_REPO_NAME}" --region "${AWS_REGION}" || \
aws ecr create-repository --repository-name "${ECR_REPO_NAME}" --region "${AWS_REGION}"

# Authenticate Docker to ECR
aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}".dkr.ecr."${AWS_REGION}".amazonaws.com

# Build the Docker image
docker build -t "${ECR_REPO_NAME}":"${IMAGE_TAG}" .

# Tag the image for ECR
docker tag "${ECR_REPO_NAME}":"${IMAGE_TAG}" "${AWS_ACCOUNT_ID}".dkr.ecr."${AWS_REGION}".amazonaws.com/"${ECR_REPO_NAME}":"${IMAGE_TAG}"

# Push the Docker image to ECR
docker push "${AWS_ACCOUNT_ID}".dkr.ecr."${AWS_REGION}".amazonaws.com/"${ECR_REPO_NAME}":"${IMAGE_TAG}"
echo "Docker image pushed to ECR: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:${IMAGE_TAG}"

# --- EKS Cluster Operations ---
echo "--- EKS Cluster Operations ---"
# Update kubeconfig for EKS cluster access
echo "Updating kubeconfig for EKS cluster: ${EKS_CLUSTER_NAME} in region: ${AWS_REGION}"
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${EKS_CLUSTER_NAME}"

# --- Create Namespace ---
echo "Creating namespace '${K8S_NAMESPACE}' if it does not exist..."
kubectl apply -f "${NAMESPACE_FILE}"

# --- Install KEDA Operator ---
echo "--- Installing KEDA CRDs and Operator ---"
# KEDA is generally installed via official Helm chart or direct manifests.
# Using direct apply for simplicity here.
KEDA_VERSION="2.17.2" # Current stable KEDA version, verify this!
kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v${KEDA_VERSION}/keda-${KEDA_VERSION}-crds.yaml
kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v${KEDA_VERSION}/keda-${KEDA_VERSION}-core.yaml

echo "Waiting for KEDA operators to be ready (timeout 5 minutes)..."
kubectl wait --for=condition=Available deployment/keda-operator -n keda --timeout=300s
kubectl wait --for=condition=Available deployment/keda-metrics-apiserver -n keda --timeout=300s
echo "KEDA operators are ready."

# --- Install External-Secrets.io (OPTIONAL for this CPU scaler example, but keeping if you add Pub/Sub later) ---
# If you decide to use Pub/Sub scaling, you'll need External-Secrets to manage GCP credentials.
# For CPU scaling, External-Secrets is NOT required.
# If you DO need External-Secrets, ensure you replace the URL with the correct bundle.yaml or individual files.
# Based on your previous context, you might not have bundle.yaml for your specific version.
# Re-enable this section if you want to integrate external secrets for future use.
# echo "--- Installing External-Secrets.io Operator (if needed) ---"
# EXTERNAL_SECRETS_BUNDLE_URL="https://github.com/external-secrets/external-secrets/releases/download/v${EXTERNAL_SECRETS_VERSION}/bundle.yaml"
#
# echo "Creating namespace 'external-secrets' for the operator..."
# kubectl get ns external-secrets || kubectl create ns external-secrets
#
# echo "Applying External-Secrets.io bundle.yaml from version ${EXTERNAL_SECRETS_VERSION}..."
# # If bundle.yaml isn't available for your version, you'll need to download and patch individual files as previously discussed.
# # For example:
# # curl -LO https://github.com/external-secrets/external-secrets/releases/download/${EXTERNAL_SECRETS_VERSION}/external-secrets-controller-deployment.yaml
# # sed -i '/name: external-secrets/a\        tolerations:\n        - key: "eks.amazonaws.com/compute-type"\n          operator: "Equal"\n          value: "fargate"\n          effect: "NoSchedule"' external-secrets-controller-deployment.yaml
# # kubectl apply -f external-secrets-controller-deployment.yaml -n external-secrets
#
# kubectl apply -f "${EXTERNAL_SECRETS_BUNDLE_URL}" # This line assumes bundle.yaml is available and contains all components
#
# echo "Waiting for external-secrets controller to be ready (timeout 5 minutes)..."
# kubectl wait --for=condition=Available deployment/external-secrets -n external-secrets --timeout=300s
# echo "External-Secrets.io controller is ready."


# --- Deploy Application Resources ---
echo "--- Deploying Hello World Application ---"
# Replace the image placeholder in deployment.yml
sed -i "s|<AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/hello-keda-app:latest|${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:${IMAGE_TAG}|g" "${DEPLOYMENT_FILE}"

kubectl apply -f "${DEPLOYMENT_FILE}"
kubectl apply -f "${SERVICE_FILE}"
kubectl apply -f "${KEDA_SCALER_FILE}"

# --- Verification ---
echo "--- Deployment Status Verification ---"
echo "Deployments in namespace ${K8S_NAMESPACE}:"
kubectl get deployments -n "${K8S_NAMESPACE}"

echo "Services in namespace ${K8S_NAMESPACE}:"
kubectl get services -n "${K8S_NAMESPACE}"

echo "Pods in namespace ${K8S_NAMESPACE}:"
kubectl get pods -n "${K8S_NAMESPACE}"

echo "ScaledObjects in namespace ${K8S_NAMESPACE}:"
kubectl get scaledobject -n "${K8S_NAMESPACE}"

echo "HorizontalPodAutoscalers (HPA) created by KEDA:"
kubectl get hpa -n "${K8S_NAMESPACE}"

echo "Deployment process completed!"
echo "To test: You may need a LoadBalancer or Ingress to access the service externally."
echo "For internal testing from another pod in the cluster: curl hello-keda-app-service:80"