# Task 3 — Multi-Environment CI/CD for a Microservices App on EKS

A production-shaped, reproducible pipeline that ships a two-service microservices
app (`api-gateway` + `orders`) to **three isolated environments** — `dev`,
`staging`, `prod` — on Amazon EKS. Environment segregation is driven by
**Terraform workspaces** on the infrastructure side and **Kustomize overlays**
on the deployment side. Images are **built once and promoted** across
environments by an immutable git-sha tag.

Base name used everywhere: **`microsvc`**.

---

## 1. Architecture

```
                 ┌────────────────────────────────────────────┐
                 │                 Jenkins                     │
                 │  build once  ->  push :<git-sha>  ->  promote│
                 └───────┬───────────────┬──────────────┬──────┘
                         │ deploy         │ approve       │ approve
                         v                v               v
        ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐
        │  workspace: dev   │  │ workspace: staging│  │  workspace: prod  │
        │  cluster:         │  │  cluster:         │  │  cluster:         │
        │  microsvc-dev     │  │  microsvc-staging │  │  microsvc-prod    │
        │  ns: microsvc-dev │  │ns:microsvc-staging│  │ ns: microsvc-prod │
        │  t3.small  1-3    │  │  t3.medium 2-4    │  │  t3.large  3-8    │
        └───────────────────┘  └───────────────────┘  └───────────────────┘
              overlays/dev          overlays/staging        overlays/prod
                         \________________ same __________________/
                                    immutable image sha
```

Each service is a small Node/Express app with a `/health` and a `/` endpoint.
`api-gateway` optionally calls `orders` over in-cluster DNS (`http://orders:3000`).

### Repository layout

```
task3-multienv-microservices/
├── Jenkinsfile                 # declarative pipeline + promotion strategy
├── terraform/                  # workspace-aware infra (VPC + EKS + ECR)
├── services/
│   ├── api-gateway/            # Node app, tests, multi-stage Dockerfile
│   └── orders/                 # Node app, tests, multi-stage Dockerfile
└── k8s/
    ├── base/                   # shared deployment/service per service
    └── overlays/{dev,staging,prod}
```

---

## 2. The workspace model

One Terraform configuration serves all three environments. `terraform.workspace`
selects a per-environment config block (`locals.env_config`) that drives:

| setting        | dev        | staging     | prod       |
|----------------|------------|-------------|------------|
| VPC CIDR       | 10.10.0.0/16 | 10.20.0.0/16 | 10.30.0.0/16 |
| node type      | t3.small   | t3.medium   | t3.large   |
| min/desired/max| 1 / 2 / 3  | 2 / 2 / 4   | 3 / 4 / 8  |
| NAT gateways   | single     | single      | one per AZ |
| cluster name   | microsvc-dev | microsvc-staging | microsvc-prod |

A **guard** hard-fails any run in the `default` workspace so state never gets
mixed. Remote state is segregated per workspace via `workspace_key_prefix`
(see `backend.tf.example`), yielding keys like `microsvc/dev/terraform.tfstate`.

### Workspace commands

```bash
cd terraform
cp backend.tf.example backend.tf     # edit bucket/table/region first
terraform init

# create the three workspaces (once)
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod

# provision an environment
terraform workspace select dev
terraform apply -var-file=dev.tfvars

terraform workspace select staging
terraform apply -var-file=staging.tfvars

terraform workspace select prod
terraform apply -var-file=prod.tfvars

# verify which env you are on
terraform workspace show
```
<img width="1316" height="223" alt="image" src="https://github.com/user-attachments/assets/1392323a-abc3-4ebb-a54e-d12d0809db12" />

<img width="1442" height="436" alt="image" src="https://github.com/user-attachments/assets/d04af825-d253-4304-9ac9-7363d663d43f" />

<img width="1258" height="575" alt="image" src="https://github.com/user-attachments/assets/19c25d68-9807-4771-9498-b62b982df9a1" />

<img width="1797" height="1008" alt="image" src="https://github.com/user-attachments/assets/2aad7c0b-ae98-4437-bb3c-0ed7b1489b09" />

<img width="1813" height="941" alt="image" src="https://github.com/user-attachments/assets/7d6c8795-c5e0-44ce-ac48-03e28248edf6" />

<img width="1918" height="931" alt="image" src="https://github.com/user-attachments/assets/bf0aebf2-c3dd-4cdc-8b30-fd45f1271849" />

<img width="1920" height="2077" alt="image" src="https://github.com/user-attachments/assets/e80b2596-d02d-4e8d-94b6-c63c419d8f90" />

<img width="1892" height="888" alt="image" src="https://github.com/user-attachments/assets/96f21901-6409-47b3-a017-0a15012ac50d" />

<img width="1918" height="952" alt="image" src="https://github.com/user-attachments/assets/cefcd86c-8cc8-4824-a9bd-4e269a49f4b6" />

<img width="1915" height="911" alt="image" src="https://github.com/user-attachments/assets/94f93bce-cd49-4661-9a17-25e6df011050" />

<img width="1918" height="946" alt="image" src="https://github.com/user-attachments/assets/59b2527f-dcdd-4e6e-af2c-8fe40a5bfb64" />

<img width="1920" height="2098" alt="image" src="https://github.com/user-attachments/assets/3d4c4945-fc10-43ac-8ef8-d2e2f1b1be60" />

<img width="1877" height="906" alt="image" src="https://github.com/user-attachments/assets/2d6332dd-a555-402a-a9ac-4228605bfecd" />

<img width="1918" height="978" alt="image" src="https://github.com/user-attachments/assets/9579719b-30dc-44f1-8633-3bdcb0718299" />

<img width="1911" height="855" alt="image" src="https://github.com/user-attachments/assets/9b74b418-23e9-45c1-ba43-2c53c5378a8e" />

<img width="1918" height="935" alt="image" src="https://github.com/user-attachments/assets/fb43d9ec-9074-4793-8ee5-5014fe5838c1" />

<img width="1920" height="2077" alt="image" src="https://github.com/user-attachments/assets/67878b78-e77a-4a81-962f-898a00f14e3a" />


After apply, wire up kubectl using the emitted output:

```bash
aws eks update-kubeconfig --region us-east-1 --name microsvc-dev
```

---

## 3. Build once, promote everywhere

The pipeline builds each service image **exactly once** and tags it with the
git commit sha (immutable ECR repos reject re-pushes of the same tag). That
single artifact is promoted:

```
build :<sha>  ->  DEV  --approve-->  STAGING  --approve-->  PROD
```

### Exact commands (manual run, from the `task3-multienv-microservices/` directory)

**Step 1 — resolve variables once** (used by every command below):

```bash
AWS_REGION=us-east-1
ACCOUNT=848504403205
REGISTRY=$ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com
SHA=$(git rev-parse HEAD)          # the immutable tag for this commit
echo "Building tag: $SHA"
```

**Step 2 — build once and push** (this happens exactly one time per commit):

```bash
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $REGISTRY

docker build -t $REGISTRY/microsvc/api-gateway:$SHA services/api-gateway
docker build -t $REGISTRY/microsvc/orders:$SHA      services/orders

docker push $REGISTRY/microsvc/api-gateway:$SHA
docker push $REGISTRY/microsvc/orders:$SHA
```

> The repos are `IMMUTABLE`: pushing the same tag twice is rejected, which
> enforces the "never rebuilt" guarantee.

**Step 3 — promote the SAME sha to an environment** (repeat per env, no
rebuild — only the overlay's image pin changes):

```bash
ENV=dev        # then: staging, prod
aws eks update-kubeconfig --region $AWS_REGION --name microsvc-$ENV

cd k8s/overlays/$ENV
kustomize edit set image microsvc/api-gateway=$REGISTRY/microsvc/api-gateway:$SHA
kustomize edit set image microsvc/orders=$REGISTRY/microsvc/orders:$SHA
cd ../../..

kubectl apply -k k8s/overlays/$ENV
kubectl -n microsvc-$ENV rollout status deploy/api-gateway --timeout=180s
kubectl -n microsvc-$ENV rollout status deploy/orders --timeout=180s
```

This guarantees the exact bytes tested in dev are what run in prod.

---

## 4. Kustomize overlays

`k8s/base` holds environment-agnostic Deployments + Services with probes,
resource limits, and hardened `securityContext` (non-root, read-only rootfs,
dropped capabilities, seccomp). Image fields use placeholders
(`microsvc/api-gateway`, `microsvc/orders`).

Each overlay in `k8s/overlays/<env>`:

- sets `namespace: microsvc-<env>` and ships a `Namespace` resource,
- patches **replicas** (dev 1, staging 2, prod 3-4),
- patches **resources** and injects `APP_ENV`,
- rewrites the **image** name+tag (the pipeline pins the real sha).

Render/inspect any environment locally:

```bash
kustomize build k8s/overlays/dev
kubectl apply -k k8s/overlays/dev
```

---

## 5. Deploy each environment

Manual (mirrors what Jenkins automates). Uses the `AWS_REGION` / `REGISTRY` /
`SHA` variables from section 3, step 1:

```bash
# 1. infra
cd terraform && terraform workspace select dev && terraform apply -var-file=dev.tfvars && cd ..

# 2. kubeconfig
aws eks update-kubeconfig --region $AWS_REGION --name microsvc-dev

# 3. pin image + deploy
cd k8s/overlays/dev
kustomize edit set image microsvc/api-gateway=$REGISTRY/microsvc/api-gateway:$SHA
kustomize edit set image microsvc/orders=$REGISTRY/microsvc/orders:$SHA
cd ../../.. && kubectl apply -k k8s/overlays/dev

# 4. verify
kubectl -n microsvc-dev rollout status deploy/api-gateway
```

Repeat with `staging` / `prod` overlays and workspaces for the other envs.

---

## 6. Promotion flow (Jenkins)

Stages: **Checkout -> Build & Test (parallel per service) -> Build & Push
images -> Deploy DEV -> Integration test -> approve -> Deploy STAGING ->
approve -> Deploy PROD**, with a `post{}` block for cleanup/notification.

- `PROMOTE_TO_STAGING` / `PROMOTE_TO_PROD` boolean parameters plus `input`
  approval gates control how far a build promotes.
- `deployEnv(env)` selects the Terraform workspace, refreshes kubeconfig,
  pins the immutable sha into the overlay, and `kubectl apply -k`.
- Region/registry are env vars; AWS creds come from the `aws-credentials`
  credential (swap for an IAM instance role in real clusters).

---

## 7. Teardown (per workspace)

Delete Kubernetes objects first, then the infra for that workspace:

```bash
kubectl delete -k k8s/overlays/dev      # remove workloads + namespace

cd terraform
terraform workspace select dev
terraform destroy -var-file=dev.tfvars

# repeat for staging and prod, then optionally drop the empty workspaces:
terraform workspace select default
terraform workspace delete dev
terraform workspace delete staging
terraform workspace delete prod
```

> ECR images are retained by the lifecycle policy (last 20). Delete the repos
> manually or via `terraform destroy` in each workspace if you want them gone.

---

## 8. Design notes

- **Environment segregation** — separate Terraform workspaces (isolated state +
  isolated VPC/EKS/CIDR per env) and separate Kubernetes namespaces
  (`microsvc-<env>`). A default-workspace guard prevents accidental mixing.
- **Modularity** — infra uses upstream `terraform-aws-modules/vpc` and
  `.../eks`; app config is DRY via a kustomize base + thin overlays; services
  are independent, individually built and tested.
- **Security** — immutable ECR tags + scan-on-push; non-root, read-only-rootfs
  containers dropping all Linux capabilities with `seccompProfile: RuntimeDefault`;
  private worker subnets; least-surface health-gated rollouts; prod uses
  one NAT gateway per AZ for availability.
```
