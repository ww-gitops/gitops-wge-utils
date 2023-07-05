#!/usr/bin/env bash

# Utility to deploy kind cluster
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] " >&2
    echo "This script will deploy Kind Cluster" >&2
}

function args() {
  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--debug") set -x;;
               "-h") usage; exit;;
           "--help") usage; exit;;
               "-?") usage; exit;;
        *) if [ "${arg_list[${arg_index}]:0:2}" == "--" ];then
               echo "invalid argument: ${arg_list[${arg_index}]}" >&2
               usage; exit
           fi;
           break;;
    esac
    (( arg_index+=1 ))
  done
}

args "$@"

source /tmp/env.sh


set +e
kind get clusters | grep -E "^${cluster_name}$" >/dev/null
ret=$?
set -e

if [ $ret -ne 0 ]; then

  if [ "$listen_address" ==  "127.0.0.1" ]; then
    listen_address="$(hostname -I | awk '{print $1}')"
  fi

  cat /tmp/kind.yaml | envsubst > /tmp/kind-config.yaml

  mkdir -p /tmp/kubernetes/policies
  sudo cp -f /tmp/audit.yaml /tmp/kubernetes/policies/audit.yaml
  rm -f /tmp/kubeconfig
  kind create cluster --name ${cluster_name} --config /tmp/kind-config.yaml

  while [ 1 -eq 1 ]
  do
    set +e
    echo "Waiting for kube-apiserver-${cluster_name}-control-plane to be ready"
    kubectl wait --for=condition=Ready -n kube-system pod/kube-apiserver-${cluster_name}-control-plane
    ret=$?
    set -e
    if [ $ret -eq 0 ]; then
      break
    fi
    sleep 1
  done

  sleep 5
fi

kubectl get nodes

kubectl get pods -A

while [ 1 -eq 1 ]
do
  set +e
  echo "Waiting for coredns to be available"
  kubectl wait --for=condition=Available --timeout=120s -n kube-system deployment.apps/coredns
  ret=$?
  set -e
  if [ $ret -eq 0 ]; then
    break
  fi
  sleep 1
done

rm -rf $HOME/$GITHUB_GLOBAL_CONFIG_REPO
git clone https://github.com/$GITHUB_GLOBAL_CONFIG_ORG/$GITHUB_GLOBAL_CONFIG_REPO $HOME/$GITHUB_GLOBAL_CONFIG_REPO

set +e
kubectl get ns | grep flux-system
bootstrap=$?
set -e

if [ $bootstrap -eq 1 ]; then
  kustomize build $HOME/$GITHUB_GLOBAL_CONFIG_REPO/mgmt-cluster/addons/flux | kubectl apply -f-
fi

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: flux-system
  namespace: flux-system
data:
  username: $(echo -n "git" | base64)
  password: $(echo -n "$GITHUB_TOKEN_READ" | base64 -w 0)
EOF
