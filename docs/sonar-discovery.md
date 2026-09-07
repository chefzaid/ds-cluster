# Automatic Sonar analysis for apps

`sonar-apps-discovery` runs every 15 minutes in `infra`. It lists Deployments,
StatefulSets, DaemonSets, CronJobs, standalone Jobs and Pods in `apps`, follows
Argo CD tracking annotations to source repositories, and deduplicates components
of the same repository. Corporate/vendor software belongs in `corp`; Odoo is
outside the source-analysis scope. Container and dependency security scanning
continues through Trivy independently.

The controller accepts only the configured GitLab hosts and group. It provisions
missing Sonar projects, binds them to the existing `swirlit-gitlab` ALM integration,
and adds a protected, masked project analysis token to GitLab when absent. Private
GitLab repositories get private Sonar projects; it never makes repositories public.

Default-branch application pipelines run their Sonar job automatically. Namespace
discovery additionally requests analysis when no successful analysis exists or
when the last one is more than 24 hours old. It requests at most one pipeline per
run and defers while an application pipeline is active. API-triggered attempts
have a six-hour retry interval to avoid repeated work after failures. Logs report
unmapped workloads, unsupported sources and missing CI contracts; errors fail the
CronJob visibly without preventing other valid repositories from being reconciled.

## Application contract

Every application keeps its build/test/scanner settings in its own repository:

- `sonar-project.properties` declares `sonar.projectKey=<group>:<repository>`
  (replace each slash in the GitLab path with a colon), source paths and reports.
- `.sonar-auto.json` contains `{"version":1,"job":"02-quality","scanOnlyVariable":"SONAR_SCAN_ONLY"}`.
  Website uses `"job":"sonar"`.
- A default-branch pipeline with `SONAR_SCAN_ONLY=true` must run only compilation,
  tests/coverage and source analysis. Image packaging, publishing, deployment and
  version changes must be excluded by job rules. The declaration is a CI contract,
  not permission for the platform to modify repository code.
- The Sonar job consumes `SONAR_TOKEN` from GitLab and reports scanner submission
  failures as failed jobs. Quality findings can remain non-blocking for delivery.

Namespace discovery cannot infer arbitrary source build requirements. A new app
with no contract is provisioned in Sonar and reported as uncovered in the failed
discovery job until its repository adds these files and CI rules. There is no
central list of application names to update.

## Credentials and operation

`./scripts/configure-sonar-discovery.sh` provisions a dedicated GitLab group
Maintainer API token in Vault `infra/gitlab:sonar_discovery_api_token` without
changing project settings. `configure-gitlab-ci.sh` invokes it during setup.
External Secrets projects the credential into `infra`; Sonar administration uses
the existing Vault-backed admin token. The GitLab token lasts 364 days; rerunning
the configurator renews it within 30 days of expiry. Kubernetes permissions only
allow listing workloads in `apps` and Argo Applications in `infra`; application
Secrets and corporate workloads are not readable by this service account.

Inspect discovery and request an immediate run:

```sh
kubectl -n infra logs job/<discovery-job>
kubectl -n infra create job sonar-apps-manual --from=cronjob/sonar-apps-discovery
```

Check the resulting GitLab quality job and Sonar analysis timestamp; a successful
submission can precede the server's completed analysis. A failed quality gate is
an analysis result, not a failed scanner submission. Completed discovery Jobs have
a one-day TTL (one successful and two failed jobs retained); application artifacts
expire in seven days. The controller has no PVC, source checkout, build cache or
persistent data copy. Scan-only pipelines avoid image and release artifacts.

## Validation

`./scripts/test-sonar-discovery.sh` covers namespace exclusion, deduplication,
repository boundaries, privacy, scan-only triggers, active/recent work, missing
contracts and execution through ConfigMap symlinks. `validate-repository.sh` runs
these checks when Node and PyYAML are installed. Validate each app's pipeline with
GitLab CI Lint using both values of `SONAR_SCAN_ONLY`, and confirm that scan-only
jobs cannot publish or deploy. Each app also has `infra/scripts/test-quality.sh`
for successful submission, scanner failure and missing-token behavior.
