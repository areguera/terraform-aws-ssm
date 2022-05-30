# Composing SSM configuration for a simple environment

The SSM configuration does nothing on its own. To see it in action you need to
create EC2 instances and tag them with the special tag `Patch Group`. This
article describes how to use the `terraform-aws-ssm` module to implement the
SSM configuration of a simple environment of EC2 instances controlled by an
auto-scaling group configured to use a pristine Amazon Linux 2 image in the
launch template.

The SSM configuration this article describes will allow you to automatically do
the following:

- Install, and configure EC2 instances to reach the desired state applying
  Ansible playbooks, when they are deployed for first time.

- Keep EC2 instances already deployed in the desired state, applying Ansible
  playbooks regularly, every 30 minutes.

- Keep the deployed EC2 instances operating system up-to-date, by applying
  system packages regularly, every 7 days.

- Keep EC2 instances desired state after system patching, applying Ansible
  playbooks, to validate the application running on the instances works as
  expected.

## Desired State

The desired state responds to the environment purpose (i.e., what we are
creating the environment for). In this example, to be in compliance with
the desired state means that, EC2 instances must be installed and configured in
a consistent way to allow their users to run an HTTP request to
`http://localhost` and receive the response `Hello, World!`.

## Patching Baseline

The EC2 instances must apply system updates, if any, for all type of packages
the operating system provider (i.e., for Amazon Linux 2 images, Amazon in this
case) released, including those related to non-security updates.

## Maintenance Window

The SSM configuration in this example creates only one Maintenance Window with
two tasks inside. One for patching and other for testing the application
running in the EC2 instances.

```
           *       *       *       *       *       *       *
    ---7---|---7---|---7---|---7---|---7---|---7---|---7---|...
           |       |       |       |       |       |       |
dev ======>|======>|======>|======>|======>|======>|======>|...
           |       |       |       |       |       |       |
    -------|-------|-------|-------|-------|-------|-------|...
```

By default `terraform-aws-ssm` module schedules the maintenance window
recurrency to run _every 7 days at 09:00 UTC_ (`cron(0 6 */7 * ?)`). To se
other possible time values, see [Reference: Cron and rate expressions for
Systems
Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/reference-cron-and-rate-expressions.html).

By default `terraform-aws-ssm` module sets the concurrency of actions triggered
by the maintenance window to _10%_ of the total number of EC2 instances
registered in the patch group configured in SSM. Only that 10% of instances may
be affected in case of failures related to software patching. The concurrency
configuration in combination with the recurrence configuration allow to
investigate what happened in the failed instances, while the other _90%_ of
developers can continue their work.

When the recurrence configured in the maintenance window doesn't provide
enough time to solve the issue, the maintenance windows must be manually
disabled to prevent later executions while still investigating and fixing the
failure. Once the problem is identified, and fixed, the maintenance window that
failed must be executed manually to reapply that specific software patching
again on the affected instances. When this manual execution passes
successfully, then the maintenance window can be enabled again for automatic
execution in the future.

## Associations (granting the desired state)

Configuring the SSM Maintenance Window to run in a limited number of EC2
instances helps to protect some EC2 instances from failures introduced during
system patching, but, in case of a failure, it doesn't protect that reduced
number of instances. In these cases, SSM Associations are a convenient way to
run automated tests regularly on all EC2 instances (e.g., during work hours,
during off-work hours, and after applying patching to monitor the application
works correctly in both scenarios.)

SSM Associations allows us to grant the desired state in the target EC2
instances by running SSM Documents on the target EC2 instance. In this example,
the SSM configuration uses the `document/ApplyAnsiblePlaybooks.json` file, an
SSM document written to run all the Ansible playbooks in the `ansible/`
directory, one by one, in alphabetic order. These playbooks are the
application's source of truth, the definition of its desired state.
