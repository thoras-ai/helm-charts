# CLAUDE.md

Two Helm charts: `charts/thoras/` installs the Thoras AI platform onto a cluster
you want to observe, and `charts/thoras-console/` installs a self-hosted console
for those clusters to report into.

## Repository Overview

This is the official Helm Charts repository for Thoras AI, an ML-powered platform that helps SRE teams view the future of their Kubernetes workloads.

`charts/thoras` installs the complete Thoras platform onto Kubernetes clusters. `charts/thoras-console` is a separate install running the console dashboard, `console-api`, a config-controller and an optional bundled TimescaleDB. The two charts are independent and may share a namespace, so resource and template names must not collide.

The console exposes two hostnames that are not interchangeable: the dashboard serves browsers and proxies the API for them, while `console-api` has its own Ingress because tenant clusters sync to it directly and the dashboard refuses ingest on its browser-facing hostname.

Both charts are published, each released when its own `Chart.yaml` version changes. A version bump cuts a release on merge, so it goes in a release PR of its own rather than inside a feature PR. `release.yml` lists the charts explicitly rather than discovering `charts/*`, so adding a chart means adding a version check and a `helm package` line there.

## Architecture

### `charts/thoras`

The Thoras platform consists of multiple interconnected components deployed as Kubernetes resources:

#### Core Components

- **Thoras Operator**: Singleton operator managing the platform lifecycle
- **Thoras API Server V2**: Main API service with configurable resource limits and caching
- **Metrics Collector**: Collects and stores metrics data backed by TimescaleDB plus a blob-service for large-object storage
- **Dashboard**: Web UI for visualization and management, fronted by an oauth2-proxy sidecar (htpasswd or OIDC)
- **Forecast Worker**: Handles ML-powered forecasting workloads
- **Worker**: Background worker for cost refresh, monitors, and reconciliation jobs
- **Config Controller**: Leader-elected controller that seeds credentials into `thoras-config-controller`, migrates pre-5.0 legacy Secrets, and drives dependency-ordered rollouts when watched Secrets change

#### Optional Components

- **Monitor**: Platform monitoring and alerting capabilities

#### Custom Resources

The chart includes Custom Resource Definitions (CRDs) for:

- AI Scale Targets (`aiscaletarget.yaml`)
- Cluster AI Scale Template (`clusteraiscaletemplate.yaml`)
- DaemonSet Autoscaler (`daemonsetautoscaler.yaml`)

### `charts/thoras-console`

- **Dashboard**: The same `thoras-dashboard-v2` image as the `thoras` chart, served by nginx. It proxies `/api/v1/` to `console-api` for browsers, deny-by-default, and refuses `ingest/` and `hook/`
- **console-api**: The console API. Serves the dashboard, receives ingest from tenant clusters on its own Ingress, and registers clusters that join with the shared secret. Prometheus metrics on a separate port (9104), off the ingress-published one
- **Config Controller**: The `config-controller` binary from the `console-api` image. Generates any credential not supplied — local admin password, database password and DSN, cluster-join secret — into `thoras-console-config-controller`, and rolls dependent workloads when they change
- **Bundled TimescaleDB**: Evaluation-only StatefulSet, the default when no external database is configured. Its volume-template labels must never change: Kubernetes forbids editing them in place, so any change fails the upgrade

Operators sign in with a local admin password by default (`auth.mode: local`), or through OIDC (`oidc`, `both`). Single-organization mode is on by default; cluster self-registration (`consoleApi.clusterJoin`) is off.

## Common Development Tasks

### Testing

Run Helm unit tests for both charts, as CI does:

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest.git
helm unittest ./charts/thoras --chart-tests-path ./charts/thoras/tests
helm unittest ./charts/thoras-console --chart-tests-path ./charts/thoras-console/tests
```

Lint both charts, as CI does:

```bash
helm lint ./charts/thoras
helm lint ./charts/thoras-console
```

### Chart Installation

Add the Thoras Helm repository:

```bash
helm repo add thoras https://thoras-ai.github.io/helm-charts
helm repo update
```

Install with minimum configuration:

```bash
helm install my-thoras-release thoras/thoras -n thoras --create-namespace -f ./values.yaml
```

Install the console, with the bundled database and a generated admin password:

```bash
helm install thoras-console thoras/thoras-console -n thoras-console --create-namespace \
  --set imageCredentials.password=$(cat thoras_license.txt)
```

### Version Management

| Chart | Chart version | App version |
| --- | --- | --- |
| `thoras` | `charts/thoras/Chart.yaml` | `thorasVersion` in `charts/thoras/values.yaml` |
| `thoras-console` | `charts/thoras-console/Chart.yaml` | `consoleVersion` in `charts/thoras-console/values.yaml` (the dashboard tag follows it unless `consoleDashboard.imageTag` is set) |

Both app versions are platform release tags, such as `4.123.0`, and never `thoras` chart versions.

- Merging a `Chart.yaml` version change releases that chart. Bump versions only in a release PR: the chart version, the app version and the README Version and AppVersion badges together, numbered by semver for what changed.

## File Structure

```
charts/thoras/
├── Chart.yaml              # Chart metadata and version
├── values.yaml             # Default configuration values
├── README.md               # User-facing chart documentation
├── UPGRADE.md              # Breaking-change migration notes
├── files/                  # Static assets bundled into ConfigMaps (e.g. oauth2-proxy sign-in template)
├── templates/              # Kubernetes manifests
│   ├── NOTES.txt                       # Post-install notes rendered by `helm install`
│   ├── _config-data.tpl                # Shared ConfigMap data payloads (hashed for checksum/config annotations)
│   ├── _helpers.tpl                    # Chart-wide template helpers, incl. thoras.secretPlan
│   ├── api-client-secret.yaml          # Legacy migration source, gated by featureFlags.enableLegacySecretSeeding
│   ├── registry-secret.yaml            # Image-pull Secret
│   ├── resource-quota.yaml             # Optional namespace ResourceQuota
│   ├── thoras-helm-values-secret.yaml  # Deterministic Secret holding pinned values
│   ├── api-server-v2/                  # API server
│   ├── collector/                      # Metrics storage (TimescaleDB + blob-service)
│   ├── config-controller/              # Config controller (seeds Secrets, drives rollouts)
│   ├── crd/                            # Custom Resource Definitions
│   ├── dashboard/                      # Dashboard UI + oauth2-proxy sidecar
│   ├── forecast-worker/                # Forecast worker
│   ├── monitor/                        # Monitoring (optional)
│   ├── operator/                       # Operator + webhook cert management
│   └── worker/                         # Background worker
└── tests/                              # Helm unit tests with snapshots

charts/thoras-console/
├── Chart.yaml              # Chart metadata and version
├── values.yaml             # Default configuration values
├── README.md               # User-facing chart documentation
├── templates/
│   ├── NOTES.txt                       # Post-install notes rendered by `helm install`
│   ├── _config-data.tpl                # Dashboard nginx config, hashed for checksum/config
│   ├── _helpers.tpl                    # Chart-wide helpers, prefixed thoras-console.
│   ├── helm-values-secret.yaml         # Deterministic Secret holding pinned values
│   ├── registry-secret.yaml            # Image-pull Secret
│   ├── config-controller/              # Credential generation and dependent rollouts
│   ├── console-api/                    # API workload, plus its own Ingress for ingest
│   ├── dashboard/                      # Web UI: nginx serving the SPA and proxying the API
│   └── database/                       # Bundled TimescaleDB (evaluation only)
└── tests/                              # Helm unit tests with snapshots
```

## Configuration

`charts/thoras` is configured through `values.yaml` with these key sections:

- **Global settings**: Image credentials, resource quotas, logging
- **Component-specific configs**: Each component has dedicated configuration blocks
- **RBAC**: Configurable namespace scoping vs cluster-wide permissions
- **Persistence**: Optional storage configuration for metrics collector
- **Monitoring**: Slack integration and Prometheus metrics

`charts/thoras-console`'s key sections:

- **`auth`**: Sign-in mode (`local`, `oidc`, `both`), the local admin, and OIDC — both what console-api accepts and the dashboard's own client
- **`consoleApi.singleOrg`, `consoleApi.clusterJoin`**: The implicit organization, and cluster self-registration (which requires it)
- **`bundledDatabase` / `externalDatabase`**: Exactly one database; configuring `externalDatabase` switches off the bundled one
- **`consoleDashboard.ingress`, `consoleApi.ingress`**: The two hostnames — browsers, and tenant-cluster ingest

## Git Commits

Follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).

- Format: `<type>[scope][!]: <description>`.
- **Accepted types** (lowercase, do not invent new ones):
  `feat`, `fix`, `docs`, `chore`, `refactor`, `build`, `ci`, `test`.
- Additional house rules (on top of the spec):
  - Subject in imperative mood, lowercase first letter, no trailing period.
  - Subject ≤72 characters.
  - Optional body/footers follow a blank line.

## Comments

Keep comments concise and forward-looking. Write for the next reader of the
chart, not for the review of the PR that added them.

- Explain non-obvious constraints, footguns, and TODOs.
- Skip history, reasoning narratives, issue numbers, and comparisons to
  approaches not taken.
- Do not restate what the code, values, or assertions already say.
- One line is usually enough; multi-line blocks need to earn it.

## CI/CD Pipeline

- **CI**: Lints and unit-tests both charts, and runs pre-commit hooks on PRs
- **Release**: Publishes each chart whose `Chart.yaml` version changed in the merged commit. Platform release notes (posted to Slack) are generated only for `thoras` releases
- Uses GitHub Actions with chart-releaser for automated releases

## Registry and Images

All container images are hosted at `us-east4-docker.pkg.dev/thoras-registry/platform` and require authentication via license key in the `imageCredentials.password` field.
