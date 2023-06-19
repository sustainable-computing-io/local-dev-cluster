#!/bin/bash
#
# This file is part of the Kepler project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright 2023 The Kepler Contributors
#
set -x
## basic check for bcc
if [ $(dpkg -l | grep bcc | wc -l) == 0 ]; then
    echo "no bcc package found"
fi
## basic check for k8s cluster info
if [ ${CLUSTER_PROVIDER} == "kind" ]; then
    if [ $(kind get kubeconfig --name=kind | grep contexts | wc -l) == 0 ]; then
        echo "fail to get kubeconfig by provider"
        exit 1
    fi
fi
## check k8s system pod is there...
if [ $(kubectl get pods --all-namespaces | wc -l) == 0 ]; then
    echo "it seems k8s cluster is not started"
    exit 1
fi
# todo: 
# - make checking prometheus
# - make checking grafana