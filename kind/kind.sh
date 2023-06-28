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

CONFIG_PATH="kind"
KIND_VERSION=${KIND_VERSION:-0.17.0}
KIND_MANIFESTS_DIR="$CONFIG_PATH/manifests"
CLUSTER_NAME=${KIND_CLUSTER_NAME:-kind}

IMAGE_REPO=${IMAGE_REPO:-localhost:5001}
ESTIMATOR_REPO=${ESTIMATOR_REPO:-quay.io/sustainable_computing_io}
MODEL_SERVER_REPO=${MODEL_SERVER_REPO:-quay.io/sustainable_computing_io}

CONFIG_OUT_DIR=${CONFIG_OUT_DIR:-"_output/generated-manifest"}
KIND_DIR=${KIND_DIR:-"kind"}
rm -rf ${CONFIG_OUT_DIR}
mkdir -p ${CONFIG_OUT_DIR}

function _wait_kind_up {
    echo "Waiting for kind to be ready ..."
    
    while [ -z "$($CTR_CMD exec --privileged "${CLUSTER_NAME}"-control-plane kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o=jsonpath='{.items..status.conditions[-1:].status}' | grep True)" ]; do
        echo "Waiting for kind to be ready ..."
        sleep 10
    done
    echo "Waiting for dns to be ready ..."
    kubectl wait -n kube-system --timeout=12m --for=condition=Ready -l k8s-app=kube-dns pods
}

function _fetch_kind() {
    mkdir -p "${KIND_DIR}"
    KIND="${KIND_DIR}"/.kind
    if [ -f "$KIND" ]; then
        current_kind_version=$($KIND --version | awk '{print $3}')
    fi
    if [[ $current_kind_version != $KIND_VERSION ]]; then
        echo "Downloading kind v$KIND_VERSION"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            curl -LSs https://github.com/kubernetes-sigs/kind/releases/download/v$KIND_VERSION/kind-darwin-${ARCH} -o "$KIND"
        else
            curl -LSs https://github.com/kubernetes-sigs/kind/releases/download/v$KIND_VERSION/kind-linux-${ARCH} -o "$KIND"
        fi
        chmod +x "$KIND"
    fi
}

function _prepare_config() {
    echo "Building manifests..."

    cp $KIND_MANIFESTS_DIR/kind.yml "${KIND_DIR}"/kind.yml
    sed "s/$_registry_name/${REGISTRY_NAME}/g" "${KIND_DIR}"/kind.yml | tee -a "${KIND_DIR}"/kind.yml >/dev/null
    sed "s/$_registry_port/${REGISTRY_PORT}/g" "${KIND_DIR}"/kind.yml | tee -a "${KIND_DIR}"/kind.yml >/dev/null

    cp $KIND_MANIFESTS_DIR/local-registry.yml "${KIND_DIR}"/local-registry.yml
    sed "s/$_registry_name/${REGISTRY_NAME}/g" "${KIND_DIR}"/local-registry.yml | tee -a "${KIND_DIR}"/local-registry.yml >/dev/null
    sed "s/$_registry_port/${REGISTRY_PORT}/g" "${KIND_DIR}"/local-registry.yml | tee -a "${KIND_DIR}"/local-registry.yml >/dev/null
}

function _setup_kind() {
     echo "Starting kind with cluster name \"${CLUSTER_NAME}\""

    $KIND create cluster --name="${CLUSTER_NAME}" -v6 --config=${KIND_DIR}/kind.yml
    $KIND get kubeconfig --name="${CLUSTER_NAME}" > ${KIND_DIR}/.kubeconfig

    _wait_kind_up
    # wait until k8s pods are running    
}

function _kind_up() {
    _fetch_kind
    _prepare_config
    _setup_kind
}

function _kind_down() {
    _fetch_kind
    if [ -z "$($KIND get clusters | grep ${CLUSTER_NAME})" ]; then
        return
    fi
    # Avoid failing an entire test run just because of a deletion error
    $KIND delete cluster --name=${CLUSTER_NAME} || "true"
    $CTR_CMD rm -f ${REGISTRY_NAME} >> /dev/null
    find ${KIND_DIR} -name kind.yml -maxdepth 1 -delete
    find ${KIND_DIR} -name local-registry.yml -maxdepth 1 -delete
    find ${KIND_DIR} -name '.*' -maxdepth 1 -delete
}
