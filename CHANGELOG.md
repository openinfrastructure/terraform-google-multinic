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
