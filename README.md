# 🐍 Python Hello World on EKS Fargate with KEDA Autoscaling

This project demonstrates how to:

* Dockerize a simple Python Flask app
* Push it to Amazon ECR
* Deploy it on an Amazon EKS cluster with Fargate
* Integrate KEDA for CPU-based autoscaling
* Automate everything with shell scripts
* Simulate CPU load to test scaling
* Clean up all resources efficiently

---

## 📁 Folder Structure

```
hello-python-keda/
├── app/
│   ├── main.py                # Python Flask Hello World app
│   └── Dockerfile             # Dockerfile to containerize the app
├── k8s/
│   ├── namespace.yaml         # Namespace definition
│   ├── deployment.yaml        # App deployment (template with placeholder)
│   ├── service.yaml           # LoadBalancer service to expose the app
│   ├── keda-scaler.yaml       # KEDA ScaledObject for autoscaling
│   └── cpu-stress.yaml        # Helper pod to generate external CPU load
├── setup.sh                   # Script to build, deploy, install, and validate everything
├── cleanup.sh                 # Script to destroy everything
└── troubleshoot.md            # Troubleshooting guide
```

---

## 🚀 Prerequisites

Make sure you have the following installed and configured:

* AWS CLI (`aws configure`)
* Docker (with Buildx enabled)
* kubectl
* eksctl
* Helm

---

## 🛠️ Setup Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/ashishah0412/EKS_FARGATE_KEDA.git
cd EKS_FARGATE_KEDA
```

### 2. Run the Setup Script

```bash
chmod +x setup.sh
./setup.sh
```

The script will:

* Build and push the Docker image to Amazon ECR
* Create an EKS cluster with Fargate (if not exists)
* Create namespaces and Fargate profiles
* Deploy the Python app and expose it via LoadBalancer
* Install KEDA and deploy the `ScaledObject`
* Patch and restart metrics-server for Fargate compatibility

---

## 🔁 Making Code Changes and Redeploying

### Step 1: Modify your app code

Edit `app/main.py`, e.g. to change `/` or `/cpu` endpoint behavior.

### Step 2: Rebuild and Push Docker Image to ECR

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=us-east-1
ECR_REPO=hello-python
ECR_URI="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest"

docker buildx build \
  --platform linux/amd64 \
  -t $ECR_URI \
  -f app/Dockerfile ./app \
  --push
```

### Step 3: Restart the Deployment to Pull the Latest Image

```bash
kubectl rollout restart deployment hello-python -n python-app
```

Ensure `imagePullPolicy: Always` is set in `deployment.yaml`.

---

## 🌐 Access the App

After setup completes, you can access the app in two ways:

### 🔹 Option 1: Using LoadBalancer

```bash
kubectl get svc -n python-app
```

Visit the external IP/hostname in your browser.

### 🔹 Option 2: Using Port Forward (local test)

If LoadBalancer IP is not ready or you're testing locally:

```bash
kubectl port-forward -n python-app deployment/hello-python 5000:5000
```

Then access:

```
http://localhost:5000/
```

---

## 📈 Autoscaling with KEDA

This project uses **KEDA's ScaledObject** with **CPU-based scaling**:

* `minReplicaCount: 1`
* `maxReplicaCount: 5`
* Scales based on 50% CPU utilization

### Test Autoscaling

1. Port forward to app:

```bash
kubectl port-forward -n python-app deployment/hello-python 5000:5000
```

2. Simulate CPU load:

```bash
for i in {1..50}; do curl http://localhost:5000/cpu & done
```

3. Watch autoscaling:

```bash
kubectl get hpa -n python-app -w
```

Expect to see replicas increase if CPU > 50%.

4. After load ends, replicas scale back down.

---

## 🧹 Cleanup

To tear down the entire environment:

```bash
chmod +x cleanup.sh
./cleanup.sh
```

This will:

* Delete KEDA resources and namespace
* Uninstall Helm release
* Delete Kubernetes objects and ECR repository
* Destroy the EKS cluster and Fargate profiles

---

## 📘 Resources

* [KEDA Documentation](https://keda.sh/docs/)
* [EKS Fargate](https://docs.aws.amazon.com/eks/latest/userguide/fargate.html)
* [Helm](https://helm.sh/)
* [Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html)

---

## 🧑‍💻 Author

Made with 💻 by Ashish Shah
