#!/bin/bash
set -euo pipefail

# This joins only this host; platform installation belongs to the bootstrap host.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K3S_ENROLLMENT_ROLE=control-plane exec "$SCRIPT_DIR/install-k3s-worker.sh" "$@"
