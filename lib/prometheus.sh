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

# configuration
declare -r PROMETHEUS_OPERATOR_VERSION=${PROMETHEUS_OPERATOR_VERSION:-v0.11.0}
declare -r PROMETHEUS_REPLICAS=${PROMETHEUS_REPLICAS:-1}

# constants
declare -r MONITORING_NS="monitoring"

deploy_prometheus_operator() {
	git clone -b "${PROMETHEUS_OPERATOR_VERSION}" --depth 1 https://github.com/prometheus-operator/kube-prometheus.git
	sed "s/replicas: 2/replicas: ${PROMETHEUS_REPLICAS}/g" kube-prometheus/manifests/prometheus-prometheus.yaml > \
		kube-prometheus/manifests/prometheus-prometheus.yaml.tmp && mv kube-prometheus/manifests/prometheus-prometheus.yaml.tmp \
		kube-prometheus/manifests/prometheus-prometheus.yaml

	_load_prometheus_operator_images_to_local_registry

	kubectl create -f kube-prometheus/manifests/setup
	kubectl wait \
		--for condition=Established \
		--all CustomResourceDefinition \
		--namespace="$MONITORING_NS"

	for file in $(ls kube-prometheus/manifests/prometheusOperator-*); do
		kubectl create -f "$file"
	done
	for file in $(ls kube-prometheus/manifests/prometheus-*); do
		kubectl create -f $file
	done
	is_set "$GRAFANA_ENABLE" && {
		for file in $(ls kube-prometheus/manifests/grafana-*); do
			kubectl create -f "$file"
		done
	}

	rm -rf kube-prometheus
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
	if [ $CLUSTER_PROVIDER == "kind" ]; then
		registry="localhost:${REGISTRY_PORT}"
	else
		registry="${MICROSHIFT_REGISTRY_NAME}:5000"
	fi
	for img in $(_get_prometheus_operator_images); do
		$CTR_CMD pull "$img"
		updated_image=$(_trim_prometheus_operator_image $img)
		$CTR_CMD tag "$img" localhost:5001/${updated_image}
		$CTR_CMD push localhost:5001/${updated_image}
		for file in $(grep -R "${img}" kube-prometheus/manifests/* | awk '{print $1}' | cut -d ':' -f 1); do
			# NOTE: can't sed <file >file hence using a tmp file
			sed <"$file" "s|${img}|${registry}/${updated_image}|g" >"${file}.tmp"
			mv "${file}.tmp" "${file}"
		done
	done
}
