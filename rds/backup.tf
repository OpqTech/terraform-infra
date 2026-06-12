resource "aws_backup_vault" "rds" {
  name        = "${var.rds_cluster_identifier}-${local.environment}-rds-vault"
  kms_key_arn = aws_kms_key.rds_key.arn
}

resource "aws_backup_plan" "rds" {
  name = "${var.rds_cluster_identifier}-${local.environment}-rds-backup-plan"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.rds.name
    schedule          = "cron(0 5 * * ? *)"

    lifecycle {
      delete_after = var.rds_backup_retention_period
    }
  }
}

resource "aws_iam_role" "backup" {
  name = "${var.rds_cluster_identifier}-${local.environment}-rds-backup-role"
  path = "/Roles/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_selection" "rds" {
  name         = "${var.rds_cluster_identifier}-${local.environment}-rds-selection"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.rds.id

  resources = [
    aws_rds_cluster.rds_cluster.arn
  ]
}
