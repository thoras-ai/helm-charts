# Thoras

Thoras is an ML-powered platform that helps SRE teams view the future of their Kubernetes workloads.

This Helm Chart installs [Thoras](https://www.thoras.ai) onto Kubernetes.

![Version: 4.16.4](https://img.shields.io/badge/Version-4.16.4-informational?style=flat-square) ![AppVersion: 4.5.2](https://img.shields.io/badge/AppVersion-4.5.2-informational?style=flat-square)

# Install

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

| Key                       | Type    | Default                                          | Description                                                  |
| ------------------------- | ------- | ------------------------------------------------ | ------------------------------------------------------------ |
| thorasVersion             | String  | 4.5.2                                            | Thoras app version                                           |
| imageCredentials.registry | String  | us-east4-docker.pkg.dev/thoras-registry/platform | Container registry name                                      |
| imageCredentials.username | String  | \_json_key_base64                                | Container registry username                                  |
| imageCredentials.password | String  | ""                                               | Container registry auth string                               |
| resourceQuota.enabled     | Bool    | false                                            | Enables resource quotas within Thoras                        |
| resourceQuota.pods        | Number  | 200                                              | Maximum number of pods allowed                               |
| resourceQuota.cronjobs    | Number  | 200                                              | Maximum number of cronjobs allowed                           |
| resourceQuota.jobs        | Number  | 200                                              | Maximum number of jobs allowed                               |
| logLevel                  | String  | info                                             | Default log level                                            |
| slackWebhookUrl           | String  | ""                                               | Slack Webhook URL destination for notifications.             |
| slackErrorsEnabled        | Boolean | false                                            | Determines if error-level logs are sent to `slackWebHookUrl` |

## Thoras Forecast

| Key                     | Type   | Default        | Description                       |
| ----------------------- | ------ | -------------- | --------------------------------- |
| thorasForecast.imageTag | String | .thorasVersion | Image tag for Thoras Forecast job |

## Thoras Operator

| Key                               | Type    | Default | Description                                                  |
| --------------------------------- | ------- | ------- | ------------------------------------------------------------ |
| thorasOperator.podAnnotations     | Object  | {}      | Pod Annotations for Thoras Operator                          |
| thorasOperator.limits.memory      | String  | 2000Mi  | Thoras Operator memory limit                                 |
| thorasOperator.requests.cpu       | String  | 1000m   | Thoras Operator CPU request                                  |
| thorasOperator.requests.memory    | String  | 1000Mi  | Thoras Operator memory request                               |
| thorasOperator.slackErrorsEnabled | Boolean | false   | Determines if error-level logs are sent to `slackWebHookUrl` |
| thorasOperator.logLevel           | String  | Nil     | Logging level                                                |

## Thoras Metrics Collector

| Key                                                             | Type    | Default          | Description                                                  |
| --------------------------------------------------------------- | ------- | ---------------- | ------------------------------------------------------------ |
| metricsCollector.persistence.enabled                            | Bool    | false            | Enables persistence for Thoras metrics collector             |
| metricsCollector.persistence.volumeName                         | String  | ""               | PV name for PVC. Keep blank if using dynamic provisioning    |
| metricsCollector.persistence.createEFSStorageClass.fileSystemId | String  | ""               | Create dynamic PV provisioner for EFS by specifying EFS id   |
| metricsCollector.persistence.storageClassName                   | String  | ""               | Storage class for PVC                                        |
| metricsCollector.persistence.pvcStorageRequestSize              | String  | "3Gi"            | Inform PV backend of minimal volume requirements             |
| metricsCollector.collector.name                                 | String  | thoras-collector | Thoras collector container name                              |
| metricsCollector.collector.logLevel                             | String  | Nil              | Logging level                                                |
| metricsCollector.podAnnotations                                 | Object  | {}               | Pod Annotations for Thoras metrics collector                 |
| metricsCollector.search.imageTag                                | String  | 8.12.1           | Elasticsearch image tag                                      |
| metricsCollector.search.name                                    | String  | elasticsearch    | Elasticsearch container name                                 |
| metricsCollector.search.containerPort                           | Number  | 9200             | Elasticsearch port                                           |
| metricsCollector.purge.ttl                                      | String  | 30d              | How long to keep metrics data in Elasticsearch               |
| metricsCollector.purge.schedule                                 | String  | 00 00 \* \* \*   | Cron expression for metrics purge job                        |
| metricsCollector.slackErrorsEnabled                             | Boolean | false            | Determines if error-level logs are sent to `slackWebHookUrl` |
| metricsCollector.purge.logLevel                                 | String  | Nil              | Logging level                                                |
| metricsCollector.init.imageTag                                  | String  | latest           | Image tag for metrics collector init container               |

## Thoras API Server

| Key                                | Type    | Default | Description                                                  |
| ---------------------------------- | ------- | ------- | ------------------------------------------------------------ |
| thorasApiServer.podAnnotations     | Object  | {}      | Pod Annotations for Thoras Thoras API                        |
| thorasApiServer.containerPort      | Number  | 8443    | Thoras API port                                              |
| thorasApiServer.port               | Number  | 443     | Thoras API service port                                      |
| thorasApiServer.limits.memory      | String  | 2000Mi  | Thoras API memory limit                                      |
| thorasApiServer.requests.cpu       | String  | 1000Mi  | Thoras API CPU request                                       |
| thorasApiServer.requests.memory    | String  | 1000Mi  | Thoras API memory request                                    |
| thorasApiServer.slackErrorsEnabled | Boolean | false   | Determines if error-level logs are sent to `slackWebHookUrl` |
| thorasApiServer.logLevel           | String  | Nil     | Logging level                                                |

## Thoras Dashboard

| Key                                              | Type    | Default          | Description                                                              |
| ------------------------------------------------ | ------- | ---------------- | ------------------------------------------------------------------------ |
| thorasDashboard.enabled                          | Bool    | true             | Enables the Thoras Dashboard                                             |
| thorasDashboard.serviceAccount.create            | Bool    | true             | Creates a Thoras-maintained service account for the Thoras Dashboard pod |
| thorasDashboard.serviceAccount.name              | String  | thoras-dashboard | Service account name for Thoras Dashboard pod                            |
| thorasDashboard.rbac.create                      | Bool    | true             | Creates cluster role for Thoras Dashboard pod                            |
| thorasDashboard.podAnnotations                   | Object  | {}               | Pod Annotations for Thoras Dashboard                                     |
| thorasDashboard.containerPort                    | Number  | 3000             | Thoras Dashboard port                                                    |
| thorasDashboard.port                             | Number  | 3000             | Thoras Dashboard service port                                            |
| thorasDashboard.limits.memory                    | String  | 2000Mi           | Thoras Dashboard memory limit                                            |
| thorasDashboard.requests.cpu                     | String  | 1000Mi           | Thoras Dashboard CPU request                                             |
| thorasDashboard.requests.memory                  | String  | 1000Mi           | Thoras Dashboard memory request                                          |
| thorasDashboard.service.type                     | String  | ClusterIP        | Type of Service to use                                                   |
| thorasDashboard.service.annotations              | Object  | {}               | Service annotations                                                      |
| thorasDashboard.service.clusterIP                | String  | nil              | Service clusterIP when type is ClusterIP                                 |
| thorasDashboard.service.loadBalancerIP           | String  | nil              | Service loadBalancerIP when type is LoadBalancer                         |
| thorasDashboard.service.loadBalancerSourceRanges | List    | nil              | Service loadBalancerSourceRanges when type is LoadBalancer               |
| thorasDashboard.service.externalIPs              | List    | nil              | Service externalIPs                                                      |
| thorasDashboard.slackErrorsEnabled               | Boolean | false            | Determines if error-level logs are sent to `slackWebHookUrl`             |
| thorasDashboard.logLevel                         | String  | Nil              | Logging level                                                            |

## Thoras Monitor

| Key                              | Type    | Default | Description                                                  |
| -------------------------------- | ------- | ------- | ------------------------------------------------------------ |
| thorasMonitor.enabled            | Bool    | false   | Enable Thoras monitoring                                     |
| thorasMonitor.podAnnotations     | Object  | {}      | Pod Annotations for Thoras monitor                           |
| thorasMonitor.slackErrorsEnabled | Boolean | false   | Determines if error-level logs are sent to `slackWebHookUrl` |
| thorasMonitor.config             | String  | ""      | Thoras Monitor configuration yaml                            |
| thorasMonitor.logLevel           | String  | Nil     | Logging level                                                |

## Thoras Agent

| Key                            | Type    | Default        | Description                                                            |
| ------------------------------ | ------- | -------------- | ---------------------------------------------------------------------- |
| thorasAgent.enabled            | Bool    | false          | Enable the Thoras Agent (opt-in, for now)                              |
| thorasAgent.imageTag           | String  | .thorasVersion | Image tag for Thoras Agent daemon set                                  |
| thorasAgent.slackErrorsEnabled | Boolean | false          | Determines if error-level logs are sent to `slackWebHookUrl`           |
| thorasAgent.frequency          | Integer | 15             | Frequency, in seconds, of agent polling for service map communications |

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
      monitor_cadence: 15s
    # Alert config
    alerts:
      - name: thoras_deployments
        notification_cooldown: 15m
        enabled: True
      - name: thoras_jobs
        notification_cooldown: 15m
        enabled: True
        options:
          max_job_life: 10m
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
