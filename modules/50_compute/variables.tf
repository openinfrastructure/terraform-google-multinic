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

variable "name_prefix" {
  description = "The name prefix to us for managed resources, for example 'multinic'.  Intended for major version upgrades of the module.  Use a unique value for each region.  See also UPGRADE.md for major version upgrades."
  type        = string
  default     = "multinic"
}

variable "project_id" {
  description = "The project ID containing the managed resources"
  type        = string
}

variable "region" {
  description = "The region containing the managed resources"
  type        = string
}

variable "zones" {
  description = "The zones containing the managed resources, for example ['us-west1-a', 'us-west1-b', 'us-west1-c']"
  type        = list(string)
}

variable "service_account_email" {
  description = "The service account bound to the bridge VM instances.  Must have permission to create Route resources in both the app and core VPC networks."
  type        = string
}

variable "image_project" {
  description = "The image project used with the MIG instance template"
  type        = string
  default     = "centos-cloud"
}

variable "image_name" {
  description = "The image name used with the MIG instance template.  If the value is the empty string, image_family is used instead."
  type        = string
  default     = "centos-8-v20200910"
}

variable "image_family" {
  description = "Configures templates to use the latest non-deprecated image in the family at the point Terraform apply is run.  Used only if image_name is empty."
  type        = string
  default     = "centos-8"
}

variable "nic0_network" {
  description = "The VPC network nic0 is attached to."
  type        = string
}

variable "nic0_subnet" {
  description = "The name of the subnet the nic0 interface of multinic instance will use.  Do not specify as a fully qualified name."
  type        = string
}

variable "nic0_project" {
  description = "The project id which hosts the shared vpc network."
  type        = string
}

variable "nic1_network" {
  description = "The VPC network nic1 is attached to."
  type        = string
}

variable "nic1_subnet" {
  description = "The name of the subnet the nic1 interface of multinic instance will use.  Do not specify as a fully qualified name."
  type        = string
}

variable "nic1_project" {
  description = "The project id which hosts the shared vpc network."
  type        = string
}

variable "hc_self_link" {
  description = "The health check self link used for auto healing.  This health check may be reused with backend services."
  type        = string
}

variable "machine_type" {
  description = "The machine type of each IP Router Bridge instance.  Check the table for Maximum egress bandwidth - https://cloud.google.com/compute/docs/machine-types"
  type        = string
  default     = "n1-highcpu-2"
}

variable "num_instances" {
  description = "The number of instances in the instance group"
  type        = number
  default     = 1
}

variable "hc_initial_delay_secs" {
  description = "The number of seconds that the managed instance group waits before it applies autohealing policies to new instances or recently recreated instances."
  type        = number
  default     = 60
}

variable "route_priority" {
  description = "The route priority MIG instances use when creating their Route resources.  Lower numbers take precedence."
  type        = number
  default     = 900
}

variable "tags" {
  description = "Additional network tags added to instances.  Useful for opening VPC firewall access.  TCP Port 80 must be allowed into nic0 for health checking to work."
  type        = list(string)
  default     = ["allow-health-check"]
}

variable "disk_size_gb" {
  description = "The size in GB of the persistent disk attached to each multinic instance."
  type        = string
  default     = "100"
}

variable "preemptible" {
  description = "Allows instance to be preempted. This defaults to false. See https://cloud.google.com/compute/docs/instances/preemptible"
  type        = bool
  default     = false
}

variable "autoscale" {
  description = "Enable autoscaling default configuration, .  For advanced configuration, set to false and manage your own google_compute_autoscaler resource with target set this module's instance_group.id output value."
  type        = bool
  default     = true
}

variable "utilization_target" {
  description = "The CPU utilization_target for the Autoscaler.  A n1-highcpu-2 instance sending at 10Gbps has CPU utilization of 22-24%."
  type        = number
  default     = 0.2 # 20% when using CPU Utilization
  # default   = 939524096 # 70% of 10Gbps when using `instance/network/sent_bytes_count`
  # default   = 161061273 # 60% of 2Gbps when using `instance/network/sent_bytes_count`
}

variable "max_replicas" {
  description = "The maximum number of instances when the Autoscaler scales out"
  type        = number
  default     = 4
}

variable "labels" {
  description = "Labels to apply to the compute instance resources managed by this module"
  type        = map
  default     = {
    role = "multinic-router"
  }
}
