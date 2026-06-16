################################################################################
# AWS / Provider
################################################################################

variable "aws_region" {
  type = string
  validation {
    condition     = can(regex("[a-z][a-z]-[a-z]+-[1-9]", var.aws_region))
    error_message = "Invalid AWS Region name."
  }
}

variable "aws_account_id" {
  type = string
  validation {
    condition     = length(var.aws_account_id) == 12 && can(regex("^\\d{12}$", var.aws_account_id))
    error_message = "Invalid AWS account ID"
  }
}

variable "aws_assume_role" { type = string }

################################################################################
# Cluster
################################################################################

variable "cluster_name" {
  description = "cluster instance name"
  type        = string
}

variable "enable_log_types" {
  description = "list of control plane log types to be generated"
  type        = list(string)
}

variable "eks_version" {
  description = "EKS-kubernetes control plane version"
  type        = string

  validation {
    condition     = can(regex("^1.[2-3][0-9]$", var.eks_version))
    error_message = "Invalid EKS version number"
  }
}

variable "isControlPlanePrivate" {
  description = "When true, the EKS API endpoint is private-only and not accessible from the public internet. Management nodes remain in the private (node) subnets of the VPC."
  type        = bool
  default     = false
}

################################################################################
# Networking
################################################################################

variable "node_subnet_identifier" {
  description = "search string to identity node pool subnets"
  type        = string
}

variable "intra_subnet_identifier" {
  description = "search string to identity intra pool subnets"
  type        = string
}

################################################################################
# Managed node group
################################################################################

variable "node_group_name" {
  type = string
  validation {
    condition     = (length(var.node_group_name) < 63)
    error_message = "Invalid node group name. Must be less than 63 characters."
  }
}

variable "node_group_role" {
  type = string
  validation {
    condition     = (length(var.node_group_role) < 128)
    error_message = "Invalid node group role name. Must be less than 128 characters."
  }
}

variable "node_group_ami_type" {
  type = string
  validation {
    condition     = contains(["AL2_x86_64", "BOTTLEROCKET_x86_64", "AL2_ARM_64", "BOTTLEROCKET_ARM_64"], var.node_group_ami_type)
    error_message = "Invalid AMI Type. Use AL2_x86_64 | BOTTLEROCKET_x86_64 | AL2_ARM_64 | BOTTLEROCKET_ARM_64"
  }
}

variable "node_group_disk_size" {
  type = string
  validation {
    condition     = can(regex("^[1-9][0-9]$", var.node_group_disk_size))
    error_message = "Invalid node disk size. Use value between 10 to 99gb."
  }
}

variable "node_group_capacity_type" {
  type = string
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_group_capacity_type)
    error_message = "Invalid capacity Type. Use ON_DEMAND | SPOT"
  }
}

variable "node_group_desired_size" {
  type = string
  validation {
    condition     = can(regex("^[1-9][0-9]{0,2}$", var.node_group_desired_size))
    error_message = "Invalid desired node group size. Must be number beween 1-999"
  }
}

variable "node_group_max_size" {
  type = string
  validation {
    condition     = can(regex("^[1-9][0-9]{0,2}$", var.node_group_max_size))
    error_message = "Invalid max node group size. Must be number beween 1-999"
  }
}

variable "node_group_min_size" {
  type = string
  validation {
    condition     = can(regex("^[1-9][0-9]{0,2}$", var.node_group_min_size))
    error_message = "Invalid min node group size. Must be number beween 1-999"
  }
}

variable "node_group_instance_types" {
  description = "list of allowable ec2 instance types"
  type        = list(string)
}

################################################################################
# EKS Addon versions
################################################################################

variable "addon_coredns_version" {
  description = "CoreDNS EKS addon version compatible with the target eks_version"
  type        = string
}

variable "addon_eks_pod_identity_agent_version" {
  description = "EKS Pod Identity Agent addon version compatible with the target eks_version"
  type        = string
}

variable "addon_kube_proxy_version" {
  description = "kube-proxy EKS addon version compatible with the target eks_version"
  type        = string
}

variable "addon_vpc_cni_version" {
  description = "VPC CNI EKS addon version compatible with the target eks_version"
  type        = string
}

variable "addon_ebs_csi_driver_version" {
  description = "EBS CSI Driver EKS addon version compatible with the target eks_version"
  type        = string
}

################################################################################
# Helm chart versions
################################################################################

variable "karpenter_chart_version" {
  description = "Karpenter Helm chart version to be installed"
  type        = string
}

variable "secrets_store_csi_driver_chart_version" {
  description = "Secrets Store CSI Driver Helm chart version to be installed"
  type        = string
}

variable "secrets_provider_aws_chart_version" {
  description = "Secrets Provider AWS Helm chart version to be installed"
  type        = string
}

variable "velero_chart_version" {
  description = "Velero Helm chart version to be installed"
  type        = string
}

variable "velero_plugin_aws_version" {
  description = "Image tag for the velero-plugin-for-aws plugin (object storage + EBS volume snapshots)"
  type        = string
}

variable "velero_backup_schedule" {
  description = "Cron expression for the default Velero backup schedule"
  type        = string
}

variable "velero_backup_ttl" {
  description = "Time-to-live for backups created by the default schedule, e.g. '720h' for 30 days"
  type        = string
}

variable "velero_backup_retention_days" {
  description = "Number of days to retain noncurrent versions of objects in the Velero S3 backup bucket"
  type        = number
}

variable "argocd_chart_version" {
  description = "Argo CD Helm chart version to be installed"
  type        = string
}

variable "cluster_autoscaler_chart_version" {
  description = "Cluster Autoscaler Helm chart version to be installed"
  type        = string
}
