# IamProfilesRole
#
# Used by: IamProfiles pipeline
# manages iam policy for platform roles, groups, and service accounts
module "IamProfilesRole" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.3.0"
  create  = true

  name            = "IamProfilesRole"
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
    custom = aws_iam_policy.IamProfilesRolePolicy.arn,
    state  = aws_iam_policy.S3StateBucketPolicy.arn
  }
}

# role permissions
resource "aws_iam_policy" "IamProfilesRolePolicy" {
  name = "IamProfilesRolePolicy"
  path = "/Policies/"

  policy = jsonencode({
    "Version" : "2012-10-17"
    "Statement" : [
      {
        "Action" : [
          "iam:AddUserToGroup",
          "iam:AttachGroupPolicy",
          "iam:AttachRolePolicy",
          "iam:AttachUserPolicy",
          "iam:ChangePassword",
          "iam:CreateAccessKey",
          "iam:CreateAccountAlias",
          "iam:CreateGroup",
          "iam:CreateLoginProfile",
          "iam:CreatePolicy",
          "iam:CreatePolicyVersion",
          "iam:CreateRole",
          "iam:CreateUser",
          "iam:DeleteAccessKey",
          "iam:DeleteGroup",
          "iam:DeleteGroupPolicy",
          "iam:DeleteLoginProfile",
          "iam:DeletePolicy",
          "iam:DeletePolicyVersion",
          "iam:DeleteRole",
          "iam:DeleteRolePolicy",
          "iam:DeleteSSHPublicKey",
          "iam:DeleteUser",
          "iam:DeleteUserPolicy",
          "iam:DetachGroupPolicy",
          "iam:DetachRolePolicy",
          "iam:DetachUserPolicy",
          "iam:GetAccessKeyLastUsed",
          "iam:GetContextKeysForCustomPolicy",
          "iam:GetContextKeysForPrincipalPolicy",
          "iam:GetGroup",
          "iam:GetGroupPolicy",
          "iam:GetLoginProfile",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:GetUser",
          "iam:GetUserPolicy",
          "iam:ListAccessKeys",
          "iam:ListAccountAliases",
          "iam:ListAttachedGroupPolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListAttachedUserPolicies",
          "iam:ListEntitiesForPolicy",
          "iam:ListGroupPolicies",
          "iam:ListGroups",
          "iam:ListGroupsForUser",
          "iam:ListInstanceProfiles",
          "iam:ListInstanceProfilesForRole",
          "iam:ListPolicies",
          "iam:ListPolicyVersions",
          "iam:ListRolePolicies",
          "iam:ListRoles",
          "iam:ListUserPolicies",
          "iam:ListUsers",
          "iam:PutGroupPolicy",
          "iam:PutRolePolicy",
          "iam:PutUserPolicy",
          "iam:RemoveUserFromGroup",
          "iam:SetDefaultPolicyVersion",
          "iam:SimulateCustomPolicy",
          "iam:SimulatePrincipalPolicy",
          "iam:UpdateAccessKey",
          "iam:UpdateAssumeRolePolicy",
          "iam:UpdateGroup",
          "iam:UpdateLoginProfile",
          "iam:UpdateUser",
          "iam:TagPolicy",
          "iam:TagRole",
          "iam:TagUser",
          "iam:CreateOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviders",
          "iam:ListOpenIDConnectProviderTags",
          "iam:GetOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider",
        ]
        "Effect" : "Allow"
        "Resource" : "*"
      },
    ]
  })
}