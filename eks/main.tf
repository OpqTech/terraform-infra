module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.22.0"

  name               = var.cluster_name
  kubernetes_version = var.eks_version

  endpoint_public_access                   = true
  endpoint_private_access                  = false
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  upgrade_policy = {
    support_type = "STANDARD"
  }

  access_entries = {
    # Administrators = {
    #   principal_arn = "arn:aws:iam::${var.aws_account_id}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_540504b3a3e11ffa"
    #   policy_associations = {
    #     adminAccess = {
    #       policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    #       access_scope = {
    #         type = "cluster"
    #       }
    #     }
    #   }
    # }

    GithubDeployer = {
      principal_arn = "arn:aws:iam::${var.aws_account_id}:role/Roles/GHAppDeployerRole"
      policy_associations = {
        arcRunnersAccess = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  vpc_id                   = data.aws_vpc.vpc.id
  subnet_ids               = data.aws_subnets.cluster_private_subnets.ids
  control_plane_subnet_ids = data.aws_subnets.cluster_intra_subnets.ids

  enabled_log_types = var.enable_log_types
  create_kms_key    = true

  iam_role_use_name_prefix = false

  addons = {
    coredns = {
      addon_version               = var.addon_coredns_version
      before_compute              = true
      resolve_conflicts_on_update = "OVERWRITE"
    }

    eks-pod-identity-agent = {
      addon_version               = var.addon_eks_pod_identity_agent_version
      before_compute              = true
      resolve_conflicts_on_update = "OVERWRITE"
    }

    kube-proxy = {
      addon_version               = var.addon_kube_proxy_version
      before_compute              = true
      resolve_conflicts_on_update = "OVERWRITE"
    }

    vpc-cni = {
      addon_version               = var.addon_vpc_cni_version
      before_compute              = true
      resolve_conflicts_on_update = "OVERWRITE"
    }
  }

  eks_managed_node_groups = {
    # dedicated mgmt node group, other node groups managed by karpenter
    (var.node_group_name) = {
      ami_type             = var.node_group_ami_type
      instance_types       = var.node_group_instance_types
      capacity_type        = var.node_group_capacity_type
      min_size             = var.node_group_min_size
      max_size             = var.node_group_max_size
      desired_size         = var.node_group_desired_size
      disk_size            = var.node_group_disk_size
      subnet_ids           = data.aws_subnets.cluster_private_subnets.ids
      force_update_version = true

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }
      labels = {
        "nodegroup"               = var.node_group_name
        "node.kubernetes.io/role" = var.node_group_role
        "karpenter.sh/controller" = "true"
      }
    }
  }

  node_security_group_additional_rules = {
    allow_data_plane_tcp = {
      description                   = "Allow TCP Protocol Port"
      protocol                      = "TCP"
      from_port                     = 1024
      to_port                       = 65535
      type                          = "ingress"
      source_cluster_security_group = true
    }
    allow_data_plane_udp = {
      description                   = "Allow UDP Protocol Port"
      protocol                      = "UDP"
      from_port                     = 0
      to_port                       = 65535
      type                          = "ingress"
      source_cluster_security_group = true
    }
    allow_node_to_node_tcp = {
      description              = "Allow node to node TCP communication"
      protocol                 = "TCP"
      from_port                = 0
      to_port                  = 65535
      type                     = "ingress"
      source_security_group_id = module.eks.node_security_group_id
    }
    allow_node_to_node_udp = {
      description              = "Allow node to node UDP communication"
      protocol                 = "UDP"
      from_port                = 0
      to_port                  = 65535
      type                     = "ingress"
      source_security_group_id = module.eks.node_security_group_id
    }
  }

  tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}


resource "aws_iam_policy" "namespace_secrets" {
  for_each = local.app_namespaces

  name = "${var.cluster_name}-${each.key}-secrets-read"
  path = "/Roles/"

  description = "Secrets Manager access for ${each.key}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${each.value.secrets_prefix}*"
        ]
      },
      {
        Sid    = "SSMParameterRead"
        Effect = "Allow"

        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]

        Resource = [
          "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${each.value.secrets_prefix}*"
        ]
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"

        Action = [
          "kms:Decrypt"
        ]

        Resource = [
          "arn:aws:kms:${var.aws_region}:${var.aws_account_id}:key/*"
        ]

        Condition = {
          StringEquals = {
            "kms:ViaService" = [
              "secretsmanager.${var.aws_region}.amazonaws.com",
              "ssm.${var.aws_region}.amazonaws.com"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "namespace_pod_identity" {
  for_each = local.app_namespaces

  name = "${var.cluster_name}-${each.key}-secrets-role"
  path = "/Roles/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "pods.eks.amazonaws.com"
        }

        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

module "aws_vpc_cni_ipv4_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.8.0"

  name                      = "aws-vpc-cni-ipv4"
  attach_aws_vpc_cni_policy = true
  aws_vpc_cni_enable_ipv4   = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-node"
    }
  }
}

# module "vpc_cni_irsa_role" {
#   source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
#   version = "5.58.0"

#   role_path             = "/Roles/"
#   role_name             = "${var.cluster_name}-vpc-cni"
#   attach_vpc_cni_policy = true
#   vpc_cni_enable_ipv4   = true

#   oidc_providers = {
#     main = {
#       provider_arn               = module.eks.oidc_provider_arn
#       namespace_service_accounts = ["kube-system:aws-node"]
#     }
#   }
# }

# # The vpc_cni_irsa_role module's bundled AmazonEKS_CNI_Policy copy predates
# # ec2:DescribeSecurityGroups, which vpc-cni >=1.18 requires for its
# # secondary-subnet security group discovery during ipamd init (without it,
# # init fails fatally rather than just falling back).
# resource "aws_iam_role_policy" "vpc_cni_describe_security_groups" {
#   name = "${var.cluster_name}-vpc-cni-describe-security-groups"
#   role = module.vpc_cni_irsa_role.iam_role_name

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid      = "DescribeSecurityGroups"
#         Effect   = "Allow"
#         Action   = ["ec2:DescribeSecurityGroups"]
#         Resource = "*"
#       }
#     ]
#   })
# }

resource "aws_iam_role_policy_attachment" "namespace_attach" {
  for_each = local.app_namespaces

  role       = aws_iam_role.namespace_pod_identity[each.key].name
  policy_arn = aws_iam_policy.namespace_secrets[each.key].arn
}


resource "aws_eks_pod_identity_association" "namespace" {
  for_each = local.app_namespaces

  cluster_name = module.eks.cluster_name

  namespace       = each.key
  service_account = kubernetes_service_account.app_secrets_sa[each.key].metadata[0].name

  role_arn = aws_iam_role.namespace_pod_identity[each.key].arn
  depends_on = [
    kubernetes_service_account.app_secrets_sa
  ]
}
