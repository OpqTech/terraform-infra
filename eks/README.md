# EKS

Terraform configuration that provisions the EKS control plane, baseline add-ons, the Karpenter autoscaler, and supporting IAM/secrets plumbing on top of an existing VPC.

State is stored in S3 (see [`backend.tf`](backend.tf)).

## Architecture

### Cluster

- EKS cluster via `terraform-aws-modules/eks/aws` (~> 21.22.0) — public API endpoint, `authentication_mode = "API"` (access entries; `GHAppDeployerRole` is granted `AmazonEKSClusterAdminPolicy`).
- A single EKS-managed node group (`var.node_group_name`, e.g. `managed-arm`) runs the cluster's system components. All other workload nodes are provisioned on demand by Karpenter.
- The VPC and subnets are **not** created here — they're discovered by tag from an existing VPC named `<cluster_name>-vpc`, with node subnets tagged `Tier=<node_subnet_identifier>` and control-plane subnets tagged `Tier=<intra_subnet_identifier>`.

### Workload placement: managed node group vs Karpenter

- The EKS-managed node group (`var.node_group_name`) is the dedicated home for cluster system/control components — `coredns`, Argo CD, Velero (server), the Karpenter controller, Cluster Autoscaler, and any future monitoring agents that aren't per-node DaemonSets. Each is pinned there via `nodeSelector: nodegroup: <node_group_name>`.
- Karpenter `NodePool`s taint their nodes with `dedicated=karpenter:NoSchedule` (see [Karpenter](#karpenter) below). None of the components pinned to the managed node group tolerate that taint, so they never land on Karpenter-provisioned capacity — and Karpenter never has to provision for them.
- [Cluster Autoscaler](#cluster-autoscaler-management-node-group) scales the managed node group itself (between `node_group_min_size`/`node_group_max_size`) as these system components' resource needs grow; Karpenter scales workload capacity independently.
- Cluster-wide DaemonSets — `kube-proxy`, `vpc-cni`, the `aws-ebs-csi-driver` node plugin, the Secrets Store CSI Driver, and the Velero `node-agent` — tolerate all taints (`operator: Exists`) and run on every node, including Karpenter-provisioned ones, since they're required wherever workload pods run.

### EKS add-ons

Installed as managed EKS add-ons in [`main.tf`](main.tf):

| Add-on | Notes |
|---|---|
| `coredns` | pinned to the managed node group via `configuration_values.nodeSelector` |
| `eks-pod-identity-agent` | DaemonSet, runs cluster-wide |
| `kube-proxy` | DaemonSet, runs cluster-wide |
| `vpc-cni` | DaemonSet, runs cluster-wide; own pod-identity association (`kube-system/aws-node`) |

Installed via `aws-ia/eks-blueprints-addons` in [`eks-addons.tf`](eks-addons.tf):

| Add-on | Notes |
|---|---|
| `aws-ebs-csi-driver` | own pod-identity association (`kube-system/ebs-csi-controller-sa`) |

### Karpenter

[`karpenter_deployment.tf`](karpenter_deployment.tf):

- `terraform-aws-modules/eks/aws//modules/karpenter` — IAM role, node IAM role, SQS interruption queue, pod-identity association.
- Karpenter CRDs and controller installed via Helm from `oci://public.ecr.aws/karpenter`, pinned to `var.karpenter_chart_version`. Controller values are templated from [`tpl/karpenter_values.tpl`](tpl/karpenter_values.tpl).
- `EC2NodeClass` / `NodePool` manifests are applied directly via `kubernetes_manifest`, one per `*.yaml` file under `tpl/` (currently `arm-node-class.yaml` + `arm-node-pool.yaml` and `amd-node-class.yaml` + `amd-node-pool.yaml`).
- Each `NodePool` taints its nodes with `dedicated=karpenter:NoSchedule`. Workload pods that should run on Karpenter-provisioned capacity must add a matching toleration plus a `karpenter.sh/nodepool: <amd|arm>-node-pool` (and `kubernetes.io/arch`) `nodeSelector` — see [`test/karpenter/`](test/karpenter/) for example deployments. This keeps app/test workloads off the EKS-managed node group and off the other architecture's pool.

### Cluster Autoscaler (management node group)

[`cluster-autoscaler.tf`](cluster-autoscaler.tf) installs the [Kubernetes Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler) via Helm, pinned to `var.cluster_autoscaler_chart_version`, scoped to the EKS-managed node group (`var.node_group_name`) that runs the cluster's system components:

- `eks_managed_node_groups[var.node_group_name].autoscaling_group_tags` ([`main.tf`](main.tf)) tags the underlying ASG with `k8s.io/cluster-autoscaler/enabled=true` and `k8s.io/cluster-autoscaler/<cluster_name>=owned` so Cluster Autoscaler's `--node-group-auto-discovery` can find it.
- `module.cluster_autoscaler_pod_identity` (`terraform-aws-modules/eks-pod-identity/aws`, `attach_cluster_autoscaler_policy = true`, scoped to this cluster name) grants the ASG describe/resize permissions via EKS Pod Identity to the `kube-system/cluster-autoscaler` service account — no static AWS credentials.
- The deployment is itself pinned to the managed node group (`nodeSelector: nodegroup: <node_group_name>`, tolerations for all taints), so it isn't evicted along with Karpenter-managed capacity.

This complements Karpenter: Karpenter provisions/deprovisions workload capacity on demand, while Cluster Autoscaler scales the dedicated management node group between `node_group_min_size` and `node_group_max_size` based on pending pods.

### Secrets access

[`secrets-store-csi-driver-provider-aws.tf`](secrets-store-csi-driver-provider-aws.tf) installs the Secrets Store CSI Driver and its AWS provider via Helm.

For each namespace defined in `local.app_namespaces` ([`locals.tf`](locals.tf); currently just `dev`):

- a Kubernetes namespace is created (`istio-injection=enabled`) — [`namespaces.tf`](namespaces.tf)
- a Kubernetes service account is created — [`serviceaccounts.tf`](serviceaccounts.tf)
- an IAM role + policy granting `secretsmanager:GetSecretValue`/`DescribeSecret` and `ssm:GetParameter*` under `<cluster_name>/app/*` is associated to that service account via EKS Pod Identity — [`main.tf`](main.tf)

### Backup / disaster recovery (Velero)

[`velero.tf`](velero.tf) provisions a per-cluster [Velero](https://velero.io/) installation for cluster backup/restore:

- A dedicated S3 bucket `<cluster_name>-velero-backups-<aws_account_id>` stores backups — versioned, encrypted with a dedicated KMS key (`aws_kms_key.velero`), public access fully blocked, a lifecycle rule expiring noncurrent object versions after `var.velero_backup_retention_days`, and a bucket policy denying non-TLS requests.
- `module.velero_pod_identity` (`terraform-aws-modules/eks-pod-identity/aws`, `attach_velero_policy = true`) creates an IAM role scoped to the backup bucket + KMS key plus the EC2 EBS snapshot permissions Velero needs, and associates it with the `velero/velero` service account via EKS Pod Identity — no static AWS credentials.
- Velero is installed via Helm from `vmware-tanzu/helm-charts` using [`tpl/velero_values.tpl`](tpl/velero_values.tpl):
  - `velero-plugin-for-aws` (pinned via `var.velero_plugin_aws_version`) provides the `aws` backup-storage-location and volume-snapshot-location providers (S3 object storage + EBS snapshots).
  - `credentials.useSecret: false` — relies on the pod identity association for AWS credentials.
  - The Velero server is pinned to the managed node group (`nodeSelector: nodegroup: <node_group_name>`); the `node-agent` DaemonSet (file-system/PV backups) tolerates all taints so it also runs on Karpenter-provisioned nodes.
  - A default `daily-backup` schedule (`var.velero_backup_schedule`, TTL `var.velero_backup_ttl`) backs up all namespaces except `kube-system`, `kube-public`, `kube-node-lease`, and `velero`.

`velero_chart_version` and `velero_plugin_aws_version` are pinned per environment in `environments/*.auto.tfvars.json` — check the [Velero Helm chart releases](https://github.com/vmware-tanzu/helm-charts/releases) and [velero-plugin-for-aws releases](https://github.com/vmware-tanzu/velero-plugin-for-aws/releases) for current/compatible versions before bumping.

#### Usage

Install the [Velero CLI](https://velero.io/docs/main/basic-install/#install-the-cli) locally and point `kubectl`/`velero` at the cluster (the `velero` namespace):

```bash
# confirm the server + node-agent are running
kubectl get pods -n velero

# confirm the backup storage location is healthy (Phase: Available)
velero backup-location get

# on-demand backup of a single namespace
velero backup create manual-$(date +%Y%m%d%H%M%S) --include-namespaces <namespace>

# full cluster backup (cluster-scoped resources + EBS volume snapshots),
# excluding system namespaces - use before risky changes (upgrades, major
# deploys, Karpenter/NodePool changes) and for periodic prod/DR snapshots
velero backup create prod-backup-$(date +%Y%m%d-%H%M) \
  --include-namespaces '*' \
  --exclude-namespaces kube-system,kube-public,kube-node-lease,velero \
  --include-cluster-resources=true \
  --snapshot-volumes

# check backup status / details / logs
velero backup get
velero backup describe <backup-name> --details
velero backup logs <backup-name>

# delete a backup (and its EBS snapshots) once no longer needed
velero backup delete <backup-name>

# verify the daily schedule is enabled and running
velero schedule get

# restore from a backup (same cluster or a freshly provisioned one),
# including cluster-scoped resources (CRDs, ClusterRoles, etc.)
velero restore create dr-restore-$(date +%Y%m%d%H%M) \
  --from-backup <backup-name> \
  --include-cluster-resources=true

# check restore status / details / logs
velero restore get
velero restore describe <restore-name> --details
velero restore logs <restore-name>
```

#### Disaster recovery

**Why it matters:** the daily `daily-backup` schedule plus on-demand full
backups (with `--include-cluster-resources` and `--snapshot-volumes`) are
the only way to recover cluster state - namespaces, workloads, RBAC, CRDs,
ConfigMaps/Secrets, and PV data (via EBS snapshots) - after accidental
deletion, a bad rollout, or loss of the cluster itself.

Routine (production):

1. Confirm the daily schedule is running: `velero schedule get` and
   `velero backup get` (latest run should be `Phase: Completed`).
2. Before any high-risk change (cluster/add-on upgrade, major app release,
   Karpenter/NodePool changes), take an on-demand full backup using the
   `prod-backup-*` command above and confirm `Phase: Completed` via
   `velero backup describe <name> --details` before proceeding.

DR restore (cluster lost or corrupted):

1. Re-provision the EKS cluster with this module using the same
   `cluster_name` (`terraform apply`), so Velero's pod-identity role and the
   existing S3 backup bucket/KMS key are reused.
2. Confirm Velero can see prior backups: `velero backup get`.
3. Restore the most recent good backup with the `restore create` command
   above, then monitor with `velero restore describe --details` /
   `velero restore logs`.
4. Validate restored workloads, PVCs/PVs (data restored from EBS snapshots),
   and application functionality before routing traffic back.

> **Note:** the backup bucket and KMS key are provisioned alongside the
> cluster in `velero.tf`. If the whole stack (including the bucket) is
> destroyed, its backups are lost too - for region-level DR, consider
> replicating the bucket cross-region or protecting it with
> `prevent_destroy` (not currently configured).

### Continuous Deployment (Argo CD)

[`argocd.tf`](argocd.tf) installs [Argo CD](https://argo-cd.readthedocs.io/) via Helm from `argo-helm`, pinned to `var.argocd_chart_version`:

- All components (`controller`, `server`, `repoServer`, `applicationSet`, `redis`) are pinned to the managed node group (`nodeSelector: nodegroup: <node_group_name>`) via [`tpl/argocd_values.tpl`](tpl/argocd_values.tpl), with tolerations so they also tolerate Karpenter taints.
- `dex` (SSO) is disabled — the built-in `admin` account / local users are used.
- The `argocd-server` Service is `ClusterIP`; access is via `kubectl port-forward` or the Argo CD CLI (see Usage below). No ingress/load balancer is provisioned here.

`argocd_chart_version` is pinned per environment in `environments/*.auto.tfvars.json` — check the [Argo Helm chart releases](https://github.com/argoproj/argo-helm/releases) for current/compatible versions before bumping.

#### Usage

```bash
# confirm the components are running
kubectl get pods -n argocd

# retrieve the initial admin password (delete the secret afterwards, per Argo CD docs)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

# port-forward the API/UI locally
kubectl -n argocd port-forward svc/argocd-server 8080:443

# log in via the Argo CD CLI (https://argo-cd.readthedocs.io/en/stable/cli_installation/)
argocd login localhost:8080 --username admin

# register an Application
argocd app create <app-name> \
  --repo <git-repo-url> \
  --path <path-in-repo> \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace <namespace>

argocd app sync <app-name>
argocd app get <app-name>
```

### Certificate management (cert-manager)

[`cert-manager.tf`](cert-manager.tf) installs [cert-manager](https://cert-manager.io/) via Helm from `jetstack/cert-manager`, pinned to `var.cert_manager_chart_version`:

- CRDs are installed and kept on `helm uninstall` (`crds.enabled = true`, `crds.keep = true`).
- The controller, `webhook`, `cainjector`, and `startupapicheck` components are pinned to the managed node group (`nodeSelector: nodegroup: <node_group_name>`) via [`tpl/cert_manager_values.tpl`](tpl/cert_manager_values.tpl), with tolerations so they also tolerate Karpenter taints. The controller, webhook, and cainjector run `replicaCount: 2` with a PDB (`minAvailable: 1`) and preferred pod anti-affinity across hosts for HA.
- `module.cert_manager_pod_identity` (`terraform-aws-modules/eks-pod-identity/aws`, `attach_cert_manager_policy = true`, scoped to all hosted zones via `arn:aws:route53:::hostedzone/*`) grants Route53 DNS-01 challenge permissions to the `cert-manager/cert-manager` service account via EKS Pod Identity — no static AWS credentials or IRSA annotations needed.

`cert_manager_chart_version` is pinned per environment in `environments/*.auto.tfvars.json` — check the [cert-manager Helm chart releases](https://github.com/cert-manager/cert-manager/releases) for current/compatible versions before bumping.

## Repository layout

```
.
├── argocd.tf                                  # Argo CD Helm release
├── backend.tf                                # S3 backend config
├── cert-manager.tf                           # cert-manager Helm release
├── cluster-autoscaler.tf                     # Cluster Autoscaler pod-identity role + Helm release
├── data.tf                                   # VPC/subnet discovery (by tag)
├── eks-addons.tf                             # aws-ebs-csi-driver via eks-blueprints-addons
├── karpenter_deployment.tf                   # Karpenter module, Helm releases, NodePool/NodeClass manifests
├── locals.tf                                 # app_namespaces, tpl/*.yaml manifest discovery
├── main.tf                                   # EKS cluster, managed node group, namespace IAM/pod-identity
├── namespaces.tf                             # Kubernetes namespaces for app_namespaces
├── outputs.tf                                # cluster + karpenter + velero outputs
├── secrets-store-csi-driver-provider-aws.tf  # Secrets Store CSI driver + AWS provider Helm releases
├── serviceaccounts.tf                        # Service accounts for app_namespaces
├── variables.tf
├── velero.tf                                 # Velero S3 bucket/KMS, pod-identity role, Helm release
├── versions.tf                               # providers: aws, kubernetes, helm
├── environments/                             # one *.auto.tfvars.json per environment
│   ├── dev.auto.tfvars.json
│   ├── qa.auto.tfvars.json
│   ├── uat.auto.tfvars.json
│   └── prod.auto.tfvars.json
└── tpl/
    ├── argocd_values.tpl                     # Helm values template for the argo-cd chart
    ├── cert_manager_values.tpl               # Helm values template for the cert-manager chart
    ├── karpenter_values.tpl                  # Helm values template for the karpenter chart
    ├── velero_values.tpl                     # Helm values template for the velero chart
    ├── arm-node-class.yaml / arm-node-pool.yaml
    └── amd-node-class.yaml / amd-node-pool.yaml
```

## Environments

| Environment | `cluster_name` | AWS Account | Region |
|---|---|---|---|
| Development | `dev` | 891543987898 | ap-south-1 |
| QA | `qa` | 891543987898 | ap-south-1 |
| UAT | `uat` | 891543987898 | ap-south-1 |
| Production | `prod` | 891543987898 | ap-south-1 |

## Usage

```bash
terraform init
terraform workspace select <env> || terraform workspace new <env>

terraform plan  -var-file=environments/<env>.auto.tfvars.json -out=tfplan
terraform apply tfplan
```

`<env>` is the basename of a file in `environments/` (`dev`, `qa`, `uat`, `prod`).

## Variables

See [`variables.tf`](variables.tf) for full descriptions and validation rules.

| Variable | Description |
|---|---|
| `aws_region` | AWS region |
| `aws_account_id` | 12-digit AWS account ID |
| `aws_assume_role` | IAM role path assumed by the providers |
| `cluster_name` | EKS cluster name |
| `eks_version` | Kubernetes control plane version (`1.2x`/`1.3x`) |
| `enable_log_types` | Control plane log types to enable |
| `node_subnet_identifier` | `Tier` tag used to discover node subnets |
| `intra_subnet_identifier` | `Tier` tag used to discover control-plane subnets |
| `node_group_name` | EKS managed node group name |
| `node_group_role` | `node.kubernetes.io/role` label value for the managed node group |
| `node_group_ami_type` | `AL2_x86_64` \| `BOTTLEROCKET_x86_64` \| `AL2_ARM_64` \| `BOTTLEROCKET_ARM_64` |
| `node_group_capacity_type` | `ON_DEMAND` \| `SPOT` |
| `node_group_disk_size` | Root volume size in GB (10–99) |
| `node_group_desired_size` / `node_group_min_size` / `node_group_max_size` | Node group scaling bounds |
| `node_group_instance_types` | EC2 instance types for the managed node group |
| `addon_coredns_version` | CoreDNS EKS add-on version |
| `addon_eks_pod_identity_agent_version` | EKS Pod Identity Agent EKS add-on version |
| `addon_kube_proxy_version` | kube-proxy EKS add-on version |
| `addon_vpc_cni_version` | VPC CNI EKS add-on version |
| `addon_ebs_csi_driver_version` | EBS CSI Driver EKS add-on version |
| `karpenter_chart_version` | Karpenter Helm chart version (CRDs + controller) |
| `secrets_store_csi_driver_chart_version` | Secrets Store CSI Driver Helm chart version |
| `secrets_provider_aws_chart_version` | Secrets Store CSI Driver AWS provider Helm chart version |
| `velero_chart_version` | Velero Helm chart version |
| `velero_plugin_aws_version` | `velero-plugin-for-aws` image tag (S3 backup storage + EBS volume snapshots) |
| `velero_backup_schedule` | Cron expression for the default Velero backup schedule |
| `velero_backup_ttl` | TTL for backups created by the default schedule, e.g. `720h` (30 days) |
| `velero_backup_retention_days` | Days to retain noncurrent versions in the Velero S3 backup bucket |
| `argocd_chart_version` | Argo CD Helm chart version |
| `cluster_autoscaler_chart_version` | Cluster Autoscaler Helm chart version |
| `cert_manager_chart_version` | cert-manager Helm chart version |

## Linting / scanning

```bash
terraform fmt -check
terraform validate
trivy config --config trivy.yaml .
checkov -d . --framework terraform --quiet
```

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.9
- AWS credentials able to assume `var.aws_assume_role` in the target account
- An existing VPC named `<cluster_name>-vpc` with subnets tagged `Tier=<node_subnet_identifier>` and `Tier=<intra_subnet_identifier>`
