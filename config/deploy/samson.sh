#!/bin/bash -ex
export ENVIRONMENT=$1
export NAMESPACE=${2:-"$STAGE"}
export CONTEXT=$ENVIRONMENT

export KUBECONFIG=/opt/kubernetes/config
export RBENV_VERSION=2.4.2

if test -z "$ENVIRONMENT" ; then
  echo '[ERROR] $ENVIRONMENT *must* be set!'
  echo 'USAGE: samson.sh <ENVIRONMENT> [NAMESPACE]'
  exit 1
fi

memory env dump -k "ConfigMap/$NAMESPACE/interstellar-env" "$ENVIRONMENT" interstellar "$PWD/config/deploy/$ENVIRONMENT/configmap.yaml"
kubernetes-deploy --bindings=namespace=$NAMESPACE --no-prune "$NAMESPACE" "$CONTEXT"
