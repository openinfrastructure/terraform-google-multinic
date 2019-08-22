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

variable "name" {
  description = "The name of the IP router instance, usually is the same as the application short name, e.g. myapp"
  default     = "myapp"
}


variable "app_name" {
  description = "The application name, used within resource names to identify resources associated with this application"
  default     = "myapp"
}

variable "region" {
  description = "The region to deploy resources into"
  default     = "us-central1"
}

variable "zone" {
  description = "The zone to deploy resources into"
  default     = "us-central1-b"
}

variable "os_image" {
  description = "The os_image used with the MIG instance template"
  default     = "centos-cloud/centos-7"
}

variable "core_subnet" {
  description = "The name of the subnet the primary interface of each vpc-link instance will use.  Do not specify as a fully qualified name."
  default     = "default"
}

variable "core_project" {
  description = "The project id which hosts the shared vpc network."
  type        = "string"
}

variable "core_network" {
  description = "The Shared VPC network in the core project."
  type        = "string"
  default     = "default"
}

variable "core_cidrs" {
  description = "A list of subnets in cidr notation to route to the core network.  Used to configure routes in the app VPC. (e.g. 10.16.0.0/20)"
  default     = []
}

variable "app_network" {
  description = "The name of the unshared VPC network located in the service project."
  default     = "default"
}

variable "app_subnet" {
  description = "The name of the subnet the secondary nic1 will use in the application service project.  Do not specify as a fully qualified name."
  default     = "default"
}

variable "app_subnet_cidr" {
  description = "The cidr network of the secondary interface.  Used configure policy routing. (e.g. 10.0.1.0/24)"
  type        = "string"
}

variable "app_project" {
  description = "The service project containing the unshared vpc network."
  type        = "string"
}

variable "app_cidrs" {
  description = "A list of subnets in cidr notation to route from the core network to the app network.  Used to configure routes in the core VPC (e.g. 10.17.0.0/16)"
  default     = []
}

variable "machine_type" {
  description = "The machine type of each IP Router Bridge instance"
  default     = "n1-standard-1"
}

variable "num_instances" {
  description = "The number of instances in the instance group"
  default     = 3
}

variable "hc_initial_delay_secs" {
  description = "The number of seconds that the managed instance group waits before it applies autohealing policies to new instances or recently recreated instances."
  default     = 60
}

variable "hc_interval" {
  description = "Health check, check interval in seconds."
  default     = 3
}

variable "hc_timeout" {
  description = "Health check, timeout in seconds."
  default     = 2
}

variable "hc_healthy_threshold" {
  description = "A so-far unhealthy instance will be marked healthy after this many consecutive successes. The default value is 2."
  default     = 2
}

variable "hc_unhealthy_threshold" {
  description = "A so-far healthy instance will be marked unhealthy after this many consecutive failures. The default value is 2."
  default     = 2
}

variable "hc_port" {
  description = "Health check port"
  default     = "80"
}

variable "hc_path" {
  description = "Health check, the http path to check."
  default     = "/bridge/status.json"
}

variable "service_account_email" {
  description = "The service account bound to the bridge VM instances.  Must have permission to create Route resources in both the app and core VPC networks."
  type        = "string"
}

variable "route_priority" {
  description = "The route priority MIG instances use when creating their Route resources.  Lower numbers take precedence."
  default     = "900"
}

variable "tags" {
  description = "Additional network tags added to instances.  Useful for opening VPC firewall access.  TCP Port 80 must be allowed into nic0 for health checking to work."
  default     = ["allow-health-check"]
}
