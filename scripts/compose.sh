#!/usr/bin/env bash
if [[ -n "$BPI_SCRIPT_DEBUG" ]]; then
    set -x
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

echo "$0 called with $*"

set -eo pipefail  ## https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/

SCRIPTS=()
declare -A ARGS

while (( "$#" )); do
   case $1 in
      --script)
         shift&&LAST_SCRIPT="$1"&&SCRIPTS+=("$1")||die
         ;;
      --args)
         shift&&ARGS["$LAST_SCRIPT"]="$1"||die
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
    sudo -E DEBIAN_FRONTEND,NEEDRESTART_MODE apt -y install $todo
  fi
}

maybe_install wget

step=0
rc=0

for script in "${SCRIPTS[@]}"; do
  step=$((step + 1))
  echo "**************************************************************************************"
  echo "$script BEGIN"
  cmd="$script"
  if [[ $script == http* ]]; then
    echo "Downloading $script to /tmp/compose.script.$step ..."
    wget -q -O /tmp/compose.step.$step $cmd
    chmod 700 /tmp/compose.step.$step
    cmd=/tmp/compose.step.$step
  fi
  echo "Running: $cmd ${ARGS["$script"]}"
  $cmd ${ARGS["$script"]} && rc=$? || rc=$?
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "$script FAILED rc=$rc"
  fi
  echo "$script END"
  echo "#####################################################################################"

  if [[ $rc != 0 ]]; then
    break
  fi
done

rm -f /tmp/compose.step.*

if [[ $rc -eq 0 ]]; then
  echo "All scripts completed successfully."
fi

exit $rc
