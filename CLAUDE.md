# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is the official Helm Charts repository for Thoras AI, an ML-powered platform that helps SRE teams view the future of their Kubernetes workloads. The repository contains a single Helm chart that installs the complete Thoras platform onto Kubernetes clusters.

## Architecture

The Thoras platform consists of multiple interconnected components deployed as Kubernetes resources:

### Core Components

- **Thoras Operator**: Singleton operator managing the platform lifecycle
- **Thoras API Server V2**: Main API service with configurable resource limits and caching
- **Metrics Collector**: Collects and stores metrics data with Elasticsearch and TimescaleDB backends
- **Dashboard**: Web UI for visualization and management
- **Forecast Worker**: Handles ML-powered forecasting workloads

### Optional Components

- **Agent**: DaemonSet for service map communications (opt-in)
- **Monitor**: Platform monitoring and alerting capabilities
- **Reasoning API**: Additional API services for ML reasoning

### Custom Resources

The chart includes Custom Resource Definitions (CRDs) for:

- AI Scale Targets (`aiscaletarget.yaml`)

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
├── templates/              # Kubernetes manifests
│   ├── agent/              # Agent DaemonSet and RBAC
│   ├── api-server-v2/      # API server deployment and service
│   ├── collector/          # Metrics collection components
│   ├── crd/                # Custom Resource Definitions
│   ├── dashboard/          # Dashboard deployment and config
│   ├── forecast-worker/    # Forecast worker deployment
│   ├── monitor/            # Monitoring components
│   ├── operator/           # Operator deployment and webhooks
│   └── reasoning-api/      # Reasoning API components
└── tests/                  # Helm unit tests with snapshots
```

## Configuration

The chart uses extensive configuration through `values.yaml` with these key sections:

- **Global settings**: Image credentials, resource quotas, logging
- **Component-specific configs**: Each component has dedicated configuration blocks
- **RBAC**: Configurable namespace scoping vs cluster-wide permissions
- **Persistence**: Optional storage configuration for metrics collector
- **Monitoring**: Slack integration and Prometheus metrics

## CI/CD Pipeline

- **CI**: Runs Helm unit tests and pre-commit hooks on PRs
- **Release**: Automatically publishes chart releases when version is bumped in `Chart.yaml`
- Uses GitHub Actions with chart-releaser for automated releases

## Registry and Images

All container images are hosted at `us-east4-docker.pkg.dev/thoras-registry/platform` and require authentication via license key in the `imageCredentials.password` field.
