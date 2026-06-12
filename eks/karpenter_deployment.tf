module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.22.0"

  cluster_name = module.eks.cluster_name

  create_pod_identity_association = true

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

# apply crd updates directly
resource "helm_release" "karpenter-crd" {
  namespace  = "kube-system"
  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = var.karpenter_chart_version
  wait       = true
  values     = []
}

resource "helm_release" "karpenter" {
  depends_on = [helm_release.karpenter-crd, module.karpenter]
  namespace  = "kube-system"
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_chart_version
  wait       = true
  skip_crds  = true

  values = [
    templatefile("tpl/karpenter_values.tpl", {
      iam_role_arn     = module.karpenter.iam_role_arn
      node_group_name  = var.node_group_name
      node_group_role  = var.node_group_role
      cluster_name     = var.cluster_name
      cluster_endpoint = module.eks.cluster_endpoint
      queue_name       = module.karpenter.queue_name
    }),
  ]
}
