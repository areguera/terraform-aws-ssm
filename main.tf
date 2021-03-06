terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

data "aws_region" "current" {}

# ------------------------------------------------------------------------------
# IAM
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "this" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "AmazonEC2SSMS3Logs" {
  name        = "AmazonEC2SSMS3Logs"
  description = "Allow EC2 instances to write to ${var.name}-ssm/logs/ S3 bucket path."
  path        = "/${var.name}/"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:PutObject"
        ],
        "Resource" : "${module.s3_bucket.s3_bucket_arn}/logs/*"
      }
    ]
  })
}

resource "aws_iam_policy" "AmazonEC2SSMS3Playbooks" {
  name        = "AmazonEC2SSMS3Playbooks"
  description = "Allow EC2 instances to read from ${var.name}-ssm/ansible/ S3 bucket path."
  path        = "/${var.name}/"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject",
        ],
        "Resource" : "${module.s3_bucket.s3_bucket_arn}/ansible/*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:ListBucket",
        ],
        "Resource" : "${module.s3_bucket.s3_bucket_arn}"
      }
    ]
  })
}

resource "aws_iam_policy" "AmazonEC2SSMCloudwatch" {
  name        = "AmazonEC2SSMCloudwatch"
  description = "Allow EC2 instances to interact with ${var.name}-ssm cloudwatch group."
  path        = "/${var.name}/"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ],
        "Resource" : "${aws_cloudwatch_log_group.this.arn}:*"
      }
    ]
  })
}

resource "aws_iam_role" "this" {
  name = "${var.name}-ssm-managed-instance"
  path = "/${var.name}/"

  assume_role_policy = data.aws_iam_policy_document.this.json
}

resource "aws_iam_role_policy_attachment" "AmazonSSMManagedInstanceCore" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "AmazonSSMPatchAssociation" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMPatchAssociation"
}
resource "aws_iam_role_policy_attachment" "AmazonEC2SSMS3Logs" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.AmazonEC2SSMS3Logs.arn
}
resource "aws_iam_role_policy_attachment" "AmazonEC2SSMS3Playbooks" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.AmazonEC2SSMS3Playbooks.arn
}
resource "aws_iam_role_policy_attachment" "AmazonEC2SSMCloudwatch" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.AmazonEC2SSMCloudwatch.arn
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-ssm-managed-instance-profile"

  role = aws_iam_role.this.name
  path = "/${var.name}/"
}

# ----------------------------------------------------------------------
# Cloudwatch
# ----------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  name = "${var.name}-ssm"
}

# ------------------------------------------------------------------------------
# S3
# ------------------------------------------------------------------------------
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket = "${var.name}-ssm"
  acl    = "private"

  versioning = {
    enabled = true
  }

  force_destroy = true
}

resource "aws_s3_object" "this" {
  for_each = fileset(path.root, "ansible/**")

  bucket = module.s3_bucket.s3_bucket_id
  key    = each.value
  source = "${path.root}/${each.value}"
  etag   = filemd5("${path.root}/${each.value}")
}

# ------------------------------------------------------------------------------
# SSM Documents
# ------------------------------------------------------------------------------
# NOTE: The AWS-RunAnsiblePlaybook document allows to execute a single playbook
# file from an s3:// location but not from a directory structure. AWS is
# deprecating it and doesn't recomend using it. Instead, the recommendation is
# to use AWS-ApplyAnsiblePlaybooks.
#
# NOTE: The AWS-ApplyAnsiblePlaybooks document allows to execute playbooks from
# a directory structure which is previously downloaded from a public s3 bucket
# to the EC2 instance where ssm-agent is running. This document doesn't support
# s3://.
#
# Neither options fit our need. So we've cloned AWS-ApplyAnsiblePlaybooks
# document into `${var.name}-ApplyAnsiblePlaybooks' document and introduced
# changes to fit our needs related to ansible playbooks execution.
#
# The `${var.name}-ApplyAnsiblePlaybooks' is intended to run regularly, as SSM
# association, to keep our hypothetical application configuration we are
# running in the EC2 instance in compliance with whatever rules specified in
# the configuration playbook. It is also used by SSM Maintenance Windows to
# check that everything is working as expected after automatic patching task.
resource "aws_ssm_document" "ApplyAnsiblePlaybooks" {
  name            = "${var.name}-ApplyAnsiblePlaybooks"
  document_format = "JSON"
  document_type   = "Command"

  content = templatefile("${path.module}/documents/ApplyAnsiblePlaybooks.json", { "name" = var.name })
}

# ------------------------------------------------------------------------------
# SSM Associations
# ------------------------------------------------------------------------------
locals {
  # Define targets of the SSM association. AWS currently supports a maximum of
  # 5 targets. By default, and for consistency, we are using `tag:Patch Group`
  # as reference for all associations."
  association_targets = [{
    key    = "tag:Patch Group"
    values = [var.name]
  }]
}

resource "aws_ssm_association" "UpdateSSMAgent" {
  name = "AWS-UpdateSSMAgent"

  association_name    = "${var.name}-UpdateSSMAgent"
  schedule_expression = "rate(14 days)"
  max_concurrency     = var.max_concurrency
  max_errors          = var.max_errors
  compliance_severity = var.approved_patches_compliance_level

  parameters = {
    allowDowngrade = false
  }

  dynamic "targets" {
    for_each = local.association_targets
    content {
      key    = lookup(targets.value, "key")
      values = lookup(targets.value, "values")
    }
  }

  output_location {
    s3_bucket_name = module.s3_bucket.s3_bucket_id
    s3_key_prefix  = "logs/AWS-UpdateSSMAgent"
  }
}

resource "aws_ssm_association" "RunPatchBaseline" {
  name = "AWS-RunPatchBaseline"

  association_name    = "${var.name}-RunPatchBaseline"
  max_concurrency     = var.max_concurrency
  max_errors          = var.max_errors
  compliance_severity = var.approved_patches_compliance_level
  schedule_expression = "rate(24 hours)"

  parameters = {
    Operation = "Scan"
  }

  dynamic "targets" {
    for_each = local.association_targets
    content {
      key    = lookup(targets.value, "key")
      values = lookup(targets.value, "values")
    }
  }

  output_location {
    s3_bucket_name = module.s3_bucket.s3_bucket_id
    s3_key_prefix  = "logs/AWS-RunPatchBaseline"
  }
}

resource "aws_ssm_association" "GatherSoftwareInventory" {
  name = "AWS-GatherSoftwareInventory"

  association_name    = "${var.name}-GatherSoftwareInventory"
  schedule_expression = "rate(30 minutes)"
  compliance_severity = var.approved_patches_compliance_level

  dynamic "targets" {
    for_each = local.association_targets
    content {
      key    = targets.value["key"]
      values = targets.value["values"]
    }
  }

  output_location {
    s3_bucket_name = module.s3_bucket.s3_bucket_id
    s3_key_prefix  = "logs/AWS-GatherSoftwareInventory"
  }
}

resource "aws_ssm_association" "ApplyAnsiblePlaybooks" {
  name = aws_ssm_document.ApplyAnsiblePlaybooks.name

  association_name    = aws_ssm_document.ApplyAnsiblePlaybooks.name
  schedule_expression = "rate(30 minutes)"
  compliance_severity = var.approved_patches_compliance_level

  dynamic "targets" {
    for_each = local.association_targets
    content {
      key    = targets.value["key"]
      values = targets.value["values"]
    }
  }

  parameters = {
    SourceInfo = "s3://${var.name}-ssm/ansible/"
  }

  output_location {
    s3_bucket_name = module.s3_bucket.s3_bucket_id
    s3_key_prefix  = "logs/${aws_ssm_document.ApplyAnsiblePlaybooks.name}"
  }
}

# ------------------------------------------------------------------------------
# SSM Patch Baseline
# ------------------------------------------------------------------------------
resource "aws_ssm_patch_baseline" "this" {
  name        = var.name
  description = "Patch baseline for ${var.name} instances."

  operating_system                     = var.operating_system
  approved_patches_compliance_level    = var.approved_patches_compliance_level
  approved_patches_enable_non_security = var.approved_patches_enable_non_security

  dynamic "approval_rule" {
    for_each = var.approval_rules

    content {
      approve_after_days  = lookup(approval_rule.value, "approve_after_days")
      compliance_level    = lookup(approval_rule.value, "compliance_level")
      enable_non_security = lookup(approval_rule.value, "enable_non_security")

      dynamic "patch_filter" {
        for_each = lookup(approval_rule.value, "patch_filters")

        content {
          key    = lookup(patch_filter.value, "key")
          values = lookup(patch_filter.value, "values")
        }
      }
    }
  }
}

# ------------------------------------------------------------------------------
# SSM Patch Group
# ------------------------------------------------------------------------------
resource "aws_ssm_patch_group" "this" {
  baseline_id = aws_ssm_patch_baseline.this.id
  patch_group = var.name
}

# ------------------------------------------------------------------------------
# SSM Maintenance Windows
# ------------------------------------------------------------------------------
resource "aws_ssm_maintenance_window" "this" {
  name        = var.name
  description = "Maintenance window for ${var.name} instances."

  enabled           = lookup(var.maintenance_window, "enabled")
  schedule          = lookup(var.maintenance_window, "schedule")
  schedule_timezone = lookup(var.maintenance_window, "schedule_timezone")
  cutoff            = lookup(var.maintenance_window, "cutoff")
  duration          = lookup(var.maintenance_window, "duration")
}

resource "aws_ssm_maintenance_window_target" "this" {
  name        = var.name
  description = "Target instances for ${var.name} maintenance window."

  window_id         = aws_ssm_maintenance_window.this.id
  resource_type     = "INSTANCE"
  owner_information = var.name

  dynamic "targets" {
    for_each = local.association_targets
    content {
      key    = lookup(targets.value, "key")
      values = lookup(targets.value, "values")
    }
  }
}

resource "aws_ssm_maintenance_window_task" "SystemPatches" {
  name        = "SystemPatches"
  description = "Run system patching on patch group instances using the patch baseline configured."
  priority    = 10

  max_concurrency = var.max_concurrency
  max_errors      = var.max_errors
  task_arn        = "AWS-RunPatchBaseline"
  task_type       = "RUN_COMMAND"
  window_id       = aws_ssm_maintenance_window.this.id

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.this.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      output_s3_bucket     = module.s3_bucket.s3_bucket_id
      output_s3_key_prefix = "logs/AWS-RunPatchBaseline"
      service_role_arn     = aws_iam_role.this.arn
      timeout_seconds      = 600

      cloudwatch_config {
        cloudwatch_log_group_name = aws_cloudwatch_log_group.this.name
        cloudwatch_output_enabled = true
      }

      parameter {
        name   = "Operation"
        values = ["Install"]
      }

      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }
    }
  }
}

resource "aws_ssm_maintenance_window_task" "ApplyAnsiblePlaybooks" {
  name        = "ApplyAnsiblePlaybooks"
  description = "Apply configuration and automated tests on application to validate that it is working as expected after patching."
  priority    = 20

  max_concurrency = var.max_concurrency
  max_errors      = var.max_errors
  task_arn        = aws_ssm_document.ApplyAnsiblePlaybooks.name
  task_type       = "RUN_COMMAND"
  window_id       = aws_ssm_maintenance_window.this.id

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.this.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      output_s3_bucket     = module.s3_bucket.s3_bucket_id
      output_s3_key_prefix = "logs/${aws_ssm_document.ApplyAnsiblePlaybooks.name}"
      service_role_arn     = aws_iam_role.this.arn
      timeout_seconds      = 600

      parameter {
        name   = "SourceInfo"
        values = ["s3://${var.name}-ssm/ansible/"]
      }
    }
  }
}
