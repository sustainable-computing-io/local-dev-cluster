# shellcheck shell=bash
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

#shellcheck disable=SC2153

declare -r KIND_DIR="${KIND_DIR:-"$PROJECT_ROOT/tmp/kind"}"
declare -r KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-kind}
declare -r KIND_REGISTRY_NAME=${KIND_REGISTRY_NAME:-kind-registry}
declare -r KIND_IMAGE_REPO=${KIND_IMAGE_REPO:-localhost:5001}
declare -r KIND_WORKER_NODES=${KIND_WORKER_NODES:-0}

# constants
declare -r KIND_MANIFESTS_DIR="$PROJECT_ROOT/providers/kind/manifests"
declare -r KIND_DEFAULT_NETWORK="kind"
declare -r KIND_CONFIG_YAML="$KIND_DIR/kind.yml"
declare -r KIND_REGISTRY_YAML="$KIND_DIR/local-registry.yml"
declare -r KIND_KUBECONFIG="$KIND_DIR/kubeconfig"

kind_preinstall_check() {
	(command -v kind && command -v kubectl) || {
		info "See details here: https://github.com/sustainable-computing-io/local-dev-cluster/blob/main/README.md#prerequisites"
		die "Please make sure kind and kubectl have been installed before test"
	}
}

kind_nodes_ready() {
	$CTR_CMD exec --privileged "${KIND_CLUSTER_NAME}"-control-plane \
		kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes \
		-o=jsonpath='{.items..status.conditions[-1:].status}' | grep True
}

kind_wait_up() {
	info "Waiting for dns to be ready ..."
	kubectl wait -n kube-system --timeout=12m --for=condition=Ready -l k8s-app=kube-dns pods || {
		fail "dns pods failed to run"
		return 1
	}
	ok "kind cluster is up and running \n"
}
#

_prepare_config() {
	local default_registry_name="kind-registry"
	local default_registry_port="5001"

	info "Building manifests..."
	sed <"$KIND_MANIFESTS_DIR/kind.yml" \
		-e "s/$default_registry_name/${KIND_REGISTRY_NAME}/g" \
		-e "s/$default_registry_port/${REGISTRY_PORT}/g" \
		>"$KIND_CONFIG_YAML"

	for ((i = 0; i < KIND_WORKER_NODES; i++)); do
		cat <<-EOF_NODE >>"$KIND_CONFIG_YAML"
			  - role: worker
			    extraMounts:
			      - hostPath: /proc
			        containerPath: /proc-host
			      - hostPath: /usr/src
			        containerPath: /usr/src

		EOF_NODE
	done

	sed <"$KIND_MANIFESTS_DIR/local-registry.yml" \
		-e "s/$default_registry_port/${REGISTRY_PORT}/g" \
		>"$KIND_REGISTRY_YAML"
}

_setup_kind() {
	info "Starting kind with cluster name \"${KIND_CLUSTER_NAME}\""
	run kind create cluster --name="${KIND_CLUSTER_NAME}" -v6 --config="$KIND_CONFIG_YAML"

	info "Generating kubeconfig"
	kind get kubeconfig --name="${KIND_CLUSTER_NAME}" >"$KIND_KUBECONFIG"

	# NOTE: all providers are expected to
	ok "copied kubeconfig to $KIND_KUBECONFIG"

}

_run_kind_registry() {
	run_container "$CTR_CMD" registry:2 "$KIND_REGISTRY_NAME" \
		-p "127.0.0.1:${REGISTRY_PORT}:5000" \
		--network "${KIND_DEFAULT_NETWORK}"

	# Document the local registry
	# https://github.com/kubernetes/enhancements/tree/master/keps/sig-cluster-lifecycle/generic/1755-communicating-a-local-registry
	run kubectl apply -f "${KIND_REGISTRY_YAML}"
}

### exported functions

kind_print_config() {
	cat <<-EOF
		KIND
		──────────────────────────────────────
		Binary:  $(command -v kind)
		Version: $(kind --version | awk '{print $3}')

		Cluster Name : $KIND_CLUSTER_NAME
		Config file  : $KIND_CONFIG_YAML
		Kubeconfig   : $KIND_KUBECONFIG

	EOF

}

kind_up() {
	info "Starting KIND cluster $KIND_CLUSTER_NAME"
	mkdir -p "$KIND_DIR"

	kind_preinstall_check
	_prepare_config
	_setup_kind
	export KUBECONFIG="$KIND_KUBECONFIG"
	wait_for_cluster_ready
	kind_wait_up
	_run_kind_registry
	ok "kind cluster $KIND_CLUSTER_NAME is up and running"
	kind_print_config
}

kind_down() {
	info "Deleting KIND cluster $KIND_CLUSTER_NAME"
	if ! kind get clusters 2>/dev/null | grep -q "${KIND_CLUSTER_NAME}"; then
		ok "No kind cluster $KIND_CLUSTER_NAME found; skipping deletion"
		return
	fi

	# NOTE: Avoid failing an entire test run just because of a deletion error
	run kind delete cluster --name="${KIND_CLUSTER_NAME}" || true

	run $CTR_CMD rm -v -f "${KIND_REGISTRY_NAME}"

	info "Removing all generated files"
	run rm -f \
		"$KIND_CONFIG_YAML" \
		"$KIND_REGISTRY_YAML" \
		"$KIND_KUBECONFIG"

	ok "kind cluster deleted successfully"
}

kind_kubeconfig() {
	echo "$KIND_KUBECONFIG"
}
