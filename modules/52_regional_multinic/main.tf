# Copyright 2020 Google, LLC
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

data "google_compute_zones" "available" {
  project = var.project_id
  region  = var.region
}

locals {
  zones    = data.google_compute_zones.available.names
  # Unique suffix for regional resources
  r_suffix = substr(sha1(var.region), 0, 6)
}

# Manage the regional MIG formation
module "multinic" {
  source = "../50_compute"

  image_project = var.image_project
  image_name    = var.image_name
  image_family  = var.image_family
  machine_type  = var.machine_type
  num_instances = var.num_instances
  preemptible   = var.preemptible

  startup_script = var.startup_script

  project_id  = var.project_id
  name_prefix = var.name_prefix
  region      = var.region
  zones       = local.zones

  nic0_project = var.project_id
  nic0_network = var.nic0_network
  nic0_subnet  = var.nic0_subnet

  nic1_project = var.project_id
  nic1_network = var.nic1_network
  nic1_subnet  = var.nic1_subnet

  autoscale          = var.autoscale
  utilization_target = var.utilization_target
  max_replicas       = var.max_replicas

  hc_self_link          = google_compute_health_check.multinic-health.self_link
  service_account_email = var.service_account_email
}

# The "health" health check is used for auto-healing with the MIG.  The
# timeouts are longer to reduce the risk of removing an otherwise healthy
# instance.
resource google_compute_health_check "multinic-health" {
  project = var.project_id
  name    = "${var.name_prefix}-hc-${local.r_suffix}"

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 9000
    request_path = "/status.json"
  }
}

# The "traffic" health check is used by the load balancer.  The instance will
# be taken out of service if the health check fails and other instances have
# passing traffic checks.  This check is more agressive so that the a
# preemptible instance is able to take itself out of rotation within the 30
# second window provided for shutdown.
resource google_compute_health_check "multinic-traffic" {
  project = var.project_id
  name    = "${var.name_prefix}-tc-${local.r_suffix}"

  check_interval_sec  = 3
  timeout_sec         = 2
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port         = 9001
    request_path = "/status.json"
  }
}

resource "google_compute_region_backend_service" "multinic-nic0" {
  provider = google-beta
  project  = var.project_id

  name                  = "${var.name_prefix}-${local.r_suffix}-0"
  network               = var.nic0_network
  region                = var.region
  load_balancing_scheme = "INTERNAL"

  dynamic "backend" {
    for_each = module.multinic.instance_groups
    content {
      group = backend.value
    }
  }

  # Note this is the traffic health check, not the auto-healing check
  health_checks = [google_compute_health_check.multinic-traffic.id]
}

resource "google_compute_region_backend_service" "multinic-nic1" {
  provider = google-beta
  project  = var.project_id

  name                  = "${var.name_prefix}-${local.r_suffix}-1"
  network               = var.nic1_network
  region                = var.region
  load_balancing_scheme = "INTERNAL"

  dynamic "backend" {
    for_each = module.multinic.instance_groups
    content {
      group = backend.value
    }
  }

  # Note this is the traffic health check, not the auto-healing check
  health_checks = [google_compute_health_check.multinic-traffic.id]
}

# Reserve an address so we have a well known address to configure for policy routing.
resource "google_compute_address" "ilb0" {
  name         = "${var.name_prefix}-${local.r_suffix}-ilb0"
  project      = var.project_id
  region       = var.region
  subnetwork   = var.nic0_subnet
  address_type = "INTERNAL"
}

resource "google_compute_address" "ilb1" {
  name         = "${var.name_prefix}-${local.r_suffix}-ilb1"
  project      = var.project_id
  region       = var.region
  subnetwork   = var.nic1_subnet
  address_type = "INTERNAL"
}

resource google_compute_forwarding_rule "ilb0" {
  name    = "${var.name_prefix}-${local.r_suffix}-ilb0"
  project = var.project_id
  region  = var.region

  ip_address      = google_compute_address.ilb0.address
  backend_service = google_compute_region_backend_service.multinic-nic0.id
  network         = var.nic0_network
  subnetwork      = var.nic0_subnet

  load_balancing_scheme = "INTERNAL"
  all_ports             = true
  allow_global_access   = true
}

resource google_compute_forwarding_rule "ilb1" {
  name    = "${var.name_prefix}-${local.r_suffix}-ilb1"
  project = var.project_id
  region  = var.region

  ip_address      = google_compute_address.ilb1.address
  backend_service = google_compute_region_backend_service.multinic-nic1.id
  network         = var.nic1_network
  subnetwork      = var.nic1_subnet

  load_balancing_scheme = "INTERNAL"
  all_ports             = true
  allow_global_access   = true
}

// Route resources
resource google_compute_route "via_nic1" {
  for_each     = toset(var.nic1_cidrs)
  name         = "${var.name_prefix}-${local.r_suffix}-${substr(sha1("${var.nic0_network}-${each.value}"), 0, 6)}"
  project      = var.project_id
  network      = var.nic0_network
  dest_range   = each.value
  priority     = var.priority
  next_hop_ilb = google_compute_forwarding_rule.ilb0.self_link
}

resource google_compute_route "via_nic0" {
  for_each     = toset(var.nic0_cidrs)
  name         = "${var.name_prefix}-${local.r_suffix}-${substr(sha1("${var.nic1_network}-${each.value}"), 0, 6)}"
  project      = var.project_id
  network      = var.nic1_network
  dest_range   = each.value
  priority     = var.priority
  next_hop_ilb = google_compute_forwarding_rule.ilb1.self_link
}
