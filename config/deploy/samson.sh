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
# we have to upload this as json, and memory dump flattens keys in a not-good-for-this way
memory -q -f json show interstellar serviceaccount 2>/dev/null >/tmp/interstellar-service-account
kubectl --context $ENVIRONMENT --namespace $NAMESPACE create configmap google-service-account --from-file /tmp/interstellar-service-account --dry-run -o yaml | kubectl --context $ENVIRONMENT --namespace $NAMESPACE apply -f -

kubernetes-deploy --bindings=namespace=$NAMESPACE --no-prune "$NAMESPACE" "$CONTEXT"
