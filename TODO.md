# Releases

## v0.4

Estimated release 2019-08-18

Theme: Evaluate the operational characteristics and behavior of the managed
instance group solution.  Exercise and understand failure modes and impact to
the application.

### Validation Checklist

For each acceptance criteria scenario, the following validation checks should
be true.

 1. IP routing is operating in under 180 seconds.  Compare `creationTimestamp`
    of the MIG instance to the most recent route resource of that instance.
 2. Fresh instances are routing in ~90 to ~100 seconds or faster.  Normally ~90
    during a rolling update.
 3. No packet loss for planned operations (scale in, out, rolling update)
 4. MIG status.isStable: true achieved
 5. Number of instances is correct.  e.g. a paniced instance is not
    permanently terminated.
 6. All route resources are deleted by the shutdown script.

### Acceptance Criteria

 1. [x] Scale up 0 to 1 using `terragrunt apply -var num_instances=1`
        (OK, OK, NA, OK, OK)
 2. [x] Scale up 1 to 3 using `terragrunt apply -var num_instances=3`
        (OK, OK, OK, OK, OK)
 3. [x] Scale down 3 to 1 using `terragrunt apply -var num_instances=1`
        (OK, OK, OK, OK, OK, OK)
 4. [x] Perform a rolling update of all images with no packet loss using
    `terragrunt apply; ./scripts/rolling_update <instance_group_name>` (1:OK,
    2:OK, 3:OK, 4:OK, 5:OK, 6:OK)
 5. [x] Kernel panic on one instance carrying traffic is autohealed within ~5
    minutes. (1: NO took ~5 minutes, 2: NO took ~5 minutes, 3: N/A loss
    expected, 4: YES after self healing, 5: YES, 6: N/A shutdown script does
    not execute during kernel panic.)

### Panic Test case

The panic test case integrated code experienced packet loss for ~5 minutes.
The routes remained in a state with warnings about the instance transitioning
to STOPPING then TERMINATED.

## Next release

Theme: Address the two caveats which arose between the demo on Wednesday
2019-08-14 and delivery on Tuesday 2019-08-20.  Address means there is a
documented method to operate the use case:

 * [ ] Rolling update using `scripts/rolling_update <instance_group>` has been
   observed to cause pauses (which recover) in established, active TCP
   connections.  Identify the root cause and document operational steps to
   avoid disruption to TCP connections when performing a rolling update.  Note,
   this may involve not using the MIG rolling update feature and instead rely
   on other means.  For example, iterating over instances in the group, running
   shutdown to remove the custom route resources, then remove the instance from
   the MIG, then add a new instance to the mig.  Performing these steps in a
   more controlled manner may avoid the interaction (possible race) between the
   instance `STOPPING` and the shutdown script removing the custom route
   resources.
 * [ ] Scaling down _may_ cause momentary pauses in TCP
   connections.  Verify if so, identify root cause, and document operational
   steps to avoid the pause when scaling down.


## Next release + 1

Theme: Reduce mean time to recover from an unexpected `scripts/panic`.  Goal:
active TCP connection MTTR 60 seconds from a panic.

Acceptance criteria:

 * [ ] Given an active TCP session when `scripts/panic` runs against the
   instance handling TCP packets, MTTR is 60 seconds for the most recent 3 test
   cases.

## Next release + 2

Theme: improve robustness of ip forwarding focusing on `eth1` policy routing.
In 0.4the startup script runs concurrently with `google-network-daemon.service`
which creates race conditions between `configure_policy_routing()` in the
startup-script and initialization of `eth1` by `google-network-daemon.service`.
Additionally, when `eth1` is configured outside of the startup process, policy
routing is not configured resulting in a failure to forward ip packets
correctly.

 * [ ] No "martian packet" log messages during DHCP operations
 * [ ] No "martion packet" log messages after `google-network-daemon.service` is started.
 * [ ] Policy routing is configured immediately after, or as part of
   `google-network-daemon.service` starting.
 * [ ] IP forwarding is well behaved following `google-network-daemon.service` restart.

For martian packets, ensure the `rp_filter` sysctl setting is set to `0` for
both eth0 and eth1.  This should happen when the interfaces are configured,
which happens via `google-network-daemon.service`

TODO
===

 1. Turn off reverse path filtering on eth0 and eth1
 2. Configure policy routing, aka rt1, when eth1 comes up (e.g. via a dhclient
    hook).  In v0.4.3 policy routing is _only_ configured via startup-script.

systemctl restart google-network-daemon.service
---

Restarting `google-network-daemon.service` resets policy routing and causes
packet loss.  Solution is to setup policy routing in a manner compatible with
`google-network-daemon.service`.  See the `dhclient_script` setting in
[/etc/default/instance_configs.cfg.template][instance_configs].

Setup rt1 when eth1 comes up
---

After `ifdown eth1`, `ifup eth`, policy routing no longer works.  Fix this by
configuring policy routing from the eth1 hooks.

```
[root@vpc-link-lfwd-us-central1-a-089d network-scripts]# ip route show table rt1
default via 10.0.3.1 dev eth1
10.0.3.0/24 dev eth1 scope link src 10.0.3.35
[root@vpc-link-lfwd-us-central1-a-089d network-scripts]# ifdown eth1
Device 'eth1' successfully disconnected.
[root@vpc-link-lfwd-us-central1-a-089d network-scripts]# ifup eth1
Connection successfully activated (D-Bus active path: /org/freedesktop/NetworkManager/ActiveConnection/5)
[root@vpc-link-lfwd-us-central1-a-089d network-scripts]# ip route show table rt1
```

Fix ifdown eth1 ifup eth1
---

On a vpc-link IP router instance carrying traffic, bringing eth1 down and up
causes packets to be dropped indefinitely:

```
sudo ifdown eth1
sudo ifup eth1
```

The interface doesn't get a DHCP address.

The logs show martion packets:

```
[32198.726538] IPv4: martian source 10.0.0.6 from 10.19.16.45, on dev eth1
[32198.733569] ll header: 00000000: 42 01 0a 00 03 23 42 01 0a 00 03 01 08 00        B....#B.......
```

Reverse Path filtering is enabled after bouncing eth1:

```
sudo sysctl -a | grep '.rp_filter'
net.ipv4.conf.all.arp_filter = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.arp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.eth0.arp_filter = 0
net.ipv4.conf.eth0.rp_filter = 1
net.ipv4.conf.eth1.arp_filter = 0
net.ipv4.conf.eth1.rp_filter = 1
net.ipv4.conf.lo.arp_filter = 0
net.ipv4.conf.lo.rp_filter = 0
```

### Steps to fix

Configure `/etc/sysconfig/network-scripts/ifcfg-eth1`

```
# Generated by startup-script
IPV6INIT="no"
DHCP_HOSTNAME="localhost"
BOOTPROTO="dhcp"
DEVICE="eth1"
ONBOOT="yes"
MTU=1460
PERSISTENT_DHCLIENT="y"
IPV6INIT=yes
```

[instance_configs]: https://github.com/GoogleCloudPlatform/compute-image-packages/issues/475#issuecomment-370967695
