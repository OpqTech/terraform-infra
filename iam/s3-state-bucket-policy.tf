resource "aws_iam_policy" "S3StateBucketPolicy" {
  name = "S3StateBucketPolicy"
  path = "/Policies/"
  policy = jsonencode({
    "Version" : "2012-10-17"
    "Statement" : [
      {
        "Action" : [
          "s3:ListBucket"
        ]
        "Effect" : "Allow"
        "Resource" : "arn:aws:s3:::terraform-infra-state-backend"
      },
      {
        "Action" : [
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetObjectVersion"
        ]
        "Effect" : "Allow"
        "Resource" : "arn:aws:s3:::terraform-infra-state-backend/*"
      },
      {
        "Action" : [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        "Effect" : "Allow"
        "Resource" : "arn:aws:s3:::terraform-infra-state-backend/*/*.tflock"
      },
    ]
  })
}