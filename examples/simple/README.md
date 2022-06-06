# Composing AWS Systems Manager configurations with Terraform

This article describes how to setup [AWS Systems Manager (SSM)](https://docs.aws.amazon.com/systems-manager/latest/userguide/what-is-systems-manager.html) using the [`terraform-aws-ssm`](https://github.com/areguera/terraform-aws-ssm) module to manage automatic patching and desired state in your infrastructure.

## Usage

1. Clone the [`terraform-aws-ssm`](https://github.com/areguera/terraform-aws-ssm)  repository:
	```
	git clone git@github.com:areguera/terraform-aws-ssm.git
	```
2. Change the working directory:
	```
	cd terraform-aws-ssm/examples/simple/
	```
3. Configure your AWS access keys using aws command-line:
	```
	aws configure
	```
4. Initialize terraform provider and modules:
	```
	terraform init
	```
5. Customize SSM configuration to adapt it to your needs:
	* `example/simple/main.tf` --- to customize the patch baseline definition, maintenance window schedule, and auto-scaling group capacity. 
	* `example/simple/ansible/` --- to customize the EC2 instances desired state.
6. Check deployment plan:
	```
	terraform plan -var name=MyProject -var=us-east-1
	```
7. Apply deployment plan:
	```
	terraform apply -var name=MyProject -var=us-east-1
	```

Iterate between steps 5 and 7.

## Simple infrastructure desired state

When you deploy the infrastructure, it must meet the following desired state:

- All EC2 instances must be installed and configured using Ansible playbooks to allow HTTP requests to `http://localhost/` and receive the `Hello, World!` response.
- All EC2 instances must approve all operating system patches that are classified as "Security" and that have a severity level of "Critical" or "Important". Patches are auto-approved seven days after release. Also approves all patches with a classification of "Bugfix" seven days after release. System reboots caused by patching must also happen without human intervention, in a coordinated, progressive, and predictable way.


## Directory structure

The [`terraform-aws-ssm`](https://github.com/areguera/terraform-aws-ssm) module expects you to work in a directory structure like the following:

```
.
├── ansible
│   ├── 00-application-configuration.yml
│   ├── 99-application-tests.yml
│   └── roles
│       ├── application-httpd
│       │   ├── handlers
│       │   │   └── main.yml
│       │   ├── tasks
│       │   │   └── main.yml
│       │   └── templates
│       │       ├── index.html.j2
│       │       └── welcome.conf.j2
│       └── application-httpd-tests
│           └── tasks
│               └── main.yml
├── main.tf
├── README.md
└── variables.tf
```

### The `ansible` directory

The `ansible` directory in this layout exists to organize Ansible playbooks and roles.  Use this location to declare the desired state of your SSM managed EC2 instances.

The [`terraform-aws-ssm`](https://github.com/areguera/terraform-aws-ssm) module creates a private S3 bucket named `${var.name}-ssm/` and uploads the entire `ansible` directory up to it for further usage, when it runs the SSM associations. When you introduce changes to `ansible` directory, they will be reflected in a new S3 bucket version the next time you run `terraform apply` command, so SSM service will use them on associations.

When you write Ansible playbooks in `ansible` directory, keep in mind they will downloaded to the SSM managed instance and applyed there. You don't need to install ansible command yourslef because the `${var.name}-ApplyAnsiblePlaybooks` SSM document already takes care of it, but you must write your playbook files to run on `localhost` only using a `local` connection. For example, consider the following playbook:

```yaml=
---
 - name: Examples simple - Configure application
  hosts: localhost
  connection: local

  roles:
     - application-httpd
```

### The `variables.tf` file

```hcl=
variable "name" {
  type        = string
  description = "The project's name. This value is used to identify resources and tags."
}

variable "region" {
  type        = string
  description = "The AWS region used by terraform provider."
}
```

### The `main.tf` file

The `main.tf` file has three main sections. The first one describes the `terraform` provider and the restrictions related to it.

```hcl=
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
```

The second section in `main.tf` file calls the [`terraform-aws-ssm`](https://github.com/areguera/terraform-aws-ssm) module and provides the information the module needs to setup the patch baseline, the maintenance window, and the associations resources of an SSM configuration.

```hcl=
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
```

This is all you need to deploy your first SSM configuration using [`terraform-aws-ssm`](https://github.com/areguera/terraform-aws-ssm) module.

The remaining configuration blocks in the `main.tf` file are dedicated to deploy SSM managed EC2 instances.

```hcl=
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
```
