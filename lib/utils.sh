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

# shellcheck disable=SC2086
err() {
	echo -e "$(date -u +%H:%M:%S) 😱 ERROR: $*\n" >&2
}

info() {
	echo -e "$(date -u +%H:%M:%S) 🔔 INFO : $*\n" >&2
}

header() {
	local title="🔆🔆🔆  $*  🔆🔆🔆 "

	local len=40
	if [[ ${#title} -gt $len ]]; then
		len=${#title}
	fi

	echo -e "\n\n  \033[1m${title}\033[0m"
	echo -n "━━━━━"
	printf '━%.0s' $(seq "$len")
	echo "━━━━━━━"

}

die() {
	echo -e "$(date -u +%H:%M:%S) 💀 FATAL: $*\n" >&2
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
	echo -e "    ✅ $*\n" >&2
}

fail() {
	echo -e "    ❌ $*\n" >&2
}

# returns 0 if arg is set to True or true or TRUE else false
# usage: is_set $x && echo "$x is set"
is_set() {
	[[ "$1" =~ true|TRUE|True ]]
}

# wait_for_resource waits for max_tries x timeout for resource to be in condition
# if it does not reach in the condition in the given time, the function returns 1
# NOTE: a selector must be passed to the function as additional argument. E.g.
# wait_for_resource 5 1m nodes --all (--all is the selector)
wait_for_resource() {
	local max_tries="$1"
	local timeout="$2"
	local resource="$3"
	local condition="$4"
	shift 4

	info "Waiting for $resource to be in $condition state"

	local -i tries=0
	while ! kubectl wait --for=condition="$condition" --timeout="2s" \
		"$resource" "$@" && [[ $tries -lt $max_tries ]]; do

		tries=$((tries + 1))
		echo "   ... [$tries / $max_tries]: waiting ($timeout) for $resource to be $condition"
		sleep "$timeout"
	done

	kubectl wait --for=condition="$condition" "$resource" "$@" --timeout=0 || {
		fail "$resource $* failed to be in $condition state"
		return 1
	}

	ok "$resource matching $* are in $condition state"
	return 0
}

wait_for_crds() {
	header "Waiting for crds to be established"

	# ensure kubectl get crds works before trying to wait for crds to be established
	[[ $(kubectl get crds -o name | wc -l) -eq 0 ]] && {
		info "no crds found; not waiting for crds to be established"
		return 0
	}
	wait_for_resource 20 15 crds Established --all
}

wait_for_nodes() {
	header "Waiting for nodes to be ready"

	# ensure kubectl get nodes works before trying to wait for them
	info "Waiting for nodes to come up"
	local -i max_tries=10
	local -i tries=0
	while [[ $(kubectl get nodes -o name | wc -l) -eq 0 ]] && [[ $tries -lt $max_tries ]]; do
		tries=$((tries + 1))
		echo "  ... [$tries / $max_tries] waiting for at least one node to come up"
		sleep 20
	done

	wait_for_resource 20 30 nodes Ready --all
}

wait_for_all_pods() {
	header "Waiting for all pods to be ready"

	wait_for_resource 20 30 pods Ready --all --all-namespaces || {
		fail "Pods below failed to run"
		kubectl get pods --field-selector status.phase!=Running --all-namespaces || true
		return 1
	}

	return 0
}

wait_for_pods_in_namespace() {
	local namespace="$1"
	shift 1

	header "Waiting for pods in $namespace to be ready"

	wait_for_resource 10 30 pods Ready --all -n "$namespace" || {
		fail "Pods below failed to run"
		kubectl get pods --field-selector status.phase!=Running -n "$namespace" || true
		return 1
	}

	ok "All pods in $namespace are running"
	return 0
}

wait_for_cluster_ready() {
	header "Waiting for cluster to be ready"
	kubectl cluster-info

	wait_for_nodes
	wait_for_pods_in_namespace kube-system
	wait_for_crds
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

rollout_ns_status() {
	local resources
	resources=$(kubectl get deployments,statefulsets,daemonsets -n=$1 -o name)
	for res in $resources; do
		kubectl rollout status $res --namespace $1 --timeout=10m || die "failed to check status of ${res} inside namespace ${1}"
	done
}