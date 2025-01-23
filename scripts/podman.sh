#!/usr/bin/env bash
if [[ -n "$BPI_SCRIPT_DEBUG" ]]; then
    set -x
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

APT_INSTALL="sudo --preserve-env=DEBIAN_FRONTEND,NEEDRESTART_MODE apt -y install"

set -euo pipefail  ## https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/

sudo apt update
$APT_INSTALL apt-transport-https ca-certificates curl software-properties-common
$APT_INSTALL podman-docker podman
