#!/usr/bin/env bash
# Developer tooling for the VM. Run once after first login, as your normal user (not root):
#
#   bash scripts/install-tools.sh
#
# Idempotent: safe to re-run. Installs
#   apt:   build tools, ripgrep, tmux, btop, ttyd, Docker (docker-ce)
#   mise:  node 24, python 3.14, aws-cli, kubectl, eksctl, gh, glab
#   other: bun, uv
#   AI CLIs: claude, opencode, codex, pi, t3
# It does NOT log you in to anything and copies no credentials.
set -euo pipefail

[ "$(id -u)" -ne 0 ] || { echo "Run as your normal user, not root." >&2; exit 1; }
log() { printf '\n== %s\n' "$*"; }
export DEBIAN_FRONTEND=noninteractive
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$HOME/.bun/bin:$HOME/.opencode/bin:$PATH"
mkdir -p "$HOME/.local/bin"

log "apt packages"
sudo apt-get update -qq
sudo apt-get install -y build-essential cmake pkg-config python3-dev python3-pip python3-venv \
  ripgrep tmux btop ttyd unzip zip fd-find fzf tree sqlite3 ca-certificates curl gnupg

log "docker"
if ! command -v docker >/dev/null; then
  codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  printf 'Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n' \
    "$codename" "$(dpkg --print-architecture)" | sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null
  sudo apt-get update -qq
  if ! sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    echo "WARNING: Docker's repo has no packages for $codename; falling back to Ubuntu's docker.io"
    sudo rm -f /etc/apt/sources.list.d/docker.sources
    sudo apt-get update -qq
    sudo apt-get install -y docker.io docker-compose-v2
  fi
fi
sudo usermod -aG docker "$USER" # takes effect on next login

log "mise + toolchains"
command -v mise >/dev/null || curl -fsSL https://mise.run | sh
mise use -g node@24 python@3.14 aws-cli@latest kubectl@latest eksctl@latest gh@latest glab@latest
# npm globals go to ~/.local (stable across node upgrades; its bin dir is already on PATH).
# Without this they land inside mise's per-version node directory and vanish on a node upgrade.
# Note: this writes ~/.npmrc; if you later replace ~/.npmrc, re-run this line.
npm config set prefix "$HOME/.local"

log "bun, uv"
[ -x "$HOME/.bun/bin/bun" ] || curl -fsSL https://bun.sh/install | bash
command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh

log "shell PATH"
marker="# >>> vps tools >>>"
block='# >>> vps tools >>>
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.opencode/bin:$PATH"
# mise shims first so per-project mise.toml versions win
export PATH="$HOME/.local/share/mise/shims:$PATH"
# <<< vps tools <<<'
for f in "$HOME/.profile" "$HOME/.bashrc"; do
  touch "$f"
  grep -qF "$marker" "$f" || printf '\n%s\n' "$block" >>"$f"
done

log "AI CLIs"
command -v claude >/dev/null || curl -fsSL https://claude.ai/install.sh | bash
[ -x "$HOME/.opencode/bin/opencode" ] || curl -fsSL https://opencode.ai/install | bash
command -v codex >/dev/null || npm install -g @openai/codex
command -v pi >/dev/null || npm install -g @earendil-works/pi-coding-agent
command -v t3 >/dev/null || npm install -g t3@nightly

log "installed versions"
version_of() {
  case "$1" in
    kubectl) kubectl version --client 2>&1 ;;
    eksctl) eksctl version 2>&1 ;;
    tmux) tmux -V 2>&1 ;;
    *) "$1" --version 2>&1 ;;
  esac | head -1
}
for c in git docker node npm python3 aws kubectl eksctl gh glab bun uv rg tmux claude opencode codex pi t3; do
  printf '%-10s %s\n' "$c" "$(version_of "$c" || true)"
done
log "done. Log out and back in so the docker group and PATH apply."
