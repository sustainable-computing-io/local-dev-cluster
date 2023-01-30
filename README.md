# Github action for sustainable-computing-io

This repo provides the scripts to create a local kubernetes cluster to used for development or integration tests.

## Usage 
1. pre-request
you need to locate your BCC lib and linux header.
2. modify kind [config](./kind/manifests/kind.yml) to make sure `extraMounts:` cover linux header and BCC.
3. The scripts are the source for the kepler cluster commands like `./kind/common.sh`.
4. [`kubectl`](https://dl.k8s.io/release/v1.25.4)
5. run `./main.sh` to set up your local env.

## Docker registry
There's a docker registry available which is exposed at `localhost:5001`.
