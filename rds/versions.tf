terraform {
  required_version = "~> 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn     = "arn:aws:iam::${var.aws_account_id}:role/${var.aws_assume_role}"
    session_name = "aws-platform-rds-${var.vpc_name}"
  }

  default_tags {
    tags = {
      env      = var.vpc_name
      cluster  = var.vpc_name
      pipeline = "aws-platform-rds"
    }
  }
}
