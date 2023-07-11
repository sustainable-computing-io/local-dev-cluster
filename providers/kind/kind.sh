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

set -eu -o pipefail

# configuration
#shellcheck disable=SC2153
declare -r KIND="$BIN_DIR/kind"

declare -r KIND_DIR="${KIND_DIR:-"$PROJECT_ROOT/tmp/kind"}"
declare -r KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-kind}
declare -r KIND_VERSION=${KIND_VERSION:-0.17.0}
declare -r KIND_REGISTRY_NAME=${KIND_REGISTRY_NAME:-kind-registry}
declare -r KIND_IMAGE_REPO=${KIND_IMAGE_REPO:-localhost:5001}

# constants
declare -r KIND_CONFIG_PATH="$PROJECT_ROOT/providers/kind"
declare -r KIND_MANIFESTS_DIR="$KIND_CONFIG_PATH/manifests"

declare -r KIND_DEFAULT_NETWORK="kind"
declare -r KIND_CONFIG_YAML="$KIND_DIR/kind.yml"
declare -r KIND_REGISTRY_YAML="$KIND_DIR/local-registry.yml"
declare -r KIND_KUBECONFIG="$KIND_DIR/kubeconfig"

# check CPU arch
cpu_arch() {
	case "$(uname -m)" in
	x86_64* | i?86_64* | amd64*)
		echo "amd64"
		;;
	ppc64le)
		echo "ppc64le"
		;;
	aarch64* | arm64*)
		echo "arm64"
		;;
	*)
		return 1
		;;
	esac
	return 0
}

kind_install() {
	if command -v kind &>/dev/null &&
		[[ $(kind --version | awk '{print $3}') == "$KIND_VERSION" ]]; then
		info "kind already installed; skipping installation"
		return 0
	fi

	local arch
	arch="$(cpu_arch)"
	[[ "$arch" == "" ]] && {
		err "failed to determine CPU arch; cannot setup kind"
		return 1
	}

	local os="linux"
	[[ "$OSTYPE" =~ darwin ]] && os=darwin

	info "Downloading kind v$KIND_VERSION for $os - $arch"
	curl -LSs https://github.com/kubernetes-sigs/kind/releases/download/v$KIND_VERSION/kind-${os}-${arch} -o "$KIND"
	chmod +x "$KIND"
}

kind_wait_up() {
	info "Waiting for kind to be ready ..."

	while [ -z "$($CTR_CMD exec --privileged "${KIND_CLUSTER_NAME}"-control-plane kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o=jsonpath='{.items..status.conditions[-1:].status}' | grep True)" ]; do
		echo "    ... waiting for all nodes to be ready"
		sleep 10
	done
	ok "all nodes are up and running"

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

	sed <"$KIND_MANIFESTS_DIR/local-registry.yml" \
		-e "s/$default_registry_name/${KIND_REGISTRY_NAME}/g" \
		-e "s/$default_registry_port/${REGISTRY_PORT}/g" \
		>"$KIND_REGISTRY_YAML"
}

_setup_kind() {
	info "Starting kind with cluster name \"${KIND_CLUSTER_NAME}\""
	echo $PATH

	run kind create cluster --name="${KIND_CLUSTER_NAME}" -v6 --config="$KIND_CONFIG_YAML"

	info "Generating kubeconfig"
	kind get kubeconfig --name="${KIND_CLUSTER_NAME}" >"$KIND_KUBECONFIG"

	# NOTE: all providers are expected to
	ok "copied kubeconfig to $KIND_KUBECONFIG"

	kind_wait_up
}

_run_kind_registry() {
	until [ -z "$($CTR_CMD ps -a | grep "${KIND_REGISTRY_NAME}")" ]; do
		$CTR_CMD stop "${KIND_REGISTRY_NAME}" || true
		$CTR_CMD rm "${KIND_REGISTRY_NAME}" || true
		sleep 5
	done

	run $CTR_CMD run \
		-d --restart=always \
		-p "127.0.0.1:${REGISTRY_PORT}:5000" \
		--name "${KIND_REGISTRY_NAME}" \
		registry:2

	# connect the registry to the cluster network if not already connected
	run $CTR_CMD network connect "${KIND_DEFAULT_NETWORK}" "${KIND_REGISTRY_NAME}" || true
	run kubectl apply -f "${KIND_DIR}"/local-registry.yml
}

### exported functions

kind_print_config() {
	cat <<-EOF
		KIND
		──────────────────────────────────────
		Binary:  $KIND
		Version: $KIND_VERSION

		Cluster Name : $KIND_CLUSTER_NAME
		Config file  : $KIND_CONFIG_YAML
		Kubeconfig   : $KIND_KUBECONFIG

	EOF

}

kind_up() {
	info "Starting KIND cluster $KIND_CLUSTER_NAME"
	mkdir -p "$KIND_DIR"

	kind_install
	_prepare_config
	_setup_kind
	wait_for_cluster_ready
	_run_kind_registry
	ok "kind cluster $KIND_CLUSTER_NAME is up and running"
}

kind_down() {
	info "Deleting KIND cluster $KIND_CLUSTER_NAME"
	kind_install
	if ! kind get clusters 2>/dev/null | grep -q "${KIND_CLUSTER_NAME}"; then
		ok "No kind cluster $KIND_CLUSTER_NAME found; skipping deletion"
		return
	fi

	# NOTE: Avoid failing an entire test run just because of a deletion error
	run kind delete cluster --name="${KIND_CLUSTER_NAME}" || true

	run $CTR_CMD rm -v -f "${KIND_REGISTRY_NAME}"
	rm -f "$KIND_CONFIG_YAML" "$KIND_REGISTRY_YAML"
	find "${KIND_DIR}" -maxdepth 1 -name '.*' -delete
	ok "kind cluster deleted successfully"
}

kind_kubeconfig() {
	echo "$KIND_KUBECONFIG"
}
