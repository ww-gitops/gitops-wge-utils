#!/usr/bin/env bash

# Utility for reconciling flux kustomizations
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] [--tls-skip] [--aws-dir <aws directory path>]" >&2
    echo "This script will create secrets in Vault" >&2
    echo " The --aws-dir option can be used to specify the path to the directory containing" >&2
    echo " the aws credentials and config files, if not specified the default is ~/.aws" >&2
    echo "use the --tls-skip option to load data prior to ingress certificate setup" >&2
}

function args() {
  tls_skip=""
  aws_dir="${HOME}/.aws"

  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--aws-dir") (( arg_index+=1 ));aws_dir=${arg_list[${arg_index}]};;
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


flux reconcile source git flux-system
flux reconcile source git global-config 
flux reconcile source git -n wge flux-system 
flux reconcile source git -n wge global-config

flux reconcile kustomization flux-components
flux reconcile kustomization flux-system
flux reconcile kustomization -n wge wge-leaf-config 
flux reconcile kustomization wge-sa
flux reconcile kustomization wge
flux reconcile kustomization wge-bases
flux reconcile kustomization -n wge wge-leaf-apps
flux reconcile kustomization -n wge kind-apps
