module "iam_oidc_provider" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-oidc-provider"
  version = "6.3.0"

  create = var.is_state_account
  url    = "https://token.actions.githubusercontent.com"

  tags = {
    Terraform = "true"
  }
}

#Used by Github actions
module "GHActionsRole" {
  count   = var.is_state_account ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.3.0"

  name            = "GHActionsRole"
  path            = "/Roles/"
  use_name_prefix = false

  enable_github_oidc = true

  oidc_wildcard_subjects = ["repo:mlkrtk/*"]

  policies = {
    custom = aws_iam_policy.assume_target_accounts[0].arn,
    state  = aws_iam_policy.S3StateBucketPolicy.arn
  }

  tags = {
    Terraform = "true"
  }
}

data "aws_iam_policy_document" "assume_target_accounts" {
  statement {
    sid    = "AssumeTargetGHActionsRoles"
    effect = "Allow"

    actions = [
      "sts:AssumeRole"
    ]

    resources = [
      "arn:aws:iam::${var.aws_account_id}:role/Roles/*"
    ]
  }
}

resource "aws_iam_policy" "assume_target_accounts" {
  count       = var.is_state_account ? 1 : 0
  name        = "assume-target-account-roles"
  description = "Allows assuming the Terraform deployment role in target accounts"
  policy      = data.aws_iam_policy_document.assume_target_accounts.json
}
