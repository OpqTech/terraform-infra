resource "aws_security_group" "rds_sg" {
  name        = "opq-${local.environment}-rds-sg"
  description = "opq-${local.environment}-vpc-rds-sg"
  vpc_id      = data.aws_vpc.selected.id

  egress {
    description = "Allow outbound traffic within the VPC"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  ingress {
    description = "Rule for VPC Link"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }
}
