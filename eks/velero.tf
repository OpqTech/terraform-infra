################################################################################
# Backup storage (S3 + KMS)
################################################################################

resource "aws_kms_key" "velero" {
  description             = "Velero backup bucket encryption key for ${var.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.aws_account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "velero" {
  name          = "alias/${var.cluster_name}-velero"
  target_key_id = aws_kms_key.velero.key_id
}

#checkov:skip=CKV_AWS_18: access logging not required for backup bucket in this platform
#checkov:skip=CKV2_AWS_62: event notifications not required for backup bucket
resource "aws_s3_bucket" "velero" {
  bucket        = "${var.cluster_name}-velero-backups-${var.aws_account_id}"
  force_destroy = true
  tags = {
    Name = "${var.cluster_name}-velero-backups"
  }
}

resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.velero.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket = aws_s3_bucket.velero.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.velero_backup_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "velero" {
  bucket = aws_s3_bucket.velero.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.velero.arn,
          "${aws_s3_bucket.velero.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

################################################################################
# Pod Identity
################################################################################

module "velero_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.8.0"

  name = "velero"

  attach_velero_policy       = true
  velero_s3_bucket_arns      = [aws_s3_bucket.velero.arn]
  velero_s3_bucket_path_arns = ["${aws_s3_bucket.velero.arn}/*"]
  velero_kms_arns            = [aws_kms_key.velero.arn]

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "velero"
      service_account = "velero"
    }
  }
}

################################################################################
# Helm Release
################################################################################

resource "helm_release" "velero" {
  name             = "velero"
  repository       = "https://vmware-tanzu.github.io/helm-charts"
  chart            = "velero"
  namespace        = "velero"
  create_namespace = true
  version          = var.velero_chart_version
  wait             = true

  values = [
    templatefile("tpl/velero_values.tpl", {
      aws_region         = var.aws_region
      backup_bucket_name = aws_s3_bucket.velero.id
      backup_schedule    = var.velero_backup_schedule
      backup_ttl         = var.velero_backup_ttl
      plugin_aws_version = var.velero_plugin_aws_version
      node_group_name    = var.node_group_name
    }),
  ]

  depends_on = [module.eks, module.velero_pod_identity]
}
