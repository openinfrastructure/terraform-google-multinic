#! /bin/bash
#

setup_status_api() {
  # Install status API
  local status_file status_unit
  status_file="$(mktemp)"
  echo '{status: "OK", host: "'"${HOSTNAME}"'"}' > "${status_file}"
  install -v -o 0 -g 0 -m 0755 -d /var/lib/multinic/status
  install -v -o 0 -g 0 -m 0644 "${status_file}" /var/lib/multinic/status/status.json

  status_unit="$(mktemp)"
  cat <<EOF>"${status_unit}"
[Unit]
Description=hc-health auto-healing endpoint (Instance is auto-healed if this unit is stopped)
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
Restart=always
WorkingDirectory=/var/lib/multinic/status
ExecStart=@/usr/bin/python3 "/usr/bin/python3" "-m" "http.server" "9000"
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
  install -m 0644 -o 0 -g 0 "${status_unit}" /etc/systemd/system/hc-health.service
  systemctl daemon-reload
  systemctl restart hc-health.service
  systemctl enable hc-health.service
}

setup_iperf_server() {
  local svcfile
  svcfile="$(mktemp)"
  cat <<EOF>"$svcfile"
[Unit]
Description=iperf server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/iperf --server --interval 5
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF
  install -m 0644 -o 0 -g 0 "$svcfile" /etc/systemd/system/iperf-server.service
  systemctl daemon-reload
  systemctl start iperf-server
  systemctl enable iperf-server
}

setup_iperf_client() {
  # 30 minutes, x*10 second runs.
  local x=180
  if [[ -n "${IPERF_CLIENT}" ]]; then
    while [[ $x -gt 0 ]]; do
      ((x--))
      # Restart the client to reset the TCP window size to create pressure on the network.
      iperf --parallel 128 --time 10 -i 1 --client "${IPERF_CLIENT}" | tee /var/log/iperf.log
    done
  fi
}

setup_status_api

# Install convenience packages for load testing
apt install -y -qq iperf

setup_iperf_server

apt install -y -qq tmux htop

setup_iperf_client
