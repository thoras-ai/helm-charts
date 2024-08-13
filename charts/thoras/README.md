# Thoras

Thoras is an ML-powered platform that helps SRE teams view the future of their Kubernetes workloads.

This Helm Chart installs [Thoras](https://www.thoras.ai) onto Kubernetes.

![Version: 2.6.0](https://img.shields.io/badge/Version-2.6.0-informational?style=flat-square) ![AppVersion: 1.1.5](https://img.shields.io/badge/AppVersion-1.1.5-informational?style=flat-square)

# Install
Using [Helm](https://helm.sh), you can easily install and test Throas in a Kubernetes cluster by running the following:

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
  registry: docker.thoras.ai
  username: thoras
  password: <your license key>

metricsCollector:
	persistence:
		enabled: false
```

#### Install Chart

Now let’s install Thoras with Helm! We recommend installing Thoras into the thoras namespace:

```
helm install
  my-thoras-release \
  thoras/thoras \
  -n thoras --create-namespace \
  -f ./values.yaml
```

# Values

#### Global
| Key | Type | Default | Description |
| --- | --- | --- | --- |
| thorasVersion | String | 1.1.5 | Thoras app version |

#### Thoras Operator
| Key | Type | Default | Description |
| --- | --- | --- | --- |
| thorasOperator.limits.cpu | String | 1000m | Thoras Operator CPU limit |
| thorasOperator.limits.memory | String | 1000Mi | Thoras Operator memory limit |
| thorasOperator.requests.cpu | String | 1000m | Thoras Operator CPU request |
| thorasOperator.requests.memory | String | 1000Mi | Thoras Operator memory request |

#### Thoras Metrics Collector
| Key | Type | Default | Description |
| --- | --- | --- | --- |
| metricsCollector.persistence.enabled | Bool | false | Enables persistence for Thoras metrics collector |
| metricsCollector.persistence.volumeName | String | "" | PV name for PVC. Keep blank if using dynamic provisioning |
| metricsCollector.persistence.storageClassName | String | "" | Storage class for PVC |
| metricsCollector.collector.name | String | thoras-collector | Thoras collector container name |
| metricsCollector.search.imageTag | String | 8.12.1 | Elasticsearch image tag |
| metricsCollector.search.name | String | elasticsearch | Elasticsearch container name |
| metricsCollector.search.containerPort | Number | 9200 | Elasticsearch port |
| metricsCollector.purge.ttl | String | 30d | How long to keep metrics data in Elasticsearch |
| metricsCollector.purge.schedule | String | 00 00 * * * | Cron expression for metrics purge job |
| metricsCollector.init.imageTag | String | latest | Image tag for metrics collector init container |

#### Thoras API Server
| Key | Type | Default | Description |
| --- | --- | --- | --- |
| thorasApiServer.containerPort | Number | 8443 | Thoras API port |
| thorasApiServer.port | Number | 443 | Thoras API service port |
| thorasApiServer.limits.cpu | String | 1000m | Thoras API CPU limit |
| thorasApiServer.limits.memory | String | 1000Mi | Thoras API memory limit |
| thorasApiServer.requests.cpu | String | 1000Mi | Thoras API CPU request |
| thorasApiServer.requests.memory | String | 1000Mi | Thoras API memory request |

#### Thoras Dashboard
| Key | Type | Default | Description |
| --- | --- | --- | --- |
| thorasDashboard.enabled | Bool | true | Enables the Thoras Dashboard |
| thorasDashboard.serviceAccount.create | Bool | true | Creates a Thoras-maintained service account for the Thoras Dashboard pod |
| thorasDashboard.serviceAccount.name | String | thoras-dashboard | Service account name for Thoras Dashboard pod |
| thorasDashboard.rbac.create | Bool | true | Creates cluster role for Thoras Dashboard pod |
| thorasDashboard.podAnnotations | Object | {} | Pod Annotations for Thoras Dashboard |
| thorasDashboard.containerPort | Number | 3000 | Thoras Dashboard port |
| thorasDashboard.port | Number | 3000 | Thoras Dashboard service port |
| thorasDashboard.limits.cpu | String | 1000m | Thoras Dashboard CPU limit |
| thorasDashboard.limits.memory | String | 1000Mi | Thoras Dashboard memory limit |
| thorasDashboard.requests.cpu | String | 1000Mi | Thoras Dashboard CPU request |
| thorasDashboard.requests.memory | String | 1000Mi | Thoras Dashboard memory request |
