# Troubleshooting Guide: Fixing KEDA CPU-Based Autoscaling in EKS Fargate

This guide documents the complete troubleshooting steps used to fix KEDA-based CPU autoscaling issues on an AWS EKS Fargate cluster with a Python application.

---

## 🚨 Problem Statement

Even after setting up KEDA and deploying the Python app, the HPA status remained:

```bash
<unknown>/50%
```

and the application did not scale out despite high CPU usage.

---

## ✅ Final Working Outcome

Once fixed, the HPA reported:

```
keda-hpa-hello-python-scaler   Deployment/hello-python   237%/50%   1   5   5
```

---

## 🔍 Key Issues Identified & Resolutions

### 1. **Missing CPU Resource Requests**

**Error:**

```yaml
the HPA was unable to compute the replica count: failed to get cpu utilization: missing request for cpu
```

**Fix:** Add `resources.requests.cpu` and `resources.limits` to your deployment YAML:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "64Mi"
  limits:
    cpu: "500m"
    memory: "128Mi"
```

---

### 2. **metrics-server Installed But Not Functional on Fargate**

**Symptoms:**

* `metrics-server` pods in `Pending` state
* No output from `kubectl top pods`

**Fixes:**

* Ensure a Fargate profile exists for the `kube-system` namespace
* Patch metrics-server to run on Fargate:

```bash
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[{
    "op": "add",
    "path": "/spec/template/spec/tolerations",
    "value": [{
      "key": "eks.amazonaws.com/compute-type",
      "operator": "Equal",
      "value": "fargate",
      "effect": "NoSchedule"
    }]
  }]'

kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[{
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--kubelet-insecure-tls"
  }]'

kubectl rollout restart deployment metrics-server -n kube-system
```

---

### 3. **No CPU Usage Being Generated on Monitored Pods**

**Fix:** Add `/cpu` endpoint in Flask app to simulate CPU load:

```python
@app.route("/cpu")
def cpu_burn():
    import time
    start = time.time()
    while time.time() - start < 10:
        pass
    return "CPU load generated"
```

Test with:

```bash
for i in {1..20}; do curl http://localhost:5000/cpu & done
```

---

### 4. **KEDA HPA Not Reacting**

Check with:

```bash
kubectl get hpa -n python-app -w
```

Make sure:

* KEDA `ScaledObject` is using `type: cpu`
* CPU request is defined
* `metrics-server` is reporting pod usage

---

## ✅ Verifications

* `kubectl top pods -n python-app` returns values
* `kubectl get hpa -n python-app` shows CPU usage over threshold
* `kubectl get pods -n python-app` shows scaled replicas

---

## 🔁 Recommended Setup Checks

* `imagePullPolicy: Always`
* `resources.requests.cpu` and `memory` defined
* `metrics-server` tolerations and insecure TLS patch applied
* Fargate profiles exist for: `kube-system`, `keda`, and `python-app`
* Use `rollout restart` or reapply deployment after pushing new image

---

## 📌 Useful Commands

```bash
kubectl top pods -n python-app
kubectl get hpa -n python-app -w
kubectl rollout restart deployment hello-python -n python-app
kubectl get deployment metrics-server -n kube-system
kubectl get fargateprofile --cluster <CLUSTER_NAME>
```

---

## 🎉 Result

KEDA autoscaling works in EKS Fargate based on CPU usage. Scaling from 1 → 5 pods was validated with CPU stress testing.

---

