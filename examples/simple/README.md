# Composing SSM configuration for a simple environment

This article describes how to configure AWS Systems Manager (SSM) to provide
automatic patching at scale and grantee application desired state, using the
[`terraform-aws-ssm`](https://github.com/areguera/terraform-aws-ssm) module.
For the purpose of this demonstration, a simple environment of EC2 instances is
deployed and tagged using an auto-scaling group to quickly create and destroy
them by changing the value of desired number of instances. This article may be
useful for people interested in SSM implementation using Terraform.

## Overview

The AWS SSM service has a server-client architecture. The server side is an AWS
managed service and the [agent](https://github.com/aws/amazon-ssm-agent) is an
open source software that runs on the EC2 instance. The agent initiates
communication to the server and runs all actions the server commands to
execute. The server component is made of different capabilities. Some
capabilites are free to use, and others have a cost. This articule only uses
free SSM capabilities like [Patch Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-patch.html),
[Maintenance Window](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-maintenance.html),
and [State Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-state.html)
for associations. However, be aware that other AWS resources like EC2
instances, and Internet Gateways, are also deployed in this example code and
they do have a cost.

In order for the SSM agent to communicate with the SSM server, an EC2 instance
profile must be configured and access granted to SSM server.

In order for the SSM server to reconize EC2 instances, they must be tagged with
the special tag named `Patch Group`. Then, a patch baseline must be configured
in the SSM server to establish the relation between the type of patching
performed and the target insntace linked to the `Patch Group` specified. Once
this relation is in place, SSM server is constantly aware of new instances
created and those no longer reachable.

For a more details about SSM, please read [What is AWS Systems
Manager?](https://docs.aws.amazon.com/systems-manager/latest/userguide/what-is-systems-manager.html
"What is AWS Systems Manager?")

## The environment desired state

- All EC2 instances must be installed and configured in a consistent way to allow their users to run an HTTP request to `http://localhost` and receive the response `Hello, World!`.
- All EC2 instances must apply system updates automatically, if any, for all type of packages the operating system provider (i.e., for Amazon Linux 2 images, Amazon in this case) releases, including those related to non-security updates. System reboots caused by system updates must also happen without human intervention, in a coordinated, progressive, and predictable way.

## The module configuration block

The [`terraform-aws-ssm`](https://github.com/areguera/terraform-aws-ssm) module
consolidates the maintenance window, the patch baseline definition, and
associations SSM capabilities in a single configuration block for you to edit.
In this configuration block you define the name of the configuration you want
to setup, the operating system of your EC2 instances, the patching compliance
level, the auto-approval rules, the patch filters, the maintenance window
schedule, the task max concurrency, and max number of errors allowed to happen
before stopping actions from propagating.

The [`terraform-aws-ssm`](https://github.com/areguera/terraform-aws-ssm) module
configuration block looks like the following:

```hcl
module "ssm" {
  source = "../../"

  name = var.name

  operating_system                     = "AMAZON_LINUX_2"
  approved_patches_compliance_level    = "UNSPECIFIED"
  approved_patches_enable_non_security = true
  max_concurrency                      = "10%"
  max_errors                           = "1"

  approval_rules = [{
    approve_after_days  = 7
    compliance_level    = "UNSPECIFIED"
    enable_non_security = true
    patch_filters = [
      { key = "PRODUCT", values = ["AmazonLinux2"] },
      { key = "CLASSIFICATION", values = ["Security", "Bugfix", "Enhancement"] },
      { key = "SEVERITY", values = ["Critical", "Important", "Medium", "Low"] }
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

### IAM permissions

The [`terraform-aws-ssm`](https://github.com/areguera/terraform-aws-ssm) module
takes care of all the IAM configuration, and the EC2 instance profile. See
[Create auxiliary resources](#1-Create-auxiliary-resources).

### Patch baseline and patch group

### Maintenance window

The [`terraform-aws-ssm`](https://github.com/areguera/terraform-aws-ssm) module
supports only one maintenance window per environment configuration and up to 5
approval rules inside it. This maintenance window has two tasks already
configured. One task for patching (`AWS-RunPatchBaseline`), and other for
testing the desired state of the applications
(`${var.name}-ApplyAnsiblePlaybooks`) in EC2 instances.

To create more than one maintenance window, create a new environment
configuration for it. Said in a different way, each environment configuration
should only have a single maintenance window. This allows you to create
multi-environment configurations with maintenance windows chained in time one
after another to reduce the risk of failures because of automatic patching.

The [`terraform-aws-ssm`](https://github.com/areguera/terraform-aws-ssm) module
by default schedules the maintenance window to run its tasks _every 7 days at
09:00 UTC_ (`cron(0 9 */7 * ?)`). You can change this setting in the SSM
configuration block. To customize this value, please see
[Reference: Cron and rate expressions for Systems Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/reference-cron-and-rate-expressions.html).

The [`terraform-aws-ssm`](https://github.com/areguera/terraform-aws-ssm) module
executes maintenance window tasks concurrently on the 10% of the total number
of EC2 instances registered in the patch group configured in SSM and a maximum
number of errors of 1. In this configuration, when the first 10% of EC2
instances passes successfully the patching action, then another 10% is picked
to apply the patching actions, until reaching the 100% of all instances. If 1
of the instances fails to apply patching then the patching action is not
propagated to the next 10% of instances. This strategy is useful to limit the
propagation of issues during automatic patching. You can change this strategy
in the SSM configuration block by changing the value of `max_concurrency` and
`max_error` attributes. Possible values to these attributes are percents (e.g.,
`"10%"`, `"50%"`) and integers (e.g., `"1"`, `"10"`).

When the maintenance window concurrency configuration doesn't provide
administrators enough time to solve the patching issue, they can disable the
maintenance window manually to prevent later executions while still
investigating and fixing the failure. Once the problem is identified, and
fixed, the maintenance window that failed must be executed manually to reapply
that specific software patching again on the affected instances. When this
manual execution passes successfully, then the maintenance window can be
enabled again for automatic execution in the future.

### The associations (granting the environment desired state)

Configuring the SSM Maintenance Window to run in a limited number of EC2
instances helps to protect some EC2 instances from failures introduced during
system patching, but, in case of a failure, it doesn't protect that reduced
number of instances. In these cases, SSM Associations are a convenient way to
run automated tests regularly on all EC2 instances (e.g., during work hours,
during off-work hours, and after applying patching to monitor the application
works correctly in both scenarios.)

SSM Associations allows the environment administrators to grant the desired
state in the target EC2 instances by running SSM Documents on the target EC2
instance. The
[`terraform-aws-ssm`](https://github.com/areguera/terraform-aws-ssm) module
provides the `document/ApplyAnsiblePlaybooks.json` document and is already
configured for you to use. This document expects Ansible playbooks in the
`ansible/` directory and executes them, one by one, in alphabetic order. These
playbooks are the application's source of truth, the definition of its desired
state.
