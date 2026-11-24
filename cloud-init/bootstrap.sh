#!/usr/bin/env bash
# First-boot bootstrap, run once by cloud-init (runcmd).
#   1. Tailscale: install + join the tailnet (required, this is the only way in).
#   2. cloudflared: install the package only (never configured or started).
# Log: /var/log/vps-bootstrap.log
set -euo pipefail
exec > >(tee -a /var/log/vps-bootstrap.log) 2>&1

ENV_FILE=/run/vps-bootstrap.env
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
export DEBIAN_FRONTEND=noninteractive

codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
install -m 0755 -d /usr/share/keyrings

echo "== $(date -Is) tailscale: install"
curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${codename}.noarmor.gpg" \
  -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${codename}.tailscale-keyring.list" \
  -o /etc/apt/sources.list.d/tailscale.list
apt-get update -qq
apt-get install -y tailscale
systemctl enable --now tailscaled

echo "== $(date -Is) tailscale: up as ${TS_HOSTNAME} (Tailscale SSH on)"
# --ssh: the only login method. No SSH keys exist on this machine.
tailscale up --auth-key="$TS_AUTHKEY" --hostname="$TS_HOSTNAME" --ssh
rm -f "$ENV_FILE" # drop the auth key from disk/tmpfs (key is single-use anyway)
tailscale status || true

# Non-fatal: Tailscale is already up, so a failure here must not break access.
echo "== $(date -Is) cloudflared: install package only"
{
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg &&
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
      >/etc/apt/sources.list.d/cloudflared.list &&
    apt-get update -qq &&
    apt-get install -y cloudflared
} || echo "WARNING: cloudflared install failed; install it manually later."

echo "== $(date -Is) done"
touch /var/lib/vps-bootstrap.done
