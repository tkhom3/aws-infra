resource "aws_s3_bucket" "home_lab_backup" {
  bucket = "tkhom3-home-lab-backup"
}

resource "aws_s3_bucket_versioning" "home_lab_backup" {
  bucket = aws_s3_bucket.home_lab_backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "home_lab_backup" {
  bucket = aws_s3_bucket.home_lab_backup.id

  rule {
    id     = "Delete noncurrent unraid backup versions after 30 days"
    status = "Enabled"

    filter {
      prefix = "unraid_backup/"
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "Delete noncurrent photos versions after 60 days"
    status = "Enabled"

    filter {
      prefix = "photos/"
    }

    noncurrent_version_expiration {
      noncurrent_days = 60
    }
  }

  rule {
    id     = "Remove expired delete markers and abort incomplete uploads"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "home_lab_backup" {
  bucket = aws_s3_bucket.home_lab_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "home_lab_backup" {
  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_acct_num}:user/docker-s3backup"]
    }

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetObject*",
      "s3:PutObject*",
      "s3:DeleteObject",
    ]

    resources = [
      aws_s3_bucket.home_lab_backup.arn,
      "${aws_s3_bucket.home_lab_backup.arn}/*",
    ]
  }

  statement {
    sid    = "DenyIncorrectEncryptionHeader"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.home_lab_backup.arn}/*"]

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["AES256"]
    }
  }

  statement {
    sid    = "DenyUnEncryptedObjectUploads"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.home_lab_backup.arn}/*"]

    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["true"]
    }
  }

  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_acct_num}:root"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.home_lab_backup.arn,
      "${aws_s3_bucket.home_lab_backup.arn}/*",
    ]
  }

  statement {
    sid    = "AllowAccessAnalyzer"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["access-analyzer.amazonaws.com"]
    }

    actions = [
      "s3:GetObject*",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.home_lab_backup.arn,
      "${aws_s3_bucket.home_lab_backup.arn}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_acct_num]
    }
  }
}

resource "aws_s3_bucket_policy" "home_lab_backup" {
  bucket = aws_s3_bucket.home_lab_backup.id
  policy = data.aws_iam_policy_document.home_lab_backup.json
}
