#! /bin/bash
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

# Signal the load balancer to stop sending traffic
systemctl stop hc-traffic.service
gcloud logging write multinic '{"vm": "'"${HOSTNAME}"'", "message": "hc-traffic.service stopped, sleeping 20 seconds for LB to drain"}' --severity=NOTICE --payload-type=json
# Wait 20 seconds while continuing
sleep 20
gcloud logging write multinic '{"vm": "'"${HOSTNAME}"'", "message": "Shutdown complete"}' --severity=INFO --payload-type=json
