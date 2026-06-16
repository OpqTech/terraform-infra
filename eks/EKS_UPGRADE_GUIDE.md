# EKS Upgrade Guide: 1.33 → 1.35

## Upgrade Rules

1. **One minor version at a time.** AWS does not allow skipping versions: `1.33 → 1.34 → 1.35`.
2. **Control plane first.** Always upgrade the control plane before addons and nodes.
3. **Addons before nodes.** Upgrade EKS-managed addons before nodes start rolling.
4. **No rollback.** EKS control plane downgrades are not supported. Validate in dev before promoting.
5. **Environment order:** `dev → qa → uat → prod`. Fully validate each before promoting.

---

## Version Reference

All addon versions sourced live from `aws eks describe-addon-versions`. Re-verify immediately before applying — AWS publishes new eksbuild patches frequently.

### EKS Managed Addons

| Addon | 1.33 | 1.34 | 1.35 | Docs |
|---|---|---|---|---|
| `coredns` | `v1.13.2-eksbuild.10` | `v1.13.2-eksbuild.10` | `v1.14.3-eksbuild.2` | [Managing CoreDNS](https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html) |
| `kube-proxy` | `v1.33.10-eksbuild.13` | `v1.34.6-eksbuild.13` | `v1.35.3-eksbuild.13` | [Managing kube-proxy](https://docs.aws.amazon.com/eks/latest/userguide/managing-kube-proxy.html) |
| `vpc-cni` | `v1.22.2-eksbuild.1` | `v1.22.2-eksbuild.1` | `v1.22.2-eksbuild.1` | [Managing VPC CNI](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html) |
| `eks-pod-identity-agent` | `v1.3.10-eksbuild.3` | `v1.3.10-eksbuild.3` | `v1.3.10-eksbuild.3` | [Pod Identity Agent](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html) |
| `aws-ebs-csi-driver` | `v1.61.1-eksbuild.1` | `v1.61.1-eksbuild.1` | `v1.61.1-eksbuild.1` | [EBS CSI Driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) |

### Helm Charts

| Chart | Helm Repo | Compatibility / Releases | k8s 1.33 | k8s 1.34 | k8s 1.35 |
|---|---|---|---|---|---|
| `karpenter` | `oci://public.ecr.aws/karpenter` | [Compatibility Matrix](https://karpenter.sh/docs/upgrading/compatibility/) · [ECR Gallery](https://gallery.ecr.aws/karpenter/karpenter) | `1.4.0` ✓ | `1.4.0` ✓ | `1.4.0` ✓ |
| `cluster-autoscaler` | `https://kubernetes.github.io/autoscaler` | [Releases](https://github.com/kubernetes/autoscaler/releases) · [ArtifactHub](https://artifacthub.io/packages/helm/cluster-autoscaler/cluster-autoscaler) | `9.51.0` | `9.52.1` | `9.57.0` |
| `argo-cd` | `https://argoproj.github.io/argo-helm` | [Releases](https://github.com/argoproj/argo-helm/releases) · [ArtifactHub](https://artifacthub.io/packages/helm/argo/argo-cd) | `8.x`+ ✓ | `8.x`+ ✓ | `8.x`+ ✓ |
| `velero` | `https://vmware-tanzu.github.io/helm-charts` | [Releases](https://github.com/vmware-tanzu/helm-charts/releases) · [ArtifactHub](https://artifacthub.io/packages/helm/vmware-tanzu/velero) | `12.x` ✓ | `12.x` ✓ | `12.x` ✓ |
| `secrets-store-csi-driver` | `https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts` | [Upgrade Guide](https://secrets-store-csi-driver.sigs.k8s.io/getting-started/upgrades) · [ArtifactHub](https://artifacthub.io/packages/helm/secrets-store-csi-driver/secrets-store-csi-driver) | current ✓ | current ✓ | current ✓ |
| `secrets-store-csi-driver-provider-aws` | `https://aws.github.io/secrets-store-csi-driver-provider-aws` | [Releases](https://github.com/aws/secrets-store-csi-driver-provider-aws/releases) · [ArtifactHub](https://artifacthub.io/packages/helm/aws-secrets-manager/secrets-store-csi-driver-provider-aws) | current ✓ | current ✓ | current ✓ |
> **ArgoCD, Velero, Secrets Store CSI Driver, and the AWS Secrets Provider** have no hard k8s version coupling across this upgrade path (all require k8s ≥ 1.25.0). Their chart versions do not need to change during this upgrade. Only `cluster-autoscaler` tracks the k8s minor version directly.

---

## Karpenter Node Drift — Fully Automatic

Both `arm-node-class` and `amd-node-class` use:

```yaml
amiSelectorTerms:
  - alias: bottlerocket@latest
```

With **Karpenter v1.4.0**, drift has been enabled by default since v0.33. After the control plane is upgraded to a new minor version, Karpenter automatically:

1. Detects that new Bottlerocket AMIs have been published for the new k8s version
2. Marks all NodeClaims backed by the old AMI as **drifted**
3. Respins nodes in a rolling fashion, fully respecting PodDisruptionBudgets
4. The `consolidationPolicy: WhenEmptyOrUnderutilized` and `expireAfter: 336h` in your NodePools accelerate this process

**No manual drain, delete, or annotation is required.** Monitor progress with:

```bash
# Watch NodeClaim drift status
kubectl get nodeclaims -w

# Confirm nodes rolling to new AMI / kubelet version
kubectl get nodes -o wide -w
```

> Reference: [Karpenter Disruption — Drift](https://karpenter.sh/docs/concepts/disruption/#drift)

---

## Pre-Upgrade Checklist

Run these before **each version hop**, on **each environment**.

### 0. Take a Velero backup (uat/prod mandatory, dev/qa optional)

Velero backs up Kubernetes resources and EBS volume snapshots — not the EKS control plane itself. It cannot undo a control plane version bump (AWS doesn't allow downgrades), but it protects against workload/state corruption *during* the upgrade: bad CRD migrations, accidentally stomped ConfigMaps, Helm upgrades that mutate resources unexpectedly.

```bash
# Take a full on-demand backup immediately before applying the upgrade
# Note: kubectl config current-context returns the full ARN on EKS; extract just the cluster name
velero backup create pre-upgrade-$(kubectl config current-context | sed 's|.*/||')-$(date +%Y%m%d%H%M) \
  --include-namespaces '*' \
  --exclude-namespaces kube-system,kube-public,kube-node-lease,velero \
  --include-cluster-resources=true \
  --snapshot-volumes \
  --wait

# Confirm it completed successfully before proceeding
velero backup describe pre-upgrade-$(kubectl config current-context | sed 's|.*/||')-* --details | tail -5
# Expected: Phase: Completed
```

> Do not proceed with `terraform apply` until the backup shows `Phase: Completed`.

### 1. Check current versions

```bash
# Control plane version and status
aws eks describe-cluster --name <cluster-name> \
  --query 'cluster.{version:version,status:status,platformVersion:platformVersion}' \
  --output table

# All node kubelet versions
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.kubeletVersion}{"\n"}{end}'
```

### 2. Scan for deprecated and removed Kubernetes APIs

This is the most common cause of upgrade failures. Fix all findings **before** touching the control plane.

Official docs: [pluto.docs.fairwinds.com](https://pluto.docs.fairwinds.com/) · [GitHub releases](https://github.com/FairwindsOps/pluto/releases)

**Install pluto**

macOS:
```bash
brew install FairwindsOps/tap/pluto
```

Linux:
```bash
# Replace VERSION with the latest from https://github.com/FairwindsOps/pluto/releases
VERSION=$(curl -s https://api.github.com/repos/FairwindsOps/pluto/releases/latest | grep tag_name | cut -d '"' -f4)
curl -L "https://github.com/FairwindsOps/pluto/releases/download/${VERSION}/pluto_${VERSION#v}_linux_amd64.tar.gz" | tar xz
sudo mv pluto /usr/local/bin/
pluto version
```

Windows (PowerShell — requires [Scoop](https://scoop.sh)):
```powershell
scoop bucket add fairwinds-stable https://github.com/FairwindsOps/scoop-bucket.git
scoop install pluto
```

Or download the `.zip` directly from the [GitHub releases page](https://github.com/FairwindsOps/pluto/releases), extract `pluto.exe`, and add it to your `PATH`.

**Run deprecation scans**

```bash
# Scan all live cluster resources
pluto detect-all-in-cluster --target-versions k8s=v1.34.0

# Scan all Helm releases for deprecated APIs
pluto detect-helm --target-versions k8s=v1.34.0
```

Alternatively via kubectl:

```bash
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis
```

### 3. Check PodDisruptionBudgets

Overly restrictive PDBs block node rolling updates.

```bash
kubectl get pdb -A
```

Any PDB with `ALLOWED DISRUPTIONS: 0` where `MIN AVAILABLE` equals the full replica count will stall node replacement. Temporarily adjust or coordinate with app teams before proceeding.

### 4. Verify latest addon versions for the target k8s version

```bash
aws eks describe-addon-versions \
  --kubernetes-version 1.34 \
  --query 'addons[?addonName==`coredns` || addonName==`kube-proxy` || addonName==`vpc-cni` || addonName==`eks-pod-identity-agent` || addonName==`aws-ebs-csi-driver`].{addon:addonName,latest:addonVersions[0].addonVersion}' \
  --output table
```

### 5. Verify Bottlerocket AMI availability for target k8s version

```bash
# ARM (Graviton) nodes
aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=bottlerocket-aws-k8s-1.34-aarch64-*" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].{Name:Name,ImageId:ImageId}' \
  --output table

# AMD nodes
aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=bottlerocket-aws-k8s-1.34-x86_64-*" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].{Name:Name,ImageId:ImageId}' \
  --output table
```

---

## Hop 1: 1.33 → 1.34

### Step 1 — Update tfvars (start with `dev`)

```json
{
  "eks_version": "1.34",
  "addon_coredns_version": "v1.13.2-eksbuild.10",
  "addon_eks_pod_identity_agent_version": "v1.3.10-eksbuild.3",
  "addon_kube_proxy_version": "v1.34.6-eksbuild.13",
  "addon_vpc_cni_version": "v1.22.2-eksbuild.1",
  "cluster_autoscaler_chart_version": "9.52.1"
}
```

### Step 2 — Plan

```bash
terraform plan -var-file=environments/dev.auto.tfvars.json
```

Expected changes in the plan:
- `aws_eks_cluster`: `version` `1.33` → `1.34`
- `aws_eks_addon.kube_proxy`: `addon_version` updating
- `helm_release.cluster_autoscaler`: `version` → `9.52.1`
- `aws_eks_node_group`: rolling update queued (runs after control plane)

### Step 3 — Apply

```bash
terraform apply -var-file=environments/dev.auto.tfvars.json
```

The module applies in this order automatically:
1. **Control plane** (`aws_eks_cluster`) — 10–15 min
2. **EKS addons** (`aws_eks_addon`) — parallel, 2–5 min each
3. **Managed node group** — rolling replacement, one node at a time

### Step 4 — Verify control plane

```bash
aws eks describe-cluster --name dev \
  --query 'cluster.{version:version,status:status,platformVersion:platformVersion}' \
  --output table
# Expected: version 1.34, status ACTIVE
```

### Step 5 — Verify all addons

```bash
for addon in coredns kube-proxy vpc-cni eks-pod-identity-agent aws-ebs-csi-driver; do
  aws eks describe-addon --cluster-name dev --addon-name $addon \
    --query 'addon.{name:addonName,version:addonVersion,status:status}' \
    --output table
done
```

All should show `status: ACTIVE`.

### Step 6 — Verify managed node group

```bash
# All managed nodes should show kubelet v1.34.x
kubectl get nodes -o wide

# Confirm none remain on old version
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.kubeletVersion}{"\n"}{end}'
```

### Step 7 — Monitor Karpenter drift (automatic)

Karpenter detects the new Bottlerocket AMIs for k8s 1.34 and replaces nodes automatically. No action required — just monitor:

```bash
# Watch NodeClaims cycling through drifted → terminating → ready
kubectl get nodeclaims -w

# Watch nodes rolling
kubectl get nodes -o wide -w

# Check Karpenter logs for drift events
kubectl -n kube-system logs -l app.kubernetes.io/name=karpenter --tail=100 | grep -i drift
```

All Karpenter nodes typically rotate within 30–60 min depending on workload density and PDB constraints.

### Step 8 — Smoke test

```bash
# No pods stuck pending or in error
kubectl get pods -A | grep -Ev "Running|Completed"

# CoreDNS healthy
kubectl -n kube-system rollout status deployment/coredns

# Cluster Autoscaler healthy
kubectl -n kube-system rollout status deployment/cluster-autoscaler

# ArgoCD healthy
kubectl -n argocd rollout status deployment/argocd-server

# Karpenter healthy
kubectl -n kube-system rollout status deployment/karpenter
```

**Validate for at least 24h in dev before promoting to qa.**

---

## Hop 2: 1.34 → 1.35

Same process. The only differences are the version values below.

### Step 1 — Update tfvars

```json
{
  "eks_version": "1.35",
  "addon_coredns_version": "v1.14.3-eksbuild.2",
  "addon_eks_pod_identity_agent_version": "v1.3.10-eksbuild.3",
  "addon_kube_proxy_version": "v1.35.3-eksbuild.13",
  "addon_vpc_cni_version": "v1.22.2-eksbuild.1",
  "cluster_autoscaler_chart_version": "9.57.0"
}
```

> **CoreDNS note:** `coredns` jumps from `v1.13.x` to `v1.14.x` at this hop. If you have a customised `Corefile` (ConfigMap), review the [CoreDNS 1.14 changelog](https://coredns.io/2024/02/26/coredns-1.14.0-release/) for any plugin changes before applying.

### Steps 2–8

Identical to Hop 1. Run plan → apply → verify control plane → verify addons → verify managed nodes → monitor Karpenter drift → smoke test.

---

## Environment Promotion Order

```
dev  → 1.34 → validate 24h  →  qa  → 1.34 → validate 24h  →  uat → 1.34 → validate 24h  →  prod → 1.34 → validate 48h
dev  → 1.35 → validate 24h  →  qa  → 1.35 → validate 24h  →  uat → 1.35 → validate 24h  →  prod → 1.35 → validate 48h
```

Minimum **8–10 days** for a two-hop, four-environment upgrade done safely.

---

## Quick Command Reference

```bash
# Re-verify available addon versions before each hop
aws eks describe-addon-versions \
  --kubernetes-version <target-version> \
  --query 'addons[].{addon:addonName,latest:addonVersions[0].addonVersion}' \
  --output table

# Check all addon statuses in one cluster
for addon in coredns kube-proxy vpc-cni eks-pod-identity-agent aws-ebs-csi-driver; do
  aws eks describe-addon --cluster-name <cluster-name> --addon-name $addon \
    --query 'addon.{name:addonName,version:addonVersion,status:status}' --output table
done

# Watch Karpenter drift in real time
kubectl get nodeclaims -w

# Check nodes and their kubelet versions
kubectl get nodes -o custom-columns='NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,STATUS:.status.conditions[-1].type'

# List all Karpenter-managed node pools
kubectl get nodepools

# Check pending pods (should be zero before node replacement)
kubectl get pods -A --field-selector=status.phase=Pending

# Force Terraform state refresh after any manual changes
terraform refresh -var-file=environments/<env>.auto.tfvars.json
```

---

## Rollback Considerations

EKS control plane downgrades are **not supported**. The primary safeguard is thorough pre-upgrade validation and incremental environment promotion.

| Scenario | Action |
|---|---|
| Deprecated API breaks a workload post-upgrade | Fix the manifest and redeploy. Control plane cannot be reversed. |
| Addon upgrade stuck (`DEGRADED`) | Re-apply previous addon version: `aws eks update-addon --cluster-name <name> --addon-name <addon> --addon-version <prev>` then fix tfvars and re-apply. |
| Managed node group rolling update stalls | Check PDBs (`kubectl get pdb -A`). Temporarily relax `minAvailable` if safe. |
| Karpenter drift causes pod disruption | Karpenter respects PDBs. If PDBs are too strict, workloads will wait — this is correct behaviour. Investigate the PDB, not Karpenter. |
| `cluster-autoscaler` Helm upgrade fails | `helm rollback cluster-autoscaler -n kube-system`, then pin old chart version in tfvars and re-apply. |

---

## What Does NOT Change During This Upgrade

| Component | Reason |
|---|---|
| ArgoCD (`8.2.5` / `v3.0.12`) | Requires k8s ≥ 1.25.0 — fully compatible across this path |
| Velero (`12.0.2` / `1.18.1`) | Requires k8s ≥ 1.25.0 — fully compatible across this path |
| Secrets Store CSI Driver | No k8s version coupling in this range |
| AWS Secrets Provider | No k8s version coupling in this range |
| `aws-ebs-csi-driver` addon | Same version (`v1.61.1-eksbuild.1`) across 1.33, 1.34, and 1.35 |
| `vpc-cni` addon | Same version (`v1.22.2-eksbuild.1`) across 1.33, 1.34, and 1.35 |
| `eks-pod-identity-agent` addon | Same version (`v1.3.10-eksbuild.3`) across 1.33, 1.34, and 1.35 |
| IAM roles, VPC, S3 backend | Unaffected by EKS version changes |
| Karpenter NodePool / EC2NodeClass | No changes needed — `bottlerocket@latest` resolves new AMIs automatically |
