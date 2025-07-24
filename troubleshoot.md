# Troubleshooting Guide: Python App on EKS Fargate with KEDA

This guide consolidates the most common issues and their resolutions encountered while deploying a Python Docker app to AWS EKS Fargate with KEDA autoscaling using `setup.sh`.

---

## 🐳 Docker Image / ECR Issues

### ❌ Error: `no match for platform in manifest: not found`

**Cause:** The Docker image pushed to ECR doesn't support the platform required by EKS Fargate.

**Fix:**

* Ensure the image is built specifically for `linux/amd64` using Docker Buildx:

  ```bash
  docker buildx build --platform linux/amd64 -t <ecr-uri>:latest --push .
  ```
* Rebuild and push the image:

  ```bash
  ./setup.sh  # will build with linux/amd64
  ```

---

## 🧩 Kubernetes Deployment Issues

### ❌ Error: `ImagePullBackOff` or `Failed to pull image`

**Cause:** The EKS pod lacks permission to pull image from ECR.

**Fix:**

1. Attach the `AmazonEC2ContainerRegistryReadOnly` policy to the Fargate pod execution role.
2. Confirm OIDC is enabled using:

   ```bash
   eksctl utils associate-iam-oidc-provider --cluster <name> --region <region> --approve
   ```
3. Re-deploy the pod:

   ```bash
   kubectl delete pod -n <namespace> <pod-name>
   kubectl apply -f k8s/deployment-final.yaml
   ```

---

## ⚙️ EKS Cluster Setup

### ❌ Error: `unknown flag: --fargate-profile-name`

**Cause:** Invalid flag passed to `eksctl create cluster`

**Fix:**

* Do **not** use `--fargate-profile-name`. Fargate profile is created later using:

  ```bash
  eksctl create fargateprofile --cluster <cluster> --namespace <namespace> --name <profile-name>
  ```

### ❗ Warning: `recommended policies found for "vpc-cni" addon, but OIDC is disabled`

**Cause:** OIDC provider not enabled for EKS cluster.

**Fix:**

```bash
eksctl utils associate-iam-oidc-provider --cluster <cluster> --region <region> --approve
```

---

## 🔍 Resource Validation

### ❌ Error: `error: the server doesn't have a resource type "fargateprofiles"`

**Cause:** Incorrect resource type used with `kubectl get`.

**Fix:**
Use `eksctl get fargateprofile` instead:

```bash
eksctl get fargateprofile --cluster <cluster-name> --region <region>
```

---

## 🚀 Runtime Verification

### ✅ How to test deployed Python app on EKS

```bash
kubectl port-forward -n python-app deployment/hello-python 5000:5000
curl http://localhost:5000
```

---

## 💡 General Tips

* Always verify Docker image architecture matches target platform (`linux/amd64` for Fargate).
* Use `helm upgrade --install` for idempotent KEDA setup.
* Validate pod status:

  ```bash
  kubectl get pods -n python-app
  kubectl describe pod -n python-app <pod-name>
  kubectl logs -n python-app <pod-name>
  ```
* Confirm KEDA pods are running in `keda` namespace:

  ```bash
  kubectl get pods -n keda
  ```

---


