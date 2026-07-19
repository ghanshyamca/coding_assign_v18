# Task 1 — Deploy a Python Flask App to AWS EKS using CI/CD

A production-shaped reference implementation that provisions AWS infrastructure
with Terraform, containerizes a Flask app, and ships it to Amazon EKS through a
Jenkins CI/CD pipeline.

Base name used consistently across Terraform, Jenkins, and Kubernetes:
**`flask-eks`**.

---

## Overview

- **App**: minimal Flask service (`GET /`, `GET /health`) served by gunicorn.
- **Infra (Terraform)**: VPC (3 AZs, public+private subnets, single NAT), EKS
  1.29 with a managed node group (t3.medium, 2–4 nodes, IRSA + OIDC), and an
  ECR repository (scan-on-push, keep last 10 images).
- **CI/CD (Jenkins)**: checkout → build → test → push to ECR → deploy to EKS →
  verify rollout.
- **Kubernetes**: namespace, service account, hardened deployment (2 replicas,
  probes, non-root, read-only rootfs, dropped caps), ClusterIP service, and an
  optional ALB ingress.

---

## Architecture

```
                          ┌─────────────────────────────────────────────┐
   git push               │                  AWS (us-east-1)             │
  ┌────────┐   webhook    │                                             │
  │  Repo  │ ───────────► │   ┌──────────┐        ┌──────────────────┐  │
  └────────┘              │   │ Jenkins  │ build  │      ECR         │  │
                          │   │  agent   │ ─────► │  flask-eks repo  │  │
                          │   └────┬─────┘  push  └────────┬─────────┘  │
                          │        │ kubectl               │ pull       │
                          │        ▼                       ▼            │
                          │   ┌─────────────────────────────────────┐  │
                          │   │            EKS cluster              │  │
                          │   │  ┌───────────── VPC ─────────────┐  │  │
                          │   │  │ private subnets (3 AZs)       │  │  │
                          │   │  │   ┌─────────┐  ┌─────────┐    │  │  │
                          │   │  │   │ node 1  │  │ node 2  │    │  │  │
                          │   │  │   │ pod x2  │  │ pod x2  │    │  │  │
                          │   │  │   └─────────┘  └─────────┘    │  │  │
                          │   │  └───────────────────────────────┘  │  │
                          │   │        ClusterIP Service            │  │
                          │   │        (opt. ALB Ingress)           │  │
                          │   └─────────────────────────────────────┘  │
                          └─────────────────────────────────────────────┘
```

---

## Repository layout

```
task1-flask-eks-cicd/
├── app/
│   ├── app.py                 # Flask app (/ and /health)
│   ├── requirements.txt       # pinned deps (flask, gunicorn, pytest)
│   └── tests/test_app.py      # pytest suite
├── k8s/
│   ├── namespace.yaml
│   ├── serviceaccount.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml           # optional AWS ALB ingress
├── terraform/
│   ├── main.tf                # VPC + EKS (official modules) + ECR (local module)
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   ├── backend.tf.example     # S3 + DynamoDB remote state (example)
│   └── modules/ecr/           # thin ECR module
├── Dockerfile                 # multi-stage, non-root, gunicorn
├── .dockerignore
├── Jenkinsfile                # declarative CI/CD pipeline
└── README.md
```

---

## Prerequisites

| Tool        | Version (min) | Purpose                         |
|-------------|---------------|---------------------------------|
| AWS CLI     | v2            | auth, ECR login, EKS kubeconfig |
| Terraform   | >= 1.5        | provision infrastructure        |
| kubectl     | >= 1.29       | deploy to the cluster           |
| Docker      | >= 24         | build/run the image             |
| Jenkins     | LTS           | run the CI/CD pipeline          |

An AWS account with permissions for VPC, EKS, EC2, IAM, and ECR is required.
Configure credentials via `aws configure` (or an instance profile).

---

## Step-by-step

### 1. Provision infrastructure (Terraform)

```bash
cd terraform

# (Optional) enable remote state: copy backend.tf.example -> backend.tf and edit.
terraform init
terraform plan
terraform apply        # ~15-20 min for EKS to come up
```

Capture the outputs:

```bash
terraform output ecr_repository_url
terraform output -raw configure_kubectl
```

### 2. Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name flask-eks
kubectl get nodes
```

### 3. Build and push the image (manual first push)

```bash
cd ..            # task root
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY=${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com
IMAGE=${REGISTRY}/flask-eks

aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin ${REGISTRY}

docker build --build-arg APP_VERSION=v1 -t ${IMAGE}:v1 -t ${IMAGE}:latest .
docker push ${IMAGE}:v1
docker push ${IMAGE}:latest
```

### 4. Deploy to Kubernetes

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/serviceaccount.yaml
kubectl apply -f k8s/service.yaml

# Substitute the image and version placeholders, then apply the deployment:
sed -e "s#REGISTRY/REPO:TAG#${IMAGE}:v1#" \
    -e "s#APP_VERSION_PLACEHOLDER#v1#" \
    k8s/deployment.yaml | kubectl apply -f -

kubectl -n flask-eks rollout status deployment/flask-eks
```

---

## How CI/CD works (Jenkins)

The `Jenkinsfile` defines a declarative pipeline with these stages:

1. **Checkout** — pulls the repo, resolves the short git SHA and AWS account id.
2. **Build** — `docker build` tags the image with the SHA and `latest`.
3. **Test** — runs `pytest` inside a container built from the image.
4. **Login to ECR** — `aws ecr get-login-password | docker login`.
5. **Push** — pushes `:<sha>` and `:latest` to ECR.
6. **Update kubeconfig** — `aws eks update-kubeconfig`.
7. **Deploy** — `kubectl apply` for base manifests + `kubectl set image` to roll
   the new tag.
8. **Verify rollout** — `kubectl rollout status` and lists pods.

A `post{}` block cleans up local images and reports success/failure.

**Environment** (`environment{}` block): `AWS_REGION`, `ECR_REPO`,
`CLUSTER_NAME`, `K8S_NAMESPACE`, `IMAGE_TAG`.

**Required Jenkins setup**: Docker Pipeline, AWS Credentials, and Git plugins;
`docker`, `aws` (v2), and `kubectl` on the agent; an `aws-credentials` entry or
an EC2 agent with an IAM role allowed to push to ECR and call `eks:*`. The
Jenkins IAM principal must also be mapped into the cluster (Terraform sets
`enable_cluster_creator_admin_permissions`; add the Jenkins role to
`aws-auth`/EKS access entries if it differs from the creator).

---

## How to access the app

**ClusterIP (default) via port-forward:**

```bash
kubectl -n flask-eks port-forward svc/flask-eks 8080:80
curl http://localhost:8080/
curl http://localhost:8080/health
```

**Public access via ALB ingress (optional):** install the AWS Load Balancer
Controller, then `kubectl apply -f k8s/ingress.yaml` and use the address from
`kubectl -n flask-eks get ingress flask-eks`.

Alternatively, change the Service `type` to `LoadBalancer` for a quick ELB.

---

## Security best practices used

- **Container**: multi-stage build, pinned `python:3.12-slim` base, non-root
  user (uid/gid 1000), `HEALTHCHECK`, minimal packages.
- **Kubernetes**: `runAsNonRoot`, `readOnlyRootFilesystem`, `drop: [ALL]`
  capabilities, `allowPrivilegeEscalation: false`, `RuntimeDefault` seccomp,
  resource requests/limits, liveness + readiness probes.
- **AWS**: ECR scan-on-push + AES256 encryption + lifecycle retention; EKS with
  IRSA/OIDC enabled — wire an IAM role to the ServiceAccount annotation in
  `k8s/serviceaccount.yaml` to give pods scoped IAM instead of the node role;
  private node subnets with a single NAT egress; endpoint public+private access.
- **State**: example S3 backend with versioning and DynamoDB locking.

---

## Teardown

```bash
# Remove Kubernetes resources (and any ALB created by the ingress).
kubectl delete -f k8s/ingress.yaml --ignore-not-found
kubectl delete namespace flask-eks --ignore-not-found

# Destroy all AWS infrastructure. ECR repo uses force_delete so images go too.
cd terraform
terraform destroy
```

> Delete any LoadBalancer/ALB before `terraform destroy` so no ENIs block VPC
> deletion. Confirm the ECR repository and CloudWatch log groups are gone to
> avoid lingering charges.
