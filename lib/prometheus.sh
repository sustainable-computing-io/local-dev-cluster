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

# configuration
declare -r PROMETHEUS_OPERATOR_VERSION=${PROMETHEUS_OPERATOR_VERSION:-v0.11.0}
declare -r PROMETHEUS_REPLICAS=${PROMETHEUS_REPLICAS:-1}

# constants
declare -r KUBE_PROM_DIR="$PROJECT_ROOT/tmp/kube-prometheus"
declare -r MONITORING_NS="monitoring"
declare -r DASHBOARD_DIR="$KUBE_PROM_DIR/grafana-dashboards"
declare KEPLER_EXPORTER_GRAFANA_DASHBOARD_JSON

KEPLER_EXPORTER_GRAFANA_DASHBOARD_JSON=$( curl -fsSL https://raw.githubusercontent.com/sustainable-computing-io/kepler/main/grafana-dashboards/Kepler-Exporter.json | sed '1 ! s/^/         /' )

deploy_prometheus_operator() {

	rm -rf "$KUBE_PROM_DIR"
	# NOTE: starting a subshell so that any exit will reset the PWD back to where it was
	(
		cd "$(dirname "$KUBE_PROM_DIR")" || return 1
		git clone -b "${PROMETHEUS_OPERATOR_VERSION}" --depth 1 https://github.com/prometheus-operator/kube-prometheus.git

		# NOTE: sed and mv is used since -i does not work on OSX
		sed -e "s/replicas: 2/replicas: ${PROMETHEUS_REPLICAS}/g" \
			kube-prometheus/manifests/prometheus-prometheus.yaml > \
			kube-prometheus/manifests/prometheus-prometheus.yaml.tmp
		mv kube-prometheus/manifests/prometheus-prometheus.yaml.tmp \
			kube-prometheus/manifests/prometheus-prometheus.yaml

		_setup_dashboard
		_load_prometheus_operator_images_to_local_registry
		kubectl create -f kube-prometheus/manifests/setup
		kubectl wait \
			--for condition=Established \
			--all CustomResourceDefinition \
			--namespace="$MONITORING_NS"

		find kube-prometheus/manifests -name 'prometheusOperator-*.yaml' -type f \
			-exec kubectl create -f {} \;

		find kube-prometheus/manifests -name 'prometheus-*.yaml' -type f \
			-exec kubectl create -f {} \;

		is_set "$GRAFANA_ENABLE" && {
			find kube-prometheus/manifests -name 'grafana-*.yaml' -type f \
				-exec kubectl create -f {} \;
			ok "Grafana deployed"
		}

		ok "Prometheus deployed"
		rm -rf kube-prometheus
	)
	wait_for_pods_in_namespace "$MONITORING_NS"
}

_get_prometheus_operator_images() {
	grep -R "image:" kube-prometheus/manifests/*prometheus-* | awk '{print $3}'
	grep -R "image:" kube-prometheus/manifests/*prometheusOperator* | awk '{print $3}'
	grep -R "prometheus-config-reloader=" kube-prometheus/manifests/ | sed 's/.*=//g'

	is_set "$GRAFANA_ENABLE" && {
		grep -R "image:" kube-prometheus/manifests/*grafana* | awk '{print $3}'

	}
}

_trim_prometheus_operator_image() {
	echo "${1}" | awk -F "/" '{ print $NF }'
}

_load_prometheus_operator_images_to_local_registry() {
	# TODO: fix this by passing in the registry information to deploy_prometheus_operator
	# from main

	header "Load prometheus operator images to local registry"
	local registry
	if [[ "$CLUSTER_PROVIDER" == "kind" ]]; then
		registry="localhost:${REGISTRY_PORT}"
	else
		registry="${MICROSHIFT_REGISTRY_NAME}:5000"
	fi

	local updated_image
	for img in $(_get_prometheus_operator_images); do
		updated_image="$(_trim_prometheus_operator_image "$img")"
		$CTR_CMD pull "$img"
		$CTR_CMD tag "$img" "localhost:5001/$updated_image"
		$CTR_CMD push "localhost:5001/${updated_image}"

		grep -R "${img}" kube-prometheus/manifests/* |
			awk '{print $1}' | cut -d ':' -f 1 | while read -r file; do
			# NOTE: can't sed <file >file hence using a tmp file
			sed <"$file" "s|${img}|${registry}/${updated_image}|g" >"${file}.tmp"
			mv "${file}.tmp" "${file}"
		done
	done
}

_setup_dashboard(){
	if [ -f "$DASHBOARD_DIR/grafana-dashboards/kepler-exporter-configmap.yaml" ]; then
		return 0
	else
	header "Setup Dashboard base on $DASHBOARD_DIR"
	mkdir -p "$DASHBOARD_DIR/grafana-dashboards/"
	cat - > "$DASHBOARD_DIR/grafana-dashboards/kepler-exporter-configmap.yaml" << EOF
apiVersion: v1
data:
    kepler-exporter.json: |-
        $KEPLER_EXPORTER_GRAFANA_DASHBOARD_JSON
kind: ConfigMap
metadata:
    labels:
        app.kubernetes.io/component: grafana
        app.kubernetes.io/name: grafana
        app.kubernetes.io/part-of: kube-prometheus
        app.kubernetes.io/version: 9.5.3
    name: grafana-dashboard-kepler-exporter
    namespace: monitoring
EOF
    fi
}
