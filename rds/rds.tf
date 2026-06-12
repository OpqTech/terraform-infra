locals {
  environment = var.vpc_name
}

resource "random_password" "dbmaster" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_ssm_parameter" "dbmaster-param" {
  name        = "/${local.environment}/database/master/password"
  description = "Aurora PostgreSQL password for ${local.environment}"
  type        = "SecureString"
  value       = random_password.dbmaster.result
  key_id      = aws_kms_key.rds_key.arn
}

resource "aws_ssm_parameter" "dbmaster-user" {
  name        = "/${local.environment}/database/master/username"
  description = "Aurora PostgreSQL username for ${local.environment}"
  type        = "SecureString"
  value       = var.rds_master_username
  key_id      = aws_kms_key.rds_key.arn
}

resource "aws_ssm_parameter" "db-name" {
  name        = "/${local.environment}/database/name"
  description = "Aurora PostgreSQL name for ${local.environment}"
  type        = "SecureString"
  value       = var.rds_database_name
  key_id      = aws_kms_key.rds_key.arn
}

resource "aws_rds_cluster" "rds_cluster" {
  cluster_identifier   = "${var.rds_cluster_identifier}-${local.environment}-cluster"
  engine               = var.rds_engine
  engine_version       = var.rds_engine_version
  db_subnet_group_name = data.aws_db_subnet_group.selected.name

  database_name           = var.rds_database_name
  master_username         = var.rds_master_username
  master_password         = random_password.dbmaster.result
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  kms_key_id              = aws_kms_key.rds_key.arn
  storage_encrypted       = true
  backup_retention_period = var.rds_backup_retention_period
  copy_tags_to_snapshot   = true
  deletion_protection     = true
  #skip_final_snapshot = true
  final_snapshot_identifier = "${var.rds_database_name}-${local.environment}-${formatdate("YYYYMMDD", timestamp())}"

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.rds_cluster_pg.name
}

resource "aws_rds_cluster_parameter_group" "rds_cluster_pg" {
  name        = "${var.rds_cluster_identifier}-${local.environment}-cluster-pg"
  family      = "aurora-postgresql${split(".", var.rds_engine_version)[0]}"
  description = "Cluster parameter group for ${local.environment} Aurora PostgreSQL"

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "0"
  }
}

resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "${var.rds_cluster_identifier}-${local.environment}-rds-monitoring-role"
  path = "/Roles/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_rds_cluster_instance" "writer_instance" {
  count                           = var.rds_writer_replica_count
  identifier                      = "${var.rds_cluster_identifier}-${local.environment}-writer-${count.index}"
  cluster_identifier              = aws_rds_cluster.rds_cluster.id
  instance_class                  = var.rds_instance_class
  engine                          = var.rds_engine
  engine_version                  = var.rds_engine_version
  auto_minor_version_upgrade      = var.rds_auto_minor_version_upgrade
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.rds_key.arn
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_enhanced_monitoring.arn
  copy_tags_to_snapshot           = true
  tags                            = { role = "writer" }
}

resource "aws_rds_cluster_instance" "reader_instances" {
  count                           = var.rds_reader_replica_count
  identifier                      = "${var.rds_cluster_identifier}-${local.environment}-reader-${count.index}"
  cluster_identifier              = aws_rds_cluster.rds_cluster.id
  instance_class                  = var.rds_instance_class
  engine                          = var.rds_engine
  engine_version                  = var.rds_engine_version
  auto_minor_version_upgrade      = var.rds_auto_minor_version_upgrade
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.rds_key.arn
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_enhanced_monitoring.arn
  depends_on = [
    aws_rds_cluster_instance.writer_instance
  ]
  copy_tags_to_snapshot = true
  tags                  = { role = "reader" }
}

resource "aws_kms_key" "rds_key" {
  description             = "RDS encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowRDSServiceUse"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowSSMServiceUse"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowBackupServiceUse"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}