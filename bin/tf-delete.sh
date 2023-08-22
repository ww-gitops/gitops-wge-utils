#!/usr/bin/env bash

# Utility cleasring deleting tf objects
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)


set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] --namespace <namespace> --resource <resource name>" >&2
    echo "This script will delete and recreate tf custom resource impacted by..." >&2
    echo "https://github.com/fluxcd/kustomize-controller/issues/881" >&2
}

function args() {
  resource=""
  namespace=""
  tf_object=""
  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--debug") set -x;;
          "--namespace") (( arg_index+=1 ));namespace=${arg_list[${arg_index}]};;
          "--resource") (( arg_index+=1 ));resource=${arg_list[${arg_index}]};;
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

  if [ -z "$namespace" ]; then
    echo "missing --namespace option" >&2
    usage; exit
  fi

  if [ -z "$resource" ]; then
    echo "missing --resource option" >&2
    usage; exit
  fi
}

args "$@"

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/envs.sh

kubectl patch terraforms.infra.contrib.fluxcd.io -n ${namespace} ${resource}  -p '{"metadata":{"finalizers":null}}' --type=merge
kubectl delete -n ${namespace} terraforms.infra.contrib.fluxcd.io ${resource}

