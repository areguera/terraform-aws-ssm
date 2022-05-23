terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

data "aws_region" "current" {}

# -------------------------------------------------------------------------------
# IAM
# -------------------------------------------------------------------------------
data "aws_iam_policy_document" "this" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name = "${var.name}-ssm-managed-instance"

  path               = "/${var.name}/"
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

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-ssm-managed-instance-profile"

  role = aws_iam_role.this.name
  path = "/${var.name}/"
}

# ----------------------------------------------------------------------
# S3
# ----------------------------------------------------------------------
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket = "${var.name}-ssm-logs"
  acl    = "private"

  versioning = {
    enabled = true
  }
}

# ----------------------------------------------------------------------
# SSM Associations
# ----------------------------------------------------------------------
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
  max_concurrency     = 1000
  max_errors          = 1000
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
}

resource "aws_ssm_association" "RunPatchBaseline" {
  name = "AWS-RunPatchBaseline"

  association_name    = "${var.name}-RunPatchBaseline"
  max_concurrency     = 1000
  max_errors          = 1000
  compliance_severity = var.approved_patches_compliance_level
  schedule_expression = "rate(1 days)"

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
}

resource "aws_ssm_association" "GatherSoftwareInventory" {
  name = "AWS-GatherSoftwareInventory"

  association_name    = "${var.name}-GatherSoftwareInventory"
  schedule_expression = "rate(30 minutes)"
  compliance_severity = var.approved_patches_compliance_level

  dynamic "targets" {
    for_each = local.association_targets
    content {
      key = targets.value["key"]
      values = targets.value["values"]
    }
  }
}

# ----------------------------------------------------------------------
# SSM Resource Groups
# ----------------------------------------------------------------------
resource "aws_resourcegroups_group" "this" {
  name        = var.name
  description = "Resource group to gather instances related to ${var.name}."

  resource_query {
    query = jsonencode({
      "ResourceTypeFilters" : ["AWS::EC2::Instance"],
      "TagFilters" : [{ "Key" : "Patch Group", "Values" : [var.name] }]
    })
  }
}

# ----------------------------------------------------------------------
# SSM Patch Baseline
# ----------------------------------------------------------------------
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

# ----------------------------------------------------------------------
# SSM Patch Group
# ----------------------------------------------------------------------
resource "aws_ssm_patch_group" "this" {
  baseline_id = aws_ssm_patch_baseline.this.id
  patch_group = var.name
}

# ----------------------------------------------------------------------
# SSM Maintenance Windows
# ----------------------------------------------------------------------
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

resource "aws_ssm_maintenance_window_task" "this" {
  max_concurrency = lookup(var.maintenance_window_task, "max_concurrency")
  max_errors      = lookup(var.maintenance_window_task, "max_errors")
  priority        = 1
  task_arn        = "AWS-RunPatchBaseline"
  task_type       = "RUN_COMMAND"
  window_id       = aws_ssm_maintenance_window.this.id

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.this.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      output_s3_bucket     = "${var.name}-ssm-logs"
      output_s3_key_prefix = "AWS-RunPatchBaseline"
      service_role_arn     = aws_iam_role.this.arn
      timeout_seconds      = 600

      cloudwatch_config {
        cloudwatch_log_group_name = "${var.name}/ssm/AWS-RunPatchBaseline"
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
