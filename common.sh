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

set -ex
set -o pipefail

_registry_port="5001"
_registry_name="registry"
DEFAULT_NETWORK="cluster"
REGISTRY_NAME=${REGISTRY_NAME:-registry}
REGISTRY_PORT=${REGISTRY_PORT:-5001}

CTR_CMD=${CTR_CMD-docker}
CLUSTER_PROVIDER=${CLUSTER_PROVIDER:-"kind"}

. ./prometheus.sh
. ./kind/kind.sh
. ./microshift/microshift.sh

# check CPU arch
CPUArch=$(uname -m)
case ${CPUArch} in
x86_64* | i?86_64* | amd64*)
    ARCH="amd64"
    ;;
ppc64le)
    ARCH="ppc64le"
    ;;
aarch64* | arm64*)
    ARCH="arm64"
    ;;
*)
    echo "invalid Arch, only support x86_64, ppc64le, aarch64"
    exit 1
    ;;
esac

function _wait_containers_ready {
    echo "Waiting for all containers to become ready ..."
    namespace=$1
    kubectl wait --for=condition=Ready pod --all -n "$namespace" --timeout 12m
}

function _get_nodes() {
    kubectl get nodes --no-headers
}

function _get_pods() {
    kubectl get pods --all-namespaces --no-headers
}

function main() {
    case $1 in
    up)
        case $CLUSTER_PROVIDER in 
        microshift)
            _microshift_up
            _wait_for_clusterReady
            ;;
        *)
            _kind_up
            _wait_for_clusterReady
            _run_registry
            ;;
        esac
        echo "cluster is ready"
        if [ ${PROMETHEUS_ENABLE} == "true" ] || [ ${PROMETHEUS_ENABLE} == "True" ]; then
            _deploy_prometheus_operator
        fi
        ;;
    down)
        case $CLUSTER_PROVIDER in 
        microshift)
            _microshift_down
            ;;
        *)
            _kind_down
            ;;
        esac
        ;;
    *)
        echo "by default set up kind cluster"
        _kind_up
        _wait_for_clusterReady
        _run_registry
        echo "cluster is ready"
        ;;
    esac
}

function _wait_for_clusterReady() {
    kubectl cluster-info
    while [ -n "$(_get_pods | grep -v Running)" ]; do
        echo "Waiting for all pods to enter the Running state ..."
        _get_pods | >&2 grep -v Running || true
        sleep 10
    done
    _wait_containers_ready kube-system
}

function _run_registry() {
    until [ -z "$($CTR_CMD ps -a | grep "${REGISTRY_NAME}")" ]; do
        $CTR_CMD stop "${REGISTRY_NAME}" || true
        $CTR_CMD rm "${REGISTRY_NAME}" || true
        sleep 5
    done

    if [ "${CLUSTER_PROVIDER}" == "kind" ]; then
        $CTR_CMD run \
            -d --restart=always \
            -p "127.0.0.1:${REGISTRY_PORT}:5000" \
            --name "${REGISTRY_NAME}" \
            registry:2
        # connect the registry to the cluster network if not already connected
        $CTR_CMD network connect "${DEFAULT_NETWORK}" "${REGISTRY_NAME}" || true
        kubectl apply -f "${KIND_DIR}"/local-registry.yml
    else
        $CTR_CMD run \
            -d --restart=always \
            -p "127.0.0.1:${REGISTRY_PORT}:5000" \
            --network "${DEFAULT_NETWORK}" \
            --name "${REGISTRY_NAME}" \
            registry:2
    fi
}

main "$@"
