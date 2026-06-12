locals {
  app_namespaces = {
    dev = {
      environment    = var.cluster_name
      secrets_prefix = "${var.cluster_name}/app/"
    }
  }
}