# Thoras

Thoras is an ML-powered platform that helps SRE teams view the future of their Kubernetes workloads.

This Helm Chart installs [Thoras](https://www.thoras.ai) onto Kubernetes.

![Version: 4.82.1](https://img.shields.io/badge/Version-4.82.1-informational?style=flat-square) ![AppVersion: 4.66.1](https://img.shields.io/badge/AppVersion-4.66.1-informational?style=flat-square)

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
imageCredentials:
  registry: "us-east4-docker.pkg.dev/thoras-registry/platform"
  username: "_json_key_base64"
  password: "<thoras license key>"

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

# Values

## Global

| Key                                | Type    | Default                                          | Description                                                                                                          |
| ---------------------------------- | ------- | ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------- |
| thorasVersion                      | String  | 4.66.1                                           | Thoras app version                                                                                                   |
| imageCredentials.registry          | String  | us-east4-docker.pkg.dev/thoras-registry/platform | Container registry name                                                                                              |
| imageCredentials.username          | String  | \_json_key_base64                                | Container registry username                                                                                          |
| imageCredentials.password          | String  | ""                                               | Container registry auth string                                                                                       |
| resourceQuota.enabled              | Bool    | false                                            | Enables resource quotas within Thoras                                                                                |
| resourceQuota.pods                 | Number  | 200                                              | Maximum number of pods allowed                                                                                       |
| resourceQuota.cronjobs             | Number  | 200                                              | Maximum number of cronjobs allowed                                                                                   |
| resourceQuota.jobs                 | Number  | 200                                              | Maximum number of jobs allowed                                                                                       |
| logLevel                           | String  | info                                             | Default log level                                                                                                    |
| slackWebhookUrl                    | String  | ""                                               | Slack Webhook URL destination for notifications.                                                                     |
| slackErrorsEnabled                 | Boolean | false                                            | Determines if error-level logs are sent to `slackWebHookUrl`                                                         |
| cloudSync.clusterKeyID             | String  | ""                                               | Identity of cluster sync key . Cloud sync is disabled if not specified                                               |
| cloudSync.clusterKey               | String  | ""                                               | Unique key identifying this cluster to the cloud.                                                                    |
| queriesPerSecond                   | String  | "50"                                             | Sets a maximum threshold for K8s API qps                                                                             |
| nodeSelector                       | Object  | {}                                               | Node selectors to designate specific nodes to run Thoras workloads                                                   |
| tolerations                        | Array   | []                                               | Node taint tolerations to be used for to set up Thoras workloads                                                     |
| affinity                           | Object  | {}                                               | Global affinity rules applied to all components (components opt-in by default via useGlobalAffinity)                 |
| rbac.namespaces                    | Array   | []                                               | List of namespaces used to scope Roles+Bindings for the Thoras apps. If undefined, ClusterRoles will be used instead |
| costRefreshBatching.enabled        | Boolean | true                                             | Enables refreshing cost data in concurrent batches                                                                   |
| costRefreshBatching.batchSize      | Number  | 200                                              | Number of AST costs to refresh per batch                                                                             |
| costRefreshBatching.maxConcurrency | Number  | 5                                                | Number of concurrent AST cost refresh batches to process concurrently                                                |

## Feature Flags

The following flags are considered temporary and gate access to specific behaviors that still undergoing testing before general availability.

| Key                                              | Type    | Default | Description                                                     |
| ------------------------------------------------ | ------- | ------- | --------------------------------------------------------------- |
| featureFlags.enableNodeDetailsCollector          | Boolean | true    | Collection of node detail snapshots                             |
| featureFlags.enableSkipScalingOnInsufficientData | Boolean | true    | Workloads are scaled only if they more than three hours of data |
| featureFlags.enableCRDSuggestionReads            | Boolean | false   | If true, webhooks read suggestions from CRD instead of API      |
| featureFlags.enableCheckDatabaseHealth           | Boolean | false   | If true, pings the database in the health endpoint              |
| featureFlags.enableCostSavingsSettingsRefresh    | Boolean | true    | If true, refreshes the costs savings settings periodically      |
| featureFlags.enableForecastRescuer               | Boolean | false   | If true, enables rescuing stalled forecast jobs                 |

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

| Key                                    | Type    | Default                     | Description                                                                                    |
| -------------------------------------- | ------- | --------------------------- | ---------------------------------------------------------------------------------------------- |
| thorasForecast.serviceAccount.name     | String  | thoras-forecast-worker      | Service account name for Thoras forecast worker pod                                            |
| thorasForecast.imageTag                | String  | .thorasVersion              | Image tag for Thoras Forecast job                                                              |
| thorasForecast.skipCache               | Boolean | false                       | Directs the forecaster to skip to model cache                                                  |
| thorasForecast.ignoreNewPods           | Boolean | true                        | Directs forecaster to adjust CPU and memory metrics temporarily for new pods                   |
| thorasForecast.enableDecoupledTraining | Boolean | true                        | Enables async training mode where forecasts report "needs_training" instead of training inline |
| thorasForecast.worker.podAnnotations   | Object  | {}                          | Pod Annotations for Thoras Forecast                                                            |
| thorasForecast.worker.labels           | Object  | {}                          | Pod labels for Thoras Forecast                                                                 |
| thorasForecast.worker.replicas         | Number  | 1                           | Number of `thoras-forecast-worker` replicas to use                                             |
| thorasForecast.worker.pollingInterval  | Number  | 15                          | Polling interval to check for work for `thoras-forecast-workers`                               |
| thorasForecast.worker.forecastTimeout  | Number  | 600                         | Maximum time (in seconds) spent on a single forecast by the `thoras-forecast-worker`           |
| thorasForecast.trainingJitterMinutes   | Number  | 0                           | Random jitter (in minutes, 0-120) added to training threshold to desynchronize training jobs   |
| thorasWorker.prometheus.enabled        | Boolean | true                        | Enables a prometheus metric exporter                                                           |
| thorasWorker.prometheus.port           | Number  | 9101                        | Port for the prometheus metric exporter                                                        |
| thorasWorker.cloudSyncBaseUrl          | String  | "https://console.thoras.ai" | Base URL for syncing metrics and forecasts to Thoras Cloud                                     |

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
| metricsCollector.timescale.imageTag                             | String  | 2.25.0-pg16      | Timescale image tag                                          |
| metricsCollector.timescale.extensionVersion                     | String  | 2.25.0           | Timescale extension version - should match imageTag          |
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
| thorasWorker.enableSnapshotChunkAutoSizing           | Boolean | false         | Enable auto resizing of metric snapshot chunks               |
| thorasWorker.enableMetricIntegrityWorker             | Boolean | false         | Enable metric integrity worker                               |
| thorasWorker.enableActiveSuggestionWorker            | Boolean | false         | Enable active suggestions worker                             |
| thorasWorker.maxTimeseriesMetricCacheSizeMb          | Number  | 1000          | Configure cache size that triggers LRU eviction              |
| thorasWorker.enableUnifiedAstUtilizationMonitor      | Boolean | false         | Enable the unified AST utilization monitor                   |
| thorasWorker.enableAstViewCacheStateReconcilerWorker | Boolean | true          | Enable view cache state reconciler jobs                      |

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

| Key                               | Type    | Default        | Description                                                  |
| --------------------------------- | ------- | -------------- | ------------------------------------------------------------ |
| thorasMonitor.enabled             | Bool    | false          | Enable Thoras monitoring                                     |
| thorasMonitor.serviceAccount.name | String  | thoras-monitor | Service account name for Thoras monitor pod                  |
| thorasMonitor.podAnnotations      | Object  | {}             | Pod Annotations for Thoras monitor                           |
| thorasMonitor.labels              | Object  | {}             | Pod labels for Thoras monitor                                |
| thorasMonitor.slackErrorsEnabled  | Boolean | false          | Determines if error-level logs are sent to `slackWebHookUrl` |
| thorasMonitor.config              | String  | ""             | Thoras Monitor configuration yaml                            |
| thorasMonitor.logLevel            | String  | Nil            | Logging level                                                |

## Thoras Agent

| Key                             | Type    | Default        | Description                                                            |
| ------------------------------- | ------- | -------------- | ---------------------------------------------------------------------- |
| thorasAgent.enabled             | Bool    | false          | Enable the Thoras Agent (opt-in, for now)                              |
| thorasAgent.serviceAccount.name | String  | thoras-agent   | Service account name for Thoras agent pod                              |
| thorasAgent.podAnnotations      | Object  | {}             | Pod Annotations for Thoras Agent                                       |
| thorasAgent.labels              | Object  | {}             | Pod labels for Thoras Agent                                            |
| thorasAgent.resources           | Object  | {}             | Specify the complete resources block. Takes precedence if set.         |
| thorasAgent.limits.memory       | String  | 128Mi          | Legacy field for setting Thoras Agent memory limit                     |
| thorasAgent.requests.cpu        | String  | 100m           | Legacy field for setting Thoras Agent CPU request                      |
| thorasAgent.requests.memory     | String  | 128Mi          | Legacy field for setting Thoras Agent memory request                   |
| thorasAgent.imageTag            | String  | .thorasVersion | Image tag for Thoras Agent daemon set                                  |
| thorasAgent.slackErrorsEnabled  | Boolean | false          | Determines if error-level logs are sent to `slackWebHookUrl`           |
| thorasAgent.frequency           | Integer | 15             | Frequency, in seconds, of agent polling for service map communications |
| thorasAgent.queriesPerSecond    | String  | "50"           | Sets a maximum threshold for K8s API qps                               |
| thorasAgent.priorityClassName   | String  | ""             | Priority class name for Thoras Agent pods                              |
| thorasAgent.securityContext     | Object  | {}             | Allows assigning additional securityContext                            |

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

## Example Thoras Monitor with default config

```yaml
# values.yaml
---
thorasMonitor:
  enabled: true
  slackWorkspaceID: "ABC123"
  slackChannelID: "ABC123"
  slackWebhookID: "SECRET_ABC123"
  config: |
    # General Settings
    general:
      name: Thoras
      monitor_cadence: 60s
    # Alert config
    alerts:
      - name: thoras_deployments
        notification_cooldown: 15m
        enabled: True
      - name: metric_integrity
        notification_cooldown: 15m
        enabled: True
      - name: auto_conflict
        notification_cooldown: 15m
        enabled: True
      - name: no_suggestions
        notification_cooldown: 15m
        enabled: True
      - name: under_provisioned
        notification_cooldown: 15m
        enabled: True
        options:
          threshold: 0.25
      - name: over_provisioned
        notification_cooldown: 15m
        enabled: True
        options:
          threshold: 10
```
