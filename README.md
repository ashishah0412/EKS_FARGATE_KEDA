# Hello KEDA Fargate Application

This repository contains a simple "Hello World" Flask application, Dockerized, and set up for deployment on AWS EKS Fargate with KEDA for CPU-based auto-scaling.

## Folder Structure:

* `app/`: Contains the Python Flask application and its dependencies.
* `k8s/`: Contains Kubernetes manifest files for deployment.
* `Dockerfile`: Defines how to build the Docker image for the application.
* `deploy-pipeline.sh`: A shell script to automate the entire deployment process (Docker build/push to ECR, EKS cluster kubeconfig update, KEDA deployment, and application deployment).

## Prerequisites:

1.  **AWS Account:** With necessary permissions for EKS, ECR, IAM.
2.  **AWS CLI:** Configured with your AWS credentials.
3.  **kubectl:** Kubernetes command-line tool.
4.  **Docker:** Docker installed and running on your local machine or CI/CD runner.
5.  **An EKS Cluster:** You need an existing EKS cluster configured with a Fargate profile that matches the `hello-keda-app` namespace.

    **Creating an EKS Cluster with Fargate (if you don't have one):**
    You can create an EKS cluster with a Fargate profile using `eksctl`.
    ```bash
    eksctl create cluster \
      --name hello-keda-cluster \
      --region <YOUR_AWS_REGION> \
      --fargate \
      --profile-name hello-keda-fargate-profile \
      --fargate-profile-selector namespace=hello-keda-app,labels={app=hello-keda-app}
    ```
    This command will create a cluster and a Fargate profile that will automatically schedule pods in the `hello-keda-app` namespace (with label `app=hello-keda-app`) onto Fargate.

    **Note on ECR Image Pull for Fargate:**
    Fargate pods pull images using the IAM role associated with the Fargate profile. Ensure the Fargate profile's execution role has `ecr:GetDownloadUrlForLayer`, `ecr:BatchGetImage`, `ecr:BatchCheckLayerAvailability` permissions for your ECR repository.

## Deployment Steps:

1.  **Configure `deploy-pipeline.sh`:**
    * Open `deploy-pipeline.sh`.
    * Replace `<YOUR_AWS_ACCOUNT_ID>` with your actual AWS Account ID.
    * Replace `<YOUR_AWS_REGION>` with your desired AWS region (e.g., `us-east-2`).
    * Ensure `EKS_CLUSTER_NAME` matches your EKS cluster's name.

2.  **Make the script executable:**
    ```bash
    chmod +x deploy-pipeline.sh
    ```

3.  **Run the deployment script:**
    ```bash
    ./deploy-pipeline.sh
    ```

## Post-Deployment:

* **Check Pod Status:**
    ```bash
    kubectl get pods -n hello-keda-app
    ```
    You should see your `hello-keda-app-deployment` pod in a `Running` state.
* **Check KEDA ScaledObject Status:**
    ```bash
    kubectl get scaledobject -n hello-keda-app
    ```
    It should show a healthy status and reflect the desired replica counts.
* **Access the Application (Internal):**
    If you have another pod in the same cluster, you can `curl` the service:
    ```bash
    kubectl run -it --rm --restart=Never debug-pod --image=busybox -- /bin/sh
    # Inside the debug pod:
    / # wget -O - hello-keda-app-service:80
    ```
* **Access the Application (External - requires LoadBalancer/Ingress):**
    For external access, you would typically modify `k8s/service.yml` to `type: LoadBalancer` or set up an Ingress Controller (like AWS Load Balancer Controller) and Ingress resource. This is beyond the scope of this basic "Hello World" setup but is the next logical step for web apps.

## Cleaning Up:

To remove the deployed application:

```bash
kubectl delete -f k8s/keda-scaler.yml -n hello-keda-app
kubectl delete -f k8s/service.yml -n hello-keda-app
kubectl delete -f k8s/deployment.yml -n hello-keda-app
kubectl delete -f k8s/namespace.yml # This will delete the namespace and all resources within it