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

# This module is intended to be instantiated multiple times to manage multiple
# VPC networks for the Multinic solution.

/** Manage the VPC network */
module "vpc" {
  source  = "terraform-google-modules/network/google//modules/vpc"
  version = "~> 3.0"

  project_id              = var.project_id
  network_name            = var.network_name
  auto_create_subnetworks = false
}

// Subnets.  These are simple subnets for testing purposes.
resource "google_compute_subnetwork" "subnet" {
  for_each    = var.subnets
  name        = "${var.network_name}-${each.key}"
  region      = lookup(each.value, "region", var.region)
  project     = var.project_id
  network     = module.vpc.network_self_link
  description = lookup(each.value, "description", null)

  // GKE Nodes are expected to communicate with Google APIs and Services.
  private_ip_google_access = true

  ip_cidr_range = lookup(each.value, "ip_cidr_range", null)
}

// Cloud Nat
module "cloud-nat" {
  source     = "terraform-google-modules/cloud-nat/google"
  version    = "~> 1.2"
  project_id = var.project_id
  region     = var.region
  name       = "cloud-nat-${module.vpc.network_name}-${var.region}"
  router     = "cloud-nat-${module.vpc.network_name}-${var.region}"
  network    = module.vpc.network_name

  create_router = true
}

// Health Check firewall rule, necessary for the Runner MIG health checks.
resource "google_compute_firewall" "allow-health-check" {
  name    = "${module.vpc.network_name}-allow-health-check"
  network = module.vpc.network_name
  project = var.project_id

  description = "Allow health check probes for instance groups"

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["allow-health-check"]

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }
}

// Allow SSH for IAP Access
resource "google_compute_firewall" "default-allow-ssh" {
  # The network name in the firewall name avoid `alreadyExists` errors
  name    = "${module.vpc.network_name}-default-allow-ssh"
  network = module.vpc.network_name
  project = var.project_id

  description = "Allow SSH"
  priority    = 65534

  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "default-allow-icmp" {
  name    = "${module.vpc.network_name}-default-allow-icmp"
  network = module.vpc.network_name
  project = var.project_id

  description = "Allow ICMP"
  priority    = 65534

  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "icmp"
  }
}

// Allow all traffic for testing
resource "google_compute_firewall" "allow-all" {
  name    = "${module.vpc.network_name}-allow-all"
  network = module.vpc.network_name
  project = var.project_id

  description = "Allow all traffic"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }
}
