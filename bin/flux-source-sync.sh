#!/usr/bin/env bash

# Utility to sync and check flux objects etc
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

function cleanup()
{
    exit 0
}

trap cleanup EXIT

set -uo pipefail

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

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/envs.sh

echo "Listing Git Repository objects"
kubectl -n flux-system get gitrepo
echo "Syncing Git Repository objects"
for git in $(kubectl -n flux-system get gitrepo -o=name| cut -f2 -d/); do flux reconcile -n flux-system source git $git;done
echo "Listing Git Repository objects"
kubectl -n flux-system get gitrepo

echo "Listing S3 Bucket objects"
kubectl -n flux-system get bucket
echo "Syncing S3 Bucketobjects"
for git in $(kubectl -n flux-system get bucket -o=name| cut -f2 -d/); do flux reconcile -n flux-system source bucket $git;done
echo "Listing S3 Bucket objects"
kubectl -n flux-system get bucket

echo "Listing OCI Repository objects"
kubectl get -A ocirepositories.source.toolkit.fluxcd.io | grep -v "^flux-system"
echo "Syncing OCI Repository objects"
kubectl get ocirepo -A -o=jsonpath='{range .items[*]}{"flux reconcile source oci -n "}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' > /tmp/reconcile-$$.sh
source  /tmp/reconcile-$$.sh
echo "Listing OCI Repository objects"
kubectl get -A ocirepositories.source.toolkit.fluxcd.io | grep -v "^flux-system"
