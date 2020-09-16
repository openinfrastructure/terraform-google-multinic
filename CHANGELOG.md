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
