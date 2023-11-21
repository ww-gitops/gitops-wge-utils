#!/usr/bin/env bash

# Utility to install software to run kind cluster
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] " >&2
    echo "This script will install software and configuring Ubuntu to run k8s" >&2
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

export PATH=$PATH:/usr/local/bin
export HOME=/root

echo "Updating system packages & installing required utilities"
sudo apt-get update
sudo apt-get install -y ca-certificates curl jq iproute2 git unzip apt-transport-https gnupg2 vim
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
rm -rf kustomize
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash -s 5.1.0
sudo mv kustomize /usr/local/bin
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
curl -s https://fluxcd.io/install.sh | bash

echo "Installing k0s"

set +e
command k0s >/dev/null
ret=$?
set -e

if [ $ret -eq 0 ]; then
  sudo k0s stop
fi
curl -sSLf https://get.k0s.sh | sudo sh
