# IamProfilesRole
#
#Used by Github actions
module "GHAppDeployerRole" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.3.0"
  create  = true

  name            = "GHAppDeployerRole"
  path            = "/Roles/"
  use_name_prefix = false

  enable_github_oidc = true

  oidc_wildcard_subjects = ["repo:mlkrtk/*"]

  policies = {
    custom = aws_iam_policy.AppDeployerRolePolicy.arn
  }

  tags = {
    Terraform = "true"
  }
}

#Used by Developers for testing
module "AppDeployerRole" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.3.0"
  create  = true

  name            = "AppDeployerRole"
  path            = "/Roles/"
  use_name_prefix = false

  trust_policy_permissions = {
    TrustRoleAndServiceToAssume = {
      actions = [
        "sts:TagSession",
        "sts:AssumeRole",
      ]
      principals = [{
        type = "AWS"
        identifiers = [
          "arn:aws:iam::${var.aws_account_id}:root",
        ]
      }]
    }
  }

  policies = {
    custom = aws_iam_policy.AppDeployerRolePolicy.arn
  }
}

# role permissions
resource "aws_iam_policy" "AppDeployerRolePolicy" {
  name = "AppDeployerRolePolicy"
  path = "/Policies/"

  policy = jsonencode({
    "Version" : "2012-10-17"
    "Statement" : [
      {
        "Action" : [
          "ecr:*",
          "eks:*",
          "secretsmanager:GetRandomPassword",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:UntagResource",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds",
          "secretsmanager:ListSecrets",
          "secretsmanager:BatchGetSecretValue",
          "secretsmanager:TagResource",
          "ssm:GetParameter",
          "kms:Sign",
          "kms:GetPublicKey"
        ]
        "Effect" : "Allow"
        "Resource" : "*"
      },
    ]
  })
}
