# Task 4 — Full-stack React + Node.js on EKS (Shared CI/CD)

A React (Vite) frontend and a Node.js (Express) backend, deployed to a single
Amazon EKS cluster through **one shared Jenkins pipeline** that builds, pushes,
and rolls out **both** services. Container images live in two ECR repositories
provisioned from a **single reusable Terraform module** invoked twice.

## Architecture

```
                    ┌──────────────────────── Shared ECR ────────────────────────┐
                    │  fullstack-frontend repo        fullstack-backend repo       │
                    └───────▲─────────────────────────────────▲────────────────────┘
                            │ push (git sha tag)              │ push (git sha tag)
                            │                                 │
                    ┌───────┴─────────────────────────────────┴───────┐
                    │           Jenkins  (ONE shared pipeline)         │
                    │  checkout → build+test (‖) → push (‖) → deploy   │
                    └───────────────────────┬─────────────────────────┘
                                            │ kubectl apply / set image
                                            ▼
        Internet ──▶ ALB Ingress ──▶ ┌──────────────── EKS (ns: fullstack) ───────────────┐
                                     │                                                      │
                                     │  frontend Deployment (nginx:8080)                    │
                                     │      │  serves SPA + proxies /api/*                   │
                                     │      ▼                                                │
                                     │  backend Service (ClusterIP:3001) ─▶ backend Pods     │
                                     │      GET /api/health, GET /api/message                │
                                     └──────────────────────────────────────────────────────┘
```

- The **frontend** is served by nginx. Requests to `/api/*` are reverse-proxied
  in-cluster to the backend Service DNS name
  `fullstack-backend.fullstack.svc.cluster.local:3001`, so the browser only ever
  talks to the frontend origin (no CORS needed).
- Both images come from the **same ECR registry** — demonstrating shared infra.

## Repository layout

```
task4-fullstack-react-node/
├── backend/            Express API + Dockerfile + jest test
├── frontend/           React (Vite) app + nginx Dockerfile + nginx.conf
├── k8s/                namespace, deployments, services, ingress
├── terraform/          VPC + EKS + 2x ECR (reused module)
│   └── modules/ecr/    reusable ECR module (called twice)
├── Jenkinsfile         shared pipeline building BOTH services
└── README.md
```

## Prerequisites

- AWS account + credentials with permissions for EKS, EC2/VPC, ECR, IAM
- Terraform >= 1.5, AWS CLI v2, kubectl, Docker, Node.js 20
- (For ingress) AWS Load Balancer Controller installed in the cluster

## 1. Provision infrastructure (Terraform)

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Key outputs:

```bash
terraform output cluster_name
terraform output frontend_ecr_repository_url
terraform output backend_ecr_repository_url
terraform output configure_kubectl   # ready-to-run aws eks update-kubeconfig
```

`modules/ecr` is invoked twice (`module.ecr_frontend`, `module.ecr_backend`) to
create both repositories with identical policy (scan-on-push, keep last 10
images) — this is the "infrastructure sharing and modularity" requirement.

Remote state: copy `backend.tf.example` to `backend.tf` and fill in your
S3 bucket + DynamoDB lock table, then `terraform init -migrate-state`.

## 2. Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name $(terraform -chdir=terraform output -raw cluster_name)
```

## 3. Build & push both images (manual, or let Jenkins do it)

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
REGISTRY=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com
TAG=$(git rev-parse --short HEAD)

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REGISTRY

# Backend
docker build -t $REGISTRY/fullstack-backend:$TAG backend/
docker push $REGISTRY/fullstack-backend:$TAG

# Frontend
docker build -t $REGISTRY/fullstack-frontend:$TAG frontend/
docker push $REGISTRY/fullstack-frontend:$TAG
```

## 4. Deploy to EKS

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/backend-deployment.yaml -f k8s/backend-service.yaml
kubectl apply -f k8s/frontend-deployment.yaml -f k8s/frontend-service.yaml
kubectl apply -f k8s/ingress.yaml

# Point the deployments at your pushed images (replace REGISTRY/TAG):
kubectl -n fullstack set image deployment/fullstack-backend  backend=$REGISTRY/fullstack-backend:$TAG
kubectl -n fullstack set image deployment/fullstack-frontend frontend=$REGISTRY/fullstack-frontend:$TAG

kubectl -n fullstack rollout status deployment/fullstack-backend
kubectl -n fullstack rollout status deployment/fullstack-frontend
```

The manifests ship with `REGISTRY/…:TAG` placeholders so `kubectl apply`
followed by `set image` (exactly what the pipeline does) is the intended flow.

## 5. The shared Jenkins pipeline

`Jenkinsfile` is a single declarative pipeline that handles **both** services:

1. **Checkout**
2. **Build & Test** — `parallel` stages for backend (jest) and frontend
   (vitest + `vite build`)
3. **ECR Login**
4. **Docker Build & Push** — `parallel` stages build and push both images,
   tagged with the short git sha
5. **Configure kubectl** — `aws eks update-kubeconfig`
6. **Deploy to EKS** — `kubectl apply` the manifests, then `set image` for both
   deployments to the new sha tag
7. **Verify Rollouts** — `kubectl rollout status` for both deployments

`environment {}` centralises region, cluster name, and both ECR repo names.
Credentials used: `aws-credentials` (access key/secret) and `aws-account-id`.
Plugins: Docker Pipeline, Kubernetes CLI / kubectl on the agent, AWS CLI v2.

## How the frontend reaches the backend

- **In-cluster (prod):** nginx in the frontend image reverse-proxies `/api/*` to
  `fullstack-backend.fullstack.svc.cluster.local:3001` (see `frontend/nginx.conf`).
  The React app calls the relative path `/api/message` (`VITE_API_BASE` empty).
- **Local dev:** `vite.config.js` proxies `/api` to `http://localhost:3001`.

## Accessing the app

```bash
# Via the ALB ingress:
kubectl -n fullstack get ingress fullstack-ingress
# open the ADDRESS in a browser

# Or port-forward the frontend Service without an ingress:
kubectl -n fullstack port-forward svc/fullstack-frontend 8080:80
# then browse http://localhost:8080
```

You should see the page render the string returned by `GET /api/message`.

## Security notes

- Images are multi-stage and run as **non-root** (`node` uid 1000 / `nginx`
  uid 101). Pods set `runAsNonRoot`, `readOnlyRootFilesystem`,
  `allowPrivilegeEscalation: false`, drop all capabilities, and use the
  `RuntimeDefault` seccomp profile.
- ECR has `scan_on_push` enabled and AES256 encryption at rest.
- EKS uses IRSA/OIDC; nodes run in **private subnets** behind a NAT gateway.
- Frontend nginx listens on unprivileged port 8080 with a writable `/tmp`
  emptyDir, keeping the container root filesystem read-only.

## Teardown

```bash
# Remove Kubernetes resources
kubectl delete -f k8s/ingress.yaml -f k8s/frontend-service.yaml \
  -f k8s/frontend-deployment.yaml -f k8s/backend-service.yaml \
  -f k8s/backend-deployment.yaml -f k8s/namespace.yaml

# Destroy infrastructure (ECR must be empty or force-deletes with the module)
cd terraform
terraform destroy
```

> If `terraform destroy` fails on non-empty ECR repos, delete the images first:
> `aws ecr batch-delete-image ...` or delete the repos from the console.
