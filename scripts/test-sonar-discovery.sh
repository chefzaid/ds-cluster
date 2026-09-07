#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
python3 - "$root/k8s/apps/sonar-apps-discovery.yaml" "$work/discovery.mjs" <<'PY'
import pathlib, sys, yaml
resources=list(yaml.safe_load_all(pathlib.Path(sys.argv[1]).read_text()))
config=next(r for r in resources if r['kind']=='ConfigMap')
pathlib.Path(sys.argv[2]).write_text(config['data']['discovery.mjs'])
PY
SONAR_DISCOVERY_MODULE="$work/discovery.mjs" node --test "$root/scripts/test-sonar-discovery.mjs"
