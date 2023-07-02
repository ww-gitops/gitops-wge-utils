#!/usr/bin/env bash

# Utility for creating CA certificate
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)


set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] " >&2
    echo "This script will create a CA certificate" >&2
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

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/envs.sh

pushd ${top_level}/resources >/dev/null

openssl genrsa -out CA.key 4096
openssl req -x509 -new -nodes -key CA.key -subj "/CN=paulc" -days 3650 -reqexts v3_req -extensions v3_ca -out CA.cer

if [[ "$OSTYPE" == "linux"* ]]; then
  mkdir -p /usr/local/share/ca-certificates/wge
  chmod 755 /usr/local/share/ca-certificates/wge
  cp CA.cer /usr/local/share/ca-certificates/wge
  chmod 644 /usr/local/share/ca-certificates/wge/CA.cer
  sudo update-ca-certificates
fi

popd >/dev/null