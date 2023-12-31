#!/usr/bin/env bash

# Utility restarting local kubernetes cluster
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] [--delete-tfs]" >&2
    echo "This script will reset docker kubernetes" >&2
}

function args() {
  delete_tfs=0
  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--delete-tfs") delete_tfs=1;;
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

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/envs.sh

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

if [ $delete_tfs -eq 1 ]; then

  for ns in $(kubectl get ns -o custom-columns=":metadata.name"); do
    for tf in $(kubectl get terraforms.infra.contrib.fluxcd.io -n $ns -o custom-columns=":metadata.name"); do
      if [[ ( $tf == "aws-dynamo-table" ||  $tf == "aws-s3-bucket" ) && $ns == "flux-system" ]]; then
        continue
      fi
      kubectl delete terraforms.infra.contrib.fluxcd.io -n $ns $tf
    done
  done

  # Wait for terraform objects to be deleted
  while ( true ); do
    echo "Waiting for terraform objects to be deleted"
    kubectl get terraforms.infra.contrib.fluxcd.io -A -o custom-columns=":metadata.namespace,:metadata.name" | grep -v "flux-system.*aws-dynamo-table" | grep -v "flux-system.*aws-s3-bucket" > /tmp/tf.list
    objects="$(wc -l /tmp/tf.list | awk '{print $1}')"
    if [[  $objects -eq 1 ]]; then
      break
    fi
    echo "${objects} terraform objects still exist"
    cat /tmp/tf.list
    sleep 5
  done

  set +e
  kubectl get terraforms.infra.contrib.fluxcd.io -n flux-system aws-dynamo-table > /dev/null 2>&1
  present=$?
  set -e
  if [ $present -eq 0 ]; then
    kubectl delete terraforms.infra.contrib.fluxcd.io -n flux-system aws-dynamo-table
  fi
  
  set +e
  kubectl get terraforms.infra.contrib.fluxcd.io -n flux-system aws-s3-bucket > /dev/null 2>&1
  present=$?
  set -e
  if [ $present -eq 0 ]; then
    kubectl delete terraforms.infra.contrib.fluxcd.io -n flux-system aws-s3-bucket
  fi

  # Wait for remote state terraform objects to be deleted
  while ( true ); do
    echo "Waiting for terraform objects to be deleted"
    kubectl get terraforms.infra.contrib.fluxcd.io -A -o custom-columns=":metadata.namespace,:metadata.name" > /tmp/tf.list
    objects="$(wc -l /tmp/tf.list | awk '{print $1}')"
    if [[  $objects -eq 1 ]]; then
      break
    fi
    echo "${objects} terraform objects still exist"
    cat /tmp/tf.list
    sleep 5
  done

else

  cluster_name=$(kubectl get cm -n flux-system cluster-config -o jsonpath='{.data.mgmtClusterName}')
  set +e
  aws s3 ls | grep -E "${PREFIX_NAME}-${AWS_ACCOUNT_ID}-${AWS_REGION}-tf-state$" > /dev/null 2>&1
  present=$?
  set -e
  if [ $present -eq 0 ]; then
    aws s3 rm s3://${PREFIX_NAME}-${AWS_ACCOUNT_ID}-${AWS_REGION}-tf-state/$cluster_name --recursive
    aws s3api delete-bucket --bucket ${PREFIX_NAME}-${AWS_ACCOUNT_ID}-${AWS_REGION}-tf-state
  fi

  set +e
  aws dynamodb  list-tables | jq -r '.TableNames[]' | grep -E "^${PREFIX_NAME}-${AWS_ACCOUNT_ID}-${AWS_REGION}-tf-state$" > /dev/null 2>&1
  present=$?
  set -e
  if [ $present -eq 0 ]; then
    aws dynamodb delete-table --table-name ${PREFIX_NAME}-${AWS_ACCOUNT_ID}-${AWS_REGION}-tf-state
  fi
  
fi


