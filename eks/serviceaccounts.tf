
resource "kubernetes_service_account" "app_secrets_sa" {
  for_each = local.app_namespaces

  metadata {
    name      = each.key
    namespace = kubernetes_namespace.apps[each.key].metadata[0].name

    labels = {
      managed-by = "terraform"
      purpose    = "secrets-access"
    }
  }

  depends_on = [
    kubernetes_namespace.apps
  ]
}