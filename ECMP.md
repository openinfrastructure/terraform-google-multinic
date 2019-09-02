ECMP Behavior
===

This document describes the behavior of the [ECMP Routes][ecmp] used in the
vpc-link solution.  The routing configuration is similar in nature to the use
of ECMP described in [Building high availability and high bandwidth NAT
gateways][multi-nat].

Each IP router instance in the vpc-link managed instance group manages a set of
[VPC Routes][routes].  When there are multiple redundant instances ECMP
behavior is activate.

Consider the following regarding the behavior of ECMP with multiple vpc link IP
router instances.

 1. An individual flow routes through one next hop only, inidivual flows are
    not distributed across multiple next hops.
 2. A flow's next hop is determined using a 5-tuple hash computed from the
    protocol number, source port, destination port, source address, destination
    address.
 3. A Route is considered valid if there is a running instance in the VPC
    matching the next hop specification.  The next hop may specify the IP
    address or name of the instance.

Consider a vpc-link instance routing an established, active, TCP connection
which becomes unhealthy from a kernel panic.  In this situation, the following
is the behavior of the vpc-link solution:

 1. Instance with id=1 and name=vpc-link-dead kernel panics.
 2. The route resource will continue sending IP packets to the unhealthy
    instance because the route resource has not yet been marked as invalid.
 3. The packets will be dropped because the vpc-link instance kernel has
    panicked.
 4. The managed instance group detects the unhealthy instance and
    begins replacing it with a new instance, id=2 and name=vpc-link-dead.  Note
    the instance name persists while the instance id is unique.
 5. The new instance will take ~30 seconds (depending on machine type) to
    provision and begin the boot sequence.
 6. During the boot sequence, the startup-script executes.
 7. The startup script uses the GCE API to identify any Route resources
    associated with previous, unhealthy instances.
 8. The startup script deletes any Route resources which are associated with
    name=vpc-link-dead and which are _not_ associated with id=2.
 9. Once the route resources are deleted, the GCP platform stops forwarding IP
    packets to instance name=vpc-link-dead.
 10. The established TCP connection resumes flow.  It typically takes ~30
     seconds to reach this point from the time the kernel panics.
 11. The vpc-link solution is operating, but with diminished capacity.  The
     reduction in capacity is equal to 2Gbps * N vCpus where N is the number of
     vCPUs of the unhealthy instance.
 12. The startup script configures the Linux kernel for IP forwarding.  This
     involves turning on IP forwarding, turning off reverse path filtering, and
     configuring policy routing.
 12. The startup script programs new Route resources with a next hop of
     name=vpc-link-dead and id=2.
 13. The vpc-link solution is fully recovered, traffic flows are automatically
     re-balanaced across all active routes using 5-tuple hashing and total
     bandwidth capacity returns to the number of active vCPUs in the managed
     instance group.

Note when an instance is shut down normally, the shutdown script will remove
route resources as quickly as possible.  This behavior is intended to avoid
temporary packet loss from the Linux kernel stopping IP routing services while
GCP route resources continue to forward traffic flows to the instance.

Shutdown scripts are best-effort, but typically run well within the 60 second
window provided to non preemptible machine types.  Note preemptible machine
times have a shorter window allocated for shutdown scripts.

[multi-nat]: https://cloud.google.com/vpc/docs/special-configurations#multiple-natgateways
[routes]: https://cloud.google.com/vpc/docs/routes
