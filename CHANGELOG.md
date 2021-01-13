v2.1.0 - 2021-01-13
===

 * Add `startup_script` input variable to specify a bash startup-script to
   execute after routing is initialized.  ([#40][issue40])

v2.0.1 - 2020-12-23
===

 * Fix [issue/27][issue27] `target_size` should not be set with an auto scaler.

v2.0.0 - 2020-09-29
===

 * Fix [issue/20][issue20] `modules/52_regional_multinic` now deploys instance
   groups to all available zones in the specified region.  Fixes error
   deploying to us-east1 and europe-west1 where there is no `a` zone.
 * Note, resources will be destroyed and re-created.  The inputs to
   `52_regional_multinic` have *not* changed relative to v1.4.0.  The `zone`
   input to `50_compute` is replaced by `zones`.

v1.4.0 - 2020-09-28
===

 * Multiple region support.  See [examples/multiregion/][multiregion].

v1.3.0 - 2020-09-28
===

 * Add `autoscale` input var, default `true`, to enable auto scaling based on
   CPU utilization.
 * Changed default instance type to `n1-highcpu-2` to gain 10Gbps send rate.
 * Added analysis doc of autoscaler behavior at
   [AUTOSCALER.md](./docs/AUTOSCALER.md).

v1.2.0 - 2020-09-16
===

 * Remove the use if iptables fwmark matches.
 * Use `ip route replace` instead of `ip route add` to prevent routes from
   piling up.
 * Specify ip rule priorities for clarity.
 * `systemctl stop policy-routing` removes rules, effectively turning off
   policy routing.

v1.1.0 - 2020-09-16
===

 * Workaround `systemctl restart google-guest-agent` breaking policy based
   routing.  Resolves [#10][issue10].  See also guest-agent [issue #76][guest76].
 * Send info(), debug() and error() logs to Stackdriver.  Use filter
   `logName="projects/[PROJECT_ID]/logs/multinic"` to find them.
 * Add num_instances_b input to control how many instances in each zone.
 * Add preemptible input var, defaults to false

v1.0.0
===

 * Switch routing mode from ECMP to ILB as Next Hop.
 * Update to centos8.
 * Virtual wire behavior, traffic ingress to eth0 egresses eth1 and vice-versa.
 * Addition of hc-traffic.service unit file for LB health checks.
 * Addition of hc-health.service unit file for MIG auto-healing checks.
 * Added basic Cloud Logging integration example.

v0.5.1
===

 * Document ECMP behavior
 * Document recovery time results
 * Create highcpu endpoint instances
 * Add troubleshooting document

v0.5.0
===

 * Merge branch 'improve_recovery_time'
 * Use a dhcp exit hook to restore rt1
 * Enable running script directly for rapid R&D
 * Delete stale route resources

v0.4.3
===

 * Initial release

[issue10]: https://github.com/openinfrastructure/terraform-google-multinic/issues/10
[guest76]: https://github.com/GoogleCloudPlatform/guest-agent/issues/76
[issue20]: https://github.com/openinfrastructure/terraform-google-multinic/issues/20
[issue27]: https://github.com/openinfrastructure/terraform-google-multinic/issues/27
