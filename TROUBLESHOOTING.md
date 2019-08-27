# Troubleshooting

This document describes common troubleshooting techniques related to the
vpc-link module.  Many of these techniques may be generalized to IP router
instances in GCP.

For the purpose of this document, compute instances are laid out as follows:

All instances are located within a Service project.  A host project contains a
shared vpc shared with the service project.

 * Client instance connected to local vpc
 * vpc-link eth0 connected to shared vpc
 * vpc-link eth1 connected to local vpc
 * Server instance connected to shared vpc

# Connect times out

TCP connection timeouts may happen for a variety of reasons.  This section is
intended to identify the root cause of connection timeouts.

## The instance is not forwarding packets

### Summary

A TCP connection (e.g. ssh) from the client to the server always times out,
even though `ip_forwarding` is turned on.

### Symptoms

Running tcpdump on eth1 indicates the packet from the client flows into the IP
router instance.

Running tcpdump on eth0 indicates the packet is not forwarded as intended.

Additional notes:

 * There are `martian source` log messages in the kernel logs (`dmesg`).
 * The firewall allows traffic into the router instance, evidenced by `tcpdump
   -i eth1` capturing results.
 * IP forwarding is enabled, `cat /proc/sys/net/ipv4/ip_forward` returns `1`.

### Root Cause

The `martian source` log entries in the kernel logs indicate the Linux kernel
is dropping the packets even though `ip_forward` is enabled.  This beheavaior
is a result of [Reverse Path Filtering][rp_filter].  See [Understanding Reverse
Path Filtering][understanding_rp_filter] for more information.

### Solution

Disable reverse path filtering on all interfaces participating in routing:

```
for i in /proc/sys/net/ipv4/conf/*/rp_filter ; do
  echo 0 > $i
done
```

Note: It is advisable to manage this using the operating systems sysctl
management system, e.g. `/etc/sysctl.d/50-ip-router.conf`.

## TCP Connections sometimes work

### Summary

A TCP connection (e.g. ssh) from the client to the server works
sometimes, times out other times.

### Symptoms

When the connection works, tcpdump running on eth0 of all vpc-link router
instances indicate symmetric routing.  That is to say, traffic from client to
server flows through the same instance as does return traffic from server to
client.

When the connection times out, tcpdump running on eth0 of all vpc-link router
instances indicates asymmetric routing.  Traffic is visible from client to
server, but no reply traffic is visible on any other vpc-link router instance.

### Root cause

This problem is likely caused by a vpc firewall rule allowing the traffic in a
stateful way.  When ECMP results in symmetric routing, the firewall allows the
reply traffic.  When ECMP results in asymmetric routing, the firewall blocks
the reply traffic because the session originated on a different vpc-link
interface.

### Solution

Allow the reply traffic through the vpc firewall.  The following example allows
reply traffic when the vpc-link router instances have the `vpc-link-router`
instance network tag.

```bash
gcloud compute firewall-rules create allow-vpc-link-routing \
  --description 'Allow all traffic ingress to a vpc-link router instance' \
  --target-tags=vpc-link-router \
  --direction ingress \
  --allow=tcp,udp,icmp \
  --network vpc-us-dev \
  --project=$HOST_PROJECT
```

[rp_filter]: http://tldp.org/HOWTO/Adv-Routing-HOWTO/lartc.kernel.rpf.html
[understanding_rp_filter]: https://www.theurbanpenguin.com/rp_filter-and-lpic-3-linux-security/
