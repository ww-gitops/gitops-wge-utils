#!/usr/bin/env bash

# Utility for creating aws credentials secrets in Vault
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] [--tls-skip] [--aws-dir <aws directory path>]" >&2
    echo "This script will create secrets in Vault" >&2
    echo "use the --tls-skip option to load data prior to ingress certificate setup" >&2
}

function args() {
  tls_skip=""

  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--debug") set -x;;
          "--tls-skip") tls_skip="-tls-skip-verify";;
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

client_id=TBA
client_secret=TBA
subscription_id=TBA
tenant_id=TBA

if [ -e resources/azure-secrets.sh ]; then
  source resources/azure-secrets.sh
fi

vault kv put ${tls_skip} -mount=secrets capz-manager-bootstrap-credentials  client-id=$client_id client-secret=$client_secret subscription-id=$subscription_id tenant-id=$tenant_id
