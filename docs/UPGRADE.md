Terraform 0.13 Upgrade
===

 1. Use Terraform 0.12 to init, plan, and apply version 3.x of this module.
 2. Use Terraform 0.13 to init, plan, and apply the same 3.x version.
 3. Update this module to version 4.x.
 4. Use Terraform 0.13 to init, plan, and apply 4.x.

Upgrade Procedure
===

This document describes how to upgrade from one major version of this module to
a new major version.  The overall process is to create an entirely new set of
multinic resources, validate, then remove the old resources.

The `name_prefix` and `priority` input variables are used to ensure the new
resources do not conflict with existing resources.  The route priority allows
traffic to cut over seamlessly without downtime.

Consider moving from version 2.0.0 to version 3.0.0.

Add v3 module declarations
---

First, add module declarations for each multinic region for v3.  The
name_prefix and priority differ from v2, all other input variables remain the
same.

Note the following diff shows the additions to a complete second copy of the
existing module declaration.  During the upgrade window there are two module
declarations for each region, one for v2, another for v3.

```diff
diff --git a/examples/multiregion/main.tf b/examples/multiregion/main.tf
index ea22047..0e6be4a 100644
--- a/examples/multiregion/main.tf
+++ b/examples/multiregion/main.tf
@@ -100,9 +100,12 @@ module "multinic-us-west2" {
 }

 # Manage the regional MIG formation
-module "multinic-us-west1" {
+module "multinic-us-west1-v3" {
   source = "../../modules/52_regional_multinic"

+  name_prefix = "multinic-v3"
+  priority    = 901
+
   num_instances = var.num_instances
   preemptible   = var.preemptible
```

Run terraform apply
---

Create the v3 resources by running `terraform init` and `terraform apply`.
Note, traffic will continue to route through existing v2 resources as long as
v3 uses a larger value for the priority input variable.

In this example, v2 uses 900, v3 uses 901, therefore traffic is routed through
the v2 multinics.

Change the v2 priority
---

With both v2 and v3 resources in place, change the priority of v2 to a value
greater than v3's priority.  This causes traffic to cut over to v3 multinics.

```diff
diff --git a/examples/multiregion/main.tf b/examples/multiregion/main.tf
index 6d5d029..eb580bd 100644
--- a/examples/multiregion/main.tf
+++ b/examples/multiregion/main.tf
@@ -50,7 +50,7 @@ module "multinic-us-west1" {
   source = "../../modules/52_regional_multinic"

   name_prefix = "multinic-v2"
-  priority    = 900
+  priority    = 902

   num_instances = var.num_instances
   preemptible   = var.preemptible
```

Run terraform apply
---

Run terraform apply to cut over from v2 to v3 multinic instances.

Remove v2 module declarations
---

Once traffic has cut over, all resources associated with v2 may be removed.  Do
so by deleting the module declarations associated with `name_prefix =
"multinic-v2"`.

Run terraform apply

Run terraform apply to delete all resources associated with multinic v2
instances.  At this point, v3 instances are handling traffic with a higher
priority route so no interruption is expected.

The major version upgrade is complete.
