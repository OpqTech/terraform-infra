resource "kubernetes_namespace" "apps" {
  for_each = local.app_namespaces

  metadata {
    name = each.key

    labels = {
      istio-injection = "enabled"
      environment     = each.value.environment
      managed-by      = "terraform"
      platform        = "eks"
    }
  }
}