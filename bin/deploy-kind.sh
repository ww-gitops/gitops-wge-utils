#!/usr/bin/env bash

# Utility to deploy kind cluster
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] [--install] [--username <username>] [--cluster-name <hostname>]  [--hostname <hostname>] [--listen-address <ip address>] [--listen-port <port>] [--mgmt]" >&2
    echo "This script will deploy Kubernetes cluster on the local machine or another host" >&2
    echo "The target machine must be accessible via ssh using hostname, add the hostname to /etc/hosts if needed first" >&2
    echo "use --mgmt option when creating a mgmt cluster" >&2
}

function args() {
  install=""
  username_str=""
  listen_address="127.0.0.1"
  listen_port="6443"
  hostname="localhost"
  cluster_name="kind"
  debug_str=""
  mgmt=""

  ssh_opts="-o StrictHostKeyChecking=no"
  scp_opts="-o StrictHostKeyChecking=no"
  ssh_cmd="ssh $ssh_opts"
  scp_cmd="scp $scp_opts"

  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--install") install="true";;
          "--mgmt") mgmt="true";;
          "--cluster-name") (( arg_index+=1 )); cluster_name="${arg_list[${arg_index}]}";;
          "--hostname") (( arg_index+=1 )); hostname="${arg_list[${arg_index}]}";;
          "--username") (( arg_index+=1 )); username_str="${arg_list[${arg_index}]}@";;
          "--listen-address") (( arg_index+=1 )); listen_address="${arg_list[${arg_index}]}";;
          "--listen-port") (( arg_index+=1 )); listen_port="${arg_list[${arg_index}]}";;
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
utils_dir="$(realpath $SCRIPT_DIR/..)"
source resources/github-secrets.sh
location="${hostname}" #:-localhost}"


export AWS_ACCOUNT_ID="none"
if [ "$aws" == "true" ]; then
  export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
fi

export leaf_target_path="clusters/kind/$location-$cluster_name"
cat .envrc | grep "export GITHUB_" > /tmp/${location}-${cluster_name}-env.sh
echo "export GITHUB_TOKEN_READ=${GITHUB_TOKEN_READ}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export GITHUB_TOKEN_WRITE=${GITHUB_TOKEN_WRITE}" >> /tmp/${location}-${cluster_name}-env.sh
if [ -z "$mgmt" ]; then
  echo "export target_path=${leaf_target_path}" >> /tmp/${location}-${cluster_name}-env.sh
fi
echo "export listen_address=${listen_address}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export listen_port=${listen_port}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export cluster_name=${cluster_name}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export hostname=${hostname}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export KUBECONFIG=/tmp/${cluster_name}.kubeconfig" >> /tmp/${location}-${cluster_name}-env.sh
echo "export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export AWS_REGION=${AWS_REGION}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export AWS_TAG_creator=${AWS_TAG_creator}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export AWS_TAG_customer=${AWS_TAG_customer}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export AWS_TAG_projectGid=${AWS_TAG_projectGid}" >> /tmp/${location}-${cluster_name}-env.sh
echo "export PREFIX_NAME=${PREFIX_NAME}" >> /tmp/${location}-${cluster_name}-env.sh

if [ "${hostname}" != "localhost" ]; then
  $scp_cmd -r ${utils_dir}/kind-leafs ${username_str}${hostname}:/tmp >/dev/null
  
  $scp_cmd -r /tmp/${location}-${cluster_name}-env.sh ${username_str}${hostname}:/tmp/env.sh >/dev/null

  $scp_cmd -r $(local_or_global resources/kind.yaml) ${username_str}${hostname}:/tmp >/dev/null
  $scp_cmd -r $(local_or_global resources/audit.yaml) ${username_str}${hostname}:/tmp >/dev/null

  if [ -n "$install" ]; then
    $ssh_cmd ${username_str}${hostname} "source /tmp/kind-leafs/leaf-install.sh $debug_str"
  fi

  $ssh_cmd ${username_str}${hostname} "source /tmp/kind-leafs/leaf-deploy.sh $debug_str"

  $scp_cmd ${username_str}${hostname}:/tmp/${cluster_name}.kubeconfig ~/.kube/${hostname}-${cluster_name}.kubeconfig >/dev/null

  echo "Cluster ${cluster_name} deployed on ${hostname}, use the following KUBECONFIG to access it:"
  echo "export KUBECONFIG=~/.kube/${hostname}-${cluster_name}.kubeconfig"
  export KUBECONFIG=~/.kube/${hostname}-${cluster_name}.kubeconfig
else
  cp -r /tmp/${location}-${cluster_name}-env.sh /tmp/env.sh
  cp -r ${utils_dir}/kind-leafs /tmp
  cp -r $(local_or_global resources/kind.yaml) /tmp
  cp -r $(local_or_global resources/audit.yaml) /tmp

  if [ -n "$install" ]; then
    ${utils_dir}/kind-leafs/leaf-install.sh $debug_str
  fi

  cat $(local_or_global resources/kind.yaml) | envsubst > /tmp/kind.yaml

  export hostname=localhost
  ${utils_dir}/kind-leafs/leaf-deploy.sh $debug_str

  if [ -n "$mgmt" ]; then
    cp /tmp/${cluster_name}.kubeconfig ~/.kube/config
  else
    cp /tmp/${cluster_name}.kubeconfig ~/.kube/localhost-${cluster-name}.kubeconfig
    echo "Cluster ${cluster_name} deployed on localhost, use the following KUBECONFIG to access it:"
    echo "export KUBECONFIG=~/.kube/localhost-${cluster_name}.kubeconfig" 
    export KUBECONFIG=~/.kube/${hostname}-${cluster_name}.kubeconfig
  fi 
fi


# Create flux-system GitRepository and Kustomization

if [ -z "$mgmt" ]; then
  export target_path="clusters/kind/$hostname-$cluster_name"
fi

mkdir -p $target_path/flux/flux-system
cat $(local_or_global resources/gotk-sync.yaml) | envsubst > $target_path/flux/flux-system/gotk-sync.yaml
git add $target_path/flux/flux-system/gotk-sync.yaml
if [[ `git status --porcelain` ]]; then
  git commit -m "update flux-system gotk-sync.yaml for cluster $hostname-$cluster_name"
  git pull
  git push
fi

cat $(local_or_global resources/gotk-sync.yaml) | envsubst | kubectl apply -f -

if [ -n "$mgmt" ]; then
  exit
fi

# Setup WGE access to the cluster

export cluster_name
export hostname
export wge_cluster_name="kind-${hostname}-${cluster_name}"
git pull
cat $(local_or_global resources/leaf-flux.yaml) | envsubst > clusters/kind/$hostname-$cluster_name/flux/flux.yaml
git add clusters/kind/$hostname-$cluster_name/flux/flux.yaml

if [[ `git status --porcelain` ]]; then
  git commit -m "deploy kustomizations to apply WGE SA to kind cluster $hostname-$cluster_name"
  git pull
  git push
fi

flux reconcile source git flux-system
flux reconcile kustomization flux-system

# Wait for wge-sa kustomization to be created
echo "Waiting for wge-sa kustomization to be created"
while ( true ); do
  set +e
  kubectl get kustomization/wge-sa -n flux-system 2>/dev/null
  ret=$?
  set -e
  if [ "$ret" == "0" ]; then
    break
  fi
  sleep 5
done

echo "Waiting for wge-sa to be applied"
kubectl wait --timeout=5m --for=condition=Ready kustomization/wge-sa -n flux-system

git pull
mkdir -p clusters//kind/$hostname-$cluster_name/wge
cat $(local_or_global resources/leaf-wge.yaml)| envsubst > clusters/kind/$hostname-$cluster_name/wge/flux.yaml
git add clusters/kind/$hostname-$cluster_name/wge/flux.yaml

if [[ `git status --porcelain` ]]; then
  git commit -m "deploy kustomizations to apply addons and apps to kind cluster $hostname-$cluster_name"
  git pull
  git push
fi

flux reconcile source git flux-system
flux reconcile kustomization flux-system

# Setup WGE access to the cluster using the WGE SA

export token="$(kubectl --kubeconfig ~/.kube/$location-${cluster_name}.kubeconfig get secrets -n wge -l "weave.works/wge-sa=wge" -o jsonpath={.items[0].data.token} | base64 -d)"
export cert="$(cat $HOME/.kube/${hostname}-${cluster_name}.kubeconfig | yq -r '.clusters[0].cluster."certificate-authority-data"')"
export endpoint="$(cat $HOME/.kube/${hostname}-${cluster_name}.kubeconfig | yq -r '.clusters[0].cluster.server')"

cat $(local_or_global resources/wge-kubeconfig.yaml) | envsubst > /tmp/kind-${hostname}-${cluster_name}-wge-kubeconfig.yaml
vault kv put -mount=secrets/leaf-cluster-secrets kind-${hostname}-${cluster_name}  value.yaml="$(cat /tmp/kind-${hostname}-${cluster_name}-wge-kubeconfig.yaml)"

mkdir -p clusters/management/clusters/kind/$hostname-$cluster_name
cat $(local_or_global resources/mgmt-flux.yaml) | envsubst > clusters/management/clusters/kind/$hostname-$cluster_name/flux.yaml
git add clusters/management/clusters/kind/$hostname-$cluster_name/flux.yaml
if [[ `git status --porcelain` ]]; then
  git commit -m "deploy kustomization to apply kubeconfig and gitopsCluster for kind cluster $hostname-$cluster_name"
  git pull
  git push
fi

flux reconcile source git flux-system
flux reconcile kustomization flux-system



