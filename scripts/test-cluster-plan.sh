#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/cluster-plan.sh
source "$SCRIPT_DIR/lib/cluster-plan.sh"
# shellcheck source=lib/installer-prompts.sh
source "$SCRIPT_DIR/lib/installer-prompts.sh"

error() { printf '%s\n' "$*" >&2; exit 1; }
info() { :; }
warn() { :; }
ask_with_default() { installer_prompt_yes_no "$1" "$2" "$AUTO_APPROVE"; }
cluster_plan_inventory() { printf '%s' "${TEST_INVENTORY:-}"; }

plan() (
    AUTO_APPROVE=true
    CONTROL_PLANE_COUNT="${1:-}"
    CLUSTER_NODE_COUNT="${2:-}"
    CONTROL_PLANE_SCHEDULABLE="${3:-}"
    configure_cluster_topology_plan
    printf '%s:%s:%s:%s:%s\n' "$CONTROL_PLANE_COUNT" "$PLANNED_WORKER_COUNT" \
        "$CONTROL_PLANES_TO_ADD" "$WORKERS_TO_ADD" "$CONTROL_PLANE_SCHEDULABLE"
)
expect() {
    local expected="$1"; shift
    local actual
    actual="$("$@")"
    [[ "$actual" == "$expected" ]] || error "Expected $expected, got $actual"
}
reject() {
    if "$@" >/dev/null 2>&1; then error "Invalid topology was accepted: $*"; fi
}

unset K3S_WORKER_HOSTS K3S_WORKER_IPS K3S_CONTROL_PLANE_HOSTS K3S_CONTROL_PLANE_IPS
expect '1:0:0:0:true' plan
expect '3:4:2:4:false' plan 3 7
expect '5:2:4:2:true' plan 5 7 true
expect '3:0:2:0:true' plan 3 3
reject plan 2 4
reject plan 0 4
reject plan 03 4
reject plan 3 2
reject plan 3 3 false
reject plan 3 7 invalid
reject plan '3+2' 7
reject plan 99999999999999999999 7
TEST_INVENTORY=$'cp1\tcontrol-plane\ncp2\tcontrol-plane\ncp3\tcontrol-plane\nw1\tworker\n'
expect '3:1:0:0:false' plan
expect '5:3:2:2:false' plan 5 8
reject plan 1 4
reject plan 3 3
TEST_INVENTORY=$'cp1\tcontrol-plane\ncp2\tcontrol-plane\n'
expect '3:0:1:0:true' plan
unset TEST_INVENTORY
K3S_CONTROL_PLANE_IPS=10.0.0.2,10.0.0.3
K3S_WORKER_IPS=10.0.0.4,10.0.0.5
expect '3:2:2:2:false' plan
reject plan 1 5
K3S_CONTROL_PLANE_IPS=10.0.0.2,10.0.0.2
reject plan 3 5
K3S_CONTROL_PLANE_IPS=10.0.0.2,
reject plan 3 5
unset K3S_CONTROL_PLANE_IPS K3S_WORKER_IPS
(
    AUTO_APPROVE=false
    CONTROL_PLANE_COUNT='' CLUSTER_NODE_COUNT='' CONTROL_PLANE_SCHEDULABLE=''
    configure_cluster_topology_plan <<< $'2\n3\n2\n7\nn'
    [[ "$CONTROL_PLANE_COUNT:$PLANNED_WORKER_COUNT:$CONTROL_PLANE_SCHEDULABLE" == 3:4:false ]]
) || error 'Interactive retry or NoSchedule selection failed.'
printf '[PASS] Cluster topology planning: odd quorum, counts, reruns, target validation, scheduling, interactive retries.\n'
