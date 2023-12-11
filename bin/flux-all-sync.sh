#!/usr/bin/env bash

# Utility to sync and check flux objects etc
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug]" >&2
    echo "This script will generate the template files in an ECR repository" >&2
    echo "  --debug: emit debugging information" >&2
}

function args() {
  debug_str=""
  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--debug") set -x; debug_str="--debug";;
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

top_level=$(git rev-parse --show-toplevel)
pushd ${top_level}
source ci/scripts/env.sh

ci/scripts/flux-source-sync.sh

echo "Listing Kustomization objects"
kubectl get ks -A | grep -v "^flux-system"
echo "Syncing Kustomization objects"
kubectl get ks -A -o=jsonpath='{range .items[*]}{"flux reconcile ks -n "}{.metadata.namespace}{" "}{.metadata.name}{" & \n"}{end}' | grep -v 'flux-system' > /tmp/reconcile-$$.sh
set +e
source  /tmp/reconcile-$$.sh >/dev/null 2>&1
set -e
echo "Listing Kustomization objects"
kubectl get ks -A | grep -v "^flux-system"

ci/scripts/flux-gitopssets-sync.sh

