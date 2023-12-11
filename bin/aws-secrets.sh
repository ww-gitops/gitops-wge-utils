#!/usr/bin/env bash

# Utility for creating aws credentials secrets in Vault
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] [--tls-skip] [--aws-dir <aws directory path>]" >&2
    echo "This script will create secrets in Vault" >&2
    echo " The --aws-dir option can be used to specify the path to the directory containing" >&2
    echo " the aws credentials and config files, if not specified the default is ~/.aws" >&2
    echo " The --aws-credentials option can be used to specify the path to the credentials file" >&2
    echo " so that this can be relocated; if not specified the default is ~/.aws/credentials" >&2
    echo "use the --tls-skip option to load data prior to ingress certificate setup" >&2
}

function args() {
  tls_skip=""
  aws_dir="${HOME}/.aws"
  aws_credentials="${aws_dir}/credentials"

  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--aws-dir") (( arg_index+=1 ));aws_dir=${arg_list[${arg_index}]};;
          "--aws-credentials") (( arg_index+=1 ));aws_credentials=${arg_list[${arg_index}]};;
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

function get_profile() {
  local file_path="$aws_credentials"
  profile_line=$(grep -n -E  "^\[$AWS_PROFILE\]$" $file_path | cut -f1 -d:)
  if [ -z $profile_line ]; then
    echo "profile $AWS_PROFILE not found in $file_path" >&2
    exit 1
  fi
  line_number=$(tail -n +`expr $profile_line + 1` $file_path| grep -n  "^\[.*\]$" | head -1 | cut -f1 -d:)
  if [ -z $line_number ]; then
    line_number=$(wc -l $file_path | awk '{print $1}')
  fi
  next_line=`expr $line_number + 1`
  sed -n "${profile_line},${line_number}p;${next_line}q" $file_path > /tmp/$$
  echo /tmp/$$
}

args "$@"

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/envs.sh

AWS_ACCESS_KEY_ID="placeholder"
AWS_SECRET_ACCESS_KEY="placeholder"
AWS_REGION="placeholder"
AWS_SESSION_TOKEN="placeholder"

profile_file="$(get_profile)"

if [ "$aws" == "true" ]; then
  AWS_ACCESS_KEY_ID=$(cat ${profile_file} | grep aws_access_key_id | cut -f2- -d=)
  AWS_SECRET_ACCESS_KEY=$(cat ${profile_file} | grep aws_secret_access_key | cut -f2- -d=)
  AWS_SESSION_TOKEN=$(cat ${profile_file} | grep aws_session_token | cut -f2- -d= | cut -f2 -d\")
  AWS_REGION=$(cat ${aws_dir}/config | grep -m 1 region | cut -f2- -d= | xargs)
fi

export AWS_B64ENCODED_CREDENTIALS="placeholder"
if [ "$aws_capi" == "true" ]; then
  export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile)
  clusterawsadm bootstrap iam create-cloudformation-stack --config $(local_or_global resources/clusterawsadm.yaml) --region $AWS_REGION
fi

vault kv put ${tls_skip} -mount=secrets aws-creds  AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
         AWS_REGION=$AWS_REGION AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN

vault kv put ${tls_skip} -mount=secrets capi-aws-creds  AccessKeyID=$AWS_ACCESS_KEY_ID SecretAccessKey=$AWS_SECRET_ACCESS_KEY \
         SessionToken=$AWS_SESSION_TOKEN

vault kv put ${tls_skip} -mount=secrets capi-aws-default  credentials=${AWS_B64ENCODED_CREDENTIALS}
