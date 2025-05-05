#!/bin/bash

BPI_SCRIPT_DEBUG="${BPI_SCRIPT_DEBUG}"

IMAGE_REGISTRY=""
IMAGE_REGISTRY_USERNAME=""
IMAGE_REGISTRY_PASSWORD=""
STACK_LOCATOR=""
PUBLISH_IMAGES=""
DEPLOY_TO=""
KUBE_CONFIG=""

BUILD_POLICY="as-needed"

STACK_CMD="stack"
if [[ -n "${BPI_SCRIPT_DEBUG}" ]]; then
  set -x
  STACK_CMD="${STACK_CMD} --debug --verbose"
fi

while (( "$#" )); do
   case $1 in
      --stack)
         shift&&STACK_LOCATOR="$1"||die
         ;;
      --stack-path)
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
fi

if [[ -n "$IMAGE_REGISTRY" ]] && [[ -n "$IMAGE_REGISTRY_PASSWORD" ]]; then
  docker login --username "$IMAGE_REGISTRY_USERNAME" --password "$IMAGE_REGISTRY_PASSWORD" $IMAGE_REGISTRY
fi

STACK_NAME="$(echo $STACK_LOCATOR | cut -d'/' -f2-)"

$STACK_CMD fetch stack $STACK_LOCATOR
if [[ -z "$STACK_PATH" ]]; then
  STACK_PATH=`dirname $(find "$HOME/bpi/${STACK_NAME}" -name 'stack.yml' | head -1)`
fi
$STACK_CMD fetch repositories --stack $STACK_PATH
$STACK_CMD build containers --stack $STACK_PATH --image-registry $IMAGE_REGISTRY --build-policy $BUILD_POLICY $PUBLISH_IMAGES

KUBE_CONFIG_ARG=""
if [[ "$DEPLOY_TO" == "k8s" ]]; then
  if [[ -z "$KUBE_CONFIG" ]]; then
    KUBE_CONFIG="/etc/rancher/k3s/k3s.yaml"
  fi
  if [[ "$KUBE_CONFIG" == "/etc/rancher/k3s/k3s.yaml" ]]; then
    sudo chmod a+r /etc/rancher/k3s/k3s.yaml
  fi
  KUBE_CONFIG_ARG="--kube-config $KUBE_CONFIG"
fi

$STACK_CMD \
  config \
    --deploy-to $DEPLOY_TO \
    init \
      $KUBE_CONFIG_ARG \
      --stack $STACK_PATH \
      --output $STACK_NAME.yml \
      --image-registry $IMAGE_REGISTRY ${EXTRA_CONFIG_ARGS}

mkdir $HOME/deployments

$STACK_CMD \
  deploy \
     --spec-file $STACK_NAME.yml \
     --deployment-dir $HOME/deployments/$STACK_NAME

$STACK_CMD manage --dir $HOME/deployments/$STACK_NAME push-images
$STACK_CMD manage --dir $HOME/deployments/$STACK_NAME start
