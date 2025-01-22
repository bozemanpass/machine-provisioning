#!/usr/bin/env bash
if [[ -n "$BPI_SCRIPT_DEBUG" ]]; then
    set -x
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

FORCE="false"
VER="latest"

while getopts "fv:" arg; do
  case $arg in
    f)
      FORCE=true
      ;;
    v)
      VER=$OPTARG
      ;;
  esac
done

set -euo pipefail  ## https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/

function maybe_install {
  local todo=""
  while (( "$#" )); do
    local exists=false
    which $1 >/dev/null && exists=true || exists=false
    if [[ "true" != "$exists" ]]; then
      todo="$todo $1"
    fi
    shift
  done
  if [[ ! -z "$todo" ]]; then
    echo "**************************************************************************************"
    echo "Installing required packages"
    sudo apt -y update
    sudo -E DEBIAN_FRONTEND,NEEDRESTART_MODE apt -y install $todo
  fi
}

maybe_install wget

if [[ -x "/usr/local/bin/stack" ]]; then
  echo "/usr/local/bin/stack already exists"
  if [[ "$FORCE" != "true" ]]; then
    exit 0
  fi
fi

if [[ "$VER" == "latest" ]]; then
  wget -O /tmp/stack.$$ https://github.com/bozemanpass/stack/releases/latest/download/stack
else
  wget -O /tmp/stack.$$ https://github.com/bozemanpass/stack/releases/download/${VER}/stack
fi
sudo mv /tmp/stack.$$ /usr/local/bin/stack
sudo chmod a+x /usr/local/bin/stack