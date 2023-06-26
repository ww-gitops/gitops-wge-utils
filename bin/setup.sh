#!/usr/bin/env bash

# Utility setting local kubernetes cluster
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] [--flux-bootstrap]" >&2
    echo "This script will initialize docker kubernetes" >&2
    echo "  --debug: emmit debugging information" >&2
    echo "  --flux-bootstrap: force flux bootstrap" >&2
}

function args() {
  bootstrap=0
  reset=0
  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--debug") set -x;;
          "--reset") reset=1;;
          "--flux-bootstrap") bootstrap=1;;
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

echo "Waiting for cluster to be ready"
kubectl wait --for=condition=Available  -n kube-system deployment coredns

git config pull.rebase true  

if [ $bootstrap -eq 0 ]; then
  set +e
  kubectl get ns | grep flux-system
  bootstrap=$?
  set -e
fi
if [ $bootstrap -eq 0 ]; then
  echo "flux-system namespace already. skipping bootstrap"
else
  kubectl apply -f ${config_dir}/mgmt-cluster/addons/flux
  source resources/github-secrets.sh
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
  cat $(local_or_global resources/gotk-sync.yaml) | envsubst | kubectl apply -f -
fi

if [ -f resources/CA.cer ]; then
  echo "Certificate Authority already exists"
else
  ca-cert.sh
fi

kubectl create ns cert-manager
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

kubectl wait --timeout=5m --for=condition=Ready kustomizations.kustomize.toolkit.fluxcd.io -n flux-system flux-system

# Wait for ingress controller to start
echo "Waiting for ingress controller to start"
kubectl wait --timeout=5m --for=condition=Ready kustomizations.kustomize.toolkit.fluxcd.io -n flux-system nginx

export CLUSTER_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')

export AWS_ACCOUNT_ID="none"
if [ "$aws" == "true" ]; then
  export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
fi

if [ "$aws" == "true" ]; then
  cp $(local_or_global resources/aws/flux/)* mgmt-cluster/flux
  cp $(local_or_global resources/aws/templates/)* mgmt-cluster/templates
  git add mgmt-cluster/flux
  git add mgmt-cluster/templates
fi

if [ "$capi" == "true" ]; then
  cp $(local_or_global resources/capi/flux/)* mgmt-cluster/flux
  cp $(local_or_global resources/capi/namespace/)* mgmt-cluster/namespace
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
  clusterawsadm bootstrap iam create-cloudformation-stack --config $(local_or_global resources/clusterawsadm.yaml) --region $AWS_REGION

  export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile)

  export EXP_EKS=true
  export EXP_MACHINE_POOL=true
  export CAPA_EKS_IAM=true
  export EXP_CLUSTER_RESOURCE_SET=true

  clusterctl init --infrastructure aws
fi

secrets.sh --tls-skip --wge-entitlement $PWD/resources/wge-entitlement.yaml --secrets $PWD/resources/github-secrets.sh

# Wait for dex to start
kubectl wait --timeout=5m --for=condition=Ready kustomization/dex -n flux-system

set +e
vault-oidc-config.sh
set -e

if [ "$aws" == "true" ]; then
  echo "Waiting for aws to be applied"
  kubectl wait --timeout=5m --for=condition=Ready kustomization/aws -n flux-system

  terraform/bin/tf-apply.sh aws-key-pair
fi
