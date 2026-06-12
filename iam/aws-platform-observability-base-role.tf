# PlatformObservabilityBaseRole
#
# Used by: -aws-iam-profiles pipeline
# manages iam policy for platform roles, groups, and service accounts

module "PlatformObservabilityBaseRole" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.3.0"
  create  = true

  name            = "PlatformObservabilityBaseRole"
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
    custom = aws_iam_policy.PlatformObservabilityBaseRolePolicy.arn,
    state  = aws_iam_policy.S3StateBucketPolicy.arn
  }
}

# role permissions
resource "aws_iam_policy" "PlatformObservabilityBaseRolePolicy" {
  name = "PlatformObservabilityBaseRolePolicy"
  path = "/Policies/"

  policy = jsonencode({
    "Version" : "2012-10-17"
    "Statement" : [
      {
        "Action" : [
          "logs:CreateLogGroup",
          "logs:DescribeLogGroups",
          "logs:DeleteLogGroup",
          "logs:ListTagsLogGroup",
          "logs:PutRetentionPolicy",
          "logs:TagLogGroup",
          "logs:UntagLogGroup",
          "aps:*"
        ]
        "Effect" : "Allow"
        "Resource" : "*"
      },
    ]
  })
}
