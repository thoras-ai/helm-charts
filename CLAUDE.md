# CLAUDE.md

Single Helm chart (`charts/thoras/`) that installs the Thoras AI platform onto
Kubernetes clusters.

## Repository Overview

This is the official Helm Charts repository for Thoras AI, an ML-powered platform that helps SRE teams view the future of their Kubernetes workloads. The repository contains a single Helm chart that installs the complete Thoras platform onto Kubernetes clusters.

## Architecture

The Thoras platform consists of multiple interconnected components deployed as Kubernetes resources:

### Core Components

- **Thoras Operator**: Singleton operator managing the platform lifecycle
- **Thoras API Server V2**: Main API service with configurable resource limits and caching
- **Metrics Collector**: Collects and stores metrics data backed by TimescaleDB plus a blob-service for large-object storage
- **Dashboard**: Web UI for visualization and management, fronted by an oauth2-proxy sidecar (htpasswd or OIDC)
- **Forecast Worker**: Handles ML-powered forecasting workloads
- **Worker**: Background worker for cost refresh, monitors, and reconciliation jobs
- **Config Controller**: Leader-elected controller that seeds credentials into `thoras-config-controller`, migrates pre-5.0 legacy Secrets, and drives dependency-ordered rollouts when watched Secrets change

### Optional Components

- **Monitor**: Platform monitoring and alerting capabilities

### Custom Resources

The chart includes Custom Resource Definitions (CRDs) for:

- AI Scale Targets (`aiscaletarget.yaml`)
- Cluster AI Scale Template (`clusteraiscaletemplate.yaml`)
- DaemonSet Autoscaler (`daemonsetautoscaler.yaml`)

## Common Development Tasks

### Testing

Run Helm unit tests:

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest.git
helm unittest ./charts/thoras --chart-tests-path ./charts/thoras/tests
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

### Version Management

- Chart version is managed in `charts/thoras/Chart.yaml`
- App version (thorasVersion) is managed in `charts/thoras/values.yaml`
- The CI/CD pipeline automatically releases new chart versions when `Chart.yaml` version is bumped

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
│   ├── api-client-secret.yaml          # Legacy migration source, gated by legacySecretSeeding
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
```

## Configuration

The chart is configured through `values.yaml` with these key sections:

- **Global settings**: Image credentials, resource quotas, logging
- **Component-specific configs**: Each component has dedicated configuration blocks
- **RBAC**: Configurable namespace scoping vs cluster-wide permissions
- **Persistence**: Optional storage configuration for metrics collector
- **Monitoring**: Slack integration and Prometheus metrics

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

- **CI**: Runs Helm unit tests and pre-commit hooks on PRs
- **Release**: Automatically publishes chart releases when version is bumped in `Chart.yaml`
- Uses GitHub Actions with chart-releaser for automated releases

## Registry and Images

All container images are hosted at `us-east4-docker.pkg.dev/thoras-registry/platform` and require authentication via license key in the `imageCredentials.password` field.
