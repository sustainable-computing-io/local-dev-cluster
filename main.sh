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
declare -r KEPLER_KUBECONFIG=${KEPLER_KUBECONFIG:-config}

declare -r REGISTRY_PORT=${REGISTRY_PORT:-5001}

declare -r PROMETHEUS_ENABLE=${PROMETHEUS_ENABLE:-false}
declare -r GRAFANA_ENABLE=${GRAFANA_ENABLE:-false}
declare -r TEKTON_ENABLE=${TEKTON_ENABLE:-false}
declare -r KUBEVIRT_ENABLE=${KUBEVIRT_ENABLE:-false}
declare -r LIBBPF_VERSION=${LIBBPF_VERSION:-v1.2.0}
declare -r RESTARTCONTAINERRUNTIME=${RESTARTCONTAINERRUNTIME:-false}

source "$PROJECT_ROOT/lib/utils.sh"

cluster_up() {
	"${CLUSTER_PROVIDER}_up"

	info "Copying $CLUSTER_PROVIDER kubeconfig to $KUBECONFIG_ROOT_DIR/$KEPLER_KUBECONFIG"
	local kubeconfig
	kubeconfig="$("${CLUSTER_PROVIDER}"_kubeconfig)"

	mkdir -p "$(basename "$KUBECONFIG_ROOT_DIR")"
	mv -f "$kubeconfig" "${KUBECONFIG_ROOT_DIR}/${KEPLER_KUBECONFIG}"

	kubeconfig="$KUBECONFIG_ROOT_DIR/config":$(find "$KUBECONFIG_ROOT_DIR" \
		-type f -name "*config*" | tr '\n' ':')
	kubeconfig=${kubeconfig%:}
	KUBECONFIG=$kubeconfig kubectl config view --merge --flatten >all-in-one-kubeconfig.yaml
	mv -f all-in-one-kubeconfig.yaml "${KUBECONFIG_ROOT_DIR}/config"

	export KUBECONFIG="${KUBECONFIG_ROOT_DIR}/$KEPLER_KUBECONFIG"

	if is_set "$PROMETHEUS_ENABLE" || is_set "$GRAFANA_ENABLE"; then
		source "$PROJECT_ROOT/lib/prometheus.sh"
		deploy_prometheus_operator
	fi

	if is_set "$TEKTON_ENABLE"; then
		kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
		rollout_ns_status tekton-pipelines
        rollout_ns_status tekton-pipelines-resolvers
	fi

	# install kubevirt per https://kubevirt.io/quickstart_kind/
	if is_set "$KUBEVIRT_ENABLE"; then
		KUBEVIRT_VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
		kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/"${KUBEVIRT_VERSION}"/kubevirt-operator.yaml
		kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/"${KUBEVIRT_VERSION}"/kubevirt-cr.yaml
		rollout_ns_status kubevirt
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
		if Grafana been enabled, the kepler dashboard will be installed.

		Tekton
		  * Install Tekton : $TEKTON_ENABLE

		KubeVirt
		  * Install KubeVirt : $KUBEVIRT_ENABLE

		$cluster_config
		━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

	EOF
}

linuxHeader() {
	if [ -f /usr/bin/apt-get ]; then
		sudo apt-get install -y linux-headers-"$(uname -r)"
		sudo apt-get install -y linux-modules-"$(uname -r)"
		sudo apt-get install -y linux-modules-extra-"$(uname -r)"
	fi
	if [ -f /usr/bin/yum ]; then
		echo "do nothing for yum with linux header?"
	fi
}

ebpf() {
	if [ -f /usr/bin/apt-get ]; then
		sudo apt-get install -y binutils-dev build-essential  pkg-config libelf-dev
		mkdir -p temp-libbpf
		cd temp-libbpf
		git clone -b "$LIBBPF_VERSION" https://github.com/libbpf/libbpf
		cd libbpf/src
		sudo BUILD_STATIC_ONLY=y make install
		sudo make install_uapi_headers
		cd ../../..
		sudo rm -rf temp-libbpf
	fi
	if [ -f /usr/bin/yum ]; then
		export workdir=$PWD
		yum -y install yum-utils cpio bzip2 clang llvm-devel zlib-devel libcurl-devel m4 xz
		yum-config-manager --enable ubi-9-baseos-source
		mkdir -p /tmp/elfutils-source
		cd /tmp/elfutils-source
		yumdownloader --source elfutils
		rpm2cpio elfutils-0.189-3.el9.src.rpm | cpio -iv
		ls -al
		tar xjvf elfutils-0.189.tar.bz2
		cd /tmp/elfutils-source/elfutils-0.189
		./configure --disable-debuginfod
		make install
		
		mkdir -p /tmp/libbpf-source
		cd /tmp/libbpf-source
		yumdownloader --source libbpf
		rpm2cpio libbpf-1.2.0-1.el9.src.rpm | cpio -iv
		tar xf ./linux-*el9.tar.xz
		cd /tmp/libbpf-source/linux-5.14.0-333.el9/tools/lib/bpf
		make install_headers
		prefix=/usr BUILD_STATIC_ONLY=y make install
		cd /tmp/libbpf-source/linux-5.14.0-333.el9/tools/bpf
		make bpftool

		cd "$workdir"
	fi
}

containerruntime() {
	set -x
	echo start install container runtime as docker
	if [ -f /usr/bin/yum ]; then
		echo install yum utils
		yum install -y yum-utils
		echo config yum repo
		yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
		echo install docker
		yum install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
	fi
	if [ -f /usr/bin/apt-get ]; then
		# Add Docker's official GPG key:
		echo install docker with apt
		sudo apt-get update -y
		sudo apt-get install ca-certificates curl gnupg -y
		install -m 0755 -d /etc/apt/keyrings
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
		chmod a+r /etc/apt/keyrings/docker.gpg
		# Add the repository to Apt sources:
		echo \
				"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
				$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
				tee /etc/apt/sources.list.d/docker.list > /dev/null
		apt-get update -y
		apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
	fi
	set +x
	if is_set "$RESTARTCONTAINERRUNTIME"; then
		sudo systemctl start docker
	fi
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

	case "$1" in
	prerequisites)
		linuxHeader
		ebpf
		return $?
		;;
	containerruntime)
		containerruntime
		return $?
		;;
	up)
		source "$cluster_lib"
		print_config
		cluster_up
		return $?
		;;

	down)
		source "$cluster_lib"
		print_config
		cluster_down
		return $?
		;;
	restart)
		source "$cluster_lib"
		print_config
		cluster_down || true
		cluster_up
		return $?
		;;
	*)
		echo "unknown command $1; bringing a cluster up"
		source "$cluster_lib"
		print_config
		cluster_up
		;;
	esac
}

main "$@"
