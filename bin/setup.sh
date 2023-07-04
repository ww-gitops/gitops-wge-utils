#!/usr/bin/env bash

# Utility setting local kubernetes cluster
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] [--flux-bootstrap] [--flux-reset] [--no-wait]" >&2
    echo "This script will initialize docker kubernetes" >&2
    echo "  --debug: emmit debugging information" >&2
    echo "  --flux-bootstrap: force flux bootstrap" >&2
    echo "  --flux-reset: unistall flux before reinstall" >&2
    echo "  --no-wait: do not wait for flux to be ready" >&2
}

function args() {
  wait=1
  bootstrap=0
  reset=0
  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--debug") set -x;;
          "--no-wait") wait=0;;
          "--flux-bootstrap") bootstrap=1;;
          "--flux-reset") reset=1;;
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

cat $(local_or_global resources/flux.yaml) | envsubst > $target_path/flux/flux.yaml
git add $target_path/flux/flux.yaml
if [[ `git status --porcelain` ]]; then
  git commit -m "Add flux.yaml"
  git pull
  git push
fi

if [[ "$OSTYPE" == "linux"* ]]; then
  delpoy-kind --cluster-name $CLUSTER_NAME
  export KUBECONFIG=~/.kube/localhost-${CLUSTER_NAME}.kubeconfig
fi

echo "Waiting for cluster to be ready"
kubectl wait --for=condition=Available  -n kube-system deployment coredns

git config pull.rebase true  

# Install Flux if not present or force reinstall option set

if [ $bootstrap -eq 0 ]; then
  set +e
  kubectl get ns | grep flux-system
  bootstrap=$?
  set -e
fi

if [ $bootstrap -eq 0 ]; then
  echo "flux-system namespace already. skipping bootstrap"
else
  if [ $reset -eq 1 ]; then
    echo "uninstalling flux"
    flux uninstall --silent --keep-namespace
    if [ -e $target_path/flux/flux-system ]; then
      rm -rf $target_path/flux/flux-system
      git add $target_path/flux/flux-system
      if [[ `git status --porcelain` ]]; then
        git commit -m "remove flux-system from cluster repo"
        git pull
        git push
      fi
    fi
  fi
  # kubectl apply -f ${config_dir}/mgmt-cluster/addons/flux
  kustomize build ${config_dir}/mgmt-cluster/addons/flux | kubectl apply -f-
  source resources/github-secrets.sh
  # flux bootstrap github --token-auth --token $GITHUB_TOKEN_WRITE --owner $GITHUB_MGMT_ORG --repository $GITHUB_MGMT_REPO --path $target_path/flux

  # Re create a secret for flux to use to access the git repo backing the cluster, using reasd only token

  kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: flux-system
  namespace: flux-system
data:
  username: $(echo -n "git" | base64)
  password: $(echo -n "$GITHUB_TOKEN_READ" | base64)
EOF

  # Create flux-system GitRepository and Kustomization

  # git pull
  mkdir -p $target_path/flux/flux-system
  cat $(local_or_global resources/gotk-sync.yaml) | envsubst > $target_path/flux/flux-system/gotk-sync.yaml
  git add $target_path/flux/flux-system/gotk-sync.yaml
  if [[ `git status --porcelain` ]]; then
    git commit -m "update flux-system gotk-sync.yaml"
    git pull
    git push
  fi

  kubectl apply -f $target_path/flux/flux-system/gotk-sync.yaml

  # flux suspend kustomization flux-system
  # rm -rf $target_path/flux/flux-system/gotk-components.yaml
  # rm -rf $target_path/flux/flux-system/kustomization.yaml
  # git add $target_path/flux/flux-system/gotk-components.yaml
  # git add $target_path/flux/flux-system/kustomization.yaml
  # if [[ `git status --porcelain` ]]; then
  #   git commit -m "remove flux-system gotk-components.yaml and kustomization.yaml from cluster repo"
  #   git pull
  #   git push
  # fi
  # 
  # flux resume kustomization flux-system
fi

# Create a CA Certificate for the ingress controller to use

if [ -f resources/CA.cer ]; then
  echo "Certificate Authority already exists"
else
  ca-cert.sh
fi

# Install CA Certificate secret so Cert Manager can issue certificates using our CA

kubectl apply -f ${config_dir}/mgmt-cluster/addons/cert-manager/namespace.yaml
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ca-key-pair
  namespace: cert-manager
data:
  tls.crt: $(base64 -i resources/CA.cer)
  tls.key: $(base64 -i resources/CA.key)
EOF

# Add CA Certificates to namespaces where it is required

namespace_list=$(local_or_global resources/local-ca-namespaces.txt)
export CA_CERT="$(cat resources/CA.cer)"
for nameSpace in $(cat $namespace_list); do
  export nameSpace
  cat $(local_or_global resources/local-ca-ns.yaml) |envsubst | kubectl apply -f -
  kubectl create configmap local-ca -n ${nameSpace} --from-file=resources/CA.cer --dry-run=client -o yaml | kubectl apply -f -
done

if [ "$wait" == "1" ]; then
  echo "Waiting for flux to flux-system Kustomization to be ready"
  kubectl wait --timeout=5m --for=condition=Ready kustomizations.kustomize.toolkit.fluxcd.io -n flux-system flux-system
fi

if [ "$wait" == "1" ]; then
  # Wait for ingress controller to start
  echo "Waiting for ingress controller to start"
  kubectl wait --timeout=5m --for=condition=Ready kustomizations.kustomize.toolkit.fluxcd.io -n flux-system nginx
  sleep 5
fi
export CLUSTER_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')

export AWS_ACCOUNT_ID="none"
if [ "$aws" == "true" ]; then
  export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
fi

if [ "$aws" == "true" ]; then
  cp $(local_or_global resources/aws/flux/)* mgmt-cluster/flux/
  cp $(local_or_global resources/aws/templates/)* mgmt-cluster/templates/
  git add mgmt-cluster/flux
  git add mgmt-cluster/templates
fi

if [ "$capi" == "true" ]; then
  cp $(local_or_global resources/capi/flux/)* mgmt-cluster/flux/
  cp $(local_or_global resources/capi/namespace/)* mgmt-cluster/namespace/
  git add mgmt-cluster/flux
  git add mgmt-cluster/namespace
fi

export namespace=flux-system
cat $(local_or_global resources/cluster-config.yaml) | envsubst > mgmt-cluster/config/cluster-config.yaml
git add mgmt-cluster/config/cluster-config.yaml

export namespace=\$\{nameSpace\}
cat $(local_or_global resources/cluster-config.yaml) | envsubst > mgmt-cluster/namespace/cluster-config.yaml
git add mgmt-cluster/namespace/cluster-config.yaml
if [[ `git status --porcelain` ]]; then
  git commit -m "update cluster config"
  git pull
  git push
fi

# Wait for vault to start
while ( true ); do
  echo "Waiting for vault to start"
  set +e
  started="$(kubectl get pod/vault-0 -n vault -o json 2>/dev/null | jq -r '.status.containerStatuses[0].started')"
  set -e
  if [ "$started" == "true" ]; then
    break
  fi
  sleep 5
done

sleep 5
# Initialize vault
vault-init.sh
vault-unseal.sh

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vault-token
  namespace: vault
data:
  vault_token: $(jq -r '.root_token' resources/.vault-init.json | base64)
EOF

set +e
vault-secrets-config.sh
set -e

if [ "$aws_capi" == "true" ]; then
  export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile)
fi

secrets.sh --tls-skip --wge-entitlement $PWD/resources/wge-entitlement.yaml --secrets $PWD/resources/github-secrets.sh

if [ "$aws_capi" == "true" ]; then
  clusterawsadm bootstrap iam create-cloudformation-stack --config $(local_or_global resources/clusterawsadm.yaml) --region $AWS_REGION

  export EXP_EKS=true
  export EXP_MACHINE_POOL=true
  export CAPA_EKS_IAM=true
  export EXP_CLUSTER_RESOURCE_SET=true

  clusterctl init --infrastructure aws
fi

# Wait for dex to start
kubectl wait --timeout=5m --for=condition=Ready kustomization/dex -n flux-system

# set +e
# vault-oidc-config.sh
# set -e

if [ "$aws" == "true" ]; then
  if [ "$wait" == "1" ]; then
    echo "Waiting for aws to be applied"
    kubectl wait --timeout=5m --for=condition=Ready kustomization/aws -n flux-system
  fi
  ${config_dir}/terraform/bin/tf-apply.sh aws-key-pair
fi

if [ "$ecr_repos" == "true" ]; then
  if [ ! -e resource-descriptions/wge/clusters.yaml ]; then
    mkdir -p resource-descriptions/wge
    cat $(local_or_global resource-descriptions/templates/wge/clusters.yaml) | envsubst > resource-descriptions/wge/clusters.yaml
    git add resource-descriptions/wge/clusters.yaml
  fi

  if [ ! -e resource-descriptions/wge/namespaces.yaml ]; then
    mkdir -p resource-descriptions/wge
    cat $(local_or_global resource-descriptions/templates/wge/namespaces.yaml) | envsubst > resource-descriptions/wge/namespaces.yaml
    git add resource-descriptions/wge/namespaces.yaml
  fi

  if [ ! -e resource-descriptions/ci/gitopset.yaml ]; then
    mkdir -p ci
    cat $(local_or_global resource-descriptions/ci/gitopset.yaml) | envsubst > ci/gitopset.yaml
    git add ci/gitopset.yaml
  fi

  cp $(local_or_global resources/ecr/flux.yaml) mgmt-cluster/flux/ecr.yaml
  git add mgmt-cluster/flux/ecr.yaml
  
  if [[ `git status --porcelain` ]]; then
    git commit -m "Add wge resource descriptions"
    git pull
    git push
  fi
fi
