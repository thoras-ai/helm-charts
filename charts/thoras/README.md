# Thoras

Thoras is an ML-powered platform that helps SRE teams view the future of their Kubernetes workloads.

This Helm Chart installs [Thoras](https://www.thoras.ai) onto Kubernetes.

![Version: 5.0.0](https://img.shields.io/badge/Version-5.0.0-informational?style=flat-square) ![AppVersion: 4.119.0](https://img.shields.io/badge/AppVersion-4.119.0-informational?style=flat-square)

**Upgrading from 4.x?** See [Upgrading to chart 5.x](#upgrading-to-chart-5x). A single sentinel-guarded values-file rewrite is required; a helper script is provided.

# Installs

Using [Helm](https://helm.sh), you can easily install and test Thoras in a Kubernetes cluster by running the following:

#### Add Helm repo

First, add the repo if you haven't already done so:

```
helm repo add thoras https://thoras-ai.github.io/helm-charts
helm repo update
```

#### Minimum Config

```
# values.yaml
thorasLicenseKey: "<thoras license key>"

metricsCollector:
  persistence:
    enabled: false
```

#### Install Chart

Now let’s install Thoras with Helm! We recommend installing Thoras into the thoras namespace:

```
helm install \
  my-thoras-release \
  thoras/thoras \
  -n thoras \
  --create-namespace \
  -f ./values.yaml
```

# Managing credentials

Chart 5.0 collapses every credential into a single Kubernetes Secret:

- `thoras-credentials` (`Opaque`) — Timescale password + DSN, api-client
  secret, and any enabled Slack / cloud-sync keys.
- `thoras-secret-registry` (`kubernetes.io/dockerconfigjson`) — image-pull
  auth. Kept separate because Kubernetes requires
  `type: kubernetes.io/dockerconfigjson` for `imagePullSecrets` references.

Both Secrets are annotated `helm.sh/resource-policy: keep` and
`argocd.argoproj.io/sync-options: Prune=false` so an accidental
`helm uninstall` / `argocd app delete` never takes credentials with it.

Three modes are supported:

### 1. Chart-seeded (default)

Set `thorasLicenseKey` and, optionally, plaintext credentials
(`apiClientSecret.secret`, `metricsCollector.timescale.password`,
`slackWebhook.url`, `cloudSync.clusterKey`). The chart generates any values
you leave empty and preserves them across upgrades via `lookup`.

Under Argo CD or `helm template`, `lookup` returns empty and the chart
would re-generate secrets on every sync. Either set the plaintext values
explicitly or use mode 2 / 3 below.

### 2. Operator-managed (top-level `existingSecret.secretName`)

Pre-create a single `Opaque` Secret with the keys the chart needs and point
the chart at it. The required keys depend on the Timescale mode:

- **In-cluster Timescale**: `timescale-password` (the DSN is built in-template).
- **External Timescale**: `timescale-dsn` (the password is not used by the chart).

Plus `api-client-secret` when simple auth is enabled, and optionally
`cloud-sync-cluster-key` / `slack-webhook-url`.

```yaml
existingSecret:
  secretName: thoras-credentials  # your Secret name
```

The chart renders no credentials Secret and every workload reads from your
Secret. This is the recommended path under Argo CD.

To bootstrap the Secret with generated values, use
`hack/seed-credentials.sh` (which wraps `helm template --show-only`):

```
hack/seed-credentials.sh --license-key <key> --chart charts/thoras > seed.yaml
# Pipe seed.yaml into your secret tooling (kubeseal, ExternalSecrets, ...).
```

### 3. Mixed mode

Set `<credential>.existingSecret.secretName` per credential to override just
that one. The chart still seeds `thoras-credentials` for the other
credentials.

# Upgrading to chart 5.x

Chart 5.0 replaces the six per-credential Secrets that shipped in 4.x with a
single unified Secret, and renames the credential values to a consistent
`existingSecret: {secretName, ...Key}` shape.

The chart refuses to render on any 4.x values file — a sentinel checks for the
renamed fields and fails with a message pointing at this section. The chart
will not silently upgrade over your live install and delete the six legacy
Secrets before you have captured their contents.

### Migration procedure

Migrate your values file. `hack/migrate-values-to-5.x.sh` rewrites every
renamed field. It is idempotent — running it twice is a no-op.

```
hack/migrate-values-to-5.x.sh values.yaml
```

The 4.x → 5.x renames:

| 4.x                                        | 5.x                                             |
| ------------------------------------------ | ----------------------------------------------- |
| `imageCredentials.password`                | `thorasLicenseKey`                              |
| `imageCredentials.secretRef`               | `imageCredentials.existingSecret.secretName`    |
| `externalTimescale.secretRefName`          | `externalTimescale.existingSecret.secretName`   |
| `externalTimescale.secretRefKey`           | `externalTimescale.existingSecret.dsnKey`       |
| `slackWebhookUrl`                          | `slackWebhook.url`                              |
| `slackWebhookUrlSecretRefName`             | `slackWebhook.existingSecret.secretName`        |
| `slackWebhookUrlSecretRefKey`              | `slackWebhook.existingSecret.secretKey`         |
| `cloudSync.clusterKeySecretRefName`        | `cloudSync.existingSecret.secretName`           |
| `cloudSync.clusterKeySecretRefKey`         | `cloudSync.existingSecret.secretKey`            |

Optional integrations (Slack, cloud-sync) are disabled unless their
`existingSecret.secretKey` is non-empty. `hack/migrate-values-to-5.x.sh`
preserves the old key name where it was set, so previously-enabled
integrations stay enabled.

### Preserving credentials across upgrade

The chart no longer emits `thoras-timescale-password`, `api-client-secret`,
`thoras-cloud-sync`, or `thoras-slack`. On upgrade, Helm/Argo CD will prune
the four legacy Secrets when they are no longer templated. Before upgrading,
capture the values you want to preserve into the new `thoras-credentials`
Secret. Two strategies:

**A. External capture (recommended for GitOps).** Extract the four legacy
Secret values, create `thoras-credentials` under your normal secret tooling
(ExternalSecrets, sealed-secrets, `kubectl create secret`), and set
`existingSecret.secretName: thoras-credentials` in your values file. Upgrade.
The chart never renders `thoras-credentials` and does not touch your Secret.

Key-name mapping when you build the Secret manually:

| Legacy Secret / key                  | New key on `thoras-credentials`                     |
| ------------------------------------ | --------------------------------------------------- |
| `thoras-timescale-password.password` | `timescale-password` (in-cluster mode only)         |
| `thoras-timescale-password.host`     | *n/a* — DSN is built in-template from the password  |
| `api-client-secret.secret`           | `api-client-secret`                                 |
| `thoras-cloud-sync.clusterKey`       | `cloud-sync-cluster-key`                            |
| `thoras-slack.webhookUrl`            | `slack-webhook-url`                                 |

In external Timescale mode, the chart reads `timescale-dsn` instead of
`timescale-password`.

**B. Values-file capture.** Copy the plaintext values out of the four legacy
Secrets into your values file:

```yaml
thorasLicenseKey: "<from imageCredentials.password>"
metricsCollector:
  timescale:
    password: "<from thoras-timescale-password data.password>"
apiClientSecret:
  secret: "<from api-client-secret data.secret>"
cloudSync:
  clusterKey: "<from thoras-cloud-sync data.clusterKey>"
slackWebhook:
  url: "<from thoras-slack data.webhookUrl>"
```

The chart seeds `thoras-credentials` with these values on the next render. The
four legacy Secrets are pruned; workloads read from the new unified Secret.

Under Argo CD, mode B carries the same drift risk it always did — either
also set `apiClientSecret.existingSecret.secretName`-style overrides (mode 3
above), or ignore `/data` on `thoras-credentials` in `spec.ignoreDifferences`.

# Values

## Global

| Key                                          | Type    | Default                                          | Description                                                                                                            |
| -------------------------------------------- | ------- | ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| thorasVersion                                | String  | 4.119.0                                          | Thoras app version                                                                                                     |
| thorasLicenseKey                             | String  | ""                                               | Thoras license key. Renamed from `imageCredentials.password` in chart 5.0.                                             |
| existingSecret.secretName                    | String  | ""                                               | Top-level default for every credential Secret name (except `imageCredentials`). See "Managing credentials".            |
| imageCredentials.registry                    | String  | us-east4-docker.pkg.dev/thoras-registry/platform | Container registry name                                                                                                |
| imageCredentials.username                    | String  | \_json_key_base64                                | Container registry username                                                                                            |
| imageCredentials.existingSecret.secretName   | String  | ""                                               | Pre-existing dockerconfigjson Secret. Alternative to `thorasLicenseKey`. Does not inherit top-level `existingSecret`.  |
| imageCredentials.imagePullSecretInDeployment | Bool    | false                                            | Emit `imagePullSecrets` on the PodSpec in addition to the ServiceAccount.                                              |
| resourceQuota.enabled                        | Bool    | false                                            | Enables resource quotas within Thoras                                                                                  |
| resourceQuota.pods                 | Number  | 200                                              | Maximum number of pods allowed                                                                                         |
| resourceQuota.cronjobs             | Number  | 200                                              | Maximum number of cronjobs allowed                                                                                     |
| resourceQuota.jobs                 | Number  | 200                                              | Maximum number of jobs allowed                                                                                         |
| logLevel                           | String  | info                                             | Default log level                                                                                                      |
| env                                | list    | []                                               | Additional environment variables that will be passed onto all Thoras components                                        |
| slackWebhook.url                             | String  | ""                                               | Slack Webhook URL destination for notifications. Renamed from top-level `slackWebhookUrl` in 5.0.                       |
| slackWebhook.existingSecret.secretName       | String  | ""                                               | Pre-existing Secret with the Slack webhook URL. Empty → inherits top-level `existingSecret.secretName`.                |
| slackWebhook.existingSecret.secretKey        | String  | ""                                               | Key on the Secret that holds the webhook URL. Empty → Slack disabled end-to-end.                                       |
| slackErrorsEnabled                           | Boolean | false                                            | Determines if error-level logs are sent to `slackWebhook.url`                                                          |
| cloudSync.clusterKeyID                       | String  | ""                                               | Identity of cluster sync key. Cloud sync is disabled if not specified.                                                 |
| cloudSync.clusterKey                         | String  | ""                                               | Unique key identifying this cluster to the cloud. Seeded into the unified credentials Secret.                          |
| cloudSync.existingSecret.secretName          | String  | ""                                               | Pre-existing Secret with the cluster key. Empty → inherits top-level `existingSecret.secretName`.                      |
| cloudSync.existingSecret.secretKey           | String  | ""                                               | Key on the Secret that holds the cluster key. Empty → cloudSync disabled end-to-end.                                   |
| cloudSync.baseUrl                            | String  | "https://console.thoras.ai"                      | Thoras cloud base URL.                                                                                                 |
| queriesPerSecond                   | String  | "50"                                             | Sets a maximum threshold for K8s API qps                                                                               |
| nodeSelector                       | Object  | {}                                               | Node selectors to designate specific nodes to run Thoras workloads                                                     |
| tolerations                        | Array   | []                                               | Node taint tolerations to be used for to set up Thoras workloads                                                       |
| affinity                           | Object  | {}                                               | Global affinity rules applied to all components (components opt-in by default via useGlobalAffinity)                   |
| rbac.namespaces                    | Array   | []                                               | List of namespaces used to scope Roles+Bindings for the Thoras apps. If undefined, ClusterRoles will be used instead   |
| costRefreshBatching.enabled        | Boolean | true                                             | Enables refreshing cost data in concurrent batches                                                                     |
| costRefreshBatching.batchSize      | Number  | 200                                              | Number of AST costs to refresh per batch                                                                               |
| costRefreshBatching.maxConcurrency | Number  | 5                                                | Number of concurrent AST cost refresh batches to process concurrently                                                  |
| apiClientSecret.secret                       | String  | ""                                               | Shared secret components send to the API server when `featureFlags.enableSimpleAuthSecret` is true. Generated if empty. |
| apiClientSecret.existingSecret.secretName    | String  | ""                                               | Pre-existing Secret holding the shared secret. Empty → inherits top-level `existingSecret.secretName`.                 |
| apiClientSecret.existingSecret.secretKey     | String  | "api-client-secret"                              | Key on the Secret that holds the shared secret.                                                                        |

## Feature Flags

The following flags are considered temporary and gate access to specific behaviors that still undergoing testing before general availability.

| Key                                            | Type    | Default | Description                                                                        |
| ---------------------------------------------- | ------- | ------- | ---------------------------------------------------------------------------------- |
| featureFlags.enableNodeDetailsCollector        | Boolean | true    | Collection of node detail snapshots                                                |
| featureFlags.enablePgLargeObjectStorage        | Boolean | true    | If true, enables storing blobs as postgres large objects                           |
| featureFlags.enableInformersStripManagedFields | Boolean | true    | If true, enables informer memory optimizations                                     |
| featureFlags.enableTypedInformers              | Boolean | true    | If true, enables additional informer memory optimizations                          |
| featureFlags.enableAstRecordMirroring          | Boolean | true    | If true, ASTs are mirrored to the database component                               |
| featureFlags.enableSimpleAuthSecret            | Boolean | false   | If true, generates the `api-client-secret` Secret and wires it into all components |
| featureFlags.enablePodLogStreaming             | Boolean | false   | If true, the API server streams container logs and the dashboard shows pod logs    |

## Affinity Configuration

Define affinity rules globally or per-component. Components opt into global affinity by default and can add component-specific rules that merge with global settings.

```yaml
# Global affinity (applied to all components)
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: node-pool
              operator: In
              values:
                - thoras-pool

# Component-specific affinity (merged with global)
thorasOperator:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchExpressions:
                - key: app
                  operator: In
                  values:
                    - high-priority-app
            topologyKey: kubernetes.io/hostname

# Opt out of global affinity
thorasApiServerV2:
  useGlobalAffinity: false
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: dedicated-pool
                operator: In
                values:
                  - api-pool
```

All components support `<component>.useGlobalAffinity` (default: `true`) and `<component>.affinity` fields.

**Note:** `metricsCollector` and `thorasForecast` include built-in anti-affinity rules to avoid co-location. These always apply and merge with global/component settings.

## Thoras Forecast

| Key                                          | Type     | Default                | Description                                                                                    |
| -------------------------------------------- | -------- | ---------------------- | ---------------------------------------------------------------------------------------------- |
| thorasForecast.serviceAccount.name           | String   | thoras-forecast-worker | Service account name for Thoras forecast worker pod                                            |
| thorasForecast.imageTag                      | String   | .thorasVersion         | Image tag for Thoras Forecast job                                                              |
| thorasForecast.skipCache                     | Boolean  | false                  | Directs the forecaster to skip to model cache                                                  |
| thorasForecast.ignoreNewPods                 | Boolean  | true                   | Directs forecaster to adjust CPU and memory metrics temporarily for new pods                   |
| thorasForecast.enableDecoupledTraining       | Boolean  | true                   | Enables async training mode where forecasts report "needs_training" instead of training inline |
| thorasForecast.useAstMetricsSeries           | Boolean  | false                  | Enables catalog-free training data fetching via the AST metrics series endpoint                |
| thorasForecast.useForecasterComputedMetricId | Boolean  | true                   | Computes legacy metric IDs locally in Python instead of fetching from the catalog              |
| thorasForecast.worker.podAnnotations         | Object   | {}                     | Pod Annotations for Thoras Forecast                                                            |
| thorasForecast.worker.labels                 | Object   | {}                     | Pod labels for Thoras Forecast                                                                 |
| thorasForecast.worker.replicas               | Number   | 1                      | Number of `thoras-forecast-worker` replicas to use                                             |
| thorasForecast.worker.pollingInterval        | Number   | 15                     | Polling interval to check for work for `thoras-forecast-workers`                               |
| thorasForecast.worker.forecastTimeout        | Number   | 600                    | Maximum time (in seconds) spent on a single forecast by the `thoras-forecast-worker`           |
| thorasForecast.trainingJitterMinutes         | Number   | 0                      | Random jitter (in minutes, 0-120) added to training threshold to desynchronize training jobs   |
| thorasForecast.minLookbackToScale            | Duration | 3h                     | Minimum lookback window before autonomous scaling (minimum: 3h). Supports 3h, 180m, 1h30m      |
| thorasForecast.prometheus.host               | String   | ::                     | Address the metrics server binds to (dual-stack by default)                                    |
| thorasWorker.prometheus.enabled              | Boolean  | true                   | Enables a prometheus metric exporter                                                           |
| thorasWorker.prometheus.port                 | Number   | 9101                   | Port for the prometheus metric exporter                                                        |

## Thoras Operator

| Key                                | Type    | Default         | Description                                                  |
| ---------------------------------- | ------- | --------------- | ------------------------------------------------------------ |
| thorasOperator.serviceAccount.name | String  | thoras-operator | Service account name for Thoras operator pod                 |
| thorasOperator.podAnnotations      | Object  | {}              | Pod Annotations for Thoras Operator                          |
| thorasOperator.labels              | Object  | {}              | Pod/service labels for Thoras Operator                       |
| thorasOperator.resources           | Object  | {}              | Specify the resources block. Takes precedence if set.        |
| thorasOperator.limits.memory       | String  | 2000Mi          | Legacy field for setting Thoras Operator memory limit        |
| thorasOperator.requests.cpu        | String  | 1000m           | Legacy field for setting Thoras Operator CPU request         |
| thorasOperator.requests.memory     | String  | 1000Mi          | Legacy field for setting Thoras Operator memory request      |
| thorasOperator.slackErrorsEnabled  | Boolean | false           | Determines if error-level logs are sent to `slackWebHookUrl` |
| thorasOperator.logLevel            | String  | Nil             | Logging level                                                |
| thorasOperator.queriesPerSecond    | String  | "50"            | Sets a maximum threshold for K8s API qps                     |
| thorasOperator.prometheus.enabled  | Boolean | true            | Enables a prometheus metric exporter                         |
| thorasOperator.prometheus.port     | Number  | 9101            | Port for the prometheus metric exporter                      |
| thorasOperator.pprof.enabled       | Boolean | false           | Enable pprof endpoint.                                       |

## External TimescaleDB

When set, the chart skips deploying the in-cluster TimescaleDB and configures
all components to use an external database instead. The TimescaleDB extension
must be pre-installed and managed externally.

| Key                                            | Type   | Default            | Description                                                                                           |
| ---------------------------------------------- | ------ | ------------------ | ----------------------------------------------------------------------------------------------------- |
| externalTimescale.dsn                          | String | ""                 | Full postgres DSN including database name, e.g. `postgres://user:pass@host:5432/tsdb?sslmode=require` |
| externalTimescale.existingSecret.secretName    | String | ""                 | Pre-existing Secret holding the DSN. Empty → inherits top-level `existingSecret.secretName`.          |
| externalTimescale.existingSecret.dsnKey        | String | "timescale-dsn"    | Key on the Secret that holds the DSN.                                                                 |

### In-cluster TimescaleDB credentials

Use `metricsCollector.timescale.existingSecret` when the chart deploys
Timescale in-cluster but you want to supply the password out-of-band. The
DSN is built in-template from the password plus the in-cluster hostname/port,
so only the password key needs to be supplied. Ignored when `externalTimescale`
is enabled.

| Key                                                        | Type   | Default             | Description                                                                                              |
| ---------------------------------------------------------- | ------ | ------------------- | -------------------------------------------------------------------------------------------------------- |
| metricsCollector.timescale.password                        | String | ""                  | Plaintext password. Chart-seeded into `thoras-credentials`. Generated when empty. Preserved via `lookup`. |
| metricsCollector.timescale.existingSecret.secretName       | String | ""                  | Pre-existing Secret holding the password. Empty → inherits top-level `existingSecret.secretName`.        |
| metricsCollector.timescale.existingSecret.passwordKey      | String | "timescale-password" | Key on the Secret that holds the Timescale postgres password.                                           |

## Thoras Metrics Collector

| Key                                                             | Type    | Default          | Description                                                  |
| --------------------------------------------------------------- | ------- | ---------------- | ------------------------------------------------------------ |
| metricsCollector.serviceAccount.name                            | String  | thoras-collector | Service account name for Thoras collector pod                |
| metricsCollector.persistence.enabled                            | Bool    | false            | Enables persistence for Thoras metrics collector             |
| metricsCollector.persistence.volumeName                         | String  | ""               | PV name for PVC. Keep blank if using dynamic provisioning    |
| metricsCollector.persistence.createEFSStorageClass.fileSystemId | String  | ""               | Create dynamic PV provisioner for EFS by specifying EFS id   |
| metricsCollector.persistence.storageClassName                   | String  | ""               | Storage class for PVC                                        |
| metricsCollector.persistence.pvcStorageRequestSize              | String  | "3Gi"            | Inform PV backend of minimal volume requirements             |
| metricsCollector.persistence.accessMode                         | String  | "ReadWriteOnce"  | The accessMode applied to the PVC                            |
| metricsCollector.podAnnotations                                 | Object  | {}               | Pod Annotations for Thoras metrics collector                 |
| metricsCollector.labels                                         | Object  | {}               | Pod/service labels for Thoras metrics collector              |
| metricsCollector.timescale.image                                | String  | timescaledb      | Timescale image                                              |
| metricsCollector.timescale.imageTag                             | String  | 2.27.0-pg16      | Timescale image tag                                          |
| metricsCollector.timescale.extensionVersion                     | String  | 2.27.0           | Timescale extension version - should match imageTag          |
| metricsCollector.timescale.name                                 | String  | timescale        | Timescale container name                                     |
| metricsCollector.timescale.containerPort                        | Number  | 5432             | Timescale port                                               |
| metricsCollector.blobService.port                               | Number  | 80               | Blob service external port                                   |
| metricsCollector.blobService.logLevel                           | String  | Nil              | Logging level                                                |
| metricsCollector.blobService.containerPort                      | Number  | 8080             | Blob service internal port                                   |
| metricsCollector.blobService.pprof.enabled                      | Boolean | false            | Enable pprof endpoint.                                       |
| metricsCollector.slackErrorsEnabled                             | Boolean | false            | Determines if error-level logs are sent to `slackWebHookUrl` |
| metricsCollector.init.imageTag                                  | String  | latest           | Image tag for metrics collector init container               |

## Thoras API Server

| Key                                            | Type    | Default    | Description                                                             |
| ---------------------------------------------- | ------- | ---------- | ----------------------------------------------------------------------- |
| thorasApiServerV2.serviceAccount.name          | String  | thoras-api | Service account name for Thoras api service pod                         |
| thorasApiServerV2.podAnnotations               | Object  | {}         | Pod Annotations for Thoras API                                          |
| thorasApiServerV2.labels                       | Object  | {}         | Pod/service labels for Thoras API                                       |
| thorasApiServerV2.containerPort                | Number  | 8443       | Thoras API port                                                         |
| thorasApiServerV2.port                         | Number  | 443        | Thoras API service port                                                 |
| thorasApiServerV2.resources                    | Object  | {}         | Specify the resources block. Takes precedence if set.                   |
| thorasApiServerV2.limits.memory                | String  | 2000Mi     | Legacy field for setting Thoras API memory limit                        |
| thorasApiServerV2.requests.cpu                 | String  | 1000Mi     | Legacy field for settingThoras API CPU request                          |
| thorasApiServerV2.requests.memory              | String  | 1000Mi     | Legacy field for settingThoras API memory request                       |
| thorasApiServerV2.slackErrorsEnabled           | Boolean | false      | Determines if error-level logs are sent to `slackWebHookUrl`            |
| thorasApiServerV2.logLevel                     | String  | Nil        | Logging level                                                           |
| thorasApiServerV2.queriesPerSecond             | String  | "50"       | Sets a maximum threshold for K8s API qps                                |
| thorasApiServerV2.prometheus.enabled           | Boolean | true       | Enables a prometheus metric scrape point                                |
| thorasApiServerV2.pprof.enabled                | Boolean | false      | Enable pprof endpoint.                                                  |
| thorasApiServerV2.enableViewCacheQueryLiveJoin | Boolean | true       | Enables AST view queries joining view cache results with live k8s state |

## Thoras Worker

| Key                                                  | Type    | Default       | Description                                                  |
| ---------------------------------------------------- | ------- | ------------- | ------------------------------------------------------------ |
| thorasWorker.serviceAccount.name                     | String  | thoras-worker | Service account name for Thoras worker pod                   |
| thorasWorker.podAnnotations                          | Object  | {}            | Pod Annotations for Thoras worker                            |
| thorasWorker.labels                                  | Object  | {}            | Pod/service labels for Thoras worker                         |
| thorasWorker.resources                               | Object  | {}            | Specify the resources block. Takes precedence if set.        |
| thorasWorker.limits.memory                           | String  | 2000Mi        | Legacy field for setting Thoras API memory limit             |
| thorasWorker.requests.cpu                            | String  | 1000Mi        | Legacy field for setting Thoras API CPU request              |
| thorasWorker.requests.memory                         | String  | 1000Mi        | Legacy field for setting Thoras API memory request           |
| thorasWorker.slackErrorsEnabled                      | Boolean | false         | Determines if error-level logs are sent to `slackWebHookUrl` |
| thorasWorker.logLevel                                | String  | Nil           | Logging level                                                |
| thorasWorker.queriesPerSecond                        | String  | "50"          | Sets a maximum threshold for K8s API qps                     |
| thorasWorker.prometheus.enabled                      | Boolean | true          | Enables a prometheus metric exporter                         |
| thorasWorker.prometheus.port                         | Number  | 9102          | Port for the prometheus metric exporter                      |
| thorasWorker.enableMetricIntegrityWorker             | Boolean | true          | Enable metric integrity worker                               |
| thorasWorker.enableDeploymentMonitorWorker           | Boolean | true          | Enable deployment monitor worker                             |
| thorasWorker.maxTimeseriesMetricCacheSizeMb          | Number  | 1000          | Configure cache size that triggers LRU eviction              |
| thorasWorker.enableUnifiedAstUtilizationMonitor      | Boolean | false         | Enable the unified AST utilization monitor                   |
| thorasWorker.enableAstViewCacheStateReconcilerWorker | Boolean | true          | Enable view cache state reconciler jobs                      |
| thorasWorker.pprof.enabled                           | Boolean | false         | Enable pprof endpoint.                                       |

## Thoras Dashboard

| Key                                              | Type    | Default          | Description                                                              |
| ------------------------------------------------ | ------- | ---------------- | ------------------------------------------------------------------------ |
| thorasDashboard.enabled                          | Bool    | true             | Enables the Thoras Dashboard                                             |
| thorasDashboard.serviceAccount.create            | Bool    | true             | Creates a Thoras-maintained service account for the Thoras Dashboard pod |
| thorasDashboard.serviceAccount.name              | String  | thoras-dashboard | Service account name for Thoras Dashboard pod                            |
| thorasDashboard.rbac.create                      | Bool    | true             | Creates cluster role for Thoras Dashboard pod                            |
| thorasDashboard.podAnnotations                   | Object  | {}               | Pod Annotations for Thoras Dashboard                                     |
| thorasDashboard.labels                           | Object  | {}               | Pod/service labels for Thoras Dashboard                                  |
| thorasDashboard.containerPort                    | Number  | 5173             | Thoras Dashboard port                                                    |
| thorasDashboard.port                             | Number  | 80               | Thoras Dashboard service port                                            |
| thorasDashboard.resources                        | Object  | {}               | Specify the resources block. Takes precedence if set.                    |
| thorasDashboard.limits.memory                    | String  | 2000Mi           | Legacy field for setting Thoras Dashboard memory limit                   |
| thorasDashboard.requests.cpu                     | String  | 1000Mi           | Legacy field for setting Thoras Dashboard CPU request                    |
| thorasDashboard.requests.memory                  | String  | 1000Mi           | Legacy field for setting Thoras Dashboard memory request                 |
| thorasDashboard.service.type                     | String  | ClusterIP        | Type of Service to use                                                   |
| thorasDashboard.service.annotations              | Object  | {}               | Service annotations                                                      |
| thorasDashboard.service.clusterIP                | String  | nil              | Service clusterIP when type is ClusterIP                                 |
| thorasDashboard.service.loadBalancerIP           | String  | nil              | Service loadBalancerIP when type is LoadBalancer                         |
| thorasDashboard.service.loadBalancerSourceRanges | List    | nil              | Service loadBalancerSourceRanges when type is LoadBalancer               |
| thorasDashboard.service.externalIPs              | List    | nil              | Service externalIPs                                                      |
| thorasDashboard.ingress.enabled                  | Bool    | false            | Enables Ingress for the Dashboard                                        |
| thorasDashboard.ingress.ingressClassName         | String  | ""               | IngressClass to use for the Dashboard Ingress                            |
| thorasDashboard.ingress.annotations              | Object  | {}               | Annotations for the Dashboard Ingress                                    |
| thorasDashboard.ingress.hosts                    | List    | see below        | List of hosts and paths for the Dashboard Ingress                        |
| thorasDashboard.ingress.tls                      | List    | []               | TLS configuration for the Dashboard Ingress                              |
| thorasDashboard.gatewayAPI.enabled               | Bool    | false            | Enables Gateway API HTTPRoute for the Dashboard                          |
| thorasDashboard.gatewayAPI.annotations           | Object  | {}               | Annotations for the Dashboard HTTPRoute                                  |
| thorasDashboard.gatewayAPI.parentRefs            | List    | see below        | Gateway references for the HTTPRoute                                     |
| thorasDashboard.gatewayAPI.hostnames             | List    | see below        | Hostnames for the HTTPRoute                                              |
| thorasDashboard.gatewayAPI.path                  | String  | /                | Path for the HTTPRoute                                                   |
| thorasDashboard.gatewayAPI.pathType              | String  | PathPrefix       | Path type for the HTTPRoute                                              |
| thorasDashboard.slackErrorsEnabled               | Boolean | false            | Determines if error-level logs are sent to `slackWebHookUrl`             |
| thorasDashboard.logLevel                         | String  | Nil              | Logging level                                                            |
| thorasDashboard.extras                           | Object  | {}               | Additional values to be injected into the Thoras Dashboard config        |

## Thoras Monitor

| Key                  | Type   | Default | Description                       |
| -------------------- | ------ | ------- | --------------------------------- |
| thorasMonitor.labels | Object | {}      | Pod labels for Thoras monitor     |
| thorasMonitor.config | String | ""      | Thoras Monitor configuration yaml |

## Example Thoras Dashboard Ingress Configuration

```yaml
# values.yaml
---
thorasDashboard:
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    hosts:
      - host: thoras.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: thoras-tls
        hosts:
          - thoras.example.com
```

Default `thorasDashboard.ingress.hosts` value:

```yaml
hosts:
  - host: thoras.local
    paths:
      - path: /
        pathType: Prefix
```

## Example Thoras Dashboard Gateway API Configuration

```yaml
# values.yaml
---
thorasDashboard:
  gatewayAPI:
    enabled: true
    annotations:
      example.com/annotation: value
    parentRefs:
      - name: my-gateway
        namespace: gateway-system
    hostnames:
      - thoras.example.com
    path: /
    pathType: PathPrefix
```

Default `thorasDashboard.gatewayAPI.parentRefs` value:

```yaml
parentRefs:
  - name: gateway
    namespace: default
```

Default `thorasDashboard.gatewayAPI.hostnames` value:

```yaml
hostnames:
  - thoras.local
```
