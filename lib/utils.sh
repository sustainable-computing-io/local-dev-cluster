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

err() {
	echo -e "ERROR: $*" >&2
}

info() {
	echo -e "INFO : $*" >&2
}

die() {
	echo -e "FATAL: $*" >&2
	exit 1
}

run() {
	echo -e " ❯ $*\n"
	"$@"
	ret=$?
	echo -e "        ────────────────────────────────────────────\n"
	return $ret
}

ok() {
	echo -e "    ✅ $*" >&2
}

fail() {
	echo -e "    ❌ $*" >&2
}

# returns 0 if arg is set to True or true or TRUE else false
# usage: is_set $x && echo "$x is set"
is_set() {
	[[ "$1" =~ true|TRUE|True ]]
}

wait_for_pods_in_namespace() {
	local namespace=$1
	shift
	local timeout="${1:-15m}"

	info "Waiting for all pods in $namespace to be Ready (max $timeout) ..."
	kubectl wait --for=condition=Ready pod --all -n "$namespace" --timeout="$timeout" || {
		kubectl get pods --field-selector status.phase!=Running -n "$namespace"
		fail "pods above in $namespace failed to run"
		return 1
	}

	ok "All pods in $namespace are running"
	return 0
}

# shellcheck disable=SC2120
wait_for_all_pods() {
	local timeout="${1:-15m}"

	info "Waiting for all pods to be ready (max $timeout) ..."

	kubectl wait --for=condition=Ready pods --all --all-namespaces --timeout="$timeout" || {
		kubectl get pods --field-selector status.phase!=Running --all-namespaces
		fail "pods above failed to run"
		return 1

	}

	ok "All pods in the cluster are running"
	return 0
}

wait_for_cluster_ready() {
	local timeout="${1:-15m}"

	info "Waiting for cluster to be ready"
	kubectl cluster-info

	wait_for_pods_in_namespace kube-system
	wait_for_all_pods
	ok "Cluster is ready\n\n"
}

get_nodes() {
	kubectl get nodes --no-headers
}

get_pods() {
	kubectl get pods --all-namespaces --no-headers
}

container_exists() {
	local ctr_cmd="$1"
	local container_name="$2"
	shift 2

	"$ctr_cmd" ps -a | grep "$container_name"
}

run_container() {
	local ctr_cmd="$1"
	local img="$2"
	local container_name="$3"
	shift 3

	while container_exists "$ctr_cmd" "$container_name"; do
		"$ctr_cmd" stop "${container_name}" || true
		"$ctr_cmd" rm -v "${container_name}" || true
		sleep 5
	done

	run $ctr_cmd run -d --restart=always \
		--name "$container_name" \
		"$@" \
		"$img"
}
