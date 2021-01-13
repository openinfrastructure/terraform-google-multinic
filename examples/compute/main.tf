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

variable "num_instances" {
  description = "Set to 0 to reduce costs when not actively developing."
  type        = number
  default     = 0
}

# Number of instances in zone b
variable "num_instances_b" {
  description = "Set to 0 to reduce costs when not actively developing."
  type        = number
  default     = 0
}

variable "preemptible" {
  description = "Allows instance to be preempted. This defaults to false. See https://cloud.google.com/compute/docs/instances/preemptible"
  type        = bool
  default     = true
}

variable "project_id" {
  description = "Project ID containing managed resources"
  type        = string
}

locals {
  project_id = var.project_id
  region     = "us-west1"

  # nic0's gateway routes to this netblock
  nic0_netblock = "10.32.0.0/14"
  # nic1's gateway routes to this netblock
  nic1_netblock = "10.36.0.0/14"

  nic0_network = "main"
  nic0_subnet  = "main-bridge"
  nic1_network = "transit"
  nic1_subnet  = "transit-bridge"
}

# Manage the regional MIG formation
module "multinic" {
  source = "../../modules/50_compute"

  num_instances = var.num_instances
  preemptible   = var.preemptible
  autoscale     = var.num_instances == 0 ? false : true

  project_id  = local.project_id
  name_prefix = "multinic"
  region      = local.region
  zones       = [ "${local.region}-b", "${local.region}-c" ]

  nic0_network = local.nic0_network
  nic0_project = local.project_id
  nic0_subnet  = local.nic0_subnet

  nic1_network = local.nic1_network
  nic1_project = local.project_id
  nic1_subnet  = local.nic1_subnet

  hc_self_link = google_compute_health_check.multinic-health.self_link
  service_account_email = "multinic@${local.project_id}.iam.gserviceaccount.com"
}

# The "health" health check is used for auto-healing with the MIG.  The
# timeouts are longer to reduce the risk of removing an otherwise healthy
# instance.
resource google_compute_health_check "multinic-health" {
  project = local.project_id
  name    = "multinic-health"

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
  project = local.project_id
  name    = "multinic-traffic"

  check_interval_sec  = 3
  timeout_sec         = 2
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port         = 9001
    request_path = "/status.json"
  }
}

resource "google_compute_region_backend_service" "multinic-main" {
  provider = google-beta
  project  = local.project_id

  name                  = "multinic-main"
  network               = "main"
  region                = local.region
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

resource "google_compute_region_backend_service" "multinic-transit" {
  provider = google-beta
  project  = local.project_id

  name                  = "multinic-transit"
  network               = "transit"
  region                = local.region
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
resource "google_compute_address" "main" {
  name         = "main-fwd"
  project      = local.project_id
  region       = local.region
  subnetwork   = "main-bridge"
  address_type = "INTERNAL"
}

resource "google_compute_address" "transit" {
  name         = "transit-fwd"
  project      = local.project_id
  region       = local.region
  subnetwork   = "transit-bridge"
  address_type = "INTERNAL"
}

resource google_compute_forwarding_rule "main" {
  name    = "multinic-main"
  project = local.project_id
  region  = local.region

  ip_address      = google_compute_address.main.address
  backend_service = google_compute_region_backend_service.multinic-main.id
  network         = "main"
  subnetwork      = "main-bridge"

  load_balancing_scheme = "INTERNAL"
  all_ports             = true
  allow_global_access   = true
}

resource google_compute_forwarding_rule "transit" {
  name    = "multinic-transit"
  project = local.project_id
  region  = local.region

  ip_address      = google_compute_address.transit.address
  backend_service = google_compute_region_backend_service.multinic-transit.id
  network         = "transit"
  subnetwork      = "transit-bridge"

  load_balancing_scheme = "INTERNAL"
  all_ports             = true
  allow_global_access   = true
}

// Route resources
resource google_compute_route "main" {
  name         = "main"
  project      = local.project_id
  network      = local.nic0_network
  dest_range   = local.nic1_netblock
  priority     = 900
  next_hop_ilb = google_compute_forwarding_rule.main.self_link
}

resource google_compute_route "transit" {
  name         = "transit"
  project      = local.project_id
  network      = local.nic1_network
  dest_range   = local.nic0_netblock
  priority     = 900
  next_hop_ilb = google_compute_forwarding_rule.transit.self_link
}
