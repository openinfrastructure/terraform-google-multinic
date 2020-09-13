/**
 * Copyright 2020 Open Infrastructure Services, LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

variable "billing_account" {
  description = "The billing account to associate with the project.  For example, `0X0X0X-0X0X0X-0X0X0X`"
  type        = string
}

variable "organization" {
  description = "The GCP organization domain name, e.g. `example.com`"
  type        = string
}

variable "org_id" {
  description = "The organization ID in numeric form, for example `123443944466`"
  type        = string
}

variable "folder_id" {
  description = "Parent folder id of the managed project"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "iap_members" {
  description = "List of members to grant IAP tunnel access, for example ['group:foo@example.com', 'jeff@ois.run']"
  type        = list(string)
  default     = []
}
