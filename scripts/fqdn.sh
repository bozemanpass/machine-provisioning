#!/bin/bash

if [[ ! -d "/etc/machine" ]]; then
  sudo mkdir -p /etc/machine
fi

if [[ -n "$MACHINE_FQDN" ]]; then
  echo "$MACHINE_FQDN" > /tmp/fqdn.??
  sudo mv /tmp/fqdn.?? /etc/machine/fqdn
fi

sudo chown -R root:root /etc/machine
