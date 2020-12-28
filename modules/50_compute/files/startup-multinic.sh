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

# Return a string payload for logging
payload() {
  local payload
  # One time fetch of instance_id, /etc/google_instance_id may not exist yet.
  if [[ -z "${INSTANCE_ID:-}" ]]; then
    local tmpfile
    tmpfile="$(mktemp)"
    curl -s -S -f -o "$tmpfile" -H Metadata-Flavor:Google metadata/computeMetadata/v1/instance/id
    INSTANCE_ID="$(<"$tmpfile")"
  fi

  payload='{"vm": "'"${HOSTNAME%%.*}"'", "message": "'"$*"'"'
  payload="${payload}, \"instance_id\": \"${INSTANCE_ID}\"}"
  echo "${payload}"
}

error() {
  if [[ -n "${STARTUP_SCRIPT_STDLIB_INITIALIZED:-}" ]]; then
    stdlib::error "$@"
  else
    echo "$@" >&2
  fi
  gcloud logging write multinic "$(payload "$@")" --severity=ERROR --payload-type=json &
}

info() {
  if [[ -n "${STARTUP_SCRIPT_STDLIB_INITIALIZED:-}" ]]; then
    stdlib::info "$@"
  else
    echo "$@"
  fi
  gcloud logging write multinic "$(payload "$@")" --severity=INFO --payload-type=json &
}

debug() {
  if [[ -n "${STARTUP_SCRIPT_STDLIB_INITIALIZED:-}" ]]; then
    stdlib::debug "$@"
  else
    echo "$@"
  fi
  gcloud logging write multinic "$(payload "$@")" --severity=DEBUG --payload-type=json &
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

# Configure two status check endpoints.  Port 9000 is used by the MIG for
# auto-ealing.  Port 9001 is used by the Load Balancer forwarding rule backend
# service to start or stop traffic forwarding to this instance.
#
# The startup script should configure routing and enable this service as
# quickly as possible.
#
# Take an instance out of rotation by stopping hc-traffic.
# Start the auto-healing process by stopping hc-health
setup_status_api() {
  # Install status API
  local status_file status_unit1 status_unit2
  status_file="$(mktemp)"
  echo '{status: "OK", host: "'"${HOSTNAME}"'"}' > "${status_file}"
  install -v -o 0 -g 0 -m 0755 -d /var/lib/multinic/status
  install -v -o 0 -g 0 -m 0644 "${status_file}" /var/lib/multinic/status/status.json

  status_unit1="$(mktemp)"
  cat <<EOF >"${status_unit1}"
[Unit]
Description=hc-health auto-healing endpoint (Instance is auto-healed if this unit is stopped)
After=network.target

[Service]
Type=simple
User=nobody
Group=nobody
Restart=always
WorkingDirectory=/var/lib/multinic/status
ExecStart=@/usr/bin/python3 "/usr/bin/python3" "-m" "http.server" "9000"
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
  install -m 0644 -o 0 -g 0 "${status_unit1}" /etc/systemd/system/hc-health.service

  status_unit2="$(mktemp)"
  cat <<EOF >"${status_unit2}"
[Unit]
Description=hc-traffic load-balancing endpoint (Instance is taken out of service if this unit is stopped)
After=network.target

[Service]
Type=simple
User=nobody
Group=nobody
Restart=always
WorkingDirectory=/var/lib/multinic/status
ExecStart=@/usr/bin/python3 "/usr/bin/python3" "-m" "http.server" "9001"
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
  install -m 0644 -o 0 -g 0 "${status_unit2}" /etc/systemd/system/hc-traffic.service

  systemctl daemon-reload
  systemctl restart hc-health.service
  systemctl restart hc-traffic.service
  systemctl enable hc-health.service
  systemctl enable hc-traffic.service
}

# Install a oneshot systemd service to trigger a kernel panic.
# Intended for gcloud compute ssh <instance> -- sudo systemctl start kpanic --no-block
install_kpanic_service() {
  local tmpfile
  tmpfile="$(mktemp)"
  cat <<EOF >"${tmpfile}"
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
  local ip0 ip1 gateway0 gateway1 netmask0 netmask1 ilb_ip0 ilb_ip1 tmpfile svcfile net0 net1 PREFIX

  # Note: This only gets the first forwarded IP address for each interface.
  ip0="$(stdlib::metadata_get -k instance/network-interfaces/0/ip)"
  # ilb_ip0="$(stdlib::metadata_get -k instance/network-interfaces/0/forwarded-ips/0)"
  netmask0="$(stdlib::metadata_get -k instance/network-interfaces/0/subnetmask)"
  gateway0="$(stdlib::metadata_get -k instance/network-interfaces/0/gateway)"
  ip1="$(stdlib::metadata_get -k instance/network-interfaces/1/ip)"
  # ilb_ip1="$(stdlib::metadata_get -k instance/network-interfaces/1/forwarded-ips/0)"
  netmask1="$(stdlib::metadata_get -k instance/network-interfaces/1/subnetmask)"
  gateway1="$(stdlib::metadata_get -k instance/network-interfaces/1/gateway)"

  eval "$(ipcalc --network --prefix "${ip0}/${netmask0}")"
  net0="${NETWORK}/${PREFIX}"
  eval "$(ipcalc --network --prefix "${ip1}/${netmask1}")"
  net1="${NETWORK}/${PREFIX}"

  tmpfile="$(mktemp)"
  cat <<EOF >"$tmpfile"
#! /bin/bash
# These tables manage default routes based on policy.
if ! grep -qx '10 viaeth0' /etc/iproute2/rt_tables; then
  echo "10 viaeth0" >> /etc/iproute2/rt_tables
fi
if ! grep -qx '11 viaeth1' /etc/iproute2/rt_tables; then
  echo "11 viaeth1" >> /etc/iproute2/rt_tables
fi

set -x

## These are essentially the same tables, just different default routes.
# via eth0
ip route replace default via ${gateway0} dev eth0 proto static table viaeth0
ip route replace ${gateway0} dev eth0 proto static scope link table viaeth0
ip route replace ${gateway1} dev eth1 proto static scope link table viaeth0
ip route replace ${net0} via ${gateway0} dev eth0 proto static table viaeth0
ip route replace ${net1} via ${gateway1} dev eth1 proto static table viaeth0
# via eth1
ip route replace default via ${gateway1} dev eth1 proto static table viaeth1
ip route replace ${gateway0} dev eth0 proto static scope link table viaeth1
ip route replace ${gateway1} dev eth1 proto static scope link table viaeth1
ip route replace ${net0} via ${gateway0} dev eth0 proto static table viaeth1
ip route replace ${net1} via ${gateway1} dev eth1 proto static table viaeth1

## Rules (Policy Based Routing)
# PREFERENCE is an unsigned integer value, higher number means lower priority,
# and rules get processed in order of increasing number.
# Traffic from the this host.  Intended for health checks.
ip rule add priority 1000 from ${net0} iif lo table viaeth0
ip rule add priority 1001 from ${net1} iif lo table viaeth1
# Traffic not from this host.  Intended to behave as a "virtual wire"
ip rule add priority 1002 iif eth0 table viaeth1
ip rule add priority 1003 iif eth1 table viaeth0
# Flush the route cache
ip route flush cache

set +x

# Save the IP rules once to be checked by the policy-routing-monitor service.
install -v -o 0 -g 0 -m 0755 -d /var/lib/multinic/status
ip rule show all > /var/lib/multinic/status/rules.txt
ip route list table viaeth0 > /var/lib/multinic/status/viaeth0.txt
ip route list table viaeth1 > /var/lib/multinic/status/viaeth1.txt
EOF
  install -o 0 -g 0 -m 0755 "$tmpfile" /usr/sbin/policy-routing

  # The corresponding stop script.
  tmpfile="$(mktemp)"
  cat <<EOF >"$tmpfile"
#! /bin/bash
# Stop policy routing by deleting the rules.  The custom tables remain but
# aren't used.
ip rule delete priority 1000
ip rule delete priority 1001
ip rule delete priority 1002
ip rule delete priority 1003
EOF
  install -o 0 -g 0 -m 0755 "$tmpfile" /usr/sbin/policy-routing-stop

  svcfile="$(mktemp)"
  cat <<EOF >"$svcfile"
[Unit]
Description=Configure Policy Routing to behave as a virtual wire
After=network-online.target
Wants=network-online.target
PartOf=network.service

[Service]
Type=oneshot
ExecStart=/usr/sbin/policy-routing
ExecStop=/usr/sbin/policy-routing-stop
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
  install -m 0644 -o 0 -g 0 "$svcfile" /etc/systemd/system/policy-routing.service

  # Start the monitoring service. If the routing tables change from when policy
  # routing was configured, then the auto-heal health check reports unhealthy.
  # Note, only viaeth0 and viaeth1 tables are monitored because the Google OS
  # Agent adds and removes route entries dynamically as forwarding rules are
  # activated and de-activated for the instance.
  tmpfile="$(mktemp)"
  cat <<'EOF' >"$tmpfile"
#! /bin/bash
rules="$(mktemp)"
viaeth0="$(mktemp)"
viaeth1="$(mktemp)"

ip rule show all > "${rules}"
ip route list table viaeth0 > "${viaeth0}"
ip route list table viaeth1 > "${viaeth1}"

errors=0

diff -U5 /var/lib/multinic/status/rules.txt "${rules}" >&2
if [[ ${PIPESTATUS[0]} -gt 0 ]]; then
  echo "Error: ip rule show all has changed"
  ((errors++))
fi

diff -U5 /var/lib/multinic/status/viaeth0.txt "${viaeth0}" >&2
if [[ ${PIPESTATUS[0]} -gt 0 ]]; then
  echo "Error: ip route list table viaeth0 has changed"
  ((errors++))
fi

diff -U5 /var/lib/multinic/status/viaeth1.txt "${viaeth1}" >&2
if [[ ${PIPESTATUS[0]} -gt 0 ]]; then
  echo "Error: ip route list table viaeth1 has changed"
  ((errors++))
fi

if [[ $(sysctl -n net.ipv4.ip_forward) -ne 1 ]]; then
  echo "Error: net.ipv4.ip_forward is not 1"
  ((errors++))
fi

if [[ $(sysctl -n net.ipv4.conf.all.forwarding) -ne 1 ]]; then
  echo "Error: net.ipv4.conf.all.forwarding is not 1"
  ((errors++))
fi

if [[ ${errors} -gt 0 ]]; then
  echo "Stopping hc-health.service to trigger auto-healing"
  systemctl stop hc-health.service
fi

exit ${errors}
EOF
  install -o 0 -g 0 -m 0755 "$tmpfile" /usr/sbin/policy-routing-nanny

  svcfile="$(mktemp)"
  cat <<EOF >"$svcfile"
[Unit]
Description=policy-routing-nanny
After=policy-routing.service

[Service]
Type=oneshot
ExecStart=/usr/sbin/policy-routing-nanny
PrivateTmp=true
EOF
  install -m 0644 -o 0 -g 0 "$svcfile" /etc/systemd/system/policy-routing-nanny.service

  svcfile="$(mktemp)"
  cat <<EOF >"$svcfile"
[Unit]
Description=Periodically verify policy routing has not changed
Documentation=https://github.com/openinfrastructure/terraform-google-multinic/issues/7

[Timer]
OnBootSec=2min
OnUnitActiveSec=5

[Install]
WantedBy=timers.target
EOF
  install -m 0644 -o 0 -g 0 "$svcfile" /etc/systemd/system/policy-routing-nanny.timer

  systemctl daemon-reload
  systemctl start policy-routing policy-routing-nanny.timer
  systemctl enable policy-routing policy-routing-nanny.timer

return 0
}

# Workaround https://github.com/GoogleCloudPlatform/guest-agent/issues/76 to
# prevent `systemctl restart google-guest-agent` from breaking policy routing.
workaround_guest_agent() {
  local tmpfile
  tmpfile="$(mktemp)"
  cat <<"EOF" >"$tmpfile"
#! /bin/bash
# Avoid the call to remove_old_addr, which calls ip addr del, which causes policy routes to be deleted.
# See https://github.com/GoogleCloudPlatform/guest-agent/issues/76
logmessage "/etc/dhcp/dhclient-down-hooks - Workaround for https://github.com/GoogleCloudPlatform/guest-agent/issues/76"
exit_with_hooks 0
EOF
  install -o 0 -g 0 -m 0755 "$tmpfile" /etc/dhcp/dhclient-down-hooks
  rval=$?
  rm -f "$tmpfile"
  return $rval
}

main() {
  local jobs

  info "BEGIN: Policy Routing Startup for ${HOSTNAME}"

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
    error "Failed to configure status API endpoints, aborting."
    exit 2
  fi

  info "CHECKPOINT: Online and ready ${HOSTNAME}"

  if ! workaround_guest_agent; then
    error "Failed to work around https://github.com/GoogleCloudPlatform/guest-agent/issues/76"
    exit 4
  fi

  # Nice to have packages
  # yum -y install tcpdump mtr tmux

  # Install panic trigger
  install_kpanic_service

  # Wait for any logging jobs to finish.
  jobs="$(jobs -p)"
  if [[ -n "${jobs}" ]]; then
    # shellcheck disable=SC2086
    wait ${jobs}
  fi

  info "END: Policy Routing Startup for ${HOSTNAME}"
  return 0
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
