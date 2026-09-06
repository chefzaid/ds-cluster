#!/usr/bin/env bash
# Exercise reconciliation through its CLI without contacting a cluster.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOPOLOGY_SCRIPT="$SCRIPT_DIR/reconcile-cluster-topology.sh"
unset CLUSTER_NODE_COUNT CONTROL_PLANE_COUNT CONTROL_PLANE_SCHEDULABLE

command -v jq >/dev/null 2>&1 || { printf 'jq is required\n' >&2; exit 1; }

kubectl() {
    case "$*" in
        cluster-info|'get namespace infra') return 0 ;;
        'get nodes -o json') printf '%s\n' "$MOCK_NODES_JSON" ;;
        '-n infra get configmap bm-cluster-topology '*) printf '%s' "${MOCK_STORED_MODE:-}" ;;
        '-n longhorn-system get settings.longhorn.io default-replica-count')
            [[ "${MOCK_LONGHORN:-false}" == true ]]
            ;;
        '-n longhorn-system get settings.longhorn.io default-replica-count -o '*) printf '1' ;;
        '-n longhorn-system get configmap '*) return 1 ;;
        '-n longhorn-system get volumes.longhorn.io -o json') printf '{"items":[]}' ;;
        'get storageclass longhorn '*) return 1 ;;
        'taint nodes '*)
            printf 'MOCK %s\n' "$*" >&3
            return "${MOCK_TAINT_EXIT:-0}"
            ;;
        'label nodes '*|'-n longhorn-system patch '*|'-n infra create configmap '*)
            printf 'MOCK %s\n' "$*" >&3
            ;;
        'apply -f -') while IFS= read -r _line; do :; done ;;
        *) printf 'Unexpected kubectl invocation: %s\n' "$*" >&2; return 99 ;;
    esac
}
export -f kubectl

nodes() {
    local cp_count="$1" workers="$2" ready_cps="${3:-$1}" ready_workers="${4:-$2}" taints="${5:-none}"
    MOCK_NODES_JSON="$(jq -cn \
        --argjson cps "$cp_count" --argjson workers "$workers" \
        --argjson readyCps "$ready_cps" --argjson readyWorkers "$ready_workers" \
        --arg taints "$taints" '
        {items: (
            [range(0; $cps) | . as $index |
                {metadata: {name: ("cp-" + tostring), labels: {"node-role.kubernetes.io/control-plane": "true"}},
                 status: {conditions: [{type: "Ready", status: (if . < $readyCps then "True" else "False" end)}]},
                 spec: {taints: (
                    if $taints == "all" or ($taints == "mixed" and $index == 0) then
                        [{key: "node-role.kubernetes.io/control-plane", effect: "NoSchedule"}]
                    elif $taints == "legacy" then
                        [{key: "node-role.kubernetes.io/master", effect: "NoSchedule"},
                         {key: "maintenance", effect: "NoExecute"}]
                    else [] end)}}] +
            [range(0; $workers) |
                {metadata: {name: ("worker-" + tostring), labels: {}},
                 status: {conditions: [{type: "Ready", status: (if . < $readyWorkers then "True" else "False" end)}]},
                 spec: {}}])}')"
    export MOCK_NODES_JSON
    unset MOCK_STORED_MODE MOCK_LONGHORN MOCK_TAINT_EXIT
}

run_success() {
    if ! TEST_OUTPUT="$(bash "$TOPOLOGY_SCRIPT" "$@" 3>&1 2>&1)"; then
        printf 'Expected success: %s\n%s\n' "$*" "$TEST_OUTPUT" >&2
        exit 1
    fi
}

run_failure() {
    if TEST_OUTPUT="$(bash "$TOPOLOGY_SCRIPT" "$@" 3>&1 2>&1)"; then
        printf 'Expected failure: %s\n%s\n' "$*" "$TEST_OUTPUT" >&2
        exit 1
    fi
    if [[ "$TEST_OUTPUT" == *'MOCK '* ]]; then
        printf 'Validation failure changed cluster state:\n%s\n' "$TEST_OUTPUT" >&2
        exit 1
    fi
}

assert_output() {
    [[ "$TEST_OUTPUT" == *"$1"* ]] || {
        printf 'Expected output to contain %s:\n%s\n' "$1" "$TEST_OUTPUT" >&2
        exit 1
    }
}

for control_planes in 1 3 5; do
    nodes "$control_planes" 0
    run_success --expected-node-count "$control_planes" --expected-control-plane-count "$control_planes" --control-plane-schedulable true
    assert_output "--from-literal=controlPlaneCount=$control_planes"
    assert_output '--from-literal=workerCount=0'
    assert_output '--from-literal=longhornReplicaCount=1'
    run_failure --control-plane-schedulable false
    assert_output 'Controller-only mode requires at least one Ready worker'
done

for invalid_count in 0 2 4 invalid; do
    run_failure --expected-control-plane-count "$invalid_count"
    assert_output 'must be a positive odd integer'
done
run_failure --expected-node-count 2 --expected-control-plane-count 3
assert_output 'cannot exceed the expected node count'

nodes 3 2
export MOCK_LONGHORN=true
run_success --expected-node-count 5 --expected-control-plane-count 3 --control-plane-schedulable false
assert_output 'taint nodes cp-0 cp-1 cp-2 node-role.kubernetes.io/control-plane:NoSchedule --overwrite'
assert_output '--from-literal=readyControlPlaneCount=3'
assert_output '--from-literal=readyWorkerCount=2'
assert_output '--from-literal=longhornReplicaCount=2'
for node in cp-0 cp-1 cp-2; do
    assert_output "patch nodes.longhorn.io $node --type=merge -p {\"spec\":{\"allowScheduling\":false,\"evictionRequested\":true}}"
done
run_failure --expected-node-count 5 --expected-control-plane-count 1 --control-plane-schedulable false
assert_output 'Expected 1 registered control-plane nodes, but found 3'

nodes 3 3 3 2
run_failure --expected-node-count 5 --expected-control-plane-count 3 --control-plane-schedulable false
assert_output 'Expected 5 registered nodes, but found 6 (5 Ready)'
run_failure --expected-node-count 6 --control-plane-schedulable false
assert_output 'Expected 6 Ready nodes, but found 5'

nodes 3 2 2 2
run_failure --expected-control-plane-count 3 --control-plane-schedulable false
assert_output 'Expected 3 Ready control-plane nodes, but found 2'

nodes 3 2 3 0
run_failure --control-plane-schedulable false
assert_output 'Controller-only mode requires at least one Ready worker'
export MOCK_LONGHORN=true
run_success --control-plane-schedulable true
assert_output '"allowScheduling":false,"evictionRequested":false'
assert_output '--from-literal=workerCount=2'
assert_output '--from-literal=readyWorkerCount=0'

nodes 3 2 3 2 mixed
run_failure --control-plane-schedulable preserve
assert_output 'Control-plane scheduling is mixed'
export MOCK_STORED_MODE=false
run_success --control-plane-schedulable preserve
assert_output '--from-literal=controlPlaneSchedulable=false'

nodes 3 2 3 2 all
run_success --control-plane-schedulable preserve
assert_output '--from-literal=controlPlaneSchedulable=false'

nodes 3 2 3 2 legacy
run_success --control-plane-schedulable true
for node in cp-0 cp-1 cp-2; do
    assert_output "taint nodes $node node-role.kubernetes.io/master:NoSchedule-"
done
[[ "$TEST_OUTPUT" != *maintenance* ]] || { printf 'Unrelated taint was removed\n' >&2; exit 1; }
export MOCK_TAINT_EXIT=1
if TEST_OUTPUT="$(bash "$TOPOLOGY_SCRIPT" --control-plane-schedulable true 3>&1 2>&1)"; then
    printf 'Taint removal errors must fail reconciliation\n' >&2
    exit 1
fi
[[ "$TEST_OUTPUT" != *'create configmap'* ]] || { printf 'Failed taint change was persisted\n' >&2; exit 1; }

printf 'Topology CLI tests passed (1/3/5 control planes, quorum inputs, role/readiness mismatches, scheduling and storage).\n'
