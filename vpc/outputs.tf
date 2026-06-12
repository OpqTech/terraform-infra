output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_arn" {
  value = module.vpc.vpc_arn
}

output "vpc_cidr_block" {
  value = var.vpc_cidr
}

output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

output "public_cidr_blocks" {
  value = var.vpc_public_subnets
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "private_cidr_blocks" {
  value = var.vpc_private_subnets
}

output "database_subnet_ids" {
  value = module.vpc.database_subnets
}

output "database_cidr_blocks" {
  value = var.vpc_database_subnets
}

output "intra_subnet_ids" {
  value = module.vpc.intra_subnets
}

output "intra_cidr_blocks" {
  value = var.vpc_intra_subnets
}