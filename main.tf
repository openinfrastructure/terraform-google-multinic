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

locals {
  name = "vpc-link-${var.app_name}-${var.zone}"
  # The zone tag is intended for use with route resources to avoid zone egress
  # The vpc-link-router tag is intended for use with firewall rules, allowing
  # traffic from vpc-link-endpoint instances
  # The vpc-link-router* tags are intended to be a stable API to coordinate
  # routes and firewall tags.
  tags = "${concat(list("vpc-link-router", "vpc-link-router-${var.zone}"), var.tags)}"
}

module "startup-script-lib" {
  source = "git::https://github.com/terraform-google-modules/terraform-google-startup-scripts.git?ref=v0.1.0"
}

data "template_file" "startup-script-config" {
  template = "${file("${path.module}/templates/startup-script-config.tpl")}"
  vars {
    core_project = "${var.core_project}"
    core_network = "${var.core_network}"
    core_cidrs   = "${join(",", var.core_cidrs)}"
    app_project  = "${var.app_project}"
    app_network  = "${var.app_network}"
    app_cidrs    = "${join(",", var.app_cidrs)}"

    app_subnet_cidr = "${var.app_subnet_cidr}"

    route_priority = "${var.route_priority}"
  }
}

resource google_compute_instance_template "vpc-link" {
  project        = "${var.app_project}"
  name_prefix    = "${local.name}-"
  machine_type   = "${var.machine_type}"
  region         = "${var.region}"
  can_ip_forward = true

  tags = "${local.tags}"

  # Primary interface on Shared VPC.
  network_interface {
    subnetwork         = "${var.core_subnet}"
    subnetwork_project = "${var.core_project}"
  }

  network_interface {
    subnetwork         = "${var.app_subnet}"
    subnetwork_project = "${var.app_project}"
  }

  disk {
    auto_delete  = true
    boot         = true
    source_image = "${var.os_image}"
    type         = "PERSISTENT"
    disk_size_gb = "100"
  }

  metadata = {
    startup-script        = "${module.startup-script-lib.content}"
    startup-script-config = "${data.template_file.startup-script-config.rendered}"
    # Creates the route resources
    startup-script-custom = "${file("${path.module}/files/ip-router-mig.sh")}"
    # Deletes the route resources
    shutdown-script       = "${file("${path.module}/files/ip-router-mig-shutdown.sh")}"
  }

  scheduling {
    automatic_restart = true
  }

  lifecycle {
    create_before_destroy = true
  }

  service_account {
    email = "${var.service_account_email}"
    # TODO: Tighten this scope, the SA need only program route resources, not
    # have full access to all Cloud API's granted by cloud-platform.
    # See: https://cloud.google.com/sdk/gcloud/reference/alpha/compute/instances/set-scopes
    scopes = ["cloud-platform"]
  }
}

resource "google_compute_instance_group_manager" "vpc-link" {
  provider = "google-beta"
  project  = "${var.app_project}"
  name     = "${local.name}"

  base_instance_name = "${local.name}"

  zone = "${var.zone}"

  update_policy = {
    type                  = "OPPORTUNISTIC"
    minimal_action        = "REPLACE"
    max_surge_percent     = 20
    max_unavailable_fixed = 1
    min_ready_sec         = 120
  }

  target_size = "${var.num_instances}"

  named_port {
    name = "http"
    port = "80"
  }

  auto_healing_policies = {
    health_check      = "${google_compute_health_check.vpc-link.self_link}"
    initial_delay_sec = "${var.hc_initial_delay_secs}"
  }

  version {
    name              = "${local.name}"
    instance_template = "${google_compute_instance_template.vpc-link.self_link}"
  }
}

resource google_compute_health_check "vpc-link" {
  name    = "${local.name}"
  project = "${var.app_project}"

  check_interval_sec  = "${var.hc_interval}"
  timeout_sec         = "${var.hc_timeout}"
  healthy_threshold   = "${var.hc_healthy_threshold}"
  unhealthy_threshold = "${var.hc_unhealthy_threshold}"

  http_health_check {
    port         = "${var.hc_port}"
    request_path = "${var.hc_path}"
  }
}
