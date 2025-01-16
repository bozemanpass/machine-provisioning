#!/usr/bin/env bash
if [[ -n "$BPI_SCRIPT_DEBUG" ]]; then
    set -x
fi

install_dir=~/bin

NEEDS_WARN=true
LETSENCRYPT_EMAIL=""
DO_TOKEN=""

while getopts "ye:t:" arg; do
  case $arg in
    y)
      NEEDS_WARN=false
      ;;
    e)
      LETSENCRYPT_EMAIL=$OPTARG
      ;;
    t)
      DO_TOKEN=$(echo -n "$OPTARG" | base64 -w0)
      ;;
  esac
done

function retry {
  local try=0
  local max=5
  local delay=5
  while [ $try -lt $max ]; do
    echo "Try $try of $* ..."
    $*
    if [ $? -eq 0 ]; then
      return 0
    fi
    try=$((try + 1))
  done
  return 1
}

# Skip the package install stuff if so directed
if ! [[ -n "$BPI_INSTALL_SKIP_PACKAGES" ]]; then

# First display a reasonable warning to the user unless run with -y
if [[ "$NEEDS_WARN" == "true" ]]; then
  echo "**************************************************************************************"
  echo "This script requires sudo privilege. It installs utilities"
  echo "into: ${install_dir}. It also *removes* any existing docker installed on"
  echo "this machine and then installs the latest docker release as well as other"
  echo "required packages."
  echo "Only proceed if you are sure you want to make those changes to this machine."
  echo "**************************************************************************************"
  read -p "Are you sure you want to proceed? " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Determine if we are on Debian or Ubuntu
linux_distro=$(lsb_release -a 2>/dev/null | grep "^Distributor ID:" | cut -f 2)
# Some systems don't have lsb_release installed (e.g. ChromeOS) and so we try to
# use /etc/os-release instead
if [[ -z "$linux_distro" ]]; then
  if [[ -f "/etc/os-release" ]]; then
    distro_name_string=$(grep "^NAME=" /etc/os-release | cut -d '=' -f 2)
    if [[ $distro_name_string =~ Debian ]]; then
      linux_distro="Debian"
    elif [[ $distro_name_string =~ Ubuntu ]]; then
      linux_distro="Ubuntu"
    fi
  else
    echo "Failed to identify distro: /etc/os-release doesn't exist"
    exit 1
  fi
fi
case $linux_distro in
  Debian)
    echo "Installing k3s for Debian"
    ;;
  Ubuntu)
    echo "Installing k3s for Ubuntu"
    ;;
  *)
    echo "ERROR: Detected unknown distribution $linux_distro, can't install k3s"
    exit 1
    ;;
esac

# dismiss the popups
export DEBIAN_FRONTEND=noninteractive

## Even though we're installing k3s, which doesn't depend on docker, we still un-install any distro-origin docker components first
## https://docs.docker.com/engine/install/ubuntu/
## https://docs.docker.com/engine/install/debian/
## https://superuser.com/questions/518859/ignore-packages-that-are-not-currently-installed-when-using-apt-get-remove1
packages_to_remove="docker docker-engine docker.io containerd runc docker-compose docker-doc podman-docker"
installed_packages_to_remove=""
for package_to_remove in $(echo $packages_to_remove); do
  $(dpkg --info $package_to_remove &> /dev/null)
  if [[ $? -eq 0 ]]; then
    installed_packages_to_remove="$installed_packages_to_remove $package_to_remove"
  fi
done

# Enable stop on error now, since we needed it off for the code above
set -euo pipefail  ## https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/

if [[ -n "${installed_packages_to_remove}" ]]; then
  echo "**************************************************************************************"
  echo "Removing existing docker packages"
  sudo apt -y remove $installed_packages_to_remove
fi

echo "**************************************************************************************"
echo "Installing extra packages"
sudo apt -y update
sudo apt -y install jq
sudo apt -y install git
sudo apt -y install curl

echo "**************************************************************************************"
echo "Installing k3s"
k3s_installer_file=$HOME/install-k3s.sh
curl -sfL https://get.k3s.io -o ${k3s_installer_file}
chmod +x ${k3s_installer_file}

export INSTALL_K3S_EXEC="--disable=traefik"
sudo --preserve-env=INSTALL_K3S_EXEC ${k3s_installer_file}
echo "Installed k3s"

echo "**************************************************************************************"
echo "Installing nginx ingress"
sudo kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/baremetal/deploy.yaml

cat > /tmp/lb.yml.$$ <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller-loadbalancer
  namespace: ingress-nginx
spec:
  selector:
    app.kubernetes.io/component: controller
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/name: ingress-nginx
  ports:
    - name: http
      port: 80
      protocol: TCP
      targetPort: 80
    - name: https
      port: 443
      protocol: TCP
      targetPort: 443
  type: LoadBalancer
EOF

sudo kubectl apply -f /tmp/lb.yml.$$
rm -f /tmp/lb.yml.$$

sudo kubectl annotate ingressclass nginx ingressclass.kubernetes.io/is-default-class=true

echo "Installed nginx ingress"

echo "**************************************************************************************"
echo "Installing cert-manager"

sudo kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml

echo "Waiting for cert-manager to come up..."

MAX_TRIES=30
TRY=0
while [ `sudo kubectl get pods --namespace cert-manager | grep Running | wc -l` -lt 3 ]; do
  TRY=$((TRY + 1))
  if [ $TRY -ge $MAX_TRIES ]; then
    echo "ERROR: cert-manager failed to come up." 1>&2
    exit 1
  fi
done

cat > $HOME/letsencrypt-prod.yml <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: $LETSENCRYPT_EMAIL
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

cat > $HOME/letsencrypt-stage.yml <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
 name: letsencrypt-staging
 namespace: cert-manager
spec:
 acme:
   # The ACME server URL
   server: https://acme-staging-v02.api.letsencrypt.org/directory
   # Email address used for ACME registration
   email: $LETSENCRYPT_EMAIL
   # Name of a secret used to store the ACME account private key
   privateKeySecretRef:
     name: letsencrypt-staging
   # Enable the HTTP-01 challenge provider
   solvers:
   - http01:
       ingress:
         class:  nginx
EOF

cat > $HOME/digitalocean-dns.yml <<EOF
apiVersion: v1
data:
  access-token: $DO_TOKEN
kind: Secret
metadata:
  name: digitalocean-dns
  namespace: cert-manager
EOF


cat > $HOME/letsencrypt-prod-dns01.yml <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod-dns
  namespace: cert-manager
spec:
  acme:
    # Email address used for ACME registration
    email: $LETSENCRYPT_EMAIL
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      # Name of a secret used to store the ACME account private key
      name: letsencrypt-prod
    solvers:
      - dns01:
          digitalocean:
            tokenSecretRef:
              name: digitalocean-dns
              key: access-token
EOF

if [[ ! -z "$LETSENCRYPT_EMAIL" ]]; then
  retry sudo kubectl apply -f $HOME/letsencrypt-prod.yml
  retry sudo kubectl apply -f $HOME/letsencrypt-stage.yml
  if [[ ! -z "$DO_TOKEN" ]]; then
    retry sudo kubectl apply -f $HOME/digitalocean-dns.yml
    retry sudo kubectl apply -f $HOME/letsencrypt-prod-dns01.yml
  else
    echo "No DigitalOcean access token specified, so a DNS-based ClusterIssuer's could not be created.  Template files created at $HOME/digitalocean-dns.yml and $HOME/letsencrypt-prod-dns-01.yml"
  fi
else
  echo "No e-mail specified, so ClusterIssuer's could not be created.  Template files created at $HOME/letsencrypt-prod.yml and $HOME/letsencrypt-stage.yml"
fi

echo "Installed cert-manager"


# End of long if block: Skip the package install stuff if so directed
fi

# Message the user to check docker is working for them
echo "Please log in again (docker will not work in this current shell) then:"
echo "test that k3s is correctly installed and working for your user by running the"
echo "command below:"
echo
echo "sudo k3s kubectl get node"
echo
