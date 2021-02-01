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

module "project" {
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 9.2"

  name                    = var.project_name
  random_project_id       = true
  folder_id               = var.folder_id
  billing_account         = var.billing_account
  default_service_account = "keep"
  domain                  = var.organization
  org_id                  = var.org_id

  # Enable API's required by Project Factory
  activate_apis = [
    "compute.googleapis.com",
    "logging.googleapis.com",
    "container.googleapis.com",
  ]
}

// Enable Shared VPC Host project.
resource "google_compute_shared_vpc_host_project" "project" {
  project = module.project.project_id
}

// Enable IAP Access.
resource "google_project_iam_member" "iap_tunnel" {
  for_each = toset(var.iap_members)
  project  = module.project.project_id
  member   = each.key
  role     = "roles/iap.tunnelResourceAccessor"
}
