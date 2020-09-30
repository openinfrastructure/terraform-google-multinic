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

variable "project_id" {
  description = "The project ID containing the managed resources"
  type        = string
}

variable "name_prefix" {
  description = "The name prefix to uss for managed resources, for example 'multinic'.  Intended for major version upgrades of the module."
  type        = string
  default     = "multinic-v2"
}

variable "priority" {
  description = "The route priority to use for managed resources.  Intended for major version upgrades of the module."
  type        = number
  default     = 900
}

variable "region" {
  description = "The region containing the managed resources"
  type        = string
}

variable "num_instances" {
  description = "Set to 0 to reduce costs when not actively developing."
  type        = number
  default     = 0
}

variable "preemptible" {
  description = "Allows instance to be preempted. This defaults to false. See https://cloud.google.com/compute/docs/instances/preemptible"
  type        = bool
  default     = false
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

variable "nic1_cidrs" {
  description = "A list of subnets in cidr notation, traffic destined for these subnets will route out nic1.  Used to configure routes. (e.g. 10.16.0.0/20)"
  type        = list(string)
  default     = []
}

variable "service_account_email" {
  description = "The service account bound to the bridge VM instances.  Must have permission to create Route resources in both the app and core VPC networks."
  type        = string
}
