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

# Instances in the same region as the multinic VMs.
variable "num_instances" {
  description = "Set to 0 to reduce costs when not actively developing."
  type        = number
  default     = 0
}

# Instances in a differnt region from the multinic VMs.
variable "num_instances_remote" {
  description = "Set to 0 to reduce costs when not actively developing."
  type        = number
  default     = 0
}

locals {
  project_id = "multinic-networks-18d1"
}

# Manage the regional MIG formation
module "endpoint-main-general" {
  source = "../../modules/51_endpoints"

  num_instances = var.num_instances
  preemptible   = true

  project_id  = local.project_id
  name_prefix = "endpoint-main-general"
  region      = "us-west1"

  nic0_network = "main"
  nic0_project = local.project_id
  nic0_subnet  = "main-general"

  service_account_email = "endpoint@${local.project_id}.iam.gserviceaccount.com"
}

module "endpoint-transit-general" {
  source = "../../modules/51_endpoints"

  num_instances = var.num_instances
  preemptible   = true

  project_id  = local.project_id
  name_prefix = "endpoint-transit-general"
  region      = "us-west1"

  nic0_network = "transit"
  nic0_project = local.project_id
  nic0_subnet  = "transit-general"

  service_account_email = "endpoint@${local.project_id}.iam.gserviceaccount.com"
}

module "endpoint-main-remote" {
  source = "../../modules/51_endpoints"

  num_instances = var.num_instances_remote

  project_id  = local.project_id
  name_prefix = "endpoint-main-remote"
  region      = "us-west2"

  nic0_network = "main"
  nic0_project = local.project_id
  nic0_subnet  = "main-remote"

  service_account_email = "endpoint@${local.project_id}.iam.gserviceaccount.com"
}

module "endpoint-transit-remote" {
  source = "../../modules/51_endpoints"

  num_instances = var.num_instances_remote

  project_id  = local.project_id
  name_prefix = "endpoint-transit-remote"
  region      = "us-west2"

  nic0_network = "transit"
  nic0_project = local.project_id
  nic0_subnet  = "transit-remote"

  service_account_email = "endpoint@${local.project_id}.iam.gserviceaccount.com"
}
