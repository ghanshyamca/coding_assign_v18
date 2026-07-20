# Task 2 — Blue-Green Deployment on EKS with Jenkins & Helm (Node.js)

A production-shaped blue-green pipeline for a minimal Node.js/Express app
(`bluegreen-node`). Terraform provisions the EKS platform, Helm defines two
colored environments plus a stable production router Service, and Jenkins
automates the build → deploy-idle → cutover flow with Helm.

---

## Contents

```
task2-bluegreen-node-helm/
├── README.md
├── Jenkinsfile                 # declarative pipeline: build, deploy idle, cut over
├── terraform/                  # EKS + VPC + ECR + helm provider wiring
│   ├── versions.tf
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── backend.tf.example
├── app/                        # Express app + tests + Dockerfile
│   ├── server.js
│   ├── package.json
│   ├── app.test.js
│   ├── Dockerfile
│   └── .dockerignore
└── helm/bluegreen-node/        # one parameterized chart
    ├── Chart.yaml
    ├── values.yaml
    ├── values-blue.yaml
    ├── values-green.yaml
    ├── values-router.yaml
    └── templates/
        ├── _helpers.tpl
        ├── deployment.yaml
        ├── service.yaml        # preview svc + stable production svc
        ├── serviceaccount.yaml
        └── NOTES.txt
```

---

## Blue-Green Concept

Two colored deployments run side by side. A single stable **production Service**
(`bluegreen-node-active`) selects pods by a `track` label. Only the color that
`track` points at receives live traffic. New versions are deployed to the *idle*
color, smoke-tested in isolation, then traffic is cut over by flipping the
production Service's `track` selector. The old color stays running for instant
rollback.

```
                      ┌──────────────────────────────────────────┐
     live traffic     │  Service: bluegreen-node-active           │
   ───────────────►   │  selector: {name: bluegreen-node,         │
                      │             track: blue}   <── flip this  │
                      └───────────────┬───────────────┬───────────┘
                                      │ (active)      │ (idle, warm)
                          track=blue  ▼               ▼  track=green
                   ┌─────────────────────┐   ┌─────────────────────┐
                   │ Deployment          │   │ Deployment          │
                   │ bluegreen-node-blue │   │ bluegreen-node-green│
                   │ COLOR=blue  v=sha1  │   │ COLOR=green v=sha2  │
                   └─────────────────────┘   └─────────────────────┘
                   preview svc: -blue         preview svc: -green
                   (smoke test only)          (smoke test only)
```

Cutover = change `productionService.activeTrack` from `blue` to `green` (via
`helm upgrade app-router`). Rollback = flip it back / `helm rollback app-router`.

---

## Prerequisites

- Terraform >= 1.5, AWS CLI v2, `kubectl`, `helm` v3, `jq`
- Node.js 20 and Docker (for local build/test)
- An AWS account with permissions for VPC, EKS, ECR, IAM
- A Jenkins controller/agent with docker, awscli, kubectl, helm, node 20 and an
  `aws-creds` credential (or an IAM instance role) able to push to ECR and
  administer the cluster.

---

## 1. Provision infrastructure (Terraform)

```bash
cd terraform
# optional: cp backend.tf.example backend.tf   # then edit bucket/table
terraform init
terraform apply \
  -var="region=us-east-1" \
  -var="cluster_name=bluegreen-node-eks"

# Wire kubectl to the new cluster (command is also a terraform output):
aws eks update-kubeconfig --region us-east-1 --name bluegreen-node-eks

# Note the ECR URL for image pushes:
terraform output ecr_url
```
<img width="1352" height="441" alt="image" src="https://github.com/user-attachments/assets/c882bee3-9d9b-45bd-8ad6-76eefb32e6d5" />

<img width="1885" height="960" alt="image" src="https://github.com/user-attachments/assets/a28b80d7-24df-4ea1-b974-3b10233db155" />

<img width="1891" height="997" alt="image" src="https://github.com/user-attachments/assets/9ccad12a-af5c-4334-8c63-35b0c6145256" />

<img width="1918" height="967" alt="image" src="https://github.com/user-attachments/assets/c8dafe04-779e-436b-9d9f-88606792996b" />

<img width="1545" height="987" alt="image" src="https://github.com/user-attachments/assets/8cf55ab5-8fb1-4587-a627-2ec368457965" />

<img width="1920" height="2100" alt="image" src="https://github.com/user-attachments/assets/3457e934-442d-47fc-95ae-2d2064778ab7" />


This creates a VPC, an EKS 1.33 cluster with a `t3.medium` managed node group
(min 2 / desired 2 / max 4), IRSA/OIDC, an ECR repo (scan-on-push, keep last 10),
and installs `metrics-server` via a `helm_release` to demonstrate Helm setup.
(An `ingress-nginx` / AWS Load Balancer Controller block is included commented.)

---

## 2. Build & push the image

```bash
ECR_URL=$(cd terraform && terraform output -raw ecr_url)
AWS_REGION=us-east-1
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin ${ECR_URL%/*}

SHA=$(git rev-parse --short HEAD)
docker build -t $ECR_URL:$SHA ./app
docker push $ECR_URL:$SHA
```
<img width="1918" height="856" alt="image" src="https://github.com/user-attachments/assets/4bcde88d-9472-4279-901e-1b1df570b8ff" />

<img width="1195" height="206" alt="image" src="https://github.com/user-attachments/assets/42a5588a-818d-454f-aa23-f3830e17fb0e" />

<img width="1920" height="869" alt="image" src="https://github.com/user-attachments/assets/68df8592-f98c-47f3-a7c2-fc6b52e60002" />

---

## 3. Install blue, then green, then the router (Helm)

```bash
CHART=helm/bluegreen-node
ECR_URL=$(cd terraform && terraform output -raw ecr_url)
SHA=$(git rev-parse --short HEAD)

# Blue (first live color)
helm upgrade --install app-blue $CHART -f $CHART/values-blue.yaml \
  --set image.repository=$ECR_URL --set image.tag=$SHA --wait

# Green (idle, new version)
helm upgrade --install app-green $CHART -f $CHART/values-green.yaml \
  --set image.repository=$ECR_URL --set image.tag=$SHA --wait

# Router owning the stable production Service, initially pointing at blue
helm upgrade --install app-router $CHART -f $CHART/values-router.yaml \
  --set productionService.activeTrack=blue --wait
```
<img width="995" height="742" alt="image" src="https://github.com/user-attachments/assets/2c81054a-226b-4936-a683-245b90149ea6" />

<img width="980" height="366" alt="image" src="https://github.com/user-attachments/assets/525ade15-4e63-46c9-bc9a-b3f405ce15d5" />

Verify each color in isolation via its **preview Service**
(`bluegreen-node-blue`, `bluegreen-node-green`) before cutting over.

---

## 4. How the cutover works

The production Service `bluegreen-node-active` selects `{name, track}`. It is
owned by the `app-router` release only, so upgrading a color never disturbs it.
To send live traffic to green:

```bash
helm upgrade --install app-router helm/bluegreen-node \
  -f helm/bluegreen-node/values-router.yaml \
  --set productionService.activeTrack=green --wait
```
<img width="1018" height="366" alt="image" src="https://github.com/user-attachments/assets/42e453fc-0ec9-431e-8984-36059790e233" />

The endpoints behind the Service switch atomically to green's pods. An imperative
alternative (faster, but drifts from Helm state) is a `kubectl patch` of the
Service selector — shown as a comment in the Jenkinsfile.

---

## 5. How Jenkins automates it

`Jenkinsfile` (declarative) stages:

1. **Checkout** — resolve short git SHA (image tag).
2. **Build & Test** — `npm ci` + `npm test` (jest + supertest against `/`, `/health`).
3. **Docker Build & Push to ECR** — tags with git SHA and `latest`.
4. **Configure kubectl** — `aws eks update-kubeconfig`.
5. **Determine Idle Color** — reads live track from `bluegreen-node-active`'s
   selector; picks the opposite color as the deploy target.
6. **Deploy to Idle Color** — `helm upgrade --install app-<idle> -f values-<idle>.yaml
   --set image.tag=$SHA`; ensures the router exists.
7. **Smoke Test Idle Color** — curls the idle preview Service `/health`.
8. **Approve Cutover** — manual `input` gate.
9. **Cut Over** — `helm upgrade app-router --set productionService.activeTrack=<idle>`.
10. **Verify** — asserts the Service selector now points at the new color and
    curls the production Service.
11. **post{}** — reports result, leaves the previous color warm, cleans workspace.

Parameters: `AWS_REGION`, `CLUSTER_NAME`, `ECR_REPO`, `NAMESPACE`, `CHART_PATH`.
Credentials: `aws-credentials` (kind: AWS Credentials) — see the header comment in the Jenkinsfile.

---
<img width="1915" height="846" alt="image" src="https://github.com/user-attachments/assets/a7da0a95-52fc-4e1b-82ef-b79d4597e90d" />

<img width="1522" height="820" alt="image" src="https://github.com/user-attachments/assets/417b93e2-0ab3-4223-91f3-b940ba7868b3" />

<img width="1920" height="11716" alt="image" src="https://github.com/user-attachments/assets/118f79e7-ea9e-4b1e-9104-a372e29b34f6" />


## ROLLBACK STRATEGY

Because the previous color is never torn down during a deploy, rollback is fast
and does not require a rebuild.

**A. Instant traffic rollback (flip the router back).** If green was just made
live and misbehaves, point production back at blue:

```bash
# Preferred — keeps Helm as source of truth and records a revision:
helm upgrade --install app-router helm/bluegreen-node \
  -f helm/bluegreen-node/values-router.yaml \
  --set productionService.activeTrack=blue --wait

# Or roll the router release back to its previous revision:
helm rollback app-router          # last good revision
helm history app-router           # inspect revisions first

# Or imperative, fastest:
kubectl patch svc bluegreen-node-active \
  -p '{"spec":{"selector":{"app.kubernetes.io/name":"bluegreen-node","track":"blue"}}}'
```
<img width="1347" height="696" alt="image" src="https://github.com/user-attachments/assets/ac928e54-9abd-40b1-954f-523dcaa1922c" />

Traffic returns to the still-running blue pods within seconds — no image pull,
no scheduling delay.

**B. Roll back a bad color release.** If a color's own release is broken (e.g.
crash-looping) and you want its prior version back:

```bash
helm history app-green
helm rollback app-green <GOOD_REVISION>
```
<img width="1278" height="93" alt="image" src="https://github.com/user-attachments/assets/7be8c5bf-4f0c-4cbb-8311-0fc586b0c029" />

<img width="883" height="62" alt="image" src="https://github.com/user-attachments/assets/68c7ed13-2e82-4edf-ab48-82444d59d9e0" />


**C. Confirm.**

```bash
kubectl get svc bluegreen-node-active -o jsonpath='{.spec.selector.track}{"\n"}'
kubectl run rb-check --rm -i --restart=Never --image=curlimages/curl:8.8.0 -- \
  curl -s http://bluegreen-node-active.default.svc.cluster.local/
```
<img width="1042" height="141" alt="image" src="https://github.com/user-attachments/assets/da1f87f8-871e-458a-a59d-d05ee8ab0933" />

Guideline: keep the previous color running until the new color has been verified
in production for a bake period; only then scale it down or redeploy it as the
next idle target.

---

## Teardown

```bash
# Remove app + router releases
helm uninstall app-router app-blue app-green

# Destroy infrastructure (empties/removes ECR, EKS, VPC)
cd terraform
terraform destroy \
  -var="region=us-east-1" \
  -var="cluster_name=bluegreen-node-eks"
```

<img width="1507" height="237" alt="image" src="https://github.com/user-attachments/assets/15c6049f-93f5-45ea-a745-aca01c9de92e" />

<img width="1918" height="823" alt="image" src="https://github.com/user-attachments/assets/704d2377-bfb4-4b4a-b422-a61ce8f052d7" />

<img width="1821" height="953" alt="image" src="https://github.com/user-attachments/assets/b3d11d23-20fa-4b9c-a040-a0533ae1c54f" />

<img width="1919" height="1016" alt="image" src="https://github.com/user-attachments/assets/cc349216-ad5e-418c-a385-350bd8b4abbe" />

If ECR still holds images, delete them first or Terraform will refuse to remove
the repository.

---
