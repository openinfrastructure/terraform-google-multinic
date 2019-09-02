# Recovery Modes

This document describes intended recovery modes.

# Glossary of Terms

## Recovery Time

Recovery time is defined as the duration of the window in time when a TCP
connection stops making progress.

## Full Recovery Time

Full recovery time is defined as the time it takes from the time an instance is
not healthy to when the managed instance group returns to `isStable: True`
after having replaced the unhealthy instance(s).

# Router Kernel Panics

This section exercised the managed instance group auto-healing functionality by
triggering a kernel panic on one or more of the IP router instances.

## Test Methodology

Using version 0.5.0 of the vpc-link terraform module.

Endpoints created using:

    MACHINE_TYPE=n1-highcpu-8 ./scripts/create_endpoints

vpc-link MIG created with 3 n1-highcpu-4 instances running in us-central1-a.

Start `iperf3 --server` on the endpoint in the Shared VPC.

Start `iperf3 --client $SERVER_IP -t 600 -f g --verbose --json | tee
results.json` on the endpoint in the Local VPC.

Determine which IP router instance is actively carrying the iperf3 connection
by monitoring `iftop` on all router instances.  The instance showing a multi
Gbit stream has been selected by the ECMP 5-tuple hash.

Trigger a kernel panic on the active router instance:

    ./scripts/panic $ACTIVE_INSTANCE_NAME

As the kernel panics, observe the window in time where the bandwidth of the
active TCP connection drops to zero.  This window is the time to recovery.

## Test 1

 * Data file: ./perf/panic_test01.json
 * Recovery time: 26seconds
 * Full recovery time: Unknown
