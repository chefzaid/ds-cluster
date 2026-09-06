#!/bin/bash
set -euo pipefail

# Keep bootstrap networking, SSH validation, and credential handling shared with
# worker enrollment. The control-plane role selects server joins and etcd ports.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K3S_ENROLLMENT_ROLE=control-plane exec "$SCRIPT_DIR/add-k3s-workers.sh" "$@"
