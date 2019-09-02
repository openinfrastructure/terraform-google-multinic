vpc-link
===

This module links two vpc networks using IP router instances with a Managed
Instance Group.  The startup and shutdown script is responsible for creating
and deleting route resources in each VPC network.

A detailed description of how ECMP routing works with this solution is provided
in the [ECMP][ecmp] document.

A detailed analysis of failure and recovery modes is provided in the
[RECOVERY][recovery] document.

Logging
===

Creation of the route entries happens in each instances startup script.  Debug
messages are available in the instance's serial-port-output.  Successful
creation of route resources looks like:

In the Service Project:

```
END: stdlib::cmd() command=[gcloud compute routes create --project=myapp-1b35 --network=myapp-vpc-us-dev --destination-range=10.0.0.0/24 --next-hop-instance=vpc-link-myapp-us-central1-a-hlwz --next-hop-instance-zone=us-central1-a --description=Route auto created by instance vpc-link-myapp-us-central1-a-hlwz startup-script instance_id=8135502727602696324 --priority=900 vpc-link-myapp-us-central1-a-hlwz-8135502727602696324-0] exit_code=0
```

And the Host Project:

```
END: stdlib::cmd() command=[gcloud compute routes create --project=core-da11 --network=vpc-us-dev --destination-range=10.19.16.0/20 --next-hop-address=10.0.17.8 --description=Route auto created by instance vpc-link-myapp-us-central1-a-hlwz startup-script --priority=900 vpc-link-myapp-us-central1-a-hlwz-8135502727602696324-0] exit_code=0
```

The instance ID is embedded in the route name because the managed instance
group will re-use the same instance name when replacing unhealthy instances.
On startup, new routes are created and the old routes associated with previous
instances are deleted.

One route resource is created for each subnet passed via `core_subnets` and
`app_subnets`.

Health Checks
==

Health checks are important to prevent the managed instance group from
auto-healing instances by deleting and re-creating them.  Health checks come
into `nic0` through the shared vpc network.  Ensure TCP port 80 is allowed into
each instance in the shared vpc network.

Verify health checks on each instance by checking the access logs:

```
$ sudo tail -f /var/log/httpd/access_log
130.211.0.59 - - [17/Aug/2019:15:15:45 +0000] "GET /bridge/status.json HTTP/1.1" 200 15 "-" "GoogleHC/1.0"
130.211.0.57 - - [17/Aug/2019:15:15:45 +0000] "GET /bridge/status.json HTTP/1.1" 200 15 "-" "GoogleHC/1.0"
130.211.0.21 - - [17/Aug/2019:15:15:45 +0000] "GET /bridge/status.json HTTP/1.1" 200 15 "-" "GoogleHC/1.0"
```

Route States
===

Route resources may enter an invalid state when the MIG replaces an unhealthy
instance.  These routes may be identified and cleand up using `gcloud computes
routes describe` and `delete`.

```
gcloud compute routes describe vpc-link-myapp-us-central1-a-hlwz-8135502727602696324-0 --project $HOST_PROJECT
```

```
creationTimestamp: '2019-08-16T17:47:34.657-07:00'
description: Route auto created by instance vpc-link-myapp-us-central1-a-hlwz startup-script
destRange: 10.19.16.0/20
id: '186308188796809289'
kind: compute#route
name: vpc-link-myapp-us-central1-a-hlwz-8135502727602696324-0
network: https://www.googleapis.com/compute/v1/projects/core-da11/global/networks/vpc-us-dev
nextHopIp: 10.0.17.8
priority: 900
selfLink: https://www.googleapis.com/compute/v1/projects/core-da11/global/routes/vpc-link-myapp-us-central1-a-hlwz-8135502727602696324-0
warnings:
- code: NEXT_HOP_ADDRESS_NOT_ASSIGNED
  data:
  - key: ip_address
    value: 10.0.17.8
  - key: route_network
    value: https://www.googleapis.com/compute/v1/projects/core-da11/global/networks/vpc-us-dev
  message: Next hop ip address '10.0.17.8' is not assigned to the primary IP address
    of any instance on 'https://www.googleapis.com/compute/v1/projects/core-da11/global/networks/vpc-us-dev'.  Please
    ensure that the address is assigned to the primary IP address of an instance on
    the route's network.
```

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

`routes`
---

displays `vpc-link` routes automatically created by instance startup
and shutdown scripts.  Creation time of the instance and each route resource is
displayed to indicate the time it takes an instance to start routing packets.
The window from instance creation to the youngest route resource is the startup
time of each instance.  Typically about 60 seconds.

`routes_delete_warnings`
---

Identifies route resources which have warnings and deletes them.  A route may
be invalid when the instance that created it became unhealthy (e.g. kernel
panic) and has since been auto-healed by the managed instance group.

Use the `CLOUDSDK_CORE_PROJECT` environment variable to delete invalid routes
in the service and host project:

```bash
CLOUDSDK_CORE_PROJECT=$SERVICE_PROJECT ./scripts/routes_delete_warnings
CLOUDSDK_CORE_PROJECT=$HOST_PROJECT ./scripts/routes_delete_warnings
```


`routes_cleanup_all`
---

Generates a bash script on standard output useful to manually remove any stale
vpc-link route resources.

`create_endpoints`
---

Creates instances in the local and shared VPC intended for testing the behavior
of the VPC link router instances.  The instances are created in the service
project for convenience.  In this example, communication between `10.19.16.44`
and `10.0.0.5` routes through the vpc-link router instances.

```
gcloud compute instances list --filter='name~^endpoint' --format='value(NAME,INTERNAL_IP)'
endpoint-vpc-link-local-vpc-1   10.19.16.44
endpoint-vpc-link-shared-vpc-1  10.0.0.5
```

Policy Routing
===

Within the service project vpc network, instances in subnets other than the
vpc-link subnet are only able to receive IP packets from the vpc-link router if
[Policy Routing][policy-routing] is configured properly.  The vpc-link instance
startup script automatically configures policy routing for each subnet listed
in the `app_subnet_cidrs` input variable.

If, for some reason, policy routing is not working, reply packets may flow out
of the vpc-link router's eth0 interface instead of eth1.  Run `tcpdump -i
eth0`, then ping the IP address of eth1 from an instance running in a subnet in
the service project vpc network which is not attached to eth1.  If you see the
reply packets flowing out of eth0 instead of eth1, policy routing is not
configured correctly.  Check the behavior of the `configuring_policy_routing`
function by looking at the vpc-link router instances serial port output.

Startup and Shutdown scripts
===

Exercise the behavior of route clean and route creation by running the vpc-link
router instance startup and shutdown scripts.  Log into the instance, then run:

```bash
sudo DEBUG=1 google_metadata_script_runner --script-type startup --debug
```

The startup script is responsible for enabling ip forwarding, configuring
policy routing in the instance, and programming routes.

```bash
sudo DEBUG=1 google_metadata_script_runner --script-type shutdown --debug
```
The shutdown script is responsible for deleting route resources associated with
the instance.  The shutdown script should run as quickly as possible to ensure
route resources are cleaned up before the instance is terminated.  Route
resources which are not terminated enter an invalid state a short (1 to 2
minutes) time after the instance is terminated.

References
===

[Red Hat Enterprise Linux Network Performance Tuning Guide][rhel-net-tune]
provides detailed information on tuning network interfaces.  It focuses on TCP,
which is not relevant to the stateless IP routing nature of the vpc-link router
instances, but it is full of useful information, like detecting dropped
packets.

[policy-routing]: https://cloud.google.com/vpc/docs/create-use-multiple-interfaces#configuring_policy_routing
[rhel-net-tune]: https://access.redhat.com/sites/default/files/attachments/20150325_network_performance_tuning.pdf
[policy-routing]: https://cloud.google.com/vpc/docs/create-use-multiple-interfaces#configuring_policy_routing
[ecmp]: ECMP.md
[recovery]: RECOVERY.md
