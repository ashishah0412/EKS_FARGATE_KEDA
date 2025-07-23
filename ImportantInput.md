## How Correct Fargate Profiles Solve the "No Nodes Available" Issue

The core problem for your KEDA pods was that **AWS EKS Fargate had no instructions to provision compute resources for pods in the `keda` namespace.**

---

### Fargate Profiles Instruct the EKS Scheduler 🎯

EKS Fargate doesn't run just any pod; it operates on a "Fargate profile" model. A **Fargate profile** acts like a rule that tells the EKS scheduler: "If a pod matches *these* criteria (e.g., in the `keda` namespace or with specific labels), then provision and schedule it onto Fargate compute."

When your Fargate profile was only selecting `hello-keda-app`, any pod in the `keda` namespace (like `keda-operator` or `keda-metrics-apiserver`) was essentially ignored by the Fargate provisioning system. The Kubernetes `default-scheduler` would then try to find a traditional EC2 node for these pods. Since your cluster is designed to run these on Fargate and likely has no dedicated EC2 nodes for them, the scheduler would conclude: "No nodes available to schedule pods."

---

### Tolerations Allow Pods to Run on Fargate ✅

Fargate nodes (the underlying compute provided by AWS when a Fargate profile matches) apply a **taint** to themselves: `eks.amazonaws.com/compute-type: fargate`. This taint is like a "do not schedule here unless you specifically allow it" flag.

By adding **tolerations** to your KEDA deployment manifests (which we did using `yq`), you are telling the KEDA pods: "It's okay to run on nodes with the `eks.amazonaws.com/compute-type: fargate` taint." However, a toleration alone doesn't *cause* a pod to be scheduled on Fargate; it only *permits* it. The Fargate profile is what *initiates* the Fargate compute.

---

### The Solution: Profile + Toleration Harmony 🤝

When you successfully establish a Fargate profile that includes the `keda` namespace (either by adding `keda` to an existing profile or by creating a dedicated `keda-fargate-profile`), EKS now knows: "Ah, pods in the `keda` namespace should go to Fargate."

When the KEDA pods are then launched (or re-launched after deletion), the EKS scheduler sees:
* "This pod is in the `keda` namespace, which is covered by a Fargate profile."
* "This pod also has the necessary toleration to run on a Fargate node."

This combination triggers Fargate to provision the necessary serverless compute, and the KEDA pods will transition from `Pending` to `Running` as their Fargate "nodes" become available.