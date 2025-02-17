#!/usr/bin/env bash
if [[ -n "$BPI_SCRIPT_DEBUG" ]]; then
    set -x
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

echo "$0 called with $*"

set -eo pipefail

PORT=4242

while (( "$#" )); do
   case $1 in
      --port)
         shift&&PORT="$1"||die
         ;;
         *)
         echo "Unrecognized argument: $1"
         ;;
   esac
   shift
done

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
    sudo --preserve-env=DEBIAN_FRONTEND,NEEDRESTART_MODE apt -y install $todo
  fi
}

maybe_install wget python3

sudo mkdir -p /var/opt/machine/status/cgi-bin

cat >/tmp/machine.status.$$ <<EOF
#!/bin/bash
CLOUD_INIT_LOG=/var/log/cloud-init-output.log
STATUS="INITIALIZING"

sudo grep 'Failed to run module scripts_user' \$CLOUD_INIT_LOG >/dev/null
if [ \$? -ne 0 ]; then
  STATUS="ERROR"
else
  sudo grep '^Cloud-init v' \$CLOUD_INIT_LOG | grep 'Up.*seconds' >/dev/null
  if [ \$? -eq 0 ]; then
    STATUS="UP"
  fi
fi

echo "Content-Type: application/json"
echo "{ \"status\": \"\$STATUS\" }"
EOF
sudo mv /tmp/machine.status.$$ /var/opt/machine/status/cgi-bin/status
sudo chmod -R a+rX /var/opt/machine
sudo chmod -R a+x /var/opt/machine/status/cgi-bin/status

nohup python3 -m http.server --cgi --directory /var/opt/machine/status $PORT &
