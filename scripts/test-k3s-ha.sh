#!/usr/bin/env bash
# sudo is deliberately replaced below; these functions never invoke the host.
# shellcheck disable=SC2032
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=configure-k3s-ha.sh
source "$SCRIPT_DIR/configure-k3s-ha.sh"
TEST_DIR="$(mktemp -d /tmp/bm-ha-test.XXXXXX)"
trap 'rm -r -- "$TEST_DIR"' EXIT

systemctl() { [[ "$*" == 'cat k3s.service' && "$TEST_SERVER" == true ]]; }
sqlite3() { return 0; }
sudo() {
    printf '%s\n' "$*" >> "$TEST_DIR/calls"
    case "$*" in
        'test -d /var/lib/rancher/k3s/server/db/etcd/member') [[ "$TEST_ETCD" == true ]] ;;
        'test -f /var/lib/rancher/k3s/server/db/state.db') [[ "$TEST_SQLITE" == true ]] ;;
        grep*) [[ "$TEST_EXTERNAL" == true ]] ;;
        'install -d '*) : ;;
        'install -D '*) cp "${@: -2:1}" "$TEST_DIR/config" ;;
        sqlite3*integrity_check*) printf '%s\n' "$TEST_INTEGRITY" ;;
        sqlite3*) : ;;
        tar*) : ;;
        'systemctl restart k3s') TEST_ETCD=true ;;
        'k3s kubectl wait '*) : ;;
        *) printf 'Unexpected sudo call: %s\n' "$*" >&2; return 1 ;;
    esac
}
reset_case() {
    TEST_SERVER=false TEST_ETCD=false TEST_SQLITE=false TEST_EXTERNAL=false TEST_INTEGRITY=ok
    : > "$TEST_DIR/calls"
    rm -f -- "$TEST_DIR/config"
}
reject() {
    if (k3s_ha_prepare) >/dev/null 2>&1; then
        printf 'Unsafe datastore preparation succeeded.\n' >&2; exit 1
    fi
    [[ ! -f "$TEST_DIR/config" ]]
    if grep -q 'systemctl restart' "$TEST_DIR/calls"; then exit 1; fi
}

reset_case
k3s_ha_prepare >/dev/null
grep -q '^cluster-init: true$' "$TEST_DIR/config"
if grep -q 'systemctl restart' "$TEST_DIR/calls"; then exit 1; fi
reset_case
TEST_SERVER=true TEST_ETCD=true
k3s_ha_prepare >/dev/null
[[ ! -f "$TEST_DIR/config" ]]
reset_case
TEST_SERVER=true TEST_SQLITE=true
k3s_ha_prepare >/dev/null
grep -q '^cluster-init: true$' "$TEST_DIR/config"
awk '/sqlite3.*\.backup/ {backup=NR} /systemctl restart k3s/ {exit !(backup && backup < NR)}' "$TEST_DIR/calls"
grep -q 'server-config.tar.gz' "$TEST_DIR/calls"
grep -q 'systemctl restart k3s' "$TEST_DIR/calls"
reset_case
TEST_SERVER=true TEST_EXTERNAL=true TEST_SQLITE=true
reject
reset_case
TEST_SERVER=true
reject
reset_case
TEST_SERVER=true TEST_SQLITE=true TEST_INTEGRITY=corrupt
reject
printf '[PASS] Embedded etcd bootstrap: fresh init, existing membership, backed-up SQLite conversion, external/unknown/corrupt datastore rejection.\n'
