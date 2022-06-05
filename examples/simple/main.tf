terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# -------------------------------------------------------------------------------
# SSM Configuration
# -------------------------------------------------------------------------------
module "ssm" {
  source = "../../"

  name = var.name

  operating_system                     = "AMAZON_LINUX_2"
  approved_patches_compliance_level    = "CRITICAL"
  approved_patches_enable_non_security = false

  approval_rules = [{
    approve_after_days  = 7
    compliance_level    = "CRITICAL"
    enable_non_security = false
    patch_filters = [
      { key = "PRODUCT", values = ["AmazonLinux2"] },
      { key = "CLASSIFICATION", values = ["Security", "Bugfix"] },
      { key = "SEVERITY", values = ["Critical", "Important"] }
    ]
  }]

  maintenance_window = {
    enabled           = true
    schedule          = "cron(0 9 */7 * ?)"
    schedule_timezone = "UTC"
    cutoff            = 0
    duration          = 1
  }
}

# -------------------------------------------------------------------------------
# VPC
# -------------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = var.name

  cidr = "10.0.0.0/16"

  azs             = ["${var.region}a"]
  public_subnets  = ["10.0.1.0/24"]
  private_subnets = ["10.0.21.0/24"]

  enable_nat_gateway = true
}

# -------------------------------------------------------------------------------
# Security Groups
# -------------------------------------------------------------------------------
module "security-group_http-80" {
  source  = "terraform-aws-modules/security-group/aws//modules/http-80"
  version = "~> 4.0"

  name        = "${var.name}-sg-http-80"
  description = "Allow http traffic from public subnets."

  vpc_id              = module.vpc.vpc_id
  ingress_cidr_blocks = module.vpc.public_subnets_cidr_blocks
}

# -------------------------------------------------------------------------------
# Autoscaling
# -------------------------------------------------------------------------------
module "asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 6.0"

  name = var.name

  min_size         = 1
  max_size         = 5
  desired_capacity = 1

  iam_instance_profile_name = module.ssm.iam_instantace_profile_name
  security_groups           = [module.security-group_http-80.security_group_id]
  vpc_zone_identifier       = module.vpc.private_subnets

  launch_template_name        = var.name
  launch_template_description = "Launch template for ${var.name} autoscaling group."
  update_default_version      = true

  image_id          = "ami-0022f774911c1d690"
  instance_type     = "t2.micro"
  ebs_optimized     = false
  enable_monitoring = true

  instance_market_options = {
    market_type = "spot"
    spot_options = {
      max_price = "0.004"
    }
  }

  tags = {
    "Name"        = "${var.name}"
    "Patch Group" = "${var.name}"
  }
}
