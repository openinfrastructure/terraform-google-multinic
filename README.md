Multi-nic VM Routing
===

This terraform module implements a Linux VM acting as IP router between two VPC
networks.  The primary use case is an alternative to VPC peering and VPN
tunneling for east-west connectivity.

Functionality:

 * [ILB as Next Hop][ilb-nh] for high availability and reliability.
 * Auto-healing with persistence of established TCP connections.
 * Auto scaling based on CPU utilization.  See [Autoscaler][autoscaler] for
   details.
 * Virtual wire behavior, traffic ingress to eth0 egresses eth1 and vice-versa.
 * Separate health checks for load balancing and auto-healing.
 * Cloud logging with structured log examples.
 * Fast startup and shutdown, no packages installed.
 * Systemd integration for easier control and logging.
 * CentOS 8 base image.

Getting Started
===

The core functionality is implemented in the
[50_compute/](./modules/50_compute/) nested module.  This module is intended to
be easily reused in your environment.

See [examples/compute/](./examples/compute/) for a complete example which ties
together the following resources.

See [examples/networksetup](./examples/networksetup/) for code to create VPC
networks and other dependencies necessary to evaluate the solution.

The module operates similar to GKE's model of one instance group per
availability zone.  Each VPC network has one [Internal TCP/UDP Load
Balancer][ilb] forwarding rule.   Each ILB distributes traffic across multiple
instances in multiple zones within a single region.

 1. Multiple zonal Instance Groups.
 2. Auto-healing health check
 3. 2 regional backend services, one for each VPC.
 4. Traffic health check to control traffic distribution separate from
    auto-healing.
 5. 2 ILB forwarding rules, one for each VPC.

Requirements
===

ILB addresses should be in the same subnet as the associated network interface
so that additional forwarding rules can be added and removed at runtime without
having to reconfigure each multinic instance.

Routed VPC networks must be attached to nic0 and nic1 presently.  Additional
VPC networks may be attached, but they are not configured for policy routing.
A future enhancement may support an arbitrary number of attached networks.

Operational Playbook
===

Take an instance out of rotation with `systemctl stop hc-traffic.service`.

Start the auto-healing process with `systemctl stop hc-health.service`.

Exercise a kernel panic with `systemctl start kpanic.service`.  This is useful
for evaluating failure modes and recovery behavior.

Behavior
===

Draining
---

Stopping `hc-traffic.service` causes new connections to use healthy instances,
if available.  Existing connections flowing through this instance continue to
do so.

See [Balancing mode][balancing] for more information.

Planned Maintenance
---

Stopping `hc-health.service` causes the instance group to [auto-heal][autoheal]
the instance.  Existing connections flowing through this instance being flowing
through another healthy instance.

Established TCP connections remain established during the process.

The process takes ~30 to ~40 seconds with the following health check
configuration.

```terraform
check_interval_sec  = 10
timeout_sec         = 5
healthy_threshold   = 2
unhealthy_threshold = 3
```

Auto-healed instances receive the same name as the instance they replace, but
have a unique instance ID number.

Unplanned Maintenance
---

Triggering a kernel panic with `systemctl start kpanic.service` exercises
auto-healing behavior.  Existing connections pause for ~45 seconds with
`check_interval_sec=10` and `unhealthy_threshold=3`, then recover without
disconnect.

Logging
===

Information regarding startup and shutdown events are logged to the projects
Global resource under the `multinic` entry.  For example:

```
gcloud logging read logName="projects/${PROJECT_ID}/logs/multinic"
```

Health Checks
==

There are two types of health checks used in this solution:

 1. Managed Instance Group auto-healing checks.
 2. Load Balancing traffic distribution checks.

The MIG auto-healing health checks will come into nic0.

The Load Balancing health checks will come into the nic attached to the network
associated with the ILB forwarding rule being checked.

Helper Scripts
==

Helper scripts are included in the [scripts](scripts/) directory.

`rolling_update`
---

Use this script after applying changes to the instance template used by the
managed instance group.  The helper script performs a [Rolling
Update][rolling-update] which replaces each instance in the vpc-link group with
a new instance.

`panic`
---

Triggers a kernel panic on one of the MIG instances.  This is intended to
exercise the behavior of auto-healing, and impact to application network flows
in unplanned situations.

Policy Routing
===

Linux Policy Routing is configured with the following behavior:

There are two additional routing tables named nic0 and nic1.  The tables are
identical except for the default route:

 1. Table nic0 uses nic0's gateway as the default route.
 2. Table nic1 uses nic1's gateway as the default route.

Traffic with a source address in the subnet attached to nic1 uses the `nic1`
routing table.  Similarly, traffic with a source address in the subnet attaced
to nic0 uses the nic0 table.  This source traffic includes ILB addresses.  See
[requirements][#Requirements].

Policy routing is configured on each instance using the
`policy-routing.service` unit file, which executes `/usr/bin/policy-routing`.

Startup and Shutdown scripts
===

The startup script is responsible for enabling ip forwarding, configuring
policy routing in the instance, and starting the health check endpoints.

Log into the instance, then run:

```bash
sudo DEBUG=1 google_metadata_script_runner --script-type startup --debug
```

The shutdown script is responsible for signaling the load balancer should take
the instance out of rotation.  It does this by stopping the `hc-traffic`
service, then sleeping.  The sleep is intended to maintain service levels until
the load balancer health check takes the instance out of service.

```bash
sudo DEBUG=1 google_metadata_script_runner --script-type shutdown --debug
```

Benchmarking
===

Due to [VPC Network Limits][vpc-network-limits] in GCP, the number of link
instances in the Managed Instance Group will determine the total bandwidth
available between the VPCs. These are different than quotas in that they cannot
be changed. To test these limits, metrics are provided using
[iPerf2](iperf.fr).

| Item | Limit | Notes |
|----|----|----|
| Maximum ingress data rate | Depends on machine type | GCP does not artificially cap VM instance inbound or ingresstraffic. VMs are allowed to receive as much traffic as resources and network conditions allow. For purposes of capacity planning, you should assume that each VM instance can handle no more than 10 Gbps of external Internet traffic. This value is an approximation, is not covered by an SLA, and is subject to change. Adding Alias IP addresses or multiple network interfaces to a VM does not increase its ingress capacity. |
| Maximum egress data rate | Depends on the machine type of the VM: <br> <ul><li>All shared-core machine types are limited to 1 Gbps.</li><li>2 Gbps per vCPU, up to 32 Gbps per VM for machine types that use the Skylake CPU platform with 16 or more vCPUs. This egress rate is also available for ultramem machine types.</li><li>2 Gbps per vCPU, up to 16 Gbps per VM for all other machine types with eight or more vCPUs.</li></ul>| Egress traffic is the total outgoing bandwidth shared among all network interfaces of a VM. It includes data transfer to persistent disks connected to the VM. |

## Tests

### Client
`iperf -c <INTERNAL IP ADDRESS> -P 100 -t 60`
`-c` Run as client 
`-P` Run multiple clients (If it’s run with one client, all traffic will go through 1 VM)
`-t` seconds to run test (Allow a large number to average out results)

### Server
`iperf -s`
`-s` Run as Server

### Descriptions
- Client VM - A Test VM inside the Service Project in a Local VPC.
- Server VM - A Test VM inside the host project inside a Subnet of the Shared VPC
- Link VM - A VM used to Route Traffic between VPCs, lives inside the Service Project.
- Potential Bandwidth - Limits according to the above chart from the GCP Documentation
- Actual bandwidth Output of the tests run by iperf. 
  - These results are consolidated into a single number if there are multiple clients/servers running at once.

__Test 1__

<!--TODO: Make this into a table, not sure of the format -->
3 Link VMs 8vCPU each - Potential Egress 16 Gbps Each
2 Client VMs 16 vCPU each - Multi-Stream Clients
2 Server VMs 16 vCPU Each

Client 1 to Server 1 - 24.4 Gbps
Client 2 to Server 2 - 22.4 Gbps
Simultaneously

Potential Bandwidth - 48 Gbps
Actual Bandwidth - 46.8 Gbps

__Test 2__

1 Link VM 16vCPU - Potential Egress 32 Gbps
1 Client VM 16vCPU - Multi-Stream Clients
1 Server VM 16vCPU

Potential Bandwidth - 32 Gbps
Actual Bandwidth - 30.2 Gbps

__Test 3__

1 Link VM 8vCPU - Potential Egress 16 Gbps
1 Client VM 16vCPU Multi-Stream Client
1 Server VM 16vCPU

Potential Bandwidth - 16 Gbps
Actual Bandwidth - 14.3 Gbps

__Test 4__

1 Link VM 8vCPU - Potential Egress 16 Gbps
1 Client VM 16 vCPU Single-Stream Client
1 Server VM 16 vCPU

Potential Bandwidth - 16 Gbps
Actual Bandwidth - 13.4 Gbps

References
===

[Red Hat Enterprise Linux Network Performance Tuning Guide][rhel-net-tune]
provides detailed information on tuning network interfaces.  It focuses on TCP,
which is not relevant to the stateless IP routing nature of the vpc-link router
instances, but it is full of useful information, like detecting dropped
packets.

[policy-routing]: https://cloud.google.com/vpc/docs/create-use-multiple-interfaces#configuring_policy_routing
[rhel-net-tune]: https://access.redhat.com/sites/default/files/attachments/20150325_network_performance_tuning.pdf
[vpc-network-limits]: https://cloud.google.com/vpc/docs/quota#per_instance
[ecmp]: ECMP.md
[recovery]: RECOVERY.md

[issue10]: https://github.com/openinfrastructure/terraform-google-multinic/issues/10
[ilb-nh]: https://cloud.google.com/load-balancing/docs/internal/ilb-next-hop-overview
[ilb]: https://cloud.google.com/load-balancing/docs/internal
[balancing]: https://cloud.google.com/load-balancing/docs/backend-service#balancing-mode
[autoheal]: https://cloud.google.com/compute/docs/instance-groups/autohealing-instances-in-migs
[autoscaler]: ./docs/AUTOSCALER.md
