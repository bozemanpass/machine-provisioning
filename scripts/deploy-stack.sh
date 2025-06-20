#!/bin/bash

BPI_SCRIPT_DEBUG="${BPI_SCRIPT_DEBUG}"

IMAGE_REGISTRY=""
IMAGE_REGISTRY_USERNAME=""
IMAGE_REGISTRY_PASSWORD=""
STACK_LOCATOR=""
PUBLISH_IMAGES="--publish-images"
DEPLOY_TO=""
KUBE_CONFIG=""
INCLUDE_SPECS=""
HTTP_PROXY_FQDN="${MACHINE_FQDN}"
HTTP_PROXY_CLUSTER_ISSUER=""

BUILD_POLICY="as-needed"

STACK_CMD="stack"
if [[ -n "${BPI_SCRIPT_DEBUG}" ]]; then
  set -x
  STACK_CMD="${STACK_CMD} --debug --verbose"
fi

while (( "$#" )); do
   case $1 in
      --stack-repo)
         shift&&STACK_LOCATOR="$1"||die
         ;;
      --stack-name)
         shift&&STACK_PATH="$1"||die
         ;;
      --build-policy)
         shift&&BUILD_POLICY="$1"||die
         ;;
      --debug)
         BPI_SCRIPT_DEBUG="true"
         ;;
      --deploy-to)
         shift&&DEPLOY_TO="$1"||die
         ;;
      --http-proxy-fqdn)
         shift&&HTTP_PROXY_FQDN="$1"||die
         ;;
      --http-proxy-clusterissuer)
         shift&&HTTP_PROXY_CLUSTER_ISSUER="$1"||die
         ;;
      --kube-config)
         shift&&KUBE_CONFIG="$1"||die
         ;;
      --image-registry)
         shift&&IMAGE_REGISTRY="$1"||die
         ;;
      --image-registry-username)
         shift&&IMAGE_REGISTRY_USERNAME="$1"||die
         ;;
      --image-registry-password)
         shift&&IMAGE_REGISTRY_PASSWORD="$1"||die
         ;;
      --publish-images)
         PUBLISH_IMAGES="--publish-images"
         ;;
      --no-publish-images)
         PUBLISH_IMAGES=""
         ;;
      --skip-deploy)
         SKIP_DEPLOY="true"
         ;;
      --include-spec)
         shift&&INCLUDE_SPECS="$INCLUDE_SPECS $1"||die
         ;;
      --)
         shift&&EXTRA_CONFIG_ARGS="$*"
         break
         ;;
      *)
         echo "Unrecognized argument: $1" 1>&2
         ;;
   esac
   shift
done

if [[ -z "$STACK_LOCATOR" ]]; then
  echo "--stack <locator> is required"
  exit 2
fi

if [[ -z "$IMAGE_REGISTRY" ]]; then
  if [[ -f "/etc/rancher/k3s/registries.yaml" ]]; then
    IMAGE_REGISTRY=$(cat /etc/rancher/k3s/registries.yaml | grep -A1 'configs:$' | tail -1 | awk '{ print $1 }' | cut -d':' -f1)
    IMAGE_REGISTRY_USERNAME=$(cat /etc/rancher/k3s/registries.yaml | grep 'username:' | awk '{ print $2 }' | sed "s/[\"']//g")
    IMAGE_REGISTRY_PASSWORD=$(cat /etc/rancher/k3s/registries.yaml | grep 'password:' | awk '{ print $2 }' | sed "s/[\"']//g")
  fi
fi

if [[ -z "$DEPLOY_TO" ]]; then
  if [[ -d "/etc/rancher/k3s" ]]; then
    DEPLOY_TO="k8s"
  else
    DEPLOY_TO="compose"
  fi
  if [ -z "`$STACK_CMD config get deploy-to`" ]; then
    $STACK_CMD config set deploy-to $DEPLOY_TO
  fi
fi

if [[ -n "$IMAGE_REGISTRY" ]] && [[ -n "$IMAGE_REGISTRY_PASSWORD" ]]; then
  docker login --username "$IMAGE_REGISTRY_USERNAME" --password "$IMAGE_REGISTRY_PASSWORD" $IMAGE_REGISTRY
  if [ -z "`$STACK_CMD config get image-registry`" ] ; then
    $STACK_CMD config set image-registry $IMAGE_REGISTRY
  fi
fi

if [[ -n "$HTTP_PROXY_FQDN" ]]; then
  $STACK_CMD config set http-proxy-fqdn $HTTP_PROXY_FQDN
fi

if [[ -n "$HTTP_PROXY_CLUSTER_ISSUER" ]]; then
  $STACK_CMD config set http-proxy-clusterissuer $HTTP_PROXY_CLUSTER_ISSUER
fi

STACK_REPO_BASE_DIR=`$STACK_CMD config get repo-base-dir`

$STACK_CMD fetch stack $STACK_LOCATOR

if [[ -z "$STACK_NAME" ]]; then
  # Is there only one stack available?
  if [[ $($STACK_CMD list stacks | wc -l) -eq 1 ]]; then
    STACK_NAME=$($STACK_CMD list stacks --name-only)
  else
    echo "Unable to determine stack name. Please specify --stack-name" >&2
    exit 1
  fi
fi

$STACK_CMD fetch repositories --stack $STACK_NAME
$STACK_CMD build containers --stack $STACK_NAME --image-registry $IMAGE_REGISTRY --build-policy $BUILD_POLICY $PUBLISH_IMAGES

KUBE_CONFIG_ARG=""
if [[ "$DEPLOY_TO" == "k8s" ]]; then
  if [[ -z "$KUBE_CONFIG" ]]; then
    KUBE_CONFIG="/etc/rancher/k3s/k3s.yaml"
  fi
  if [[ "$KUBE_CONFIG" == "/etc/rancher/k3s/k3s.yaml" ]]; then
    sudo chmod a+r /etc/rancher/k3s/k3s.yaml
  fi
  KUBE_CONFIG_ARG="--kube-config $KUBE_CONFIG"
  if [ -z "`$STACK_CMD config get kube-config`" ] ; then
    $STACK_CMD config set kube-config $KUBE_CONFIG
  fi
fi

$STACK_CMD init \
      --deploy-to $DEPLOY_TO \
      --stack $STACK_PATH \
      --output ${STACK_NAME}.yml \
      --image-registry $IMAGE_REGISTRY \
      ${KUBE_CONFIG_ARG} \
      ${EXTRA_CONFIG_ARGS}

if [[ "$SKIP_DEPLOY" == "true" ]]; then
  exit 0
fi

mkdir $HOME/deployments

SPEC_FILE_ARG="--spec-file ${STACK_NAME}.yml"
for spec in $INCLUDE_SPECS; do
  SPEC_FILE_ARG="$SPEC_FILE_ARG --spec-file $spec"
done

$STACK_CMD deploy $SPEC_FILE_ARG --deployment-dir $HOME/deployments/$STACK_NAME

$STACK_CMD manage --dir $HOME/deployments/$STACK_NAME push-images
$STACK_CMD manage --dir $HOME/deployments/$STACK_NAME start
