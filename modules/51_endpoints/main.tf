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
  tags = concat(list("multinic-endpoint"), var.tags)
}

module "startup-script-lib" {
  source = "git::https://github.com/terraform-google-modules/terraform-google-startup-scripts.git?ref=v1.0.0"
}

data "template_file" "startup-script-config" {
  template = "${file("${path.module}/templates/startup-script-config.tpl")}"
}

resource google_compute_instance_template "template" {
  project        = var.project_id
  name_prefix    = var.name_prefix
  machine_type   = var.machine_type
  region         = var.region
  can_ip_forward = false

  tags = local.tags

  network_interface {
    subnetwork         = var.nic0_subnet
    subnetwork_project = var.nic0_project
  }

  disk {
    auto_delete  = true
    boot         = true
    source_image = var.os_image
    type         = "PERSISTENT"
    disk_size_gb = var.disk_size_gb
  }

  metadata                = {
    startup-script        = module.startup-script-lib.content
    startup-script-config = data.template_file.startup-script-config.rendered
    startup-script-custom = file("${path.module}/files/startup.sh")
    shutdown-script       = file("${path.module}/files/shutdown.sh")
  }

  scheduling {
    preemptible       = var.preemptible
    automatic_restart = var.preemptible ? false : true
  }

  lifecycle {
    create_before_destroy = true
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }
}

data "google_compute_zones" "available" {
  project = var.project_id
  region  = var.region
}

module "mig" {
  source            = "terraform-google-modules/vm/google//modules/mig"
  version           = "4.0.0"
  project_id        = var.project_id
  region            = var.region
  target_size       = var.num_instances
  hostname          = var.name_prefix
  instance_template = google_compute_instance_template.template.self_link
  health_check      = {
    type                = "http"
    check_interval_sec  = 3
    port                = 80
    timeout_sec         = 2
    healthy_threshold   = 1
    host                = ""
    initial_delay_sec   = 60
    proxy_header        = "NONE"
    request             = ""
    request_path        = "/"
    response            = ""
    unhealthy_threshold = 5
  }
  update_policy     = [{
    minimal_action        = "REPLACE"
    type                  = "PROACTIVE"
    min_ready_sec         = 120
    max_surge_fixed       = null
    max_unavailable_fixed = length(data.google_compute_zones.available.names)
    # Required but not used below
    instance_redistribution_type  = null
    max_surge_percent             = null
    max_unavailable_percent       = null
  }]
}
