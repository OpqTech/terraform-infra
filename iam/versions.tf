terraform {
  required_version = "~> 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # this section commented out during the initial bootstrap run.
  # once the assumeable roles are created, uncomment and change
  # op.*.env to contain the appropriate service account identity
  # assume_role {
  #   role_arn     = "arn:aws:iam::${var.aws_account_id}:role/${var.aws_assume_role}"
  #   session_name = "aws-iam-profiles"
  # }

  default_tags {
    tags = {
      product    = "platform"
      pipeline   = "aws-iam-profiles"
      IAC_repo   = "https://github.com/mlkrtk/infra/iam"
      managed_by = "terraform"
    }
  }
}
