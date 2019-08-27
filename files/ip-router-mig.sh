#! /bin/bash
#
# Copyright 2019 Google LLC
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
# This script configures a centos-cloud/centos-7 instance to route IP traffic.
# The script has no effect on debian-cloud/debian-9

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
# package which sets values in /etc/sysctl.d/11-gce-network-security.conf
# /etc/sysctl.d/50-ip-router.conf is used to take precedence.
setup_sysctl() {
  local sysctl_file sysctl_conf
  debug '# BEGIN # setup_sysctl() ...'
  sysctl_file="$(mktemp)"
  sysctl_conf="$(mktemp)"
  # shellcheck disable=SC2129
  echo 'net.ipv4.ip_forward=1'              >> "$sysctl_file"
  echo 'net.ipv4.conf.default.forwarding=1' >> "$sysctl_file"
  echo 'net.ipv4.conf.all.forwarding=1'     >> "$sysctl_file"
  echo 'net.ipv4.conf.default.rp_filter=0'  >> "$sysctl_file"
  echo 'net.ipv4.conf.all.rp_filter=0'      >> "$sysctl_file"
  echo 'net.ipv4.conf.eth0.rp_filter=0'     >> "$sysctl_file"
  echo 'net.ipv4.conf.eth1.rp_filter=0'     >> "$sysctl_file"
  echo 'net.ipv4.conf.eth2.rp_filter=0'     >> "$sysctl_file"
  echo 'net.ipv4.conf.eth3.rp_filter=0'     >> "$sysctl_file"
  echo 'net.ipv4.conf.eth4.rp_filter=0'     >> "$sysctl_file"
  echo 'net.ipv4.conf.eth5.rp_filter=0'     >> "$sysctl_file"
  echo 'net.ipv4.conf.eth6.rp_filter=0'     >> "$sysctl_file"
  echo 'net.ipv4.conf.eth7.rp_filter=0'     >> "$sysctl_file"
  install -o 0 -g 0 -m 0644 "$sysctl_file" '/etc/sysctl.d/50-ip-router.conf'
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
  info "IP Forwarding enabled via /etc/sysctl.d/50-ip-router.conf"
}

# Expose /bridge/status.json endpoint
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

# Create route resources to route IP traffic through this instance.
# Credentials are handled using Google managed keys via the service account
# bound to the instance.
program_routes() {
  local instance_name instance_zone instance_zone_full core_ip core_cidr ary idx instance_id
  # Program route in App VPC
  # Program route in Shared VPC

  # Find the name of this instance.
  instance_id="$(stdlib::metadata_get -k instance/id)"
  instance_name="$(stdlib::metadata_get -k instance/name)"
  instance_zone_full="$(stdlib::metadata_get -k instance/zone)"
  instance_zone="${instance_zone_full##*/}"
  # The first NIC is in the Core project and VPC network
  # The second NIC is in the App project and VPC networ
  core_ip="$(stdlib::metadata_get -k instance/network-interfaces/0/ip)"

  ## Routes from APP to CORE
  IFS=',' read -ra ary <<< "${CORE_CIDRS}"
  idx=0
  for core_cidr in "${ary[@]}"; do
    cmd gcloud compute routes create \
      --project="${APP_PROJECT}" \
      --network="${APP_NETWORK}" \
      --destination-range="${core_cidr}" \
      --next-hop-instance="${instance_name}" \
      --next-hop-instance-zone="${instance_zone}" \
      --description="Route auto created by instance ${instance_name} startup-script instance_id=${instance_id}" \
      --priority="${ROUTE_PRIORITY}" \
      "${instance_name}-${instance_id}-${idx}" &

    ((idx++))
  done


  ## Route from CORE to APP
  # NOTE: This route uses IP addresses instead of instance names to avoid:
  # ERROR: (gcloud.compute.routes.create) Could not fetch resource:
  # Invalid value for field 'resource.nextHopInstance': '<instance_uri>'.
  # Cross project referencing is not allowed for this resource.
  IFS=',' read -ra ary <<< "${APP_CIDRS}"
  idx=0
  for app_cidr in "${ary[@]}"; do
    cmd gcloud compute routes create \
      --project="${CORE_PROJECT}" \
      --network="${CORE_NETWORK}" \
      --destination-range="${app_cidr}" \
      --next-hop-address="${core_ip}" \
      --description="Route auto created by instance ${instance_name} startup-script" \
      --priority="${ROUTE_PRIORITY}" \
      "${instance_name}-${instance_id}-${idx}" &

    ((idx++))
  done
  wait
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
configure_policy_routing() {
  local ary app_cidr ip gateway
  if ! grep -qx '1 rt1' /etc/iproute2/rt_tables; then
    echo "1 rt1" >> /etc/iproute2/rt_tables
  fi
  ip="$(stdlib::metadata_get -k instance/network-interfaces/1/ip)"
  gateway="$(stdlib::metadata_get -k instance/network-interfaces/1/gateway)"
  # NOTE: dhclient clears out this
  # Clear all rules associated with rt1 to prevent rules from building up
  ip rule | grep 'table rt1' | cut -d: -f1 \
    | xargs -n1 sudo ip rule del pref
  cmd ip route add "${APP_SUBNET_CIDR}" src "${ip}" dev eth1 table rt1
  cmd ip route add default via "${gateway}" dev eth1 table rt1
  # NOTE: These route rules are not cleared by dhclient, they persist.
  cmd ip rule add from "${ip}/32" table rt1
  cmd ip rule add to "${ip}/32" table rt1

  IFS=',' read -ra ary <<< "${APP_CIDRS}"
  for app_cidr in "${ary[@]}"; do
    cmd ip rule add to "${app_cidr}" table rt1
  done
  # Flush the route cache as per the iproute2 manual
  cmd ip route flush cache
  info "Finished configuring policy routing rules"
  cmd ip rule
  return 0
}

##
# Delete routes matching this instances name but not this instances ID.  Routes
# associated with the instance name but not the ID are invalid, left over from
# a previous instance which has been auto-healed.  Such routes should be
# removed as quickly as possible to avoid traffic being sent to an invalid
# next-hop, which results in dropped packets.
delete_stale_routes() {
  local instance_id instance_name routes_list route
  instance_id="$(stdlib::metadata_get -k instance/id)"
  instance_name="$(stdlib::metadata_get -k instance/name)"
  routes_list="$(mktemp)"

  gcloud compute routes list \
    --project="${CORE_PROJECT}" \
    --filter="name~^${instance_name} AND NOT name~^${instance_name}-${instance_id}" \
    --format='value(name)' > "${routes_list}"

  while read -r route; do
    cmd gcloud compute routes delete --project="${CORE_PROJECT}" "${route}" &
  done < "${routes_list}"

  gcloud compute routes list \
    --project="${APP_PROJECT}" \
    --filter="name~^${instance_name} AND NOT name~^${instance_name}-${instance_id}" \
    --format='value(name)' > "${routes_list}"

  while read -r route; do
    cmd gcloud compute routes delete --project="${APP_PROJECT}" "${route}" &
  done < "${routes_list}"

  wait
}

main() {
  if ! save_config; then
    error "Failed to save configuration to /etc/startup-script-config, needed for dhclient hooks"
    exit 1
  fi

  if ! setup_sysctl; then
    error "Failed to configure ip forwarding via sysctl, aborting."
    exit 1
  fi

  if ! configure_policy_routing; then
    error "Failed to configure local routing table, aborting"
    exit 3
  fi
  info "Configured Policy Routing as per https://cloud.google.com/vpc/docs/create-use-multiple-interfaces#configuring_policy_routing"

  if ! configure_dhclient_exit_hook; then
    error "Failed to install /etc/dhcp/dhclient-exit-hooks.d/vpc-link.sh"
    exit 1
  fi
  info "Installed /etc/dhcp/dhclient-exit-hooks.d/vpc-link.sh to restore policy routing on new DHCP lease"

  # Restart google-network-daemon to avoid race condition with dhclient eth1
  systemctl restart google-network-daemon

  if ! delete_stale_routes; then
    error "Failed to delete stale routes, aborting"
    exit 4
  fi
  info "Configured Policy Routing as per https://cloud.google.com/vpc/docs/create-use-multiple-interfaces#configuring_policy_routing"

  if ! setup_status_api; then
    error "Failed to configure status API, aborting."
    exit 2
  fi

  if ! program_routes; then
    error "Failed to configure routes in VPC networks, aboirting."
    exit 9
  fi

  # Nice to have packages
  yum -y install tcpdump mtr tmux

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

# Saves the startup-script-config metadata key to /etc/startup-script-config so
# that /etc/dhcp/dhclient-exit-hooks.d/vpc-link.sh can load the configuration
# from the local filesystem easily.
save_config() {
  local tmpfile ip gateway
  tmpfile="$(mktemp)"
  if ! curl --silent --fail -H 'Metadata-Flavor: Google' -o "${tmpfile}" \
    http://metadata/computeMetadata/v1/instance/attributes/startup-script-config; then
    error "Could not load config from metadata instance/attributes/startup-script-config"
    return 1
  fi
  install -o 0 -g 0 -m 0644 "${tmpfile}" /etc/startup-script-config

  # The gateway is not available in dhclient-exit-hooks.d because dhclient does
  # not set routers when classless static routes are provided.
  tmpfile="$(mktemp)"
  gateway="$(stdlib::metadata_get -k instance/network-interfaces/1/gateway)"
  echo "GATEWAY='${gateway}'" >> "${tmpfile}"
  install -o 0 -g 0 -m 0644 "${tmpfile}" /etc/startup-script-config-eth1
}

# Configure dhclient exit hook to avoid race condition at startup and to ensure
# ip routing configuration persists across restarts of the
# google-network-daemon service.
# See: https://github.com/openinfrastructure/terraform-google-vpc-link/issues/1
# See: https://github.com/openinfrastructure/terraform-google-vpc-link/issues/2
configure_dhclient_exit_hook() {
  local tmpfile
  tmpfile="$(mktemp)"
  cat >"${tmpfile}" <<'EOF'
#! /bin/bash
#
# NOTE: This script is sourced by dhclient-script instead of executed

configure_policy_routing() {
  # The startup-script should have configured this already, but in case not.
  if ! grep -qx '1 rt1' /etc/iproute2/rt_tables; then
    echo "1 rt1" >> /etc/iproute2/rt_tables
  fi
  # Get the GATEWAY for the interface becasue it is not provided by dhclient
  # See: https://github.com/openinfrastructure/terraform-google-vpc-link/issues/2
  # The startup-script is expected to write this file once on boot.
  source /etc/startup-script-config-"${interface}"
  # Get the APP_SUBNET_CIDR from the user provided configuration
  source /etc/startup-script-config

  logger -t vpc-link ip route add default via "${GATEWAY}" dev "${interface}" table rt1
  ip route add default via "${GATEWAY}" dev "${interface}" table rt1
  logger -t vpc-link ip route add "${APP_SUBNET_CIDR}" src "${new_ip_address}" dev "${interface}" table rt1
  ip route add "${APP_SUBNET_CIDR}" src "${new_ip_address}" dev "${interface}" table rt1
  logger -t vpc-link ip route flush cache
  ip route flush cache
  return 0
}

# Return true if the DHCP reason is valid to reconfigure routing.
# BOUND, RENEW, REBIND, REBOOT
valid_reason() {
  local check
  # Do nothing for eth0
  [[ "${interface}" == "eth0" ]] && return 2
  # For non eth0 interfaces, execute when a valid IP is obtained
  for check in BOUND RENEW REBIND REBOOT; do
    [[ "${reason}" == "${check}" ]] && return 0
  done
  return 1
}

case "${interface}" in
  eth0) exit 0 ;;
  eth*) valid_reason && configure_policy_routing ;;
  *) exit 0 ;;
esac
EOF
  install -o 0 -g 0 -m 0755 "${tmpfile}" /etc/dhcp/dhclient-exit-hooks.d/vpc-link.sh
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
