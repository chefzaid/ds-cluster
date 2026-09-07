# Trivy remediation — 2026-09-07

This change updates the platform's desired state and fixes application images
in their owning repositories. The evidence below covers locally built images
and manifest dry runs. The running cluster continues reporting its current
images until the corresponding releases and reconciliations finish.

## Verification method

Replacement images were resolved from their upstream registries and pinned by
digest. Trivy 0.74.0 scanned the Linux/amd64 images against the cluster's Trivy
server. The downloaded scanner binary was checked against the upstream release
checksum. The comparisons below use fresh scans of both image versions, not
cached Kubernetes report totals. Counts are package occurrences, not distinct
CVEs; the same CVE can appear in several binaries. No findings were suppressed.

## Application images

| Repository | Change | Final image scan |
| --- | --- | --- |
| DevApp | Spring Boot 4.1.1, Tomcat 11.0.25, LZ4 1.11.1 and Alpine package updates | User and order images: zero vulnerabilities |
| Indezy | Spring Boot 4.1.1, Tomcat 11.0.25, NGINX 1.30.4 and Alpine package updates | Server and web images: zero vulnerabilities |
| Thoughty | Pinned Node 22.23.2, Alpine package updates, `qs` 6.16.0, npm/Yarn removed from runtime | Server/worker image: zero vulnerabilities |
| Website | Pinned Node 24.19.0 on Alpine, package updates, npm/Yarn removed from runtime | Website image: zero vulnerabilities |

Thoughty's production migration hook now executes `node dist/scripts/migrate.js`
directly. Its AWS CLI backup uploader is pinned to the scanned 2.36.40 image,
which also reported zero vulnerabilities. Application-owned observability jobs
use the same scanned curl image as the platform.

Spring Boot supplies the patched Jackson, Netty, Log4j and PostgreSQL JDBC
versions. Tomcat and DevApp's Kafka LZ4 dependency still require explicit
overrides. Relevant upstream references are the
[Tomcat security advisories](https://tomcat.apache.org/security-11.html),
[Spring Boot 4.1.1 dependency BOM](https://repo.maven.apache.org/maven2/org/springframework/boot/spring-boot-dependencies/4.1.1/spring-boot-dependencies-4.1.1.pom)
and [pgJDBC changelog](https://jdbc.postgresql.org/changelogs/).

## Platform image comparisons

| Component | Replacement | Before critical / high | After critical / high |
| --- | --- | ---: | ---: |
| OAuth2 Proxy | 7.15.4 | 3 / 38 | 0 / 1 |
| Elasticsearch | 9.4.6 | 0 / 101 | 0 / 40 |
| Kibana | 9.4.6 | 2 / 85 | 0 / 9 |
| Kibana authentication sidecar | NGINX 1.30.4 Alpine | 3 / 39 | 0 / 7 |
| Logstash | 9.4.6 | 2 / 68 | 0 / 15 |
| Filebeat | 9.4.6 Wolfi | 1 / 56 | 0 / 0 |
| Grafana | 13.2.1 | 5 / 179 | 3 / 159 |
| Keycloak | 26.7.3 | 0 / 4 | 0 / 2 |
| Homepage | 2.2.0 | 1 / 13 | 1 / 12 |
| GitLab Runner | 19.3.1 | 5 / 48 | 2 / 40 |
| Redis | 8.10.0 Alpine | 3 / 79 | 0 / 8 |
| Argo CD | 3.5.2 | 5 / 107 | 5 / 107 |

Argo CD's patch reduces medium findings from 197 to 184. Its unused Dex
installation is disabled because `configs.cm.oidc.config` connects Argo CD
directly to Keycloak. The curl helper image was replaced throughout the platform
and applications; the replacement reports zero vulnerabilities. Redis retains
version 8.10.0 and its configured UID/GID 999. It has no persistent volume in
this repository, and the Alpine variant passed startup and PING checks.

Filebeat uses the official Wolfi variant because the standard 9.4.6 image
requires x86-64-v3 CPU features unavailable on this node. The Wolfi image
passed a read-only startup check and a fresh vulnerability scan.

Kibana's authentication sidecar uses the official NGINX image with its njs
module instead of carrying an ingress-controller binary. A non-root, read-only
container smoke test covered health, anonymous and forged-identity rejection,
session creation with a relative redirect, and existing-session forwarding.
Temporary NGINX paths are under `/tmp`; the sidecar drops all capabilities.

The K3s installer default advances to 1.36.4+k3s1, which updates containerd and
the local-path provisioner. Existing nodes require a separate upgrade.
The current release retains the same CoreDNS and metrics-server versions.

Upstream release information:

- [OAuth2 Proxy 7.15.4](https://github.com/oauth2-proxy/oauth2-proxy/releases/tag/v7.15.4)
- [Elastic release notes](https://www.elastic.co/docs/release-notes/elasticsearch)
- [Grafana 13.2.1](https://github.com/grafana/grafana/releases/tag/v13.2.1)
- [Keycloak 26.7.3](https://github.com/keycloak/keycloak/releases/tag/26.7.3)
- [Homepage 2.2.0](https://github.com/gethomepage/homepage/releases/tag/v2.2.0)
- [Argo CD 3.5.2](https://github.com/argoproj/argo-cd/releases/tag/v3.5.2)
- [K3s 1.36.4+k3s1](https://github.com/k3s-io/k3s/releases/tag/v1.36.4%2Bk3s1)

## Remaining work

The platform is not vulnerability-free. Several current upstream images still
bundle vulnerable OS packages or libraries even when a package-level fix exists.
Examples include gRPC 1.83.0 in OAuth2 Proxy, bundled Grafana plugins, Redis's
OpenSSL/setpriv packages and libraries inside Elastic images. Updated upstream
images or separately maintained and tested image rebuilds are needed to remove
those remaining findings.

Fresh candidate scans did not demonstrate a vulnerability-count improvement
for GitLab 19.3.1. PostgreSQL image candidates still contain numerous findings;
changing its base distribution also needs database collation and extension
review. MongoDB remains constrained to the compatible 7.0 line by the node's
kernel, as documented beside its image. No database major-version change is
part of this remediation.

Ingress NGINX, Longhorn/CSI, K3s system components, Vault, Trivy, External
Secrets, Prometheus, Alertmanager, Kafka, Kafka UI, SonarQube, DBGate and
Portainer retain findings. These must remain visible for follow-up against
supported upstream releases or replacement/rebuild plans. A fixed transitive
package version in a report does not prove that a compatible fixed vendor
image exists. In particular, the current Longhorn release still supplies the
vulnerable CSI provisioner; changing storage sidecars independently requires
Longhorn compatibility validation.

## Checks and delivery

Live rollout also exposed two causes of stale reporting. Trivy Operator reached
its old 512 MiB memory limit and repeatedly failed health probes; its allocation
is now 1 GiB. The configured ten-minute scan-job retention also exhausted the
two-job concurrency limit because the operator counts completed jobs. Automatic
job cleanup after report persistence is restored; report retention remains 24
hours. No vulnerability report filters or severity suppressions were added.

- DevApp: `mvn clean verify` passed, with 68 tests.
- Indezy: all 517 tests and SpotBugs passed using the documented CI setting
  `-Djacoco.haltOnFailure=false`. Unmodified coverage policy still reports
  70% branch coverage against an 80% requirement; strict `verify` fails that gate.
- Thoughty: all 836 tests passed; both Docker build paths and direct Node
  migration/worker entry-point checks passed.
- Website: all 33 tests passed both locally and inside the new runtime;
  both Docker build targets, generated CSP checks and a read-only container
  HTTP smoke test passed.
- Indezy web: production build, NGINX configuration and read-only container
  SPA/health smoke checks passed.
- Platform: all 49 repository validation checks passed. Both Helm charts
  rendered, Dex resources were absent from the Argo CD chart, and 91 platform
  resources passed Kubernetes server-side dry-run. All three application
  manifest sets also passed server-side dry-run; both Thoughty overlays render.

Publish each application's tested images through its existing release pipeline
and reconcile its own Argo CD application. Platform manifest updates use the
`bm-cluster` application; Argo CD Helm settings and the K3s version need the
repository's operator reconciliation/upgrade workflow. After rollout, verify
workload health and allow Trivy Operator to generate reports for the new image
digests. These local scans do not demonstrate that production has been remediated.
