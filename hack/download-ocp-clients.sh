#!/usr/bin/env bash

set -o pipefail
set -o nounset
set -o errexit

test -z ${1:-''} && ( echo "Release not found"; exit 1 )
RELEASE=${1}

test -z ${2:-''} && ( echo "Pull secret path not found. Use: $0 <RELEASE> <path/to/pull-secret.txt>"; exit 1 )
PULL_SECRET=${2}

mkdir -p .local/tmp .local/bin

pushd .local/tmp
oc adm release extract -a ${PULL_SECRET} --tools quay.io/openshift-release-dev/ocp-release:${RELEASE}-x86_64
tar xvfz openshift-client-linux-${RELEASE}.tar.gz
tar xvfz openshift-install-linux-${RELEASE}.tar.gz
mv openshift-install ../bin/openshift-install-linux-${RELEASE}
mv oc ../bin/oc-linux-$RELEASE
mv kubectl ../bin/kubectl-linux-$RELEASE
popd

echo "All clients was saved on ./local.bin"
