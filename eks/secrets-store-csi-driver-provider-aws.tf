resource "helm_release" "secrets_store_csi_driver" {
  name       = "secrets-store-csi-driver"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = "kube-system"
  version    = var.secrets_store_csi_driver_chart_version
  wait       = true

  values = [
    yamlencode({
      enableSecretRotation = true
      rotationPollInterval = "2m"

      linux = {
        tolerations = [{ operator = "Exists" }]
      }
      tokenRequests = [
        {
          audience          = "sts.amazonaws.com"
          expirationSeconds = 3600
        },
        {
          audience          = "pods.eks.amazonaws.com"
          expirationSeconds = 3600
        }
      ]
    })
  ]

  depends_on = [module.eks]
}

resource "helm_release" "secrets_provider_aws" {
  name       = "secrets-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  namespace  = "kube-system"
  version    = var.secrets_provider_aws_chart_version
  wait       = true

  values = [
    yamlencode({
      "secrets-store-csi-driver" = { install = false }
    })
  ]

  depends_on = [helm_release.secrets_store_csi_driver]
}