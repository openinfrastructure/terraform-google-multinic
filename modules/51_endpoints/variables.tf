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
  description = "The name prefix to us for managed resources, for example 'multinic'"
  type        = string
}

variable "project_id" {
  description = "The project ID containing the managed resources"
  type        = string
}

variable "region" {
  description = "The region containing the managed resources"
  type        = string
}

variable "os_image" {
  description = "The os_image used with the MIG instance template"
  type        = string
  default     = "centos-cloud/centos-8"
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

variable "nic0_cidrs" {
  description = "A list of subnets in cidr notation, traffic destined for these subnets will route out nic0.  Used to configure routes. (e.g. 10.16.0.0/20)"
  type        = list(string)
  default     = []
}

variable "machine_type" {
  description = "The machine type of each IP Router Bridge instance"
  type        = string
  default     = "n1-standard-1"
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

variable "hc_interval" {
  description = "Health check, check interval in seconds."
  type        = number
  default     = 3
}

variable "hc_timeout" {
  description = "Health check, timeout in seconds."
  type        = number
  default     = 2
}

variable "hc_healthy_threshold" {
  description = "A so-far unhealthy instance will be marked healthy after this many consecutive successes. The default value is 2."
  type        = number
  default     = 2
}

variable "hc_unhealthy_threshold" {
  description = "A so-far healthy instance will be marked unhealthy after this many consecutive failures. The default value is 2."
  type        = number
  default     = 2
}

variable "hc_port" {
  description = "Health check port"
  type        = string
  default     = "80"
}

variable "hc_path" {
  description = "Health check, the http path to check."
  type        = string
  default     = "/bridge/status.json"
}

variable "service_account_email" {
  description = "The service account bound to the bridge VM instances.  Must have permission to create Route resources in both the app and core VPC networks."
  type        = string
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
