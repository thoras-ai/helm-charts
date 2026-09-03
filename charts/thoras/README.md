# Thoras

Thoras is an ML-powered platform that helps SRE teams view the future of their Kubernetes workloads.

This Helm Chart installs [Thoras](https://www.thoras.ai) onto Kubernetes.

![Version: 4.144.2](https://img.shields.io/badge/Version-4.144.2-informational?style=flat-square) ![AppVersion: 4.119.0](https://img.shields.io/badge/AppVersion-4.119.0-informational?style=flat-square)

## Requirements

* Thoras license key (email support@thoras.ai if you don’t have one)
* Recommended Kubernetes Minimum: 1.24+

## Upgrading

A major chart version change (like v1.2.3 -> v2.0.0) indicates that there is an incompatible breaking change needing manual actions.

Detailed upgrade procedures found [here](./UPGRADE.md).

### [To 5.0.0](./UPGRADE.md#to-500)

- **Dashboard now requires authentication.** Fronted by an oauth2-proxy
  sidecar (`htpasswd` default, `oidc` optional).
    * If you currently ship an oauth2-proxy sidecar, see [migration docs](./UPGRADE.md#migrating-from-the-standalone-oauth2-proxy-sidecar).
    * If you provide external auth via ingress or gateway, see [externally-managed auth notes](./UPGRADE.md#externally-managed-auth).
- **Chart no longer seeds Secrets.** A new `thoras-config-controller`
  component owns seeding and rotation. Upgrades from 4.x must go through
  5.x with `legacySecretSeeding: true` before flipping it off; see
  [Migrating from 4.x](./UPGRADE.md#migrating-from-4x).
- **`featureFlags.enableSimpleAuthSecret` renamed** to
  `apiClientSecret.enabled`. Legacy field still works as an alias; see
  [Feature flag deprecation](./UPGRADE.md#feature-flag-deprecation).

See [UPGRADE.md](./UPGRADE.md#to-500) for step-by-step migration.

## Installing the Chart

### Use the Thoras Helm repo

Install the Thoras Helm repo, which will give you access to all of the
Thoras Helm charts.

```
helm repo add thoras https://thoras-ai.github.io/helm-charts
helm repo update thoras
```

### Install Thoras

1. Note the name of your license key file. We'll use `thoras_license.txt`
   in the example below.
2. Install Thoras via Helm:

```
helm install thoras thoras/thoras \
  --namespace thoras \
  --create-namespace \
  --set imageCredentials.password="$(cat ./thoras_license.txt)"
```

New installs should also set `legacySecretSeeding: false` in a values
file — the flag only exists as a migration source for existing 4.x
deployments. See [Migrating from 4.x](./UPGRADE.md#migrating-from-4x).

### Verify installation

Confirm all Thoras pods reach `Running` status (usually takes 1-2
minutes):

```
kubectl get pods -n thoras
```

On a fresh install the workload pods briefly report
`CreateContainerConfigError` while they wait for config-controller to
seed `thoras-config-controller`. This resolves itself; no action is
needed.

### Load the dashboard

Port-forward the dashboard Service to your workstation:

```
kubectl port-forward -n thoras svc/thoras-dashboard 8080:80
```

Then open <http://localhost:8080>. At chart defaults the dashboard is
fronted by an oauth2-proxy sidecar in `htpasswd` mode. Sign in with:

- **Username**: `thoras` (`thorasDashboard.auth.htpasswd.username`)
- **Password**: seeded by config-controller into the
  `thoras-config-controller` Secret:

  ```
  kubectl get secret thoras-config-controller -n thoras \
    -o jsonpath='{.data.dashboard-auth-password}' | base64 -d
  ```

If you pinned the password in values or point at your own Secret via
`thorasDashboard.auth.htpasswd.existingSecret`, use that instead; the
lookup above only applies to the default seeded-by-controller path. See
[Secrets](#secrets) for the full resolution model.

## Secrets

Every credential resolves to exactly one of three places, in this order:

| # | Where you configure it | Where it is stored | Who writes it |
|---|---|---|---|
| 1 | `*.existingSecret.secretName` / `*SecretRefName` | your own Secret | you |
| 2 | the plain values field | `thoras-helm-values` | Helm |
| 3 | nothing — leave it empty | `thoras-config-controller` | config-controller |

| Credential | Existing Secret | Values field |
|---|---|---|
| API client token | `apiClientSecret.existingSecret.{secretName,secretKey}` | `apiClientSecret.secret` |
| Dashboard password | `thorasDashboard.auth.htpasswd.existingSecret.{secretName,passwordKey}` | `thorasDashboard.auth.htpasswd.password` |
| Dashboard cookie secret | `thorasDashboard.auth.htpasswd.existingSecret.{secretName,cookieSecretKey}` | `thorasDashboard.auth.htpasswd.cookieSecret` |
| TimescaleDB DSN | `externalTimescale.{secretRefName,secretRefKey}` | `externalTimescale.dsn` |
| TimescaleDB password | — (bundled database only) | — (not configurable) |
| Slack webhook | `slackWebhookUrlSecretRef{Name,Key}` | `slackWebhookUrl` |
| Cloud-sync cluster key | `cloudSync.clusterKeySecretRef{Name,Key}` | `cloudSync.clusterKey` |
| Dashboard OIDC credentials | `thorasDashboard.auth.oidc.existingSecret.*` | — (never chart-managed) |

Notes:

- `thoras-helm-values` holds only what you pinned in values. It is fully
  deterministic — no `lookup`, no random generation — so `helm template` and
  Argo CD render exactly what an apply produces. **Argo CD users no longer
  need `ignoreDifferences` on this Secret.**
- `thoras-config-controller` is created and owned by config-controller, never
  by Helm, so Argo CD does not track or prune it. Values are seeded once and
  never rotated.
- The bundled TimescaleDB password cannot be pinned. There is no rotation
  path for a database that is already initialised, so the chart fails if
  `metricsCollector.timescale.password` is set.
- Slack and cloud-sync are never seeded. Leave them unset and the consuming
  environment variable is omitted entirely.

### Rotating secrets

config-controller drives every rotation. It observes changes to the managed
Secret, to `thoras-helm-values`, and to any customer-managed Secret referenced
via a `existingSecret` field (all three are projected into the controller pod
as files), then rolls affected workloads in dependency order on its own.
Rotation propagates within `pollInterval + rolloutDebounce` (defaults: 30s +
10s) plus the time to evict and replace each tier.

**Seeded values are never rotated automatically.** config-controller writes a
key once and then leaves it alone. To change one, delete the key from
`thoras-config-controller` and let the controller re-seed it:

```bash
kubectl patch secret thoras-config-controller -n <namespace> \
  --type=json -p='[{"op":"remove","path":"/data/dashboard-auth-password"}]'
```

**Values you pinned in `values.yaml`** rotate on the next `helm upgrade`:
change the field, apply, and the controller picks the new value up from the
re-rendered `thoras-helm-values` Secret.

**Values in Secrets you manage** rotate whenever you update the Secret. No
`helm upgrade` needed; the controller sees the file change and rolls the
consumers.

Rotating the dashboard cookie secret invalidates every logged-in dashboard
session.

### Changing ConfigMap-backed settings

Values that land in a chart ConfigMap — `thorasMonitor.config`,
`metricsCollector.timescale.config.content`, the dashboard's nginx and
oauth2-proxy settings — roll their consumers on the next `helm upgrade`. The
chart puts a `checksum/config` annotation over the ConfigMap's data on each
consumer's pod template, so no manual restart is needed. These ConfigMaps are
mounted with `subPath`, which Kubernetes never updates in place, so the
restart is what makes the change take effect.

The annotation is computed at template time, so Argo CD renders the same value
an apply produces and reports no drift.

## ArgoCD

Argo CD renders manifests without `lookup`, so a small set of chart
outputs still drifts on every reconcile even after the 5.x
config-controller migration:

- The webhook configs' `caBundle` is injected in-cluster after apply
  (either by cert-manager's CA injector when
  `thorasOperator.webhookCertGen.certManager.enabled: true`, or by the
  certgen patch Job otherwise).
- The `thoras-forecast-worker` replica count is managed by Thoras at
  runtime.

Tell Argo to ignore these fields in your `Application`'s
`spec.ignoreDifferences`:

```yaml
ignoreDifferences:
  - group: admissionregistration.k8s.io
    kind: MutatingWebhookConfiguration
    jqPathExpressions:
      - ".webhooks[]?.clientConfig.caBundle"
  - group: admissionregistration.k8s.io
    kind: ValidatingWebhookConfiguration
    jqPathExpressions:
      - ".webhooks[]?.clientConfig.caBundle"
  - jsonPointers:
      - /spec/replicas
    kind: Deployment
    name: thoras-forecast-worker
```

`thoras-helm-values` is deterministic and needs no `ignoreDifferences`;
`thoras-config-controller` is owned by the controller and is not tracked
by Argo CD at all. The one exception is the pair of legacy Secrets
(`api-client-secret`, `thoras-timescale-password`) rendered under
`legacySecretSeeding: true` during the 4.x -> 5.x migration; see
[Migrating from 4.x](./UPGRADE.md#migrating-from-4x) for the extra
entries and when to drop them.

The full `Application` example plus the ArgoCD HPA custom health
assessment (needed when Argo watches a Thoras-horizontally-controlled
workload) live at
[docs.thoras.ai/guides/argo-cd](https://docs.thoras.ai/guides/argo-cd).

## helm template

Under `helm template` there is no cluster for config-controller to seed
into, so any credential not already pinned or pointed at an existing
Secret renders empty — and even randomly-generated placeholders would
churn on every render. Either pin every chart-generated credential or
point the chart at a pre-existing Secret you manage out-of-band
(Sealed Secrets, External Secrets, SOPS, ...).

### Pinning credentials

Set the following values to pin:

| Credential                  | Pin in values                                |
| --------------------------- | -------------------------------------------- |
| API client bearer token     | `apiClientSecret.secret`                     |
| Dashboard htpasswd password | `thorasDashboard.auth.htpasswd.password`     |
| Dashboard htpasswd cookie   | `thorasDashboard.auth.htpasswd.cookieSecret` |
| TimescaleDB DSN (external)  | `externalTimescale.dsn`                      |

### Using external secret references

Or point the chart at Secrets you manage out-of-band via the following
`existingSecret` / `secretRef` fields:

| Credential                                 | secretName field                                          | Key field(s)                                                                                    |
| ------------------------------------------ | --------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| API client bearer token                    | `apiClientSecret.existingSecret.secretName`               | `apiClientSecret.existingSecret.secretKey`                                                      |
| Dashboard htpasswd password + cookie       | `thorasDashboard.auth.htpasswd.existingSecret.secretName` | `thorasDashboard.auth.htpasswd.existingSecret.passwordKey`, `.cookieSecretKey`                  |
| Dashboard OIDC client credentials + cookie | `thorasDashboard.auth.oidc.existingSecret.secretName`     | `thorasDashboard.auth.oidc.existingSecret.clientIDKey`, `.clientSecretKey`, `.cookieSecretKey`  |
| TimescaleDB DSN (external)                 | `externalTimescale.secretRefName`                         | `externalTimescale.secretRefKey`                                                                |

**Notes:**
- Pinning the in-cluster TimescaleDB password
  (`metricsCollector.timescale.password`) for the chart-managed
  TimescaleDB is not supported; use `externalTimescale`, or run under a
  live cluster and let config-controller seed
  `thoras-config-controller`.
- Under `thorasDashboard.auth.mode: oidc`, dashboard credentials come
  from your IdP via `thorasDashboard.auth.oidc.existingSecret.secretName`
  and are never chart-generated, so no dashboard pinning is needed.

### Webhook certificates

Set `thorasOperator.webhookCertGen.certManager.enabled: true` when
rendering offline. The default certgen path emits a set of imperative
`Job`/`ClusterRole`/`ServiceAccount` resources gated on Helm lifecycle
hooks (`pre-install`, `pre-upgrade`), which GitOps tools handle poorly.
cert-manager mode replaces them with declarative `Issuer` and
`Certificate` CRs. Requires cert-manager installed in the cluster.

## Configuration

### Affinity Configuration

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

**Note:** `metricsCollector` and `thorasForecast` ship optional built-in anti-affinity rules to avoid co-location. These are opt-in: `featureFlags.enableForecastCollectorAntiAffinity` (default `false`) keeps the collector and forecast worker on separate nodes; `thorasForecast.enableSelfAntiAffinity` (default `false`) spreads forecast-worker replicas. When enabled they merge with global/component settings.

### Example Thoras Monitor Configuration

`thorasMonitor.config` is raw monitor YAML. `general.metadata` holds optional string key/value pairs that are surfaced on every named monitor Slack alert, one line per pair. This is useful to disambiguate clusters that share a name across regions (e.g. `prod-a` in `use1` and `euw1`):

```yaml
# values.yaml
---
thorasMonitor:
  config: |
    general:
      name: 'prod-a'
      monitor_cadence: 5m
      metadata:
        region: euw1
    alerts:
      - name: thoras_deployments
        notification_cooldown: 15m
        enabled: true
      - name: no_suggestions
        notification_cooldown: 15m
        enabled: true
```

The alert is then prefixed with the metadata:

```
*Cluster:* prod-a
*region:* euw1
*Alert:* thoras_deployments
...
```

### Thoras Dashboard

#### Thoras Dashboard Authentication

The dashboard ships with HTTP authentication enabled by default, terminated by
an [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/) sidecar. Two
modes are supported via `thorasDashboard.auth.mode`: `htpasswd` (default,
chart-managed username + password) and `oidc` (full OIDC login flow against
your identity provider). Fields under the unused mode's block are silently
ignored, so switching between modes is just flipping `auth.mode`. Credentials
and session cookies are only meaningful behind TLS — terminate TLS at the edge.

##### Bring your own auth

Set `thorasDashboard.auth.enabled: false` to disable the built-in sidecar and
front the dashboard with your own auth — for example a custom SSO sidecar
wired through `extraContainers` and `service.targetPort`, an edge-level auth
plugin, or a service-mesh policy.

```yaml
thorasDashboard:
  auth:
    enabled: false
```

This leaves the dashboard reachable in-cluster with no auth in front of it,
which exposes part of the API it proxies to and subverts `apiClientSecret`.
Only safe if something external gates every request.

##### htpasswd mode

config-controller seeds a random password and cookie secret on first install
and never rotates them. Retrieve the password:

```bash
kubectl get secret thoras-config-controller -n <namespace> \
  -o jsonpath='{.data.dashboard-auth-password}' | base64 -d
```

Pin them instead if you would rather manage them in values, in which case they
live in `thoras-helm-values`. Changing a pinned value invalidates every
logged-in session.

```yaml
thorasDashboard:
  auth:
    htpasswd:
      username: thoras
      password: <your-password>
      cookieSecret: <your-32-char-cookie-secret>
```

Both approaches are GitOps-safe: seeded values live outside Helm's control and
pinned values render deterministically.

##### OIDC mode

Register the dashboard as an OIDC application with your identity provider,
create a Kubernetes Secret with the resulting credentials, and switch the
chart into OIDC mode:

```yaml
thorasDashboard:
  auth:
    mode: oidc
    oidc:
      provider: oidc  # or okta, entra-id, google, ...
      issuerURL: https://<your-okta-domain>/oauth2/default
      redirectURL: https://thoras.example.com/oauth2/callback
      emailDomains: [example.com]
      existingSecret:
        secretName: oauth2-proxy-secrets
```

The Secret must contain three keys (names configurable via
`auth.oidc.existingSecret.{clientIDKey,clientSecretKey,cookieSecretKey}`):

```bash
kubectl create secret generic oauth2-proxy-secrets -n <namespace> \
  --from-literal=client-id="<idp-client-id>" \
  --from-literal=client-secret="<idp-client-secret>" \
  --from-literal=cookie-secret="$(openssl rand -base64 32 | head -c 32 | base64)"
```

The `redirectURL` must exactly match the redirect URI registered on the IdP
application.

##### Notes

- `thorasDashboard.auth.cookieSecure` defaults to `false` so `kubectl
  port-forward` works (Safari drops Secure cookies over plain HTTP).
  Set it to `true` in production; it requires TLS at the edge.
- The sign-in page is chart-branded (Thoras wordmark, dashboard-sidebar
  primary button) in both auth modes. Under `mode: htpasswd` only the
  username/password form is shown; under `mode: oidc` the provider
  button is retained as the entry point.
- With auth enabled, the oauth2-proxy sidecar owns
  `thorasDashboard.containerPort` and proxies to nginx on `127.0.0.1:8181`
  (loopback-only). To hit nginx directly for debugging:
  ```
  kubectl debug -n thoras <dashboard-pod> -it \
    --image=<debug-image> --target=thoras-dashboard
  # curl http://127.0.0.1:8181/
  ```

#### Example Thoras Dashboard Ingress Configuration

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

#### Example Thoras Dashboard Gateway API Configuration

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

### NetworkPolicy

Set `networkPolicy.enabled: true` to have the chart render a
`CiliumNetworkPolicy` (`cilium.io/v2`) per component. Requires
[Cilium](https://cilium.io/) in the cluster; policies are no-ops with
any other CNI.

Each policy allows all ingress from same-namespace endpoints, permits
DNS to `kube-system/kube-dns`, and opens the component's public port to
its expected callers (`entities: all` for the dashboard, in-namespace
callers for API/collector/worker/forecast).

**NOTE:** when Thoras Dashboard auth is enabled in OIDC mode, the chart
opens broad egress on the dashboard's `CiliumNetworkPolicy` to
`world:443` so oauth2-proxy can reach the IdP's discovery, token, and
userinfo endpoints. Okta / Entra / other IdPs resolve to broad, drifting
CIDR ranges, so a scoped rule would be brittle. Tighten by layering an
additional `CiliumNetworkPolicy` that restricts egress to specific IdP
hostnames (`toFQDNs`), or manage egress out-of-band.

## Values

### Global

| Key                                | Type    | Default                                          | Description                                                                                                            |
| ---------------------------------- | ------- | ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| thorasVersion                      | String  | 4.119.0                                          | Thoras app version                                                                                                     |
| imageCredentials.registry          | String  | us-east4-docker.pkg.dev/thoras-registry/platform | Container registry name                                                                                                |
| imageCredentials.username          | String  | \_json_key_base64                                | Container registry username                                                                                            |
| imageCredentials.password          | String  | ""                                               | Container registry auth string                                                                                         |
| resourceQuota.enabled              | Bool    | false                                            | Enables resource quotas within Thoras                                                                                  |
| resourceQuota.pods                 | Number  | 200                                              | Maximum number of pods allowed                                                                                         |
| resourceQuota.cronjobs             | Number  | 200                                              | Maximum number of cronjobs allowed                                                                                     |
| resourceQuota.jobs                 | Number  | 200                                              | Maximum number of jobs allowed                                                                                         |
| logLevel                           | String  | info                                             | Default log level                                                                                                      |
| env                                | list    | []                                               | Additional environment variables that will be passed onto all Thoras components                                        |
| slackWebhookUrl                    | String  | ""                                               | Slack Webhook URL destination for notifications.                                                                       |
| slackErrorsEnabled                 | Boolean | false                                            | Determines if error-level logs are sent to `slackWebHookUrl`                                                           |
| cloudSync.clusterKeyID             | String  | ""                                               | Identity of cluster sync key. Cloud sync is disabled if not specified                                                  |
| cloudSync.clusterKey               | String  | ""                                               | Unique key identifying this cluster to the cloud.                                                                      |
| cloudSync.baseUrl                  | String  | "https://console.thoras.ai"                      | Thoras cloud base url.                                                                                                 |
| queriesPerSecond                   | String  | "50"                                             | Sets a maximum threshold for K8s API qps                                                                               |
| nodeSelector                       | Object  | {}                                               | Node selectors to designate specific nodes to run Thoras workloads                                                     |
| tolerations                        | Array   | []                                               | Node taint tolerations to be used for to set up Thoras workloads                                                       |
| affinity                           | Object  | {}                                               | Global affinity rules applied to all components (components opt-in by default via useGlobalAffinity)                   |
| rbac.namespaces                    | Array   | []                                               | List of namespaces used to scope Roles+Bindings for the Thoras apps. If undefined, ClusterRoles will be used instead   |
| costRefreshBatching.enabled        | Boolean | true                                             | Enables refreshing cost data in concurrent batches                                                                     |
| costRefreshBatching.batchSize      | Number  | 200                                              | Number of AST costs to refresh per batch                                                                               |
| costRefreshBatching.maxConcurrency | Number  | 5                                                | Number of concurrent AST cost refresh batches to process concurrently                                                  |
| apiClientSecret.enabled                         | Boolean | true                                             | If true, components authenticate to the API server with a shared bearer token |
| apiClientSecret.secret                          | String  | ""                                               | Shared secret components send to the API server when `apiClientSecret.enabled` is true. Chart generates if empty. Setting a value overrides any existing value on the next `helm upgrade`; consumer workloads require a manual rollout (see [rotating secrets](#rotating-secrets)). `apiClientSecret.existingSecret` takes precedent. |
| apiClientSecret.existingSecret.secretName       | String  | ""                                               | Read the API-client secret from this pre-existing externally managed secret. Required key documented below |
| apiClientSecret.existingSecret.secretKey        | String  | api-client-secret                                | Key in `apiClientSecret.existingSecret.secretName` that holds the value.                                                                                                            |

### Feature Flags

The following flags are considered temporary and gate access to specific behaviors that still undergoing testing before general availability.

| Key                                            | Type    | Default | Description                                                                        |
| ---------------------------------------------- | ------- | ------- | ---------------------------------------------------------------------------------- |
| featureFlags.enableNodeDetailsCollector        | Boolean | true    | Collection of node detail snapshots                                                |
| featureFlags.enablePgLargeObjectStorage        | Boolean | true    | If true, enables storing blobs as postgres large objects                           |
| featureFlags.enableInformersStripManagedFields | Boolean | true    | If true, enables informer memory optimizations                                     |
| featureFlags.enableTypedInformers              | Boolean | true    | If true, enables additional informer memory optimizations                          |
| featureFlags.enableAstRecordMirroring          | Boolean | true    | If true, ASTs are mirrored to the database component                               |
| featureFlags.enablePodLogStreaming             | Boolean | false   | If true, the API server streams container logs and the dashboard shows pod logs    |

### Thoras Forecast

| Key                                          | Type     | Default                | Description                                                                                    |
| -------------------------------------------- | -------- | ---------------------- | ---------------------------------------------------------------------------------------------- |
| thorasForecast.serviceAccount.name           | String   | thoras-forecast-worker | Service account name for Thoras forecast worker pod                                            |
| thorasForecast.imageTag                      | String   | .thorasVersion         | Image tag for Thoras Forecast job                                                              |
| thorasForecast.skipCache                     | Boolean  | false                  | Directs the forecaster to skip to model cache                                                  |
| thorasForecast.ignoreNewPods                 | Boolean  | true                   | Directs forecaster to adjust CPU and memory metrics temporarily for new pods                   |
| thorasForecast.enableDecoupledTraining       | Boolean  | true                   | Enables async training mode where forecasts report "needs_training" instead of training inline |
| thorasForecast.useAstMetricsSeries           | Boolean  | true                   | Enables catalog-free training data fetching via the AST metrics series endpoint                |
| thorasForecast.useForecasterComputedMetricId | Boolean  | true                   | Computes legacy metric IDs locally in Python instead of fetching from the catalog              |
| thorasForecast.worker.podAnnotations         | Object   | {}                     | Pod Annotations for Thoras Forecast                                                            |
| thorasForecast.worker.labels                 | Object   | {}                     | Pod labels for Thoras Forecast                                                                 |
| thorasForecast.worker.replicas               | Number   | unset                  | Number of `thoras-forecast-worker` replicas. Left unset by default so the forecast worker scaler manages replicas; setting a value disables the scaler |
| thorasForecast.worker.pollingInterval        | Number   | 15                     | Polling interval to check for work for `thoras-forecast-workers`                               |
| thorasForecast.worker.forecastTimeout        | Number   | 600                    | Maximum time (in seconds) spent on a single forecast by the `thoras-forecast-worker`           |
| thorasForecast.trainingJitterMinutes         | Number   | 0                      | Random jitter (in minutes, 0-120) added to training threshold to desynchronize training jobs   |
| thorasForecast.minLookbackToScale            | Duration | 24h                    | Minimum lookback window before autonomous scaling (minimum: 3h). Supports 3h, 180m, 1h30m      |
| thorasForecast.prometheus.host               | String   | ::                     | Address the metrics server binds to (dual-stack by default)                                    |

### Thoras Operator

| Key                                    | Type    | Default         | Description                                                                                                   |
| -------------------------------------- | ------- | --------------- | ------------------------------------------------------------------------------------------------------------- |
| thorasOperator.postUpgradeHook.enabled | Boolean | true            | Runs the operator's post-upgrade migration steps as a Job after each upgrade; requires thorasVersion 4.120.0+ |
| thorasOperator.serviceAccount.name     | String  | thoras-operator | Service account name for Thoras operator pod                                                                  |
| thorasOperator.podAnnotations          | Object  | {}              | Pod Annotations for Thoras Operator                                                                           |
| thorasOperator.labels                  | Object  | {}              | Pod/service labels for Thoras Operator                                                                        |
| thorasOperator.resources               | Object  | {}              | Specify the resources block. Takes precedence if set.                                                         |
| thorasOperator.limits.memory           | String  | 4Gi             | Legacy field for setting Thoras Operator memory limit                                                         |
| thorasOperator.requests.cpu            | String  | 100m            | Legacy field for setting Thoras Operator CPU request                                                          |
| thorasOperator.requests.memory         | String  | 1Gi             | Legacy field for setting Thoras Operator memory request                                                       |
| thorasOperator.slackErrorsEnabled      | Boolean | false           | Determines if error-level logs are sent to `slackWebHookUrl`                                                  |
| thorasOperator.logLevel                | String  | Nil             | Logging level                                                                                                 |
| thorasOperator.queriesPerSecond        | String  | "50"            | Sets a maximum threshold for K8s API qps                                                                      |
| thorasOperator.prometheus.enabled      | Boolean | true            | Enables a prometheus metric exporter                                                                          |
| thorasOperator.prometheus.port         | Number  | 9101            | Port for the prometheus metric exporter                                                                       |
| thorasOperator.pprof.enabled           | Boolean | false           | Enable pprof endpoint.                                                                                        |

### External TimescaleDB

When set, the chart skips deploying the in-cluster TimescaleDB and configures
all components to use an external database instead. The TimescaleDB extension
must be pre-installed and managed externally.

| Key                             | Type   | Default | Description                                                                                           |
| ------------------------------- | ------ | ------- | ----------------------------------------------------------------------------------------------------- |
| externalTimescale.dsn           | String | ""      | Full postgres DSN including database name, e.g. `postgres://user:pass@host:5432/tsdb?sslmode=require` |
| externalTimescale.secretRefName | String | ""      | Name of a pre-existing Secret containing the DSN (alternative to `dsn`). Requires `secretRefKey`      |
| externalTimescale.secretRefKey  | String | ""      | Key within the Secret that holds the DSN. Requires `secretRefName`                                    |

### Thoras Metrics Collector

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
| metricsCollector.timescale.imageTag                             | String  | 2.28.2-pg16      | Timescale image tag                                          |
| metricsCollector.timescale.extensionVersion                     | String  | 2.28.2           | Timescale extension version - should match imageTag          |
| metricsCollector.timescale.name                                 | String  | timescale        | Timescale container name                                     |
| metricsCollector.timescale.containerPort                        | Number  | 5432             | Timescale port                                               |
| metricsCollector.blobService.port                               | Number  | 80               | Blob service external port                                   |
| metricsCollector.blobService.logLevel                           | String  | info             | Logging level                                                |
| metricsCollector.blobService.containerPort                      | Number  | 8080             | Blob service internal port                                   |
| metricsCollector.blobService.pprof.enabled                      | Boolean | false            | Enable pprof endpoint.                                       |
| metricsCollector.slackErrorsEnabled                             | Boolean | false            | Determines if error-level logs are sent to `slackWebHookUrl` |
| metricsCollector.init.imageTag                                  | String  | latest           | Image tag for metrics collector init container               |

### Thoras API Server

| Key                                            | Type    | Default    | Description                                                             |
| ---------------------------------------------- | ------- | ---------- | ----------------------------------------------------------------------- |
| thorasApiServerV2.serviceAccount.name          | String  | thoras-api | Service account name for Thoras api service pod                         |
| thorasApiServerV2.podAnnotations               | Object  | {}         | Pod Annotations for Thoras API                                          |
| thorasApiServerV2.labels                       | Object  | {}         | Pod/service labels for Thoras API                                       |
| thorasApiServerV2.containerPort                | Number  | 8080       | Thoras API port                                                         |
| thorasApiServerV2.port                         | Number  | 80         | Thoras API service port                                                 |
| thorasApiServerV2.resources                    | Object  | {}         | Specify the resources block. Takes precedence if set.                   |
| thorasApiServerV2.limits.memory                | String  | 4Gi        | Legacy field for setting Thoras API memory limit                        |
| thorasApiServerV2.requests.cpu                 | String  | 128m       | Legacy field for setting Thoras API CPU request                         |
| thorasApiServerV2.requests.memory              | String  | 1Gi        | Legacy field for setting Thoras API memory request                      |
| thorasApiServerV2.slackErrorsEnabled           | Boolean | false      | Determines if error-level logs are sent to `slackWebHookUrl`            |
| thorasApiServerV2.logLevel                     | String  | Nil        | Logging level                                                           |
| thorasApiServerV2.queriesPerSecond             | String  | "50"       | Sets a maximum threshold for K8s API qps                                |
| thorasApiServerV2.prometheus.enabled           | Boolean | true       | Enables a prometheus metric scrape point                                |
| thorasApiServerV2.pprof.enabled                | Boolean | false      | Enable pprof endpoint.                                                  |
| thorasApiServerV2.enableViewCacheQueryLiveJoin | Boolean | true       | Enables AST view queries joining view cache results with live k8s state |

### Thoras Worker

| Key                                                  | Type    | Default       | Description                                                                                                                          |
| ---------------------------------------------------- | ------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| thorasWorker.serviceAccount.name                     | String  | thoras-worker | Service account name for Thoras worker pod                                                                                           |
| thorasWorker.podAnnotations                          | Object  | {}            | Pod Annotations for Thoras worker                                                                                                    |
| thorasWorker.labels                                  | Object  | {}            | Pod/service labels for Thoras worker                                                                                                 |
| thorasWorker.resources                               | Object  | {}            | Specify the resources block. Takes precedence if set.                                                                                |
| thorasWorker.limits.memory                           | String  | 4Gi           | Legacy field for setting Thoras Worker memory limit                                                                                  |
| thorasWorker.requests.cpu                            | String  | 128m          | Legacy field for setting Thoras Worker CPU request                                                                                   |
| thorasWorker.requests.memory                         | String  | 1Gi           | Legacy field for setting Thoras Worker memory request                                                                                |
| thorasWorker.slackErrorsEnabled                      | Boolean | false         | Determines if error-level logs are sent to `slackWebHookUrl`                                                                         |
| thorasWorker.forecastRescueMaxAttempts               | Number  | 3             | Times a stuck forecast may be fast-tracked to the head of the queue before it falls back to its normal schedule; -1 disables the cap |
| thorasWorker.logLevel                                | String  | Nil           | Logging level                                                                                                                        |
| thorasWorker.queriesPerSecond                        | String  | "50"          | Sets a maximum threshold for K8s API qps                                                                                             |
| thorasWorker.prometheus.enabled                      | Boolean | true          | Enables a prometheus metric exporter                                                                                                 |
| thorasWorker.prometheus.port                         | Number  | 9102          | Port for the prometheus metric exporter                                                                                              |
| thorasWorker.enableMetricIntegrityWorker             | Boolean | true          | Enable metric integrity worker                                                                                                       |
| thorasWorker.enableDeploymentMonitorWorker           | Boolean | true          | Enable deployment monitor worker                                                                                                     |
| thorasWorker.maxTimeseriesMetricCacheSizeMb          | Number  | 1000          | Configure cache size that triggers LRU eviction                                                                                      |
| thorasWorker.enableUnifiedAstUtilizationMonitor      | Boolean | true          | Enable the unified AST utilization monitor                                                                                           |
| thorasWorker.enableAstViewCacheStateReconcilerWorker | Boolean | true          | Enable view cache state reconciler jobs                                                                                              |
| thorasWorker.pprof.enabled                           | Boolean | false         | Enable pprof endpoint.                                                                                                               |

### Thoras Config Controller

| Key                                                | Type    | Default                                                                                                        | Description                                                                                            |
| -------------------------------------------------- | ------- | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| thorasConfigController.enabled                     | Boolean | true                                                                                                           | Deploy the controller. Disabling requires every credential to be pinned or point at an existing Secret |
| thorasConfigController.serviceAccount.name         | String  | thoras-config-controller                                                                                       | Service account name for the controller pod                                                            |
| thorasConfigController.podAnnotations              | Object  | {}                                                                                                             | Pod annotations for the controller                                                                     |
| thorasConfigController.labels                      | Object  | {}                                                                                                             | Pod/service labels for the controller                                                                  |
| thorasConfigController.replicas                    | Number  | 1                                                                                                              | Number of `thoras-config-controller` replicas to use                                                   |
| thorasConfigController.resources                   | Object  | {}                                                                                                             | Specify the resources block. Takes precedence if set.                                                  |
| thorasConfigController.limits.memory               | String  | 256Mi                                                                                                          | Legacy field for setting the controller memory limit                                                   |
| thorasConfigController.requests.cpu                | String  | 10m                                                                                                            | Legacy field for setting the controller CPU request                                                    |
| thorasConfigController.requests.memory             | String  | 64Mi                                                                                                           | Legacy field for setting the controller memory request                                                 |
| thorasConfigController.logLevel                    | String  | info                                                                                                           | Logging level                                                                                          |
| thorasConfigController.prometheus.enabled          | Boolean | true                                                                                                           | Enables a prometheus metric exporter                                                                   |
| thorasConfigController.prometheus.port             | Number  | 9103                                                                                                           | Port for the prometheus metric exporter                                                                |
| thorasConfigController.pprof.enabled               | Boolean | false                                                                                                          | Enable pprof endpoint.                                                                                 |
| thorasConfigController.enableSeeding               | Boolean | true                                                                                                           | Write seeded and migrated values into the managed Secret                                               |
| thorasConfigController.enableRestartRollouts       | Boolean | true                                                                                                           | Apply rollouts. With this off the controller logs the diffs it would apply but touches nothing         |
| thorasConfigController.pollInterval                | String  | 30s                                                                                                            | Interval between reconcile ticks                                                                       |
| thorasConfigController.rolloutDebounce             | String  | 10s                                                                                                            | Coalescing window after a change before a rollout starts                                               |
| thorasConfigController.rolloutTimeout              | String  | 5m                                                                                                             | Per-workload deadline for eviction plus replacement readiness. A tier that overruns aborts the sequence                              |
| thorasConfigController.restartOrder                | Array   | metrics-collector, thoras-api-server-v2, thoras-operator, thoras-worker, thoras-forecast-worker, thoras-dashboard | Strict sequential restart tiers. Unlisted workloads are restarted last, together                       |
| thorasConfigController.restartExclude              | Array   | [thoras-config-controller]                                                                                     | Workloads never restarted. Must keep the controller itself                                             |

### Thoras Dashboard

| Key                                              | Type    | Default          | Description                                                              |
| ------------------------------------------------ | ------- | ---------------- | ------------------------------------------------------------------------ |
| thorasDashboard.enabled                          | Bool    | true             | Enables the Thoras Dashboard                                             |
| thorasDashboard.serviceAccount.create            | Bool    | true             | Creates a Thoras-maintained service account for the Thoras Dashboard pod |
| thorasDashboard.serviceAccount.name              | String  | thoras-dashboard | Service account name for Thoras Dashboard pod                            |
| thorasDashboard.rbac.create                      | Bool    | true             | Creates cluster role for Thoras Dashboard pod                            |
| thorasDashboard.podAnnotations                   | Object  | {}               | Pod Annotations for Thoras Dashboard                                     |
| thorasDashboard.labels                           | Object  | {}               | Pod/service labels for Thoras Dashboard                                  |
| thorasDashboard.containerPort                    | Number  | 8080             | Container port for the Thoras Dashboard. Owned by the oauth2-proxy sidecar when `thorasDashboard.auth.enabled` (default), otherwise by nginx directly. |
| thorasDashboard.port                             | Number  | 80               | Thoras Dashboard service port                                            |
| thorasDashboard.resources                        | Object  | {}               | Specify the resources block. Takes precedence if set.                    |
| thorasDashboard.limits.memory                    | String  | 2Gi              | Legacy field for setting Thoras Dashboard memory limit                   |
| thorasDashboard.requests.cpu                     | String  | 100m             | Legacy field for setting Thoras Dashboard CPU request                    |
| thorasDashboard.requests.memory                  | String  | 128Mi            | Legacy field for setting Thoras Dashboard memory request                 |
| thorasDashboard.service.type                     | String  | ClusterIP        | Type of Service to use                                                   |
| thorasDashboard.service.annotations              | Object  | {}               | Service annotations                                                      |
| thorasDashboard.service.clusterIP                | String  | nil              | Service clusterIP when type is ClusterIP                                 |
| thorasDashboard.service.loadBalancerIP           | String  | nil              | Service loadBalancerIP when type is LoadBalancer                         |
| thorasDashboard.service.loadBalancerSourceRanges | List    | nil              | Service loadBalancerSourceRanges when type is LoadBalancer               |
| thorasDashboard.service.externalIPs              | List    | nil              | Service externalIPs                                                      |
| thorasDashboard.auth.enabled                                | Bool    | true                | Fronts the dashboard with an oauth2-proxy sidecar. Disable to run your own auth |
| thorasDashboard.auth.mode                                   | String  | htpasswd            | `htpasswd` (chart-managed username+password) or `oidc` (OIDC via your IdP). Fields under the unused mode's block are silently ignored |
| thorasDashboard.auth.cookieSecure                           | Bool    | false               | Marks session cookies as Secure. Recommended enabled in production. Requires TLS at the edge and breaks Safari via `kubectl port-forward`. Applies to both modes |
| thorasDashboard.auth.imageTag                               | String  | v7.15.4-alpine      | oauth2-proxy sidecar image tag. Applies to both modes                    |
| thorasDashboard.auth.resources                              | Object  | see values.yaml     | oauth2-proxy sidecar resources                                           |
| thorasDashboard.auth.extraArgs                              | List    | []                  | Extra flags appended to the sidecar's `args` verbatim. Applies to both modes. Flags here override any equivalent directive in the chart-generated `oauth2-proxy.cfg` |
| thorasDashboard.auth.htpasswd.username                      | String  | thoras              | Login username under `mode: htpasswd`                                    |
| thorasDashboard.auth.htpasswd.password                      | String  | ""                  | Dashboard login password. Chart generates if empty. Setting a value overrides any existing value on the next `helm upgrade`; consumer workloads require a manual rollout (see [rotating secrets](#rotating-secrets)). `thorasDashboard.auth.htpasswd.existingSecret` takes precedent |
| thorasDashboard.auth.htpasswd.cookieSecret                  | String  | ""                  | Session cookie secret; 16, 24, or 32 bytes (`openssl rand -base64 32`). Chart generates if empty. Setting a value overrides any existing value on the next `helm upgrade`; consumer workloads require a manual rollout, which invalidates all logged-in dashboard sessions (see [rotating secrets](#rotating-secrets)). `thorasDashboard.auth.htpasswd.existingSecret` takes precedent |
| thorasDashboard.auth.htpasswd.existingSecret.secretName     | String  | ""                  | Read the htpasswd password + cookie secret from this pre-existing externally managed secret. Required keys documented below |
| thorasDashboard.auth.htpasswd.existingSecret.passwordKey    | String  | dashboard-auth-password | Key inside `existingSecret.secretName` that holds the password         |
| thorasDashboard.auth.htpasswd.existingSecret.cookieSecretKey | String | dashboard-auth-cookie-secret | Key inside `existingSecret.secretName` that holds the cookie secret  |
| thorasDashboard.auth.htpasswd.initImage.imageTag            | String  | 2.4.68-alpine3.24   | httpd image tag for the init container that regenerates the htpasswd file at pod start |
| thorasDashboard.auth.htpasswd.initImage.resources           | Object  | see values.yaml     | htpasswd init container resources                                        |
| thorasDashboard.auth.oidc.provider                          | String  | oidc                | oauth2-proxy provider name (`oidc`, `okta`, `entra-id`, `google`, ...)   |
| thorasDashboard.auth.oidc.issuerURL                         | String  | ""                  | OIDC issuer URL. Required under `mode: oidc`                             |
| thorasDashboard.auth.oidc.redirectURL                       | String  | ""                  | External redirect URL registered on your IdP app. Required under `mode: oidc` |
| thorasDashboard.auth.oidc.emailDomains                      | List    | ["*"]               | Allowed login email domains. Rendered as repeated oauth2-proxy `email_domains` entries |
| thorasDashboard.auth.oidc.skipProviderButton                | Bool    | true                | Skip oauth2-proxy's provider-choice landing page (safe under OIDC)       |
| thorasDashboard.auth.oidc.insecureAllowUnverifiedEmail      | Bool    | false               | Allow login for accounts with unverified email addresses                 |
| thorasDashboard.auth.oidc.existingSecret.secretName         | String  | ""                  | Pre-existing externally managed secret with the IdP client credentials + cookie secret. Required under `mode: oidc`; the chart never generates these. Required keys documented below |
| thorasDashboard.auth.oidc.existingSecret.clientIDKey        | String  | client-id           | Key inside `existingSecret.secretName` that holds the OIDC client ID     |
| thorasDashboard.auth.oidc.existingSecret.clientSecretKey    | String  | client-secret       | Key inside `existingSecret.secretName` that holds the OIDC client secret |
| thorasDashboard.auth.oidc.existingSecret.cookieSecretKey    | String  | cookie-secret       | Key inside `existingSecret.secretName` that holds the session cookie secret |
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

### Thoras Monitor

| Key                  | Type   | Default | Description                       |
| -------------------- | ------ | ------- | --------------------------------- |
| thorasMonitor.labels | Object | {}      | Pod labels for Thoras monitor     |
| thorasMonitor.config | String | ""      | Thoras Monitor configuration yaml |
