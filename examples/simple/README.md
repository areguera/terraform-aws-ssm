# Single environment configuration

This example describes the implementation of a single environment of EC2
instances configured to receive automatic patching through AWS Systems Manager
(SSM) capabilities.

The environment name is `dev` and provides compute power for developers do
their work. It has been configured to apply system updates automatically every
7 days. The auto-approved update action considers all type of packages released
by the package provider, including those related to non-security updates. In
case some of these packages need a reboot, the reboot will during the specified
maintenance window time frame.

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
