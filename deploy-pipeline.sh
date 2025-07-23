#!/bin/bash
set -eo pipefail

# --- Configuration Variables ---
AWS_ACCOUNT_ID="261358761679"   # Replace with your AWS Account ID
AWS_REGION="us-east-2"           # Replace with your AWS Region (e.g., us-east-2)
EKS_CLUSTER_NAME="hello-keda-cluster"  # Replace with your actual EKS cluster name
ECR_REPO_NAME="hello-keda-app"
IMAGE_TAG="latest"
K8S_NAMESPACE="hello-keda-app" # The namespace for your application
KEDA_VERSION="2.17.2" # KEDA version, VERIFY THIS!
EXTERNAL_SECRETS_VERSION="0.7.1" # External Secrets version, VERIFY THIS! (Using 0.7.1 for separate files)

# Paths to Kubernetes manifests
NAMESPACE_FILE="k8s/namespace.yml"
DEPLOYMENT_FILE="k8s/deployment.yml"
SERVICE_FILE="k8s/service.yml"
KEDA_SCALER_FILE="k8s/keda-scaler.yml"

# URLs for External Secrets (based on v0.7.1 for individual files)
EXTERNAL_SECRETS_CRD_URL="https://github.com/external-secrets/external-secrets/releases/download/v${EXTERNAL_SECRETS_VERSION}/external-secrets-crd.yaml"
EXTERNAL_SECRETS_RBAC_URL="https://github.com/external-secrets/external-secrets/releases/download/v${EXTERNAL_SECRETS_VERSION}/external-secrets-rbac.yaml"
EXTERNAL_SECRETS_CONTROLLER_DEPLOYMENT_URL="https://github.com/external-secrets/external-secrets/releases/download/v${EXTERNAL_SECRETS_VERSION}/external-secrets-controller-deployment.yaml"
EXTERNAL_SECRETS_WEBHOOK_DEPLOYMENT_URL="https://github.com/external-secrets/external-secrets/releases/download/v${EXTERNAL_SECRETS_VERSION}/external-secrets-webhook-deployment.yaml"


# --- ECR Login and Docker Build/Push ---
echo "--- Docker Build and Push to ECR ---"
# Check if ECR repo exists, create if not
aws ecr describe-repositories --repository-names "${ECR_REPO_NAME}" --region "${AWS_REGION}" || \
  aws ecr create-repository --repository-name "${ECR_REPO_NAME}" --region "${AWS_REGION}"

# Authenticate Docker to ECR
aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}".dkr.ecr."${AWS_REGION}".amazonaws.com

# Build the Docker image (assuming Dockerfile is in the root of the context)
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

# --- Create Application Namespace ---
echo "Creating namespace '${K8S_NAMESPACE}' if it does not exist..."
kubectl apply -f "${NAMESPACE_FILE}"

# --- Install KEDA Operator ---
echo "--- Installing KEDA CRDs and Operator ---"
KEDA_CRDS_URL="https://github.com/kedacore/keda/releases/download/v${KEDA_VERSION}/keda-${KEDA_VERSION}-crds.yaml"
KEDA_CORE_URL="https://github.com/kedacore/keda/releases/download/v${KEDA_VERSION}/keda-${KEDA_VERSION}-core.yaml"
KEDA_CORE_FILE="keda-${KEDA_VERSION}-core.yaml" # Local filename

echo "Creating namespace 'keda' for KEDA operator if it does not exist..."
kubectl get namespace keda || kubectl create namespace keda

# Apply KEDA CRDs
echo "Applying KEDA CRDs..."
kubectl apply --server-side -f "${KEDA_CRDS_URL}"

# Download KEDA core manifest
echo "Downloading KEDA core manifest..."
curl -LO "${KEDA_CORE_URL}"

# Inject Fargate toleration into KEDA deployments using yq
echo "Injecting Fargate toleration into KEDA operator deployments using yq..."
# yq select all documents that are Deployments, then add the toleration to their pod spec
# .metadata.name must be 'keda-operator' OR 'keda-metrics-apiserver'
# The toleration block is appended to the 'tolerations' array within 'spec.template.spec'
yq e '
  (select(.kind == "Deployment" and (.metadata.name == "keda-operator" or .metadata.name == "keda-metrics-apiserver")) | .spec.template.spec.tolerations) =
    (select(.kind == "Deployment" and (.metadata.name == "keda-operator" or .metadata.name == "keda-metrics-apiserver")) | .spec.template.spec.tolerations | . + [{"key": "eks.amazonaws.com/compute-type", "operator": "Equal", "value": "fargate", "effect": "NoSchedule"}])
' -i "${KEDA_CORE_FILE}"

# Apply the modified KEDA core manifest
echo "Applying KEDA core manifest with tolerations..."
kubectl apply --server-side -f "${KEDA_CORE_FILE}"

echo "Waiting for KEDA operators to be ready (timeout 5 minutes)..."
kubectl wait --for=condition=Available deployment/keda-operator -n keda --timeout=300s
kubectl wait --for=condition=Available deployment/keda-metrics-apiserver -n keda --timeout=300s
echo "KEDA operators are ready."


# --- Install External-Secrets.io Operator (Only if you intend to use it, e.g., for GCP Pub/Sub secrets) ---
# NOTE: This section is commented out by default for a simple CPU scaler.
# Uncomment and configure if you proceed with GCP Pub/Sub triggers later.
# If uncommented, ensure your KEDA ScaledObject uses the correct SecretStore/ExternalSecret setup.
# echo "--- Installing External-Secrets.io Operator ---"
# echo "Creating namespace 'external-secrets' for the operator if it does not exist..."
# kubectl get ns external-secrets || kubectl create ns external-secrets
#
# echo "Applying External-Secrets.io CRDs..."
# kubectl apply -f "${EXTERNAL_SECRETS_CRD_URL}"
#
# echo "Applying External-Secrets.io RBAC..."
# kubectl apply -f "${EXTERNAL_SECRETS_RBAC_URL}"
#
# # Download and Modify the controller deployment to add Fargate toleration
# # Note: External Secrets often comes in separate deployment files for controller and webhook.
# # You'll need to apply yq to each downloaded file.
#
# # Controller Deployment
# echo "Downloading External-Secrets.io Controller Deployment..."
# curl -LO "${EXTERNAL_SECRETS_CONTROLLER_DEPLOYMENT_URL}"
#
# echo "Injecting Fargate toleration into external-secrets controller deployment using yq..."
# yq e '.spec.template.spec.tolerations += [{"key": "eks.amazonaws.com/compute-type", "operator": "Equal", "value": "fargate", "effect": "NoSchedule"}]' -i "external-secrets-controller-deployment.yaml"
#
# echo "Applying External-Secrets.io Controller Deployment with toleration..."
# kubectl apply -f external-secrets-controller-deployment.yaml -n external-secrets
#
# # Webhook Deployment
# echo "Downloading External-Secrets.io Webhook Deployment..."
# curl -LO "${EXTERNAL_SECRETS_WEBHOOK_DEPLOYMENT_URL}"
#
# echo "Injecting Fargate toleration into external-secrets webhook deployment using yq..."
# yq e '.spec.template.spec.tolerations += [{"key": "eks.amazonaws.com/compute-type", "operator": "Equal", "value": "fargate", "effect": "NoSchedule"}]' -i "external-secrets-webhook-deployment.yaml"
#
# echo "Applying External-Secrets.io Webhook Deployment with toleration..."
# kubectl apply -f external-secrets-webhook-deployment.yaml -n external-secrets
#
# echo "Waiting for external-secrets controller to be ready (timeout 5 minutes)..."
# kubectl wait --for=condition=Available deployment/external-secrets -n external-secrets --timeout=300s
# echo "External-Secrets.io controller is ready."

# --- Deploy Application Resources ---
echo "--- Deploying Hello World Application ---"
# Dynamically update the image in deployment.yml
# This part still uses sed, but it's a simple find/replace on one line, less prone to issues.
TEMP_DEPLOYMENT_FILE=$(mktemp)
sed "s|<AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/hello-keda-app:latest|${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:${IMAGE_TAG}|g" "${DEPLOYMENT_FILE}" > "${TEMP_DEPLOYMENT_FILE}"

kubectl apply -f "${TEMP_DEPLOYMENT_FILE}"
rm "${TEMP_DEPLOYMENT_FILE}" # Clean up temporary file

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