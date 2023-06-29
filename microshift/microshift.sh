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

microshift_registry_name="registry"
MICROSHIFT_DEFAULT_NETWORK="cluster"
MICROSHIFT_REGISTRY_NAME=${MICROSHIFT_REGISTRY_NAME:-registry}
MICROSHIFT_IMAGE=${MICROSHIFT_IMAGE:-quay.io/microshift/microshift-aio}
MICROSHIFT_TAG=${MICROSHIFT_TAG:-latest}
MICROSHIFT_CONTAINER_NAME=${MICROSHIFT_CONTAINER_NAME:-microshift}
DEFAULT_KUBECONFIG_DIR=".kube"

ESTIMATOR_REPO=${ESTIMATOR_REPO:-quay.io/sustainable_computing_io}
MODEL_SERVER_REPO=${MODEL_SERVER_REPO:-quay.io/sustainable_computing_io}

function _fetch_microshift {
    # pulls the image from quay.io
    $CTR_CMD pull "${MICROSHIFT_IMAGE}":"${MICROSHIFT_TAG}"
}

function _wait_microshift_up {
    # wait till container is in running state
    while [ "$(${CTR_CMD} inspect -f '{{.State.Status}}' "${MICROSHIFT_CONTAINER_NAME}")" != "running" ]; do
        echo "Waiting for container ${MICROSHIFT_CONTAINER_NAME} to start..."
        sleep 5
    done
    echo "Container $MICROSHIFT_CONTAINER_NAME} is now running!"

    echo "Waiting for cluster to be ready ..."

    while [ -z "$($CTR_CMD exec --privileged "${MICROSHIFT_CONTAINER_NAME}" \
        kubectl --kubeconfig=/var/lib/microshift/resources/kubeadmin/kubeconfig \
        get nodes -o=jsonpath='{.items..status.conditions[-1:].status}' | grep True)" ]; do
        echo "Waiting for microshift cluster to be ready ..."
        sleep 20
    done
}

function _deploy_microshift_cluster {
    # create network for microshift and registry to communicate
    $CTR_CMD network create ${MICROSHIFT_DEFAULT_NETWORK}
    # run the docker container
    $CTR_CMD run -d --name "${MICROSHIFT_CONTAINER_NAME}" --privileged \
        -v microshift-data:/var/lib -p 6443:6443 -p 80:80 -p 443:443 --network ${MICROSHIFT_DEFAULT_NETWORK} "${MICROSHIFT_IMAGE}":"${MICROSHIFT_TAG}"
}

function _setup_microshift() {
    echo "Starting microshift cluster"
    _deploy_microshift_cluster
    # copy the kubeconfig from container to local
    mkdir -p ~/${DEFAULT_KUBECONFIG_DIR}
    _run_microshift_registry
    _configure_registry
    $CTR_CMD cp "${MICROSHIFT_CONTAINER_NAME}":/var/lib/microshift/resources/kubeadmin/kubeconfig ~/${DEFAULT_KUBECONFIG_DIR}/config
    kubectl cluster-info
    # wait until ocp pods are running
    while [ -n "$(_get_pods | grep -v Running)" ]; do
        echo "Waiting for all pods to enter the Running state ..."
        _get_pods | >&2 grep -v Running || true
        sleep 10
    done
    _wait_containers_ready kube-system
}

function _run_microshift_registry() {
    until [ -z "$($CTR_CMD ps -a | grep "${MICROSHIFT_REGISTRY_NAME}")" ]; do
        $CTR_CMD stop "${MICROSHIFT_REGISTRY_NAME}" || true
        $CTR_CMD rm "${MICROSHIFT_REGISTRY_NAME}" || true
        sleep 5
    done
        
    $CTR_CMD run \
        -d --restart=always \
        -p "127.0.0.1:${REGISTRY_PORT}:5000" \
        --network "${MICROSHIFT_DEFAULT_NETWORK}" \
        --name "${MICROSHIFT_REGISTRY_NAME}" \
        registry:2
}

function _microshift_up() {
    _fetch_microshift
    _setup_microshift
}

function _microshift_down() {
    if [ -z "$($CTR_CMD ps -f name="${MICROSHIFT_CONTAINER_NAME}")" ]; then
        return
    fi
    $CTR_CMD rm -f "${MICROSHIFT_CONTAINER_NAME}" >>/dev/null
    $CTR_CMD rm -f "${MICROSHIFT_REGISTRY_NAME}" >>/dev/null
    $CTR_CMD volume rm -f microshift-data
    $CTR_CMD network rm ${MICROSHIFT_DEFAULT_NETWORK}
    find ~/${DEFAULT_KUBECONFIG_DIR} -delete
}

function _configure_registry() {
    # add local registry to microshift container
    $CTR_CMD exec "$MICROSHIFT_CONTAINER_NAME" /bin/sh -c \
        "echo -e '[[registry]]\ninsecure = true\nlocation = \"'${MICROSHIFT_REGISTRY_NAME}:5000'\"' >> /etc/containers/registries.conf"
    sleep 5
    $CTR_CMD restart "$MICROSHIFT_CONTAINER_NAME"
    sleep 10
    _wait_microshift_up
}
