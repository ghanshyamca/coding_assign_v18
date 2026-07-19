# DevOps on AWS EKS — Assignment Monorepo

Five self-contained DevOps deliverables, each provisioning AWS infrastructure with
**Terraform**, containerizing an app with **Docker**, automating delivery with a
**Jenkins** pipeline, and deploying to **Amazon EKS** with Kubernetes manifests or Helm.

Every task lives in its own directory and is fully independent — you can `cd` into any
one of them and follow its README end to end without touching the others.

| # | Task | Focus | Deploy method | Directory |
|---|------|-------|---------------|-----------|
| 1 | Flask app on EKS with CI/CD | Baseline build → test → deploy | K8s manifests | [task1-flask-eks-cicd/](task1-flask-eks-cicd/) |
| 2 | Blue-Green Node.js deployment | Zero-downtime cutover & rollback | Helm charts | [task2-bluegreen-node-helm/](task2-bluegreen-node-helm/) |
| 3 | Multi-environment microservices | dev/staging/prod segregation & promotion | Terraform workspaces + Kustomize | [task3-multienv-microservices/](task3-multienv-microservices/) |
| 4 | Full-stack React + Node | One shared pipeline, shared infra | K8s manifests + reused module | [task4-fullstack-react-node/](task4-fullstack-react-node/) |
| 5 | HA app with auto-scaling | HPA (pods) + Cluster Autoscaler (nodes) | K8s manifests + HPA | [task5-ha-autoscaling/](task5-ha-autoscaling/) |

---

## Repository layout

```
coding_assign_v18/
├── README.md                     # this index
├── .gitignore
├── task1-flask-eks-cicd/         # Terraform + Dockerfile + Jenkinsfile + k8s/
├── task2-bluegreen-node-helm/    # Terraform + Helm charts + Jenkinsfile
├── task3-multienv-microservices/ # Terraform workspaces + Kustomize + Jenkinsfile
├── task4-fullstack-react-node/   # Terraform (reused ECR module) + Jenkinsfile + k8s/
└── task5-ha-autoscaling/         # Terraform (Cluster Autoscaler + metrics-server) + HPA
```

Each task directory contains its own `README.md` with step-by-step setup, a
`terraform/` folder, a `Jenkinsfile`, and the application source.

---

## Shared prerequisites

Install and configure these once; all five tasks reuse them.

| Tool | Version | Purpose |
|------|---------|---------|
| [AWS CLI](https://docs.aws.amazon.com/cli/) | v2 | Auth, ECR login, `aws eks update-kubeconfig` |
| [Terraform](https://developer.hashicorp.com/terraform/downloads) | ≥ 1.5 | Provision VPC / EKS / ECR |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | ≥ 1.29 | Deploy & inspect workloads |
| [Docker](https://docs.docker.com/get-docker/) | ≥ 24 | Build images |
| [Helm](https://helm.sh/docs/intro/install/) | ≥ 3.12 | Tasks 2 & 5 |
| [Jenkins](https://www.jenkins.io/) | ≥ 2.4 LTS | CI/CD (with Docker, Kubernetes CLI, AWS Credentials plugins) |

```bash
# Authenticate to AWS (any method: SSO, access keys, assumed role)
aws configure                 # or: aws sso login
aws sts get-caller-identity   # confirm you're authenticated
```

> **Cost warning:** each task provisions a real EKS cluster, NAT gateway, and node
> group. These incur AWS charges while running. Every task README ends with a
> **Teardown** section — run `terraform destroy` when you are done to avoid a bill.

---

## Conventions used across all tasks

These practices are applied consistently so the tasks read as one body of work:

- **Terraform** — pinned provider versions (`aws ~> 5.0`), official
  `terraform-aws-modules/{vpc,eks}` modules for reproducibility, a thin local ECR
  module, common resource tags via `locals`, and a commented `backend.tf.example`
  showing S3 + DynamoDB remote state.
- **Docker** — multi-stage builds on pinned slim/alpine bases, a non-root runtime
  user, a `HEALTHCHECK`, and a `.dockerignore`.
- **Kubernetes** — resource **requests and limits**, liveness/readiness probes, and a
  hardened `securityContext` (`runAsNonRoot`, dropped capabilities, read-only root
  filesystem where the app allows).
- **Jenkins** — declarative pipelines, immutable image tags derived from the Git commit
  SHA, ECR login via `aws ecr get-login-password`, and `kubectl rollout status`
  verification. Required credentials/plugins are documented in each `Jenkinsfile`.
- **CI/CD image promotion** — the *same* image built once is promoted across stages;
  environments never rebuild from source (see tasks 2 and 3).

---

## Quick start (any task)

```bash
cd task1-flask-eks-cicd          # pick a task

# 1. Provision infrastructure
cd terraform
terraform init
terraform apply                  # creates VPC, EKS, ECR

# 2. Point kubectl at the new cluster (command is a Terraform output)
aws eks update-kubeconfig --region us-east-1 --name <cluster_name>

# 3. Build & push the image, then deploy — see the task README for exact commands.
#    In practice the Jenkins pipeline (Jenkinsfile) does steps 2–3 automatically.

# 4. When finished
cd terraform && terraform destroy
```

See each task's `README.md` for the complete, task-specific walkthrough.
