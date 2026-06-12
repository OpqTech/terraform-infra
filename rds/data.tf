data "aws_caller_identity" "current" {}

data "aws_vpc" "selected" {
  tags = {
    Name = "${var.vpc_name}-vpc"
  }
}

data "aws_db_subnet_group" "selected" {
  name = "${var.vpc_name}-vpc"
}
