# terraform-aws-ssm

Terraform module to compose [AWS Systems Manager (SSM)](https://docs.aws.amazon.com/systems-manager/latest/userguide/what-is-systems-manager.html) configurations.

## Usage

```hcl=
module "ssm" {
  source = "areguera/ssm/aws"

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
    schedule_timezonk = "UTC"
    cutoff            = 0
    duration          = 1
  }
}
```

## Patch baseline

This module creates one patch baseline named `${var.name}`. this patch baseline
applies to all Amazon Linux 2 EC2 instances tagged with the `Patch Group` tag
name and value `${var.name}`. These instances will approve all operating system
patches that are classified as "Security" and have a severity level of
"Critical" or "Important". Patches are auto-approved seven days after release.
Also approves all patches with a classification of "Bugfix" seven days after
release.

```
       *       *       *       *       *
       |       |       |       |       |
------>|------>|------>|------>|------>|
       |       |       |       |       |
       *       *       *       *       *
```

This module configures the `${var.name}` patch baseline to reboot instances
during maintenance window automatically, if needed. To prevent down-time, you
need to design your infrastructure to keep your application up-and-running in
spite of system reboots or unexpected application failures because of patching
itself. For example, you could use the SSM configuration this module provides
in combination with other AWS technologies like load balancer and auto-scaling
groups with the health checks enabled and properly configured on them.

To know more about patch baseline, see [AWS Systems Manager Patch Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-patch.html) documentation.

## Maintenance window

This module creates a maintenance window that runs every seven days at 9 AM
UTC. This maintenance window is configured with two tasks that run in order.
The first task installs new patches and reboots the target operating systems if
needed. The second task applies configuration playbooks on target operating
system to grantee their desired state after patching. The second task also
executes simple tests to validate the application is running as expected. In
case any of these two tasks fail, the maintenance window will fail and the
patching action stops from being propagated to remaining target systems.

This module schedules the maintenance window to run every seven days at 9 A.M.
The schedule was set in alignment with the patch baseline approval time frame,
which is also seven days. So, that's the moment in time when system patching
will happen.

This module only supports one maintenance window per module instantiation. To
create more than one maintenance window, create one new module call for each
one of them.

To know more about maintenance window, see [AWS Systems Manager Maintenance Windows](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-maintenance.html) documentation.

## Associations

This module creates the following associations:


| Name                                  | Recurrency | Description |
| ------------------------------------- | ---------- | ----------- |
| `${var.name}-UpdateSSMAgent`          | 14 days    | Update SSM agent when a new version is available. |
| `${var.name}-ApplyAnsiblePlaybooks`   | 30 minutes | Apply ansible playbooks available in `${path.root}/ansible/` directory. |
| `${var.name}-GatherSoftwareInventory` | 30 minutes | Collect system information. |
| `${var.name}-RunPatchBaseline`        | 24 hours   | Applies the `${var.name}` patch baseline in Scan mode to identify available patching. |

To know more about associations, see [AWS System Manger State Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-patch.html) documentation.

## Documents

This module creates the `${var.name}-ApplyAnsiblePlaybooks` document. It is a
modified version of `AWS-ApplyAnsiblePlaybooks` document that allows you to
apply ansible playbooks using private calls to S3 bucket (e.g., using `s3://`).

To know more about documents, see [AWS Systems Manager documents](https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-ssm-docs.html) documentation.

## Desired state

This module implements desired state for SSM managed EC2 instances by using the
`${var.name}-ApplyAnsiblePlaybooks` document, and ansible playbooks stored in
the `${path.root}/ansible/` directory.

## Examples

* [Simple SSM configurations](https://github.com/areguera/terraform-aws-ssm/tree/main/examples/simple)

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_s3_bucket"></a> [s3\_bucket](#module\_s3\_bucket) | terraform-aws-modules/s3-bucket/aws | ~> 3.0 |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_instance_profile.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_policy.AmazonEC2SSMCloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.AmazonEC2SSMS3Logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.AmazonEC2SSMS3Playbooks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.AmazonEC2SSMCloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.AmazonEC2SSMS3Logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.AmazonEC2SSMS3Playbooks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.AmazonSSMManagedInstanceCore](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.AmazonSSMPatchAssociation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_s3_object.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_ssm_association.ApplyAnsiblePlaybooks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_association) | resource |
| [aws_ssm_association.GatherSoftwareInventory](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_association) | resource |
| [aws_ssm_association.RunPatchBaseline](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_association) | resource |
| [aws_ssm_association.UpdateSSMAgent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_association) | resource |
| [aws_ssm_document.ApplyAnsiblePlaybooks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_document) | resource |
| [aws_ssm_maintenance_window.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_maintenance_window) | resource |
| [aws_ssm_maintenance_window_target.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_maintenance_window_target) | resource |
| [aws_ssm_maintenance_window_task.ApplyAnsiblePlaybooks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_maintenance_window_task) | resource |
| [aws_ssm_maintenance_window_task.SystemPatches](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_maintenance_window_task) | resource |
| [aws_ssm_patch_baseline.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_patch_baseline) | resource |
| [aws_ssm_patch_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_patch_group) | resource |
| [aws_iam_policy_document.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_approval_rules"></a> [approval\_rules](#input\_approval\_rules) | (Required) A set of rules used to include patches in the baseline. Up to 10 approval rules can be specified. Each approval\_rule block requires the fields documented below. | <pre>list(object({<br>    approve_after_days  = number<br>    compliance_level    = string<br>    enable_non_security = bool<br><br>    patch_filters = list(object({<br>      key    = string<br>      values = list(string)<br>    }))<br>  }))</pre> | n/a | yes |
| <a name="input_approved_patches_compliance_level"></a> [approved\_patches\_compliance\_level](#input\_approved\_patches\_compliance\_level) | (Optional) Defines the compliance level for approved patches. This means that if an approved patch is reported as missing, this is the severity of the compliance violation. Valid compliance levels include the following: CRITICAL, HIGH, MEDIUM, LOW, INFORMATIONAL, UNSPECIFIED. The default value is UNSPECIFIED. | `string` | `"UNSPECIFIED"` | no |
| <a name="input_approved_patches_enable_non_security"></a> [approved\_patches\_enable\_non\_security](#input\_approved\_patches\_enable\_non\_security) | (Optional) Indicates whether the list of approved patches includes non-security updates that should be applied to the instances. Applies to Linux instances only. | `bool` | `false` | no |
| <a name="input_description"></a> [description](#input\_description) | (Optional) The project description. | `string` | `""` | no |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | (Required) | <pre>object({<br>    schedule          = string<br>    schedule_timezone = string<br>    cutoff            = number<br>    duration          = number<br>    enabled           = bool<br>  })</pre> | n/a | yes |
| <a name="input_max_concurrency"></a> [max\_concurrency](#input\_max\_concurrency) | (Optional) Specify the number of managed nodes that run a command simultaneously. By default uses 10%. | `string` | `"10%"` | no |
| <a name="input_max_errors"></a> [max\_errors](#input\_max\_errors) | (Optional) Specify how many errors are allowed before the system stops sending the command to additional managed nodes. By default uses 1. | `string` | `"1"` | no |
| <a name="input_name"></a> [name](#input\_name) | (Required) The project name. This value is prefixed to resources. | `string` | n/a | yes |
| <a name="input_operating_system"></a> [operating\_system](#input\_operating\_system) | (Optional) Defines the operating system the patch baseline applies to. Supported operating systems include WINDOWS, AMAZON\_LINUX, AMAZON\_LINUX\_2, SUSE, UBUNTU, CENTOS, and REDHAT\_ENTERPRISE\_LINUX. The Default value is AMAZON\_LINUX\_2. | `string` | `"AMAZON_LINUX_2"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_iam_instantace_profile_name"></a> [iam\_instantace\_profile\_name](#output\_iam\_instantace\_profile\_name) | n/a |
