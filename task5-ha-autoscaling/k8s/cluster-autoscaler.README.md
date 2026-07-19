# Cluster Autoscaler

The Cluster Autoscaler (CA) is **installed and managed by Terraform** (not by a
manifest in this folder). See `terraform/main.tf` — the `helm_release`
`cluster_autoscaler` block plus the `cluster_autoscaler_irsa` module.

This file documents what Terraform sets up and how the pieces fit, so the CA can
be understood or reproduced by hand if Helm is not used.

## What Terraform provisions

1. **IRSA role** — `module.cluster_autoscaler_irsa`
   (`terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks`)
   with `attach_cluster_autoscaler_policy = true`. This attaches an IAM policy
   granting:
   - `autoscaling:DescribeAutoScalingGroups`
   - `autoscaling:DescribeAutoScalingInstances`
   - `autoscaling:DescribeLaunchConfigurations`
   - `autoscaling:DescribeTags`
   - `autoscaling:SetDesiredCapacity`
   - `autoscaling:TerminateInstanceInAutoScalingGroup`
   - `ec2:DescribeLaunchTemplateVersions`, `ec2:DescribeInstanceTypes`

   The role trust policy is scoped (via the cluster OIDC provider) to the
   `kube-system:cluster-autoscaler` service account only.

2. **ASG auto-discovery tags** — the CA finds which Auto Scaling Groups it may
   manage via these tags on the ASG:
   ```
   k8s.io/cluster-autoscaler/enabled       = "true"
   k8s.io/cluster-autoscaler/<cluster-name> = "owned"
   ```
   For EKS **managed** node groups, AWS applies these tags to the underlying
   ASG automatically — that is what enables discovery here. (The matching tags
   in `main.tf` sit on the node-group resource itself for documentation; node
   group resource tags do not propagate to the ASG. Self-managed node groups
   would need the ASG tagged explicitly, e.g. via `aws_autoscaling_group_tag`.)

3. **Helm release** of the `cluster-autoscaler` chart in `kube-system`, with:
   - `autoDiscovery.clusterName = <cluster-name>`
   - `awsRegion = <region>`
   - the service account annotated with the IRSA role ARN:
     `eks.amazonaws.com/role-arn: <role-arn>`

## The IRSA service account annotation (the critical wire)

The CA pod authenticates to AWS by assuming the IRSA role through the service
account annotation. Effectively the chart renders:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/ha-app-cluster-autoscaler
```

## How it behaves

- When a pod is **Pending** because no node has room (e.g. HPA scaled the
  Deployment up past current capacity), CA increases the ASG desired count →
  a new node joins across one of the 3 AZs.
- When nodes are underutilized for ~10 minutes and their pods can be rescheduled
  elsewhere, CA scales the ASG back down (respecting `min_size = 2`).
- CA never scales below `node_min_size` (2) or above `node_max_size` (6).

## Manual install alternative (reference only)

If you were NOT using the Terraform Helm approach, you would:

```bash
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=ha-app-eks \
  --set awsRegion=us-east-1 \
  --set rbac.serviceAccount.name=cluster-autoscaler \
  --set 'rbac.serviceAccount.annotations.eks\.amazonaws\.com/role-arn'=<ROLE_ARN>
```

## Verify

```bash
kubectl -n kube-system get deploy cluster-autoscaler
kubectl -n kube-system logs -l app.kubernetes.io/name=aws-cluster-autoscaler -f
```
