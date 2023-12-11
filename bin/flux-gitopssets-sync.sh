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
  sources=""
  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--debug") set -x; debug_str="--debug";;
          "--sources") sources="1";;
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

if [ -n "$sources" ]; then
  ci/scripts/flux-source-sync.sh
fi

echo "Listing Gitopssets objects"
kubectl get -A gitopssets
echo "Syncing Gitopssets objects"
date=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
kubectl get gitopssets -A -o=jsonpath="{range .items[*]}{\"kubectl annotate --field-manager=flux-client-side-apply --overwrite -n \"}{.metadata.namespace}{\" gitopssets/\"}{.metadata.name}{\" reconcile.fluxcd.io/requestedAt=$date\n\"}{end}" > /tmp/reconcile-$$.sh

source /tmp/reconcile-$$.sh
sleep 5

echo "Listing Gitopsets objects reconcile time, reconcilaton requested at: $date"
kubectl get gitopsset  -A -o=jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.lastHandledReconcileAt}{"\n"}{end}'

echo "Listing Gitopsets objects"
kubectl get -A gitopssets


