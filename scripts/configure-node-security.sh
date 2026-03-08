#!/bin/bash
set -euo pipefail

APPLY=false
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=true ;;
    *) echo "Unknown option: $arg"; echo "Usage: $0 [--apply]"; exit 1 ;;
  esac
done

info() { echo -e "\033[0;32m[INFO]\033[0m  $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
err()  { echo -e "\033[0;31m[ERROR]\033[0m $*"; exit 1; }

command -v sudo >/dev/null 2>&1 || err "sudo is required"
command -v ufw >/dev/null 2>&1 || { info "Installing ufw..."; sudo apt-get update -qq && sudo apt-get install -y -qq ufw >/dev/null; }

if [[ "$APPLY" != "true" ]]; then
  info "Audit mode (no changes). Run with --apply to enforce rules."
  sudo ufw status verbose || true
  exit 0
fi

info "Configuring UFW baseline..."
sudo sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
sudo ufw --force reset >/dev/null
sudo ufw default deny incoming >/dev/null
sudo ufw default allow outgoing >/dev/null

info "Allowing required inbound ports..."
sudo ufw allow OpenSSH >/dev/null
sudo ufw allow 80/tcp >/dev/null
sudo ufw allow 443/tcp >/dev/null
sudo ufw allow 6443/tcp >/dev/null
sudo ufw allow 8472/udp >/dev/null
sudo ufw allow 10250/tcp >/dev/null

if ip link show cni0 >/dev/null 2>&1; then
  sudo ufw allow in on cni0 >/dev/null
fi
if ip link show flannel.1 >/dev/null 2>&1; then
  sudo ufw allow in on flannel.1 >/dev/null
fi

sudo ufw --force enable >/dev/null
info "UFW enabled with Kubernetes-safe baseline."
sudo ufw status verbose
