# shellcheck shell=bash
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

set -eu -o pipefail

# configuration
declare -r MICROSHIFT_REGISTRY_NAME=${MICROSHIFT_REGISTRY_NAME:-registry}
declare -r MICROSHIFT_IMAGE=${MICROSHIFT_IMAGE:-quay.io/microshift/microshift-aio}
declare -r MICROSHIFT_TAG=${MICROSHIFT_TAG:-latest}
declare -r MICROSHIFT_CONTAINER_NAME=${MICROSHIFT_CONTAINER_NAME:-microshift}

# constants
declare -r MICROSHIFT_CTR_NETWORK="cluster"
declare -r MICROSHIFT_KUBECONFIG_DIR="$PROJECT_ROOT/tmp/microshift"
declare -r MICROSHIFT_KUBECONFIG="$MICROSHIFT_KUBECONFIG_DIR/kubeconfig"

function _fetch_microshift {
	# pulls the image from quay.io
	run $CTR_CMD pull "${MICROSHIFT_IMAGE}":"${MICROSHIFT_TAG}"
}

microshift_nodes_ready() {
	$CTR_CMD exec --privileged "${MICROSHIFT_CONTAINER_NAME}" \
		kubectl --kubeconfig=/var/lib/microshift/resources/kubeadmin/kubeconfig \
		get nodes -o=jsonpath='{.items..status.conditions[-1:].status}' | grep True

}

function _wait_microshift_up {
	# wait till container is in running state
	info "Waiting for microshift to start"

	while [[ "$(${CTR_CMD} inspect -f '{{.State.Status}}' "${MICROSHIFT_CONTAINER_NAME}")" != "running" ]]; do
		echo "   ... waiting for container ${MICROSHIFT_CONTAINER_NAME} to start"
		sleep 5
	done
	ok "Container $MICROSHIFT_CONTAINER_NAME is now running!\n"
}

function _deploy_microshift_cluster {
	# create network for microshift and registry to communicate
	run $CTR_CMD network create ${MICROSHIFT_CTR_NETWORK}
	# create volume for microshift
	run $CTR_CMD volume create microshift-data --opt type=tmpfs --opt device=tmpfs --opt o=size=7G,uid=1000
	# run the docker container
	run_container "$CTR_CMD" \
		"${MICROSHIFT_IMAGE}":"${MICROSHIFT_TAG}" "$MICROSHIFT_CONTAINER_NAME" \
		--privileged \
		-v microshift-data:/var/lib -p 6443:6443 \
		-p 80:80 \
		-p 443:443 \
		--network ${MICROSHIFT_CTR_NETWORK}
}

function _setup_microshift() {
	info "Starting microshift cluster"
	_deploy_microshift_cluster

	info "Configuring registry"
	_run_microshift_registry
	_configure_registry
	ok "registry is up and running"

	_wait_microshift_up

	info "Copying microshift kubeconfig"
	# copy the kubeconfig from container to local
	mkdir -p "${MICROSHIFT_KUBECONFIG_DIR}"
	run $CTR_CMD cp "${MICROSHIFT_CONTAINER_NAME}:/var/lib/microshift/resources/kubeadmin/kubeconfig" "$MICROSHIFT_KUBECONFIG"
	ok "copied kubeconfig to $MICROSHIFT_KUBECONFIG"

	export KUBECONFIG="$MICROSHIFT_KUBECONFIG"

	wait_for_cluster_ready
}

function _run_microshift_registry() {
	info "Running registry for microshift"

	run_container "$CTR_CMD" registry:2 \
		"$MICROSHIFT_REGISTRY_NAME" \
		-p "127.0.0.1:${REGISTRY_PORT}:5000" \
		--network "${MICROSHIFT_CTR_NETWORK}"
}

function _configure_registry() {
	info "Configuring microshift registry"

	# add local registry to microshift container
	$CTR_CMD exec "$MICROSHIFT_CONTAINER_NAME" /bin/sh -c \
		"echo -e '[[registry]]\ninsecure = true\nlocation = \"'${MICROSHIFT_REGISTRY_NAME}:5000'\"' >> /etc/containers/registries.conf"
	sleep 5
	$CTR_CMD restart "$MICROSHIFT_CONTAINER_NAME"
	sleep 10
}

### required provider functions

microshift_up() {
	info "Starting microshift"
	_fetch_microshift
	_setup_microshift
}

microshift_print_config() {
	cat <<-EOF
		Microshift
		──────────────────────────────────────
		Image:  $MICROSHIFT_IMAGE:$MICROSHIFT_TAG

		Cluster Name : $MICROSHIFT_CONTAINER_NAME
		kubeconfig   : $MICROSHIFT_KUBECONFIG

	EOF
}

microshift_down() {
	info "Deleting microshift cluster"

	if ! container_exists "$CTR_CMD" "$MICROSHIFT_CONTAINER_NAME"; then
		ok "no microshift cluster is running "
		return
	fi
	$CTR_CMD rm -f "${MICROSHIFT_CONTAINER_NAME}" >>/dev/null
	$CTR_CMD rm -f "${MICROSHIFT_REGISTRY_NAME}" >>/dev/null
	$CTR_CMD volume rm -f microshift-data
	$CTR_CMD network rm ${MICROSHIFT_CTR_NETWORK}
	find "${MICROSHIFT_KUBECONFIG_DIR}" -delete
	ok "cleaned up microshift"
}

microshift_kubeconfig() {
	echo "$MICROSHIFT_KUBECONFIG"
}
