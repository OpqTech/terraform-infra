module "PlatformStorageRole" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.3.0"
  create  = true

  name            = "PlatformStorageRole"
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
    custom = aws_iam_policy.PlatformStorageRolePolicy.arn,
    state  = aws_iam_policy.S3StateBucketPolicy.arn
  }
}

# role permissions
resource "aws_iam_policy" "PlatformStorageRolePolicy" {
  #checkov:skip=CKV2_AWS_40: "Broad permissions until filtered"
  #trivy:ignore:AWS-0345 "Broad permissions until filtered"
  name = "PlatformStorageRolePolicy"
  path = "/Policies/"

  policy = jsonencode({
    "Version" : "2012-10-17"
    "Statement" : [
      {
        "Action" : [
          "s3:*",
          "rds:*",
          "iam:*",
          "vpc:*",
          "ec2:*",
          "ecs:*",
          "elasticloadbalancing:*",
          "logs:*",
          "secretsmanager:*",
          "ssm:*",
          "kms:*",
          "backup:*",
          "backup-storage:*",
          "iam:PutRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:PassRole",
          "ecr:TagResource",
          "ecr:UntagResource",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:ListImages",
          "ecr:DescribeRepositories",
          "ecr:TagResource",
          "ecr:UntagResource",
          "ecr:ListTagsForResource",
          "ecr:CreateRepository",
          "ecr:DeleteRepository",
          "ecr:SetRepositoryPolicy",
          "ecr:DeleteRepositoryPolicy",
          "ecr:GetLifecyclePolicy",
          "ecr:PutLifecyclePolicy",
          "ecr:DeleteLifecyclePolicy"
        ]
        "Effect" : "Allow",
        "Resource" : "*"
      }
    ]
  })
}