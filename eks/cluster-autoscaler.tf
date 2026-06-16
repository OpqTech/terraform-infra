################################################################################
# Pod Identity
################################################################################

module "cluster_autoscaler_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.8.0"

  name = "cluster-autoscaler"

  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "cluster-autoscaler"
    }
  }
}

################################################################################
# Helm Release
################################################################################

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = var.cluster_autoscaler_chart_version
  wait       = true

  values = [
    yamlencode({
      autoDiscovery = {
        clusterName = module.eks.cluster_name
      }
      awsRegion = var.aws_region

      rbac = {
        serviceAccount = {
          create = true
          name   = "cluster-autoscaler"
        }
      }

      replicaCount = 2

      nodeSelector = {
        nodegroup = var.node_group_name
      }
      tolerations = [{ operator = "Exists" }]

      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [{
            weight = 100
            podAffinityTerm = {
              topologyKey = "kubernetes.io/hostname"
              labelSelector = {
                matchLabels = {
                  "app.kubernetes.io/name" = "aws-cluster-autoscaler"
                }
              }
            }
          }]
        }
      }

      extraArgs = {
        "balance-similar-node-groups"   = true
        "skip-nodes-with-local-storage" = false
        "expander"                      = "least-waste"
      }

      resources = {
        requests = {
          cpu    = "100m"
          memory = "300Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "600Mi"
        }
      }
    })
  ]

  depends_on = [module.eks, module.cluster_autoscaler_pod_identity]
}