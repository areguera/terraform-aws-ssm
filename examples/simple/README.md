# Composing SSM configuration for one simple environment

Let's consider an hypothetical environment `dev` which provides compute power
for developers do their work. We want this environment to apply system updates
automatically every 7 days for all type of packages released by the package
provider, including those related to non-security updates. In case some of
these packages need a reboot, the reboot will take place during the off work
hours.

The developers are working on an application which sole purpose is to print the
`Hello, World!` message on the web browser, when they request the
`http://localhost/` URL in the workstation. For this purpose, developers need
an EC2 instance with a (httpd) web server permanently running, and configured
to serve the file `index.html`. Note that, for this example, instances must
deployed from a pristine image and the web server needs to be installed and
configured every time a new EC2 instance is deployed for a developer.

```
           *       *       *       *       *       *       *       *
    ---7---|---7---|---7---|---7---|---7---|---7---|---7---|---7---|
           |       |       |       |       |       |       |       |
dev ======>|======>|======>|======>|======>|======>|======>|======>|
           |       |       |       |       |       |       |       |
    -------|-------|-------|-------|-------|-------|-------|-------|
```

To reduce the downtime impact produced by reboot actions on the environment,
the maintenance windows runs out of work hours and the concurrency of actions
is limited to 10% of the total number of EC2 instances registered in the patch
group configured in SSM. This way, in case of a failure that makes them not to
boot, only the 10% of instances may be out-of-service. That would provide time
to investigate what happened, while the other 90% of developers can continue
their work. When a failure occurs, the maintenance window must be manually
deactivated to prevent later executions while still investigating and fixing
the failure.

Once the problem has been identified, and fixed, the maintenance window must be
executed manually to reapply that specific software patching again. If this
manual execution passes successfully, then the maintenance window can be
enabled again for automatic execution in the future.

Applying actions in a limited number of EC2 instances is not enough to reduce
the possibility of downtime because an application failure. It exists the
remote possibility of inconsistencies between the application we are running
and the new software introduced by automatic patching. In these cases, it is
also necessary to provide automated tests in the maintenance window to validate
the application works correctly once the software patches recently applied.

For automated tests, this example uses an run-command document to make a local
HTTP request to the instance IP address, and expect a "Hello World!" message as
response. This run-command document is configured in the maintenance window to
run after the software patching document.

So far the environment able to receive automatic software patching with a
failure rate of 10% of its capacity. To provide automatic software patching
with less failure rate, implement a multi-environment configuration.

## The Infrastructure

In order to illustrate SSM configuration the `terraform-aws-ssm` module
provides, this example deploys an auto-scaling group (ASG) to control the
number of EC2 instances the environment will have. By default, the ASG uses a
pristine Amazon Linux 2 image and only one instance is deployed. With this
infrastructure in place, the SSM configuration keeps the EC2 instances software
patching up-to-date and applies regular actions on to grantee the application
running inside all the EC2 instances is healthy, both during operation and
after new patches has been applied.

## The Application

The application running on EC2 instances is an httpd web server, which only
output is the string `Hello, World!`. Since the ASG is using pristine AMI, the
httpd package is not installed, nor configured. This is intentional to
illustrate how we can use SSM associations to run regular configuration
actions, and SSM Maintenance Window to test our application after automatic
patching.
