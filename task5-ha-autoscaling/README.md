# Task 5 — High Availability App with Auto Scaling on EKS (HPA + Cluster Autoscaler)

A production-shaped, reproducible deployment of a demo app (`ha-app`) onto Amazon
EKS with **two complementary layers of autoscaling**:

- **HPA (Horizontal Pod Autoscaler)** scales the number of **pods** based on CPU.
- **Cluster Autoscaler (CA)** scales the number of **nodes** when pods can't be
  scheduled.

The cluster is spread across **3 Availability Zones** for high availability.

---

## Architecture

```
                                 Internet
                                    |
                          +---------v---------+
                          |  Service (LB)     |
                          +---------+---------+
                                    |
        ================ EKS Cluster (v1.33, 3 AZs) ================
        |                          |                               |
   +----v----------+       +-------v--------+            +---------v-----+
   |  AZ us-east-1a|       | AZ us-east-1b  |            | AZ us-east-1c |
   | +-----------+ |       | +-----------+  |            | +-----------+ |
   | |  Node     | |       | |  Node     |  |            | |  Node     | |  <- managed
   | | +-------+ | |       | | +-------+ |  |            | | (added by | |     node group
   | | | pod   | | |       | | | pod   | |  |            | |  CA when  | |     min 2 /
   | | | pod   | | |       | | | pod   | |  |            | |  needed)  | |     desired 2 /
   | | +-------+ | |       | | +-------+ |  |            | +-----------+ |     max 6
   | +-----------+ |       | +-----------+  |            +---------------+
   +---------------+       +----------------+
        |                          |
        |    metrics-server  -->  HPA (autoscaling/v2)
        |    watches pod CPU      scales pods 2..10 @ 60% CPU
        |
        +--> Cluster Autoscaler (IRSA role) watches for Pending pods
             and scales the node ASG 2..6 across the 3 AZs.

  Scale-out flow:
    load rises -> pod CPU > 60% -> HPA adds pods -> if no node capacity,
    pods go Pending -> Cluster Autoscaler adds a node -> pods schedule.
```

**How HPA and Cluster Autoscaler complement each other**

| Layer | Watches | Acts on | Bounds |
|-------|---------|---------|--------|
| HPA   | Pod CPU/memory via metrics-server | Deployment replica count | 2 → 10 pods |
| CA    | Unschedulable (Pending) pods      | Node group ASG desired  | 2 → 6 nodes |

HPA reacts first (seconds) by adding pods. When the existing nodes run out of
CPU/memory to place those new pods, the pods sit **Pending**; CA notices and
adds nodes (minutes). On the way down, HPA removes idle pods, then CA removes
nodes that have become empty — always respecting the `min_size` floor of 2 for
HA.

---

## Repository layout

```
task5-ha-autoscaling/
├── terraform/                 # EKS + VPC + ECR + metrics-server + CA (Helm)
│   ├── versions.tf
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── backend.tf.example
├── app/                       # CPU-burnable Node/Express demo app
│   ├── package.json
│   ├── server.js
│   ├── server.test.js
│   ├── Dockerfile
│   └── .dockerignore
├── k8s/
│   ├── namespace.yaml
│   ├── deployment.yaml        # resource requests+limits, probes, securityContext
│   ├── service.yaml
│   ├── hpa.yaml               # CPU 60% / mem 75%, minReplicas 2, maxReplicas 10
│   ├── pdb.yaml               # PodDisruptionBudget: minAvailable 1 through drains
│   ├── load-generator.yaml    # Job that hammers /load to trigger the HPA
│   └── cluster-autoscaler.README.md
├── Jenkinsfile
└── README.md
```

---

## Prerequisites

- Terraform >= 1.5
- AWS CLI v2, authenticated with rights to create VPC/EKS/IAM/ECR
- `kubectl`, `helm`, `docker`
- An AWS account with sufficient EC2 quota for up to 6 `t3.medium` nodes

---

## 1. Provision infrastructure (Terraform)

`terraform apply` creates the VPC, EKS cluster + node group, ECR repo, **and**
installs metrics-server and the cluster-autoscaler via Helm.

```bash
cd terraform
terraform init
terraform plan
terraform apply

# Configure kubectl against the new cluster
$(terraform output -raw kubectl_config_command)

# Handy outputs
terraform output ecr_url
terraform output cluster_autoscaler_role_arn
```

<img width="1222" height="978" alt="image" src="https://github.com/user-attachments/assets/2a4036b7-2e20-43fd-a83f-867557ea0f16" />

<img width="1613" height="915" alt="image" src="https://github.com/user-attachments/assets/33b63878-e701-4dd8-8078-bdc7e2bf8d56" />

<img width="1871" height="957" alt="image" src="https://github.com/user-attachments/assets/384eedc5-51bd-4728-9d84-54e7a13a08b1" />

<img width="1851" height="967" alt="image" src="https://github.com/user-attachments/assets/3cecea64-9b52-40ef-a6eb-818021dcb9da" />

<img width="1792" height="932" alt="image" src="https://github.com/user-attachments/assets/048528a8-ba4b-41e8-94b1-2e3404f8e6d0" />

<img width="1097" height="212" alt="image" src="https://github.com/user-attachments/assets/bb42546d-3787-45c0-b9f2-ab2ce85b6263" />

<img width="1920" height="2088" alt="image" src="https://github.com/user-attachments/assets/e5575e0f-6aac-483f-9c28-e6e2f4bc04f1" />

> Remote state: copy `backend.tf.example` to `backend.tf` and fill in your S3
> bucket + DynamoDB lock table before `terraform init` for team/CI use.

Verify the autoscaling controllers are running:

```bash
kubectl -n kube-system get deploy cluster-autoscaler-aws-cluster-autoscaler
kubectl top nodes           # confirms metrics-server is serving metrics
```

<img width="905" height="251" alt="image" src="https://github.com/user-attachments/assets/393c0aec-6a56-4a00-8338-895a349ec85a" />

---

## 2. Build & push the image

```bash
ECR_URL=$(cd terraform && terraform output -raw ecr_url)
AWS_REGION=us-east-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

cd app
docker build -t ${ECR_URL}:latest .
docker push ${ECR_URL}:latest
```

<img width="1918" height="977" alt="image" src="https://github.com/user-attachments/assets/5dfbba1b-98e6-46ae-b090-787e34b49050" />

<img width="1918" height="917" alt="image" src="https://github.com/user-attachments/assets/2bea13f0-147a-4e48-8061-bb4e1e9749f1" />

(In CI this is done automatically by the `Jenkinsfile`, tagging with the git SHA.)

---

## 3. Deploy the app + HPA

```bash
kubectl apply -f k8s/namespace.yaml

# Substitute the real image, then apply the deployment
sed "s|<ECR_URL>:latest|${ECR_URL}:latest|g" k8s/deployment.yaml | kubectl apply -f -

kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml
kubectl apply -f k8s/pdb.yaml

kubectl -n ha-app rollout status deployment/ha-app
kubectl -n ha-app get hpa ha-app
```

<img width="1041" height="488" alt="image" src="https://github.com/user-attachments/assets/a3784810-3a09-426e-872b-2a11ab076e89" />

---

## 4. HOW TO DEMONSTRATE scaling

Open three terminals to watch the two autoscaling layers react:

```bash
# Terminal 1 - HPA + pods (pod-level scaling)
kubectl -n ha-app get hpa ha-app -w

# Terminal 2 - pods
kubectl -n ha-app get pods -w

# Terminal 3 - nodes (cluster-level scaling)
kubectl get nodes -w
```

Now generate load:

```bash
kubectl apply -f k8s/load-generator.yaml
```

<img width="1918" height="1015" alt="image" src="https://github.com/user-attachments/assets/e01365b1-6572-44b7-b48a-12befdc49d92" />

<img width="1918" height="1003" alt="image" src="https://github.com/user-attachments/assets/809dbd59-f9c9-4e23-8c4e-d0cf86f6f883" />

What you should observe:

1. Within ~30–60s the HPA `TARGETS` column climbs past `60%` and `REPLICAS`
   starts increasing toward `maxReplicas: 10`.
2. As pods multiply, some may become **Pending** (no room on the 2 initial
   nodes). Watch the Cluster Autoscaler logs:
   ```bash
   kubectl -n kube-system logs -l app.kubernetes.io/name=aws-cluster-autoscaler -f
   ```
3. New **nodes** appear in Terminal 3 (up to `max_size: 6`), the Pending pods
   schedule, and CPU per pod drops back under 60%.

Stop the load and watch it scale back in:

<img width="1058" height="200" alt="image" src="https://github.com/user-attachments/assets/13aa5640-f0c5-470b-b043-53e15bad1b4c" />

<img width="1918" height="411" alt="image" src="https://github.com/user-attachments/assets/2137dd4f-a4ca-413a-9a38-85c581043ca8" />

```bash
kubectl -n ha-app delete job ha-app-load
# HPA scales pods down after its scaleDown stabilization window (5 min),
# then CA removes now-empty nodes after ~10 min, never below 2 nodes.
```
<img width="998" height="170" alt="image" src="https://github.com/user-attachments/assets/5653c5d5-815b-46ca-81ee-eb60222bd858" />

<img width="1027" height="198" alt="image" src="https://github.com/user-attachments/assets/0c2580a6-b136-4607-b011-6db525ee1063" />

---

## Design notes

- **Scalability** — two independent, bounded autoscalers (pods 2→10, nodes 2→6)
  handle load spikes automatically; `behavior` policies make scale-up fast and
  scale-down conservative to avoid flapping.
- **Resource efficiency** — explicit CPU/memory **requests** let the scheduler
  bin-pack pods and let the HPA compute utilization accurately; CA reclaims idle
  nodes so you don't pay for unused capacity.
- **Reliability / HA** — 3-AZ VPC, node group across 3 AZs, `min_size = 2`,
  pod `topologySpreadConstraints` across zones and hosts, and liveness/readiness
  probes.
- **Security** — non-root container (built-in `node` user), `readOnlyRootFilesystem`,
  `allowPrivilegeEscalation: false`, all Linux capabilities dropped,
  `seccompProfile: RuntimeDefault`; least-privilege IAM via IRSA (the autoscaler
  role is scoped to its service account through OIDC); ECR scan-on-push.

---

## CI/CD (Jenkins)

`Jenkinsfile` (declarative) runs: **Checkout → Build → Test → ECR login + push
(git-sha tag) → Update kubeconfig → Deploy (apply deployment/service/hpa) →
Verify rollout → Show HPA**. Configure an `aws-creds` credential (or run the
agent on an IRSA/instance role) with ECR + EKS permissions.

<img width="1920" height="1372" alt="image" src="https://github.com/user-attachments/assets/a98e23c9-f12e-4745-8bb9-a25094fd22d0" />

<img width="1920" height="3682" alt="image" src="https://github.com/user-attachments/assets/d89fc0e8-0301-4cff-982e-1479963eddec" />

<img width="1497" height="775" alt="image" src="https://github.com/user-attachments/assets/c2c7a360-5501-470f-818f-320ac5be226a" />

<img width="1920" height="13915" alt="image" src="https://github.com/user-attachments/assets/11d70b09-e78e-4e8b-b4b7-84c959ec37ab" />


<img width="1920" height="1127" alt="image" src="https://github.com/user-attachments/assets/6c55afe6-e197-4ff3-b1a6-884fbe152311" />

---

## Teardown

```bash
# Remove app workloads first
kubectl -n ha-app delete job ha-app-load --ignore-not-found
kubectl delete -f k8s/hpa.yaml -f k8s/pdb.yaml -f k8s/service.yaml --ignore-not-found
kubectl -n ha-app delete deployment ha-app --ignore-not-found
kubectl delete -f k8s/namespace.yaml --ignore-not-found

# Then destroy the infrastructure (this also removes the Helm releases,
# node group, cluster, VPC and ECR repo)
cd terraform
terraform destroy
```

<img width="1365" height="332" alt="image" src="https://github.com/user-attachments/assets/2b508e92-fc3f-4c7f-b072-e5e929334eb0" />

<img width="1892" height="547" alt="image" src="https://github.com/user-attachments/assets/e2b4d9ad-899b-42a0-bc0d-776a428c4eaf" />

<img width="1918" height="982" alt="image" src="https://github.com/user-attachments/assets/ab5ebdbb-ec4d-423d-8a48-4148099485b7" />

<img width="1897" height="512" alt="image" src="https://github.com/user-attachments/assets/11b45ba7-531f-402c-9358-ced47efd0cc9" />



> If the LoadBalancer Service was created, ensure it is deleted (above) before
> `terraform destroy` so the ELB and its ENIs don't block VPC deletion.
