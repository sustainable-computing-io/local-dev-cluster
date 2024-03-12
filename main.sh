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
# Copyright 2023 The Kepler Contributors
#

set -eu -o pipefail

# NOTE: PROJECT_ROOT is the root the local-dev-cluster project
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# CALLER_PROJECT_ROOT is the root of the project from which this script is
# being called
CALLER_PROJECT_ROOT="$(git rev-parse --show-toplevel)"
declare -r PROJECT_ROOT CALLER_PROJECT_ROOT

# NOTE: define environment variables in this file to set the defaults
#
# CTR_CMD=podman
# CLUSTER_PROVIDER=microshift
#
# # 💡 tip: honor env variables if set explicitly using the technique below
# #         This allows PROMETHEUS_ENABLE=true ./main.sh up to override the
# #         default value.
# PROMETHEUS_ENABLE=${PROMETHEUS_ENABLE:-false}
#

# shellcheck disable=SC1091
[[ -f "$CALLER_PROJECT_ROOT/.env" ]] && source "$CALLER_PROJECT_ROOT/.env"

# configuration
declare -r CTR_CMD=${CTR_CMD:-docker}
declare -r CLUSTER_PROVIDER=${CLUSTER_PROVIDER:-kind}
declare -r KUBECONFIG_ROOT_DIR=${KUBECONFIG_ROOT_DIR:-$PROJECT_ROOT/.kube}
declare -r KEPLER_KUBECONFIG=${KEPLER_KUBECONFIG:-config-kepler}

declare -r REGISTRY_PORT=${REGISTRY_PORT:-5001}

declare -r PROMETHEUS_ENABLE=${PROMETHEUS_ENABLE:-false}
declare -r GRAFANA_ENABLE=${GRAFANA_ENABLE:-false}
declare -r TEKTON_ENABLE=${TEKTON_ENABLE:-false}

source "$PROJECT_ROOT/lib/utils.sh"

cluster_up() {
	"${CLUSTER_PROVIDER}_up"

	info "Coping $CLUSTER_PROVIDER kubeconfig to $KUBECONFIG_ROOT_DIR/$KEPLER_KUBECONFIG"
	local kubeconfig
	kubeconfig="$("${CLUSTER_PROVIDER}"_kubeconfig)"

	mkdir -p "$(basename "$KUBECONFIG_ROOT_DIR")"
	mv -f "$kubeconfig" "${KUBECONFIG_ROOT_DIR}/${KEPLER_KUBECONFIG}"

	kubeconfig="$KUBECONFIG_ROOT_DIR/config":$(find "$KUBECONFIG_ROOT_DIR" \
		-type f -name "*config*" | tr '\n' ':')
	kubeconfig=${kubeconfig%:}
	KUBECONFIG=$kubeconfig kubectl config view --merge --flatten >all-in-one-kubeconfig.yaml
	mv -f all-in-one-kubeconfig.yaml "${KUBECONFIG_ROOT_DIR}/config"

	export KUBECONFIG="${KUBECONFIG_ROOT_DIR}/config"

	if is_set "$PROMETHEUS_ENABLE" || is_set "$GRAFANA_ENABLE"; then
		source "$PROJECT_ROOT/lib/prometheus.sh"
		deploy_prometheus_operator
	fi

	if is_set "$TEKTON_ENABLE"; then
		kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
		rollout_ns_status tekton-pipelines
        rollout_ns_status tekton-pipelines-resolvers
	fi
}

cluster_down() {
	"$CLUSTER_PROVIDER"_down
	rm "$KUBECONFIG_ROOT_DIR/$KEPLER_KUBECONFIG"
}

print_config() {
	local cluster_config
	cluster_config=$("${CLUSTER_PROVIDER}"_print_config)

	local prom_install_msg="$PROMETHEUS_ENABLE"
	if ! is_set "$PROMETHEUS_ENABLE" && is_set "$GRAFANA_ENABLE"; then
		prom_install_msg="false  👈 but will install prometheus because grafana is enabled"
	fi

	cat <<-EOF

		         Configuration
		━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
		cluster provider   : $CLUSTER_PROVIDER
		kubeconfig file    : $KUBECONFIG_ROOT_DIR/$KEPLER_KUBECONFIG

		container runtime  : $CTR_CMD
		registry port      : $REGISTRY_PORT

		Monitoring
		  * Install Prometheus : $prom_install_msg
		  * Install Grafana    : $GRAFANA_ENABLE

		Tekton
		  * Install Tekton : $TEKTON_ENABLE

		$cluster_config
		━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

	EOF
}

main() {
	# ensure that all relative file refs are relative to the project root
	cd "$PROJECT_ROOT"

	# NOTE: this cannot moved to main since all declarations in the library
	# should be in the global namespace
	local cluster_lib="$PROJECT_ROOT/providers/$CLUSTER_PROVIDER/$CLUSTER_PROVIDER.sh"
	[[ -f "$cluster_lib" ]] || {
		err "No Cluster library for $CLUSTER_PROVIDER at $cluster_lib"
		info "known providers are:"
		find providers -maxdepth 1 -mindepth 1 -type d | sed -e 's|providers/|  * |g'

		die "invalid CLUSTER_PROVIDER - '$CLUSTER_PROVIDER'"
	}

	# shellcheck source=providers/kind/kind.sh
	# shellcheck source=providers/microshift/microshift.sh
	source "$cluster_lib"
	print_config

	case "$1" in
	up)
		cluster_up
		return $?
		;;

	down)
		cluster_down
		return $?
		;;
	restart)
		cluster_down || true
		cluster_up
		return $?
		;;
	*)
		echo "unknown command $1; bringing a cluster up"
		cluster_up
		;;
	esac
}

main "$@"
