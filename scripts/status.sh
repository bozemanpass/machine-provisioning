#!/usr/bin/env bash
if [[ -n "$BPI_SCRIPT_DEBUG" ]]; then
    set -x
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

echo "$0 called with $*"

set -eo pipefail

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
#!/usr/bin/env python3
print("Content-Type: text/html\n")
print("<!doctype html><title>Hello</title><h2>hello world</h2>")
EOF
sudo mv /tmp/machine.status.$$ /var/opt/machine/status/cgi-bin/status
sudo chmod -r a+rX /var/opt/machine
sudo chmod -r a+x /var/opt/machine/status/cgi-bin/status

nohup python3 -m http.server --cgi --directory /var/opt/machine/status $PORT
