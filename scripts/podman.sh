#!/usr/bin/env bash
if [[ -n "$BPI_SCRIPT_DEBUG" ]]; then
    set -x
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

APT_INSTALL="sudo --preserve-env=DEBIAN_FRONTEND,NEEDRESTART_MODE apt -y install"

set -eo pipefail  ## https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/

which podman >/dev/null && rc=$? || rc=$?
if [[ $rc -eq 0 ]]; then
  echo "podman already installed."
  if [[ "$1" != "-f" ]]; then
    exit 0
  fi
fi

which docker >/dev/null && HAS_DOCKER=true || HAS_DOCKER=false

sudo apt update
$APT_INSTALL apt-transport-https ca-certificates curl software-properties-common
$APT_INSTALL podman

if [[ "$HAS_DOCKER" == "false" ]]; then
  $APT_INSTALL podman-docker
  sudo touch /etc/containers/nodocker
fi
