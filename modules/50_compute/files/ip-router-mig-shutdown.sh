#! /bin/bash
#
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
#
# Shutdown script to remove routes before the instance itself is removed.
# Removing the routes has the effect of "draining" the MIG IP router instance
# before the MIG itself terminates and replaces the instance.  This is
# particularly useful for zero-downtime rolling updates of the instances in the
# group.

# See documentation: https://cloud.google.com/compute/docs/shutdownscript
# Key points:
# Shutdown scripts have a limited amount of time to finish running before the instance stops:
# * On-demand instances: 90 seconds after you stop or delete an instance
# * Preemptible instances: 30 seconds after instance preemption begins
# Compute Engine executes shutdown scripts only on a best-effort basis. In rare
# cases, Compute Engine cannot guarantee that the shutdown script will
# complete.

set -u

delete_routes() {
  local instance_name instance_id name_file id_file
  # Find the name of this instance.
  name_file="$(mktemp)"
  if ! curl --silent --fail -H 'Metadata-Flavor: Google' -o "${name_file}" \
    http://metadata/computeMetadata/v1/instance/name; then
    echo "Could not determine instance name" >&2
    return 1
  fi
  instance_name="$(<"${name_file}")"

  id_file="$(mktemp)"
  if ! curl --silent --fail -H 'Metadata-Flavor: Google' -o "${id_file}" \
    http://metadata/computeMetadata/v1/instance/id; then
    echo "Could not determine instance id" >&2
    return 1
  fi
  instance_id="$(<"${id_file}")"

  ## Route from APP to CORE
  gcloud compute routes list --project="${APP_PROJECT}" \
    --filter="name~^${instance_name}-${instance_id}" \
    --format="value(name)" \
    | xargs --no-run-if-empty -t -P16 \
      gcloud compute routes delete --project="${APP_PROJECT}" -q &

  ## Routes from CORE to APP
  gcloud compute routes list --project="${CORE_PROJECT}" \
    --filter="name~^${instance_name}-${instance_id}" \
    --format="value(name)" \
    | xargs --no-run-if-empty -t -P16 \
      gcloud compute routes delete --project="${CORE_PROJECT}" -q &

  wait
}

# TODO(jmccune): Wrap this in stdlib to operationalize it with standard config
# loading behavior, logs, etc...
tmpfile="$(mktemp)"
if ! curl --silent --fail -H 'Metadata-Flavor: Google' -o "${tmpfile}" \
  http://metadata/computeMetadata/v1/instance/attributes/startup-script-config
then
  echo "Could not load startup-script-config" >&2
  exit 2
fi
# shellcheck disable=SC1090
source "${tmpfile}"

delete_routes
