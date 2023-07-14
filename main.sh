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

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
declare -r PROJECT_ROOT
declare -r BIN_DIR="$PROJECT_ROOT/tmp/bin"

# NOTE: define environment variables in this file to set the defaults
#
# CTR_CMD=podman
# CLUSTER_PROVIDER=microshift
#
# # 💡 tip: honor env variables if set explicitly using the technique below
# #         This allows PROMETHEUS_ENABLE=true ./main.sh up to override the
# #         default value.
# PROMETHEUS_ENABLE=${PROMETHEUS_ENABLE:-false}
# CONFIG_OUT_DIR=${CONFIG_OUT_DIR:-"/tmp/generated-manifest"}
#
[[ -f "$PROJECT_ROOT/.env" ]] && source "$PROJECT_ROOT/.env"

# configuration
declare -r CTR_CMD=${CTR_CMD:-docker}
declare -r CLUSTER_PROVIDER=${CLUSTER_PROVIDER:-kind}
declare -r CLUSTER_KUBECONFIG=${CLUSTER_KUBECONFIG_FILE:-~/.kube/config}

declare -r REGISTRY_PORT=${REGISTRY_PORT:-5001}
declare -r CONFIG_OUT_DIR=${CONFIG_OUT_DIR:-"_output/generated-manifest"}

declare -r PROMETHEUS_ENABLE=${PROMETHEUS_ENABLE:-true}
declare -r GRAFANA_ENABLE=${GRAFANA_ENABLE:-true}

source "$PROJECT_ROOT/lib/utils.sh"

init_output_dir() {
	rm -rf "${CONFIG_OUT_DIR}"
	mkdir -p "${CONFIG_OUT_DIR}"
}

cluster_up() {
	"${CLUSTER_PROVIDER}_up"

	info "Coping $CLUSTER_PROVIDER kubeconfig to $CLUSTER_KUBECONFIG"
	local kubeconfig
	kubeconfig="$("${CLUSTER_PROVIDER}"_kubeconfig)"

	mkdir -p "$(basename "$CLUSTER_KUBECONFIG")"
	run cp "$kubeconfig" "$CLUSTER_KUBECONFIG"
	export KUBECONFIG="$CLUSTER_KUBECONFIG"

	if is_set "${PROMETHEUS_ENABLE}" || is_set "GRAFANA_ENABLE"; then
		source "$PROJECT_ROOT/lib/prometheus.sh"
		deploy_prometheus_operator
	fi
}

cluster_down() {
	"$CLUSTER_PROVIDER"_down
}

print_config() {
	local cluster_config
	cluster_config=$("${CLUSTER_PROVIDER}"_print_config)

	cat <<-EOF

		         Configuration
		━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
		cluster provider   : $CLUSTER_PROVIDER
		kubeconfig file    : $CLUSTER_KUBECONFIG

		container runtime  : $CTR_CMD
		config output dir  : $CONFIG_OUT_DIR
		registry port      : $REGISTRY_PORT

		Monitoring
		  * Install Prometheus : $PROMETHEUS_ENABLE
		  * Install Grafana    : $PROMETHEUS_ENABLE

		$cluster_config
		━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

	EOF
}

main() {
	# ensure that all relative file refs are relative to the project root
	cd "$PROJECT_ROOT"
	mkdir -p "$BIN_DIR"

	# Add tmp/bin to path so that all tools installed to tmp/bin takes precedence
	# over those in $PATH
	export PATH="$BIN_DIR:$PATH"

	# NOTE: this cannot moved to main since all declarations in the library
	# should be in the global namespace
	local cluster_lib="$PROJECT_ROOT/providers/$CLUSTER_PROVIDER/$CLUSTER_PROVIDER.sh"
	[[ -f "$cluster_lib" ]] || {
		err "No Cluster library for $CLUSTER_PROVIDER at $cluster_lib"
		info "known providers are:"
		ls providers/ | sed 's|^|  * |g'

		die "invalid CLUSTER_PROVIDER - '$CLUSTER_PROVIDER'"
	}

	# shellcheck source=providers/kind/kind.sh
	# shellcheck source=providers/microshift/microshift.sh
	source "$cluster_lib"
	print_config

	init_output_dir

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
