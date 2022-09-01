provider "aws" {
  region = var.aws_region
}

locals {
  clamav_update_name        = "update-clamav-definitions"
  clamav_scan_name          = "scan-bucket-file"
  clamav_definitions_bucket = "clamav-definitions"
  layer_name                = "clamav"
}

# -----------------------------
# Datasources
# -----------------------------

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "update" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.clamav_update_name}",
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.clamav_update_name}:*"
    ]
    effect = "Allow"
  }
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:PutObjectVersionTagging"
    ]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.clamav_definitions.bucket}",
      "arn:aws:s3:::${aws_s3_bucket.clamav_definitions.bucket}/*"
    ]
    effect = "Allow"
  }
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "scan" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.clamav_scan_name}",
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.clamav_scan_name}:*"
    ]
    effect = "Allow"
  }
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:GetObjectVersion",
      "s3:PutObjectTagging",
      "s3:PutObjectVersionTagging"
    ]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.clamav_definitions.bucket}",
      "arn:aws:s3:::${aws_s3_bucket.clamav_definitions.bucket}/*"
    ]
    effect = "Allow"
  }
  dynamic "statement" {
    for_each = var.buckets_to_scan

    content {
      actions = [
        "s3:GetObject",
        "s3:GetObjectTagging",
        "s3:GetObjectVersion",
        "s3:PutObjectTagging",
        "s3:PutObjectVersionTagging"
      ]
      resources = [
        format("arn:aws:s3:::%s", statement.value),
        format("arn:aws:s3:::%s/*", statement.value)
      ]
      effect = "Allow"
    }
  }
}

# -----------------------------
# Create bucket where will be bases with vulnerability stored 
# -----------------------------

resource "aws_s3_bucket" "clamav_definitions" {
  bucket_prefix = local.clamav_definitions_bucket
}

# -----------------------------
# Create IAM Roles for the Lambdas
# -----------------------------

resource "aws_iam_role" "update" {
  name = local.clamav_update_name

  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_policy" "update" {
  name = local.clamav_update_name

  policy = data.aws_iam_policy_document.update.json
}

resource "aws_iam_role_policy_attachment" "update" {
  role       = aws_iam_role.update.name
  policy_arn = aws_iam_policy.update.arn
}

resource "aws_iam_role" "scan" {
  name = local.clamav_scan_name

  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_policy" "scan" {
  name = local.clamav_scan_name

  policy = data.aws_iam_policy_document.scan.json
}

resource "aws_iam_role_policy_attachment" "scan" {
  role       = aws_iam_role.scan.name
  policy_arn = aws_iam_policy.scan.arn
}

# -----------------------------
# Create Lambdas
# -----------------------------

resource "aws_lambda_layer_version" "this" {
  layer_name          = local.layer_name
  filename            = "${path.module}/files/layer.zip"
  compatible_runtimes = [var.lambda_runtime]

  source_code_hash = filebase64sha256("${path.module}/files/layer.zip")
}

resource "aws_lambda_function" "update_clamav_definitions" {
  filename         = "${path.module}/files/code.zip"
  function_name    = local.clamav_update_name
  role             = aws_iam_role.update.arn
  handler          = var.update_handler
  source_code_hash = filebase64sha256("${path.module}/files/code.zip")
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.update_memory_size

  layers = [aws_lambda_layer_version.this.id]

  environment {
    variables = {
      AV_DEFINITION_S3_BUCKET = aws_s3_bucket.clamav_definitions.bucket
    }
  }
}

resource "aws_lambda_function" "scan_file" {
  filename         = "${path.module}/files/code.zip"
  function_name    = local.clamav_scan_name
  role             = aws_iam_role.scan.arn
  handler          = var.scan_handler
  source_code_hash = filebase64sha256("${path.module}/files/code.zip")
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.scan_memory_size

  layers = [aws_lambda_layer_version.this.id]

  environment {
    variables = {
      AV_DEFINITION_S3_BUCKET = aws_s3_bucket.clamav_definitions.bucket
    }
  }
}

# -----------------------------
# Create Cloudwatch events with Lambda PErmissions
# -----------------------------
resource "aws_cloudwatch_event_rule" "every_three_hours" {
  name                = var.event_name
  description         = var.event_description
  schedule_expression = var.event_schedule_expression
}

resource "aws_cloudwatch_event_target" "update_clamav_definitions" {
  rule      = aws_cloudwatch_event_rule.every_three_hours.name
  target_id = local.clamav_update_name
  arn       = aws_lambda_function.update_clamav_definitions.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_update_antivirus" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = var.lambda_action
  function_name = aws_lambda_function.update_clamav_definitions.function_name
  principal     = var.lambda_update_principal
  source_arn    = aws_cloudwatch_event_rule.every_three_hours.arn
}

resource "aws_lambda_permission" "allow_terraform_bucket" {
  count         = length(var.buckets_to_scan)
  statement_id  = "AllowExecutionFromS3Bucket_${element(var.buckets_to_scan, count.index)}"
  action        = var.lambda_action
  function_name = aws_lambda_function.scan_file.arn
  principal     = var.lambda_scan_principal
  source_arn    = "arn:aws:s3:::${element(var.buckets_to_scan, count.index)}"
}

# -----------------------------
# Allow the S3 bucket to send notifications to the lambda function
# -----------------------------

resource "aws_s3_bucket_notification" "new_file_notification" {
  count  = length(var.buckets_to_scan)
  bucket = element(var.buckets_to_scan, count.index)

  lambda_function {
    lambda_function_arn = aws_lambda_function.scan_file.arn
    events              = var.bucket_events
  }
}

# -----------------------------
# Add a policy to the bucket that prevents download of infected files
# -----------------------------
resource "aws_s3_bucket_policy" "buckets_to_scan" {
  count  = length(var.buckets_to_scan)
  bucket = element(var.buckets_to_scan, count.index)

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "NotPrincipal": {
          "AWS": [
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
              "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${aws_iam_role.scan.name}/${aws_lambda_function.scan_file.function_name}",
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.scan.name}"
          ]
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${element(var.buckets_to_scan, count.index)}/*",
      "Condition": {
          "StringNotEquals": {
              "s3:ExistingObjectTag/av-status": "CLEAN"
          }
      }
    }
  ]
}
POLICY
}
