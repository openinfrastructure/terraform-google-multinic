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

data "google_compute_image" "img" {
  project = var.image_project
  name    = var.image_name == "" ? null : var.image_name
  family  = var.image_name == "" ? var.image_family : null
}

locals {
  tags = concat(list("multinic-router"), var.tags)
  # Unique suffix for regional resources
  r_suffix = substr(sha1(var.region), 0, 6)
  mig_target_size = var.num_instances == 0 ? 0 : null
}

module "startup-script-lib" {
  source = "git::https://github.com/terraform-google-modules/terraform-google-startup-scripts.git?ref=v1.0.0"
}

data "template_file" "startup-script-config" {
  template = file("${path.module}/templates/startup-script-config.tpl")
}

resource google_compute_instance_template "multinic" {
  project        = var.project_id
  name_prefix    = var.name_prefix
  machine_type   = var.machine_type
  region         = var.region
  can_ip_forward = true

  tags = local.tags

  labels = var.labels

  network_interface {
    subnetwork         = var.nic0_subnet
    subnetwork_project = var.nic0_project
  }

  network_interface {
    subnetwork         = var.nic1_subnet
    subnetwork_project = var.nic1_project
  }

  disk {
    source_image = data.google_compute_image.img.self_link
    auto_delete  = true
    boot         = true
    type         = "PERSISTENT"
    disk_size_gb = var.disk_size_gb
  }

  metadata = {
    startup-script        = module.startup-script-lib.content
    startup-script-config = data.template_file.startup-script-config.rendered
    # Configure  Linux Policy Routing
    startup-script-custom = file("${path.module}/files/startup-multinic.sh")
    startup-script-user   = var.startup_script
    # Deletes the route resources
    shutdown-script       = file("${path.module}/files/shutdown-multinic.sh")
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

resource "google_compute_instance_group_manager" "multinic" {
  for_each = toset(var.zones)
  project  = var.project_id
  name     = "${var.name_prefix}-${substr(sha1(each.value), 0, 6)}"

  base_instance_name = var.name_prefix

  zone = each.value

  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 1
    max_unavailable_fixed = 0
    min_ready_sec         = 120
  }

  # See https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance_group_manager#target_size
  # This value should always be explicitly set unless this resource is attached
  # to an autoscaler, in which case it should never be set.
  target_size = var.autoscale ? local.mig_target_size : var.num_instances

  named_port {
    name = "hc-health"
    port = "9000"
  }

  named_port {
    name = "hc-traffic"
    port = "9001"
  }

  auto_healing_policies {
    health_check      = var.hc_self_link
    initial_delay_sec = var.hc_initial_delay_secs
  }

  version {
    name              = var.name_prefix
    instance_template = google_compute_instance_template.multinic.self_link
  }
}

resource "google_compute_autoscaler" "multinic" {
  for_each = toset(var.autoscale ? var.zones : [])
  project  = var.project_id
  name     = "${var.name_prefix}-${substr(sha1(each.value), 0, 6)}"
  zone     = each.value
  target   = google_compute_instance_group_manager.multinic[each.value].id

  autoscaling_policy {
    max_replicas    = var.max_replicas
    min_replicas    = var.num_instances
    # systemd-analyze
    # Startup finished in 1.265s (kernel) + 5.206s (initrd) + 46.529s (userspace) = 53.001s
    # multi-user.target reached after 27.702s in userspace
    cooldown_period = 45

    # CPU Utilization results in more responsive autoscaler behavior than
    # `sent_bytes_count`
    cpu_utilization {
      # multinic n1-highcpu-2 utilizes ~22-24% CPU when sending 10Gbps
      # 0.2 is a good value for a n1-highcpu-2 as of 2020-09-24
      target = var.utilization_target
    }
  }
}
