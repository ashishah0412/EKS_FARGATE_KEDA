
# 🐍 Python Hello World on EKS Fargate with KEDA Autoscaling

This project demonstrates how to:
- Dockerize a simple Python Flask app
- Push it to Amazon ECR
- Deploy it on an Amazon EKS cluster with Fargate
- Integrate KEDA for CPU-based autoscaling
- Automate everything with shell scripts
- Clean up all resources efficiently

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
│   └── keda-scaler.yaml       # KEDA ScaledObject for autoscaling
├── setup.sh                   # Script to build, deploy, install, and validate everything
└── cleanup.sh                 # Script to destroy everything
```

---

## 🚀 Prerequisites

Make sure you have the following installed and configured:

- AWS CLI (`aws configure`)
- Docker
- kubectl
- eksctl
- Helm

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

- Build and push the Docker image to Amazon ECR
- Create an EKS cluster with Fargate
- Deploy the Python app and expose it via LoadBalancer
- Install KEDA and create a `ScaledObject`
- Verify all resources are properly deployed

---

## 🌐 Access the App

After setup completes, get the LoadBalancer URL:

```bash
kubectl get svc -n python-app
```

Visit the external IP/hostname in your browser.

---

## 📈 Autoscaling with KEDA

This project uses **KEDA's ScaledObject** with **CPU-based scaling**:

- `minReplicaCount: 1`
- `maxReplicaCount: 5`
- Scales out/in based on 50% CPU utilization

> KEDA uses a Custom Resource Definition (CRD) to extend Kubernetes API.

---

## 🧹 Cleanup

To tear down the entire environment:

```bash
chmod +x cleanup.sh
./cleanup.sh
```

This will:

- Delete KEDA resources
- Uninstall Helm release
- Delete all Kubernetes objects
- Destroy the EKS cluster
- Delete the ECR repository

---

## 📘 Resources

- [KEDA Documentation](https://keda.sh/docs/)
- [EKS Fargate](https://docs.aws.amazon.com/eks/latest/userguide/fargate.html)
- [Helm](https://helm.sh/)
- [Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html)

---

## 🧑‍💻 Author

Made with 💻 by Ashish Shah

