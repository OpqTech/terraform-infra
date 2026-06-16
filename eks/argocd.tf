################################################################################
# Helm Release
################################################################################

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = var.argocd_chart_version
  wait             = true

  values = [
    templatefile("tpl/argocd_values.tpl", {
      node_group_name = var.node_group_name
    }),
  ]

  depends_on = [module.eks]
}
