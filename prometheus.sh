#!/usr/bin/env bash
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
# Copyright 2022 The Kepler Contributors
#

PROMETHEUS_OPERATOR_VERSION=${PROMETHEUS_OPERATOR_VERSION:-v0.11.0}
PROMETHEUS_ENABLE=${PROMETHEUS_ENABLE:-true}
PROMETHEUS_REPLICAS=${PROMETHEUS_REPLICAS:-1}
GRAFANA_ENABLE=${GRAFANA_ENABLE:-false}


function _deploy_prometheus_operator {
    git clone -b "${PROMETHEUS_OPERATOR_VERSION}" --depth 1 https://github.com/prometheus-operator/kube-prometheus.git
    sed "s/replicas: 2/replicas: ${PROMETHEUS_REPLICAS}/g" kube-prometheus/manifests/prometheus-prometheus.yaml | \
        tee -a kube-prometheus/manifests/prometheus-prometheus.yaml >/dev/null
    if [ "${CLUSTER_PROVIDER}" == "kind" ]; then
        _load_prometheus_operator_images_to_local_registry
    fi
    kubectl create -f kube-prometheus/manifests/setup
    kubectl wait \
        --for condition=Established \
        --all CustomResourceDefinition \
        --namespace=monitoring
    for file in $(ls kube-prometheus/manifests/prometheusOperator-*); do
        kubectl create -f "$file"
    done
    for file in $(ls kube-prometheus/manifests/prometheus-*); do
        kubectl create -f $file
    done
    if [ "${GRAFANA_ENABLE}" == "true" ] || [ "${GRAFANA_ENABLE}" == "True" ]; then
        for file in $(ls kube-prometheus/manifests/grafana-*); do
            kubectl create -f "$file"
        done
    fi
    rm -rf kube-prometheus
    _wait_containers_ready monitoring
}

function _load_prometheus_operator_images_to_local_registry {
    for img in $(_get_prometheus_operator_images); do
        $CTR_CMD pull "$img"
        $KIND load docker-image "$img"
    done
}

function _get_prometheus_operator_images {
    grep -R "image:" kube-prometheus/manifests/*prometheus-* | awk '{print $3}'
    grep -R "image:" kube-prometheus/manifests/*prometheusOperator* | awk '{print $3}'
    grep -R "prometheus-config-reloader=" kube-prometheus/manifests/ | sed 's/.*=//g'
    if [ ${GRAFANA_ENABLE} == "true" ] || [ ${GRAFANA_ENABLE} == "True" ] ; then
        grep -R "image:" kube-prometheus/manifests/*grafana* | awk '{print $3}'
    fi
}