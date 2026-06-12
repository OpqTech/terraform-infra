# EKS

Terraform configuration that provisions the EKS control plane, baseline add-ons, the Karpenter autoscaler, and supporting IAM/secrets plumbing on top of an existing VPC.

State is stored in S3 (see [`backend.tf`](backend.tf)).

## Architecture

### Cluster

- EKS cluster via `terraform-aws-modules/eks/aws` (~> 21.22.0) — public API endpoint, `authentication_mode = "API"` (access entries; `GHAppDeployerRole` is granted `AmazonEKSClusterAdminPolicy`).
- A single EKS-managed node group (`var.node_group_name`, e.g. `managed-arm`) runs the cluster's system components. All other workload nodes are provisioned on demand by Karpenter.
- The VPC and subnets are **not** created here — they're discovered by tag from an existing VPC named `<cluster_name>-vpc`, with node subnets tagged `Tier=<node_subnet_identifier>` and control-plane subnets tagged `Tier=<intra_subnet_identifier>`.

### EKS add-ons

Installed as managed EKS add-ons in [`main.tf`](main.tf):

| Add-on | Notes |
|---|---|
| `coredns` | |
| `eks-pod-identity-agent` | |
| `kube-proxy` | |
| `vpc-cni` | own pod-identity association (`kube-system/aws-node`) |

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

### Secrets access

[`secrets-store-csi-driver-provider-aws.tf`](secrets-store-csi-driver-provider-aws.tf) installs the Secrets Store CSI Driver and its AWS provider via Helm.

For each namespace defined in `local.app_namespaces` ([`locals.tf`](locals.tf); currently just `dev`):

- a Kubernetes namespace is created (`istio-injection=enabled`) — [`namespaces.tf`](namespaces.tf)
- a Kubernetes service account is created — [`serviceaccounts.tf`](serviceaccounts.tf)
- an IAM role + policy granting `secretsmanager:GetSecretValue`/`DescribeSecret` and `ssm:GetParameter*` under `<cluster_name>/app/*` is associated to that service account via EKS Pod Identity — [`main.tf`](main.tf)

## Repository layout

```
.
├── backend.tf                                # S3 backend config
├── data.tf                                   # VPC/subnet discovery (by tag)
├── eks-addons.tf                             # aws-ebs-csi-driver via eks-blueprints-addons
├── karpenter_deployment.tf                   # Karpenter module, Helm releases, NodePool/NodeClass manifests
├── locals.tf                                 # app_namespaces, tpl/*.yaml manifest discovery
├── main.tf                                   # EKS cluster, managed node group, namespace IAM/pod-identity
├── namespaces.tf                             # Kubernetes namespaces for app_namespaces
├── outputs.tf                                # cluster + karpenter outputs
├── secrets-store-csi-driver-provider-aws.tf  # Secrets Store CSI driver + AWS provider Helm releases
├── serviceaccounts.tf                        # Service accounts for app_namespaces
├── variables.tf
├── versions.tf                               # providers: aws, kubernetes, helm
├── environments/                             # one *.auto.tfvars.json per environment
│   ├── dev.auto.tfvars.json
│   ├── qa.auto.tfvars.json
│   ├── uat.auto.tfvars.json
│   └── prod.auto.tfvars.json
└── tpl/
    ├── karpenter_values.tpl                  # Helm values template for the karpenter chart
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
| `karpenter_chart_version` | Karpenter Helm chart version (CRDs + controller) |
| `secrets_store_csi_driver_chart_version` | Secrets Store CSI Driver Helm chart version |
| `secrets_provider_aws_chart_version` | Secrets Store CSI Driver AWS provider Helm chart version |

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
