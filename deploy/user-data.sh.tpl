#!/bin/bash
set -euo pipefail
exec > >(tee -a /var/log/b6-1-bootstrap.log) 2>&1
trap 'echo "B6-1 BOOTSTRAP FAILED line=$LINENO"' ERR
echo 'B6-1 bootstrap start'
# 512 MiB swap inside the existing encrypted 8 GiB root volume.
if ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
  if [ ! -e /swapfile ]; then
    install -m 600 /dev/null /swapfile
    dd if=/dev/zero of=/swapfile bs=1M count=512 status=none
    mkswap /swapfile
  fi
  chmod 600 /swapfile
  swapon /swapfile
fi
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
# Official signed Amazon Linux repository package; no third-party installer.
dnf --setopt=gpgcheck=1 install -y docker
systemctl enable --now docker
install -d -m 755 /usr/local/lib/docker/cli-plugins
curl --fail --show-error --silent --location --retry 3 \
  https://github.com/docker/compose/releases/download/v2.39.4/docker-compose-linux-aarch64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
printf '%s  %s\n' 49082844b87f03cdcd5f5bbef1ba8c9c897b7a2dfb80cea18d61ec8ca6117e0c /usr/local/lib/docker/cli-plugins/docker-compose | sha256sum -c -
chmod 755 /usr/local/lib/docker/cli-plugins/docker-compose
install -d -m 755 /opt/b6-1/app
printf '%s' '@@INDEX_B64@@' | base64 -d > /opt/b6-1/app/index.html
printf '%s' '@@NGINX_B64@@' | base64 -d > /opt/b6-1/nginx.conf
printf '%s' '@@COMPOSE_B64@@' | base64 -d > /opt/b6-1/compose.yaml
chmod 644 /opt/b6-1/app/index.html /opt/b6-1/nginx.conf /opt/b6-1/compose.yaml
cd /opt/b6-1
docker version
docker compose version
docker compose config --quiet
docker compose up -d
for attempt in $(seq 1 40); do
  if curl --fail --silent http://127.0.0.1/health | grep -qx 'B6-1 OK'; then
    echo 'B6-1 BOOTSTRAP READY'
    exit 0
  fi
  sleep 5
done
echo 'B6-1 health timeout'
exit 1
