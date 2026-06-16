module "eks_addons" {
  #checkov:skip=CKV_AWS_124: observability_tag=null sets count=0 for usage_telemetry; Checkov flags it statically regardless
  source     = "aws-ia/eks-blueprints-addons/aws"
  version    = "~> 1.23.0"
  depends_on = [module.eks, kubernetes_namespace.apps]

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # Disable the module's usage-telemetry CloudFormation stack (CKV_AWS_124)
  observability_tag = null

  eks_addons = {
    aws-ebs-csi-driver = {
      addon_version = var.addon_ebs_csi_driver_version
    }
  }
}

module "aws_ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.8.0"

  name = "aws-ebs-csi"

  attach_aws_ebs_csi_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }
}

# module "ebs_csi_irsa_role" {
#   source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
#   version = "5.58.0"

#   role_path             = "/Roles/"
#   role_name             = "${var.cluster_name}-ebs-csi-controller-sa"
#   attach_ebs_csi_policy = true

#   oidc_providers = {
#     main = {
#       provider_arn               = module.eks.oidc_provider_arn
#       namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
#     }
#   }
# }
