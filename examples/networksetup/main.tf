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

locals {
  # project_id = "network-dev-123456"
  project_id = module.host.project_id
  region     = "us-west1"

  # Name prefix used for VM resources
  name_prefix = "multinic"
}

# Comment this out if you already have a project.
module "host" {
  source = "../../modules/10_project"

  folder_id       = "folders/504963200559"
  organization    = "openinfrastructure.co"
  org_id          = "600043944461"
  project_name    = "multinic-networks"
  billing_account = "010C18-6A318B-190124"
  iap_members     = ["group:gcp-platform-admin@openinfrastructure.co"]
}

# Comment this out if you already have a VPC
# 10.32.0.0/14 - 10.35.255.255
module "main-vpc" {
  source = "../../modules/20_vpc"

  network_name = "main"
  subnets      = {
    general = { ip_cidr_range = "10.32.0.0/20", region = local.region },
    bridge  = { ip_cidr_range = "10.33.0.0/20", region = local.region },
    remote  = { ip_cidr_range = "10.34.0.0/20", region = "us-west2" },
    bridge2  = { ip_cidr_range = "10.40.0.0/20", region = "us-west2" },
  }
  project_id = local.project_id
  region     = local.region
}

# Comment this out if you already have a VPC
# 10.36.0.0/14 - 10.39.255.255
module "transit-vpc" {
  source = "../../modules/20_vpc"

  network_name = "transit"
  subnets      = {
    general = { ip_cidr_range = "10.36.0.0/20", region = local.region },
    bridge = { ip_cidr_range = "10.37.0.0/20", region = local.region },
    remote  = { ip_cidr_range = "10.38.0.0/20", region = "us-west2" },
    bridge2 = { ip_cidr_range = "10.41.0.0/20", region = "us-west2" },
  }
  project_id   = local.project_id
  region       = local.region
}

// Google Service Account to attach to multinic VM instances.
resource "google_service_account" "multinic" {
  project      = local.project_id
  account_id   = "multinic"
  display_name = "multinic vm router"
  description  = "Multinic VM Router"
}

// Google Service Account to attach to endpoint VM instances.
resource "google_service_account" "endpoint" {
  project      = local.project_id
  account_id   = "endpoint"
  display_name = "endpoint"
  description  = "Endpoint used for Multinic Testing"
}

// Allow multinic instances to write log entries
resource "google_project_iam_member" "log_writer" {
  project = local.project_id
  member  = "serviceAccount:${google_service_account.multinic.email}"
  role    = "roles/logging.logWriter"
}

resource "google_project_iam_member" "log_writer_endpoint" {
  project = local.project_id
  member  = "serviceAccount:${google_service_account.endpoint.email}"
  role    = "roles/logging.logWriter"
}
