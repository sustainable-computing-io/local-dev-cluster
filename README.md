# Github action for sustainable-computing-io

![GitHub](https://img.shields.io/github/license/sustainable-computing-io/local-dev-cluster)

This repo provides the scripts to create a local kubernetes cluster to used for development or integration tests.

## Usage 
1. pre-request
you need to locate your BCC lib and linux header.
2. modify kind [config](./kind/manifests/kind.yml) to make sure `extraMounts:` cover linux header and BCC.
3. The scripts are the source for the kepler cluster commands like `./kind/common.sh`.
4. [`kubectl`](https://dl.k8s.io/release/v1.25.4)
5. run `./main.sh up` to set up your local env.
6. run `./main.sh down` to teardown your local env.

## Docker registry
There's a docker registry available which is exposed at `localhost:5001`.

## For contributor
To set up a local cluster for kepler development.
We need:
1. ebpf
1. k8s cluster
1. modify k8s cluster to make sure `extraMounts:` cover linux header and BCC.
1. make the cluster connected with a local docker reg.