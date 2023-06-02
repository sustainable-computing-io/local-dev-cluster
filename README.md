# Github action for sustainable-computing-io

![GitHub](https://img.shields.io/github/license/sustainable-computing-io/local-dev-cluster)
[![units-test](https://github.com/sustainable-computing-io/local-dev-cluster/actions/workflows/test.yml/badge.svg)](https://github.com/sustainable-computing-io/local-dev-cluster/actions/workflows/test.yml)

This repo provides the scripts to create a local kubernetes cluster to used for development or integration tests.

## Usage 
### pre-request
- Locate your BCC lib and linux header.
- [`kubectl`](https://dl.k8s.io/release/v1.25.4)

### Start up
1. modify kind [config](./kind/manifests/kind.yml) to make sure `extraMounts:` cover linux header and BCC.
1. The scripts are the source for the kepler cluster commands like `./kind/common.sh`.
1. run `./main.sh up` to set up your local env.
1. run `./main.sh down` to tear down your local env.

### Container registry
There's a container registry available which is exposed at `localhost:5001`.

## For kepler contributor
To set up a local cluster for kepler development.
We need make the cluster connected with a local container registry.

### Bump version step for this repo
1. Check kubectl version.
1. Check k8s cluster provider's version(as KIND).
1. Check prometheus operator version.

## How to contirbute to this repo
### A new k8s cluster provider
You are free to ref kind to contribute a k8s cluster, but we will have a check list as kepler feature.
1. Set up the k8s cluster.
1. The connection between the specific registry and cluster, as for local development usage. We hope to pull development image to the registry instead of a public registry.
1. Able to get k8s cluster config, for test case.
1. Mount local path for linux kenerl and ebpf(BCC) inside kepler pod.
