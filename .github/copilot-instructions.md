# Copilot Instructions for `ds-cluster`

## Build, test, and lint commands

This repository is infrastructure-only (Kubernetes manifests + provisioning automation).  
There is no repo-local unit test suite or lint target (no `Makefile`, no language package manifest, no CI workflow files in this repo).

Use the existing deployment/validation commands:

- Full bootstrap + deploy (recommended for fresh hosts):
  ```bash
  chmod +x install-infrastructure.sh
  ./install-infrastructure.sh
  # non-interactive:
  ./install-infrastructure.sh --yes
  ```
- Ansible deployment path:
  ```bash
  ansible-playbook ansible/deploy.yml
  ```
- Apply a single infrastructure component (single-target equivalent):
  ```bash
  kubectl apply -f deployments/<component>.yaml
  # example
  kubectl apply -f deployments/postgres.yaml
  ```
- Validate a single deployed component:
  ```bash
  kubectl wait --for=condition=ready pod -l app=<app-label> -n infrastructure --timeout=180s
  # example
  kubectl wait --for=condition=ready pod -l app=postgres -n infrastructure --timeout=180s
  ```
- Inspect current platform status:
  ```bash
  kubectl get pods -n infrastructure
  ```

## High-level architecture

- This repo owns **platform infrastructure** on a K3s cluster; application workloads/manifests are owned by a separate application repository.
- Provisioning has two supported paths:
  - `install-infrastructure.sh`: installs host prerequisites (Java/Maven/Node/Docker/Ansible/K3s/Helm/Longhorn), then deploys infrastructure.
  - `ansible/deploy.yml`: applies manifests from `deployments/` with readiness waits.
- Deployment is intentionally staged:
  1. Data layer: `postgres`, `kafka`/`zookeeper`, `redis`
  2. Platform layer: `keycloak`, `monitoring`, `elk`, `jenkins`, `sonarqube`, `nexus`, `gitlab`, `ingress`
  3. GitOps layer: ArgoCD via Helm
- North-south traffic uses Nginx Ingress with host-based routes and one shared TLS secret (`swirlit-dev-tls`) for platform domains.
- Monitoring/logging wiring is cross-namespace and service-DNS based:
  - Prometheus scrapes application services in the `application` namespace.
  - Logstash ingests TCP logs and Kafka topics, writes to Elasticsearch, and Kibana reads from Elasticsearch.

## Key repository conventions

- **Namespace convention:** manifests target the `infrastructure` namespace by default. Keep new infrastructure resources there unless intentionally redesigning namespace boundaries.
- **Deployment ordering matters:** keep data stores deployed before dependent services (e.g., Keycloak/Postgres, ELK dependencies), then ingress/platform, then ArgoCD.
- **Service-name DNS convention:** manifests use in-cluster FQDNs like `<service>.infrastructure.svc.cluster.local`; service renames require updating dependent env/config values across files.
- **Ingress/TLS coupling:** if adding/changing public platform hosts, update `deployments/ingress.yaml` host rules and ensure the TLS secret covers the same hostnames.
- **Storage convention:** stateful components use PVCs and Longhorn (`storageClassName: longhorn`) with mostly single-replica defaults.
- **Secret pattern in manifests:** credentials are currently defined directly in YAML (mix of `data` base64 and `stringData`). Follow existing pattern when editing, and preserve key names consumed by deployments.
- **Readiness label convention:** waits rely on `app` labels (`kubectl wait -l app=...`); keep label/selector alignment when modifying workloads.
- **Ansible scope convention:** `ansible/deploy.yml` runs locally (`hosts: localhost`, `connection: local`) and supports namespace override via `infra_ns`.
