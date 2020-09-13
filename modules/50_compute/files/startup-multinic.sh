#! /bin/bash
#
# Copyright 2020 Open Infrastructure Services, LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

##
# This script configures a centos-cloud/centos-8 instance to route IP traffic.

set -u

error() {
  if [[ -n "${STARTUP_SCRIPT_STDLIB_INITIALIZED:-}" ]]; then
    stdlib::error "$@"
  else
    echo "$@" >&2
  fi
}

info() {
  if [[ -n "${STARTUP_SCRIPT_STDLIB_INITIALIZED:-}" ]]; then
    stdlib::info "$@"
  else
    echo "$@"
  fi
}

debug() {
  if [[ -n "${STARTUP_SCRIPT_STDLIB_INITIALIZED:-}" ]]; then
    stdlib::debug "$@"
  else
    echo "$@"
  fi
}

cmd() {
  if [[ -n "${STARTUP_SCRIPT_STDLIB_INITIALIZED:-}" ]]; then
    DEBUG=1 stdlib::cmd "$@"
  else
    "$@"
  fi
}

# Write a sysctl value in a manner compatible with the google-compute-engine
# package which sets values in /etc/sysctl.d/60-gce-network-security.conf
# /etc/sysctl.d/98-ip-router.conf is used to take precedence.
setup_sysctl() {
  local sysctl_file sysctl_conf
  debug '# BEGIN # setup_sysctl() ...'
  sysctl_file="$(mktemp)"
  sysctl_conf="$(mktemp)"
  # shellcheck disable=SC2129
  echo 'net.ipv4.ip_forward=1'                  >> "$sysctl_file"
  echo 'net.ipv4.conf.default.forwarding=1'     >> "$sysctl_file"
  echo 'net.ipv4.conf.all.forwarding=1'         >> "$sysctl_file"
  echo 'net.ipv4.conf.default.rp_filter=0'      >> "$sysctl_file"
  echo 'net.ipv4.conf.all.rp_filter=0'          >> "$sysctl_file"
  echo 'net.ipv4.conf.eth0.rp_filter=0'         >> "$sysctl_file"
  echo 'net.ipv4.conf.eth1.rp_filter=0'         >> "$sysctl_file"
  echo 'net.ipv4.conf.eth2.rp_filter=0'         >> "$sysctl_file"
  echo 'net.ipv4.conf.eth3.rp_filter=0'         >> "$sysctl_file"
  echo 'net.ipv4.conf.eth4.rp_filter=0'         >> "$sysctl_file"
  echo 'net.ipv4.conf.eth5.rp_filter=0'         >> "$sysctl_file"
  echo 'net.ipv4.conf.eth6.rp_filter=0'         >> "$sysctl_file"
  echo 'net.ipv4.conf.eth7.rp_filter=0'         >> "$sysctl_file"
  echo 'net.ipv4.ip_forward=1'                  >> "$sysctl_file"
  echo 'net.ipv4.conf.all.send_redirects=1'     >> "$sysctl_file"
  echo 'net.ipv4.conf.default.send_redirects=1' >> "$sysctl_file"
  install -o 0 -g 0 -m 0644 "$sysctl_file" '/etc/sysctl.d/98-ip-router.conf'
  debug '# END # setup_sysctl() ...'

  # Need to remove entries from /etc/sysctl.conf otherwise they always take
  # precendence.
  sed '/\bip_forward\b/d; /\brp_filter\b/d' /etc/sysctl.conf > "${sysctl_conf}"
  if cmp --silent /etc/sysctl.conf "${sysctl_conf}"; then
    debug "No changes made to /etc/sysctl.conf"
  else
    info "Patching /etc/sysctl.conf with changes for IP forwarding..."
    diff -U2 /etc/sysctl.conf "${sysctl_conf}"
    install -o 0 -g 0 -m 0644 "${sysctl_conf}" /etc/sysctl.conf
  fi

  # Activate changes (enables IP routing)
  cmd systemctl restart systemd-sysctl.service
  info "IP Forwarding enabled via /etc/sysctl.d/98-ip-router.conf"
}

# Expose /bridge/status.json endpoint
# TODO: Configure this as two systemd service units using python 3.7, which is
# already on the system.  Two units to enable draining.
# Maybe as simple as systemd-run /usr/bin/python -m SimpleHTTPServer 80
setup_status_api() {
  # Install status API
  status_file="$(mktemp)"
  echo '{status: "OK"}' > "${status_file}"

  # Hack to wait for the network
  while ! curl http://mirrorlist.centos.org/; do
    info "Cannot curl mirrorlist.centos.org, sleeping 1 second..."
    sleep 1
  done

  [[ -x /sbin/httpd ]] || yum -y install httpd
  install -v -o 0 -g 0 -m 0755 -d /var/www/html/bridge
  install -v -o 0 -g 0 -m 0644 "${status_file}" /var/www/html/bridge/status.json

  cmd systemctl enable httpd || return $?
  cmd systemctl start httpd || return $?
}

# Install a oneshot systemd service to trigger a kernel panic.
# Intended for gcloud compute ssh <instance> -- sudo systemctl start kpanic --no-block
install_kpanic_service() {
  local tmpfile
  tmpfile="$(mktemp)"
  cat <<EOF>"${tmpfile}"
[Unit]
Description=Triggers a kernel panic 1 second after being started

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'sleep 1; echo c > /proc/sysrq-trigger'
RemainAfterExit=true
EOF
  install -m 0644 -o 0 -g 0 "${tmpfile}" /etc/systemd/system/kpanic.service
  systemctl daemon-reload
}

## See: Configuring Policy Routing
# https://cloud.google.com/vpc/docs/create-use-multiple-interfaces#configuring_policy_routing
# For Google supported images, when you need a secondary network interface (an
# interface other than nic0) to communicate with any IP address not local to
# the primary subnet range of that secondary interface's associated subnet, you
# need to configure policy routing to ensure that egress packets will leave
# through the correct interface. In such cases, you must configure a separate
# routing table for each network interface using policy routing.
#
# There are two major policies in play:
#  1. Traffic from an IP associated with a NIC, either the primary or an ILB.
#  2. Routed traffic, e.g. ingress into nic0 and egress nic1.
configure_policy_routing() {
  local ip0 ip1 gateway0 gateway1 ilb_ip0 ilb_ip1 tmpfile svcfile

  # Note: This only gets the first forwarded IP address for each interface.
  ip0="$(stdlib::metadata_get -k instance/network-interfaces/0/ip)"
  ilb_ip0="$(stdlib::metadata_get -k instance/network-interfaces/0/forwarded-ips/0)"
  gateway0="$(stdlib::metadata_get -k instance/network-interfaces/0/gateway)"
  ip1="$(stdlib::metadata_get -k instance/network-interfaces/1/ip)"
  ilb_ip1="$(stdlib::metadata_get -k instance/network-interfaces/1/forwarded-ips/0)"
  gateway1="$(stdlib::metadata_get -k instance/network-interfaces/1/gateway)"

  tmpfile="$(mktemp)"
  cat <<EOF >"$tmpfile"
#! /bin/bash
# These tables manage default routes based on policy.
if ! grep -qx '10 nic0' /etc/iproute2/rt_tables; then
  echo "10 nic0" >> /etc/iproute2/rt_tables
fi
if ! grep -qx '11 nic1' /etc/iproute2/rt_tables; then
  echo "11 nic1" >> /etc/iproute2/rt_tables
fi

## These are essentially the same tables, just different default gateways.
# Traffic addresses attached to the nic0 primary interface
ip route add default via "${gateway0}" dev eth0 table nic0
ip route add "${gateway0}" dev eth0 scope link table nic0
ip route add "${gateway1}" dev eth1 scope link table nic0
# Traffic addresses attached to the nic1 primary interface
ip route add default via "${gateway1}" dev eth1 table nic1
ip route add "${gateway0}" dev eth0 scope link table nic1
ip route add "${gateway1}" dev eth1 scope link table nic1

# NOTE: These route rules are not cleared by dhclient, they persist.
ip rule add from "${ip0}" table nic0
ip rule add from "${ip1}" table nic1
# ILB IP addresses
ip rule add from "${ilb_ip0}" table nic0
ip rule add from "${ilb_ip1}" table nic1
# Firewall marking
iptables -A PREROUTING -i eth0 -t mangle -j MARK --set-mark 1
iptables -A PREROUTING -i eth1 -t mangle -j MARK --set-mark 2
# Packets ingress nic0 egress nic1
ip rule add fwmark 1 table nic1
# Packets ingress nic1 egress nic0
ip rule add fwmark 2 table nic0
# Netblocks via VPC default gateways
ip route flush cache
ip rule
EOF

  install -o 0 -g 0 -m 0755 "$tmpfile" /usr/bin/policy-routing

  svcfile="$(mktemp)"
  cat <<EOF>"$svcfile"
[Unit]
Description=Enable policy routing for multinic

[Service]
Type=oneshot
ExecStart=/usr/bin/policy-routing
EOF
  install -m 0644 -o 0 -g 0 "$svcfile" /etc/systemd/system/policy-routing.service
  systemctl daemon-reload
  systemctl start policy-routing
  systemctl enable policy-routing

return 0
}

main() {
  if ! setup_sysctl; then
    error "Failed to configure ip forwarding via sysctl, aborting."
    exit 1
  fi

  if ! configure_policy_routing; then
    error "Failed to configure local routing table, aborting"
    exit 3
  fi
  info "Configured Policy Routing as per https://cloud.google.com/vpc/docs/create-use-multiple-interfaces#configuring_policy_routing"
  info "See: systemctl status policy-routing.service"

  if ! setup_status_api; then
    error "Failed to configure status API, aborting."
    exit 2
  fi

  # Nice to have packages
  # yum -y install tcpdump mtr tmux

  # Install panic trigger
  install_kpanic_service
}

# To make this easier to execute interactively during development, load stdlib
# from the metadata server.  When the instance boots normally stdlib will load
# this script via startup-script-custom.  As a result, only use this function
# outside of the normal startup-script behavior, e.g. when developing and
# testing interactively.
load_stdlib() {
  local tmpfile
  tmpfile="$(mktemp)"
  if ! curl --silent --fail -H 'Metadata-Flavor: Google' -o "${tmpfile}" \
    http://metadata/computeMetadata/v1/instance/attributes/startup-script; then
    error "Could not load stdlib from metadata instance/attributes/startup-script"
    return 1
  fi
  # shellcheck disable=1090
  source "${tmpfile}"
}

# If the script is being executed directly, e.g. when running interactively,
# initialize stdlib.  Note, when running via the google_metadata_script_runner,
# this condition will be false because the stdlib sources this script via
# startup-script-custom.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  TMPDIR="/tmp/startup"
  [[ -d "${TMPDIR}" ]] || mkdir -p "${TMPDIR}"
  load_stdlib
  stdlib::init
  stdlib::load_config_values
fi

main "$@"
# vim:sw=2
