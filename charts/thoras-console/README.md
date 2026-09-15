# Thoras Console

The Thoras console is the control plane that tenant clusters report into. This
Helm Chart installs a self-hosted [Thoras](https://www.thoras.ai) console onto
Kubernetes, as an alternative to the hosted console at `console.thoras.ai`.

![Version: 0.2.0](https://img.shields.io/badge/Version-0.2.0-informational?style=flat-square)

To install the Thoras platform onto a cluster you want to *observe*, you want
the [thoras](../thoras/README.md) chart instead. The two are separate installs
and may share a namespace.

The chart installs `console-api`, a `config-controller` that generates any
credential you do not supply, and — for evaluation only — a bundled TimescaleDB.
The console dashboard arrives in a later release, so today you reach the console
through its API.

## Requirements

- Thoras license key (email support@thoras.ai if you don't have one)
- Recommended Kubernetes Minimum: 1.24+
- For the bundled database: **Kubernetes 1.27+** and a default StorageClass. On
  older clusters the volume-retention policy is ignored, so the database volume
  survives `helm uninstall` instead of being removed with it.
- For an external database: Postgres with the `timescaledb` and `citext`
  extensions available

## Upgrading

The chart is pre-1.0 while the value surface settles, so a minor bump
(`0.2.0` → `0.3.0`) may contain breaking value changes. Read the release notes
before upgrading, and pin the chart version in production.

An upgrade never rotates a generated credential: config-controller writes a
value only when it is absent from the managed Secret. Your admin password
survives upgrades untouched.

## Installing the Chart

### Use the Thoras Helm repo

```
helm repo add thoras https://thoras-ai.github.io/helm-charts
helm repo update thoras
```

### Install the console

A license key is the only thing you must supply. The database, the admin
password and the database credentials are all created for you:

```
helm install thoras-console thoras/thoras-console \
  -n thoras-console --create-namespace \
  --set imageCredentials.password=$(cat thoras_license.txt)
```

For anything beyond a first look, use a values file instead — see
[Sample configurations](#sample-configurations).

### Verify installation

Confirm all three pods reach `Running` (usually under a minute):

```
kubectl get pods -n thoras-console
```

On a fresh install `console-api` and the database briefly report
`CreateContainerConfigError` while they wait for config-controller to generate
their credentials. This resolves itself; no action is needed.

### Sign in

Port-forward the console to your workstation:

```
kubectl port-forward -n thoras-console svc/thoras-console-api 8080:80
```

Then reach it at <http://localhost:8080>. In the default `local` auth mode there
is a single admin, and its password is generated into the
`thoras-console-config-controller` Secret:

```
kubectl get secret thoras-console-config-controller -n thoras-console \
  -o jsonpath='{.data.local-admin-password}' | base64 -d
```

```
curl -s localhost:8080/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"password":"<the password above>"}'
```

The response carries a bearer token, valid for one hour, that authenticates
subsequent API calls. If you pinned the password in values or point at your own
Secret, use that instead; the lookup above only applies to the default
generated-by-controller path. See [Secrets](#secrets) for the full resolution
model.

## Sample configurations

Three complete setups. Each is a `values.yaml` you can copy and adapt.

### Evaluation

Bundled database, generated admin password, local sign-in. Nothing external
beyond the image registry.

```yaml
# values.yaml
imageCredentials:
  password: "<your license key>"
```

```
helm install thoras-console thoras/thoras-console \
  -n thoras-console --create-namespace -f values.yaml
```

Remember the bundled database is evaluation-only: uninstalling destroys it.

### Production with OIDC

Pinned image version, a database you manage, sign-in through your identity
provider, network policies on.

```yaml
# values.yaml
consoleVersion: "5.1.0"

imageCredentials:
  secretRef: thoras-console-registry

consoleApi:
  replicas: 2
  externalUrl: https://console.example.com
  pdb:
    enabled: true
  auth:
    mode: oidc
    oidc:
      issuer: https://id.example.com/
      audiences: https://console.example.com

externalDatabase:
  existingSecret:
    secretName: console-db
    dsnKey: postgresql-dsn

networkPolicy:
  enabled: true

serviceMonitor:
  enabled: true
```

Create the two Secrets first:

```
kubectl create ns thoras-console

kubectl create secret docker-registry thoras-console-registry -n thoras-console \
  --docker-server=us-east4-docker.pkg.dev \
  --docker-username=_json_key_base64 \
  --docker-password="$(cat thoras_license.txt)"

kubectl create secret generic console-db -n thoras-console \
  --from-literal=postgresql-dsn='postgres://user:pass@db.example.com:5432/thoras_cloud'

helm install thoras-console thoras/thoras-console -n thoras-console -f values.yaml
```

`serviceMonitor.enabled` needs the Prometheus Operator installed; without its
CRDs the release fails to apply with `no matches for kind "ServiceMonitor"`. It
scrapes config-controller — `console-api` exports no metrics.

`replicas: 2` multiplies the login rate limit, which is per-process. That
matters only in `local` and `both` modes.

### Production without an identity provider

The same, but signing in with a shared password you control rather than one the
chart generates. Set a salt: without it the install falls back to a value shared
by every install that also leaves it empty.

```yaml
# values.yaml
consoleVersion: "5.1.0"

imageCredentials:
  secretRef: thoras-console-registry

consoleApi:
  externalUrl: https://console.example.com
  auth:
    mode: local
    existingSecret:
      secretName: console-admin
      passwordKey: local-admin-password
    adminSalt: "a-unique-string-for-this-install"

externalDatabase:
  existingSecret:
    secretName: console-db
```

```
kubectl create secret generic console-admin -n thoras-console \
  --from-literal=local-admin-password='<at least 12 characters>'
```

Never change `adminSalt` once the install is live: the session signing key
derives from it, so changing it signs everyone out.

## ArgoCD

The chart renders deterministically. There is no `lookup`, no value generated
inside a template, and nothing a mutating webhook rewrites after apply, so
`helm template` and a cluster apply produce the same manifests and **no
`ignoreDifferences` is needed**.

Credentials you do not supply are generated in-cluster by config-controller into
the `thoras-console-config-controller` Secret. That Secret is not part of the
release and carries no Argo tracking label, so Argo neither diffs nor prunes it.

## helm template

Nothing special is required: the chart is safe to render offline and apply with
any GitOps tool. The only thing to know is the startup ordering — the generated
Secret does not exist at apply time, so `console-api` and the database report
`CreateContainerConfigError` until config-controller creates it. Sync waves are
not needed; the pods recover on their own.

## Configuration

### The database

`bundledDatabase` and `externalDatabase` are mutually exclusive, and the chart
fails to render if both or neither are configured. The bundled database is the
default, so configuring `externalDatabase` is enough to switch over — you do not
also have to disable the bundled one.

#### Bundled — evaluation only

A single-replica TimescaleDB StatefulSet with a PersistentVolumeClaim. It exists
so `helm install` works with no external dependency, and it is not suitable for
production:

- no backups and no point-in-time recovery
- no high availability, and no read replicas
- one replica, so every upgrade is downtime
- the volume is **deleted with the release**

That last point is deliberate. `helm uninstall`, or switching to
`externalDatabase`, destroys the data irrecoverably. For evaluation data that is
the right trade: uninstall leaves no orphaned volume behind.

The credentials outlive the volume. `thoras-console-config-controller` is
written by config-controller at runtime rather than by Helm, so it survives
`helm uninstall`, and a reinstall reuses the same generated passwords against a
fresh, empty database. Delete that Secret too if you want a genuinely clean
slate.

Take a dump first if the data matters:

```
kubectl exec sts/thoras-console-db -n thoras-console -- \
  pg_dump -U postgres thoras_cloud > console-backup.sql
```

Postgres bakes its password into the data directory at first start and cannot
be made to adopt a new one by restarting. The database is therefore excluded
from config-controller's rollouts, and regenerating `postgres-password` on a
running install does not change the password the database actually accepts --
see [Rotating secrets](#rotating-secrets).

#### External — for production

```
kubectl create secret generic console-db -n thoras-console \
  --from-literal=postgresql-dsn='postgres://user:pass@host:5432/thoras_cloud'

helm install ... --set externalDatabase.existingSecret.secretName=console-db
```

The DSN must include the database name, and the database needs the
`timescaledb` and `citext` extensions available. **Stock Postgres will not
work**: the console migrations create hypertables and continuous aggregates.
Timescale Cloud, Azure Database for PostgreSQL, or self-managed Postgres with
the extension installed all work; RDS and Cloud SQL do not offer TimescaleDB.

There is deliberately no way to pin the DSN in values: it carries a password,
and a pinned value would land in `thoras-console-helm-values` and in
`helm get values`.

### Secrets

Every secret-bearing value can be pinned in values, read from a Secret you
manage, or — where the chart can generate it — left empty. Each pair follows the
same shape: `secretName` picks the Secret, and the companion `*Key` picks the
entry within it.

| Value             | Generated    | Pin it                        | Or reference it                   |
| ----------------- | ------------ | ----------------------------- | --------------------------------- |
| Admin password    | yes          | consoleApi.auth.adminPassword | consoleApi.auth.existingSecret    |
| Database DSN      | when bundled | — (never pinnable)            | externalDatabase.existingSecret   |
| Webhook secret    | no           | consoleApi.webhook.secret     | consoleApi.webhook.existingSecret |
| Slack webhook URL | no           | slack.webhookUrl              | slack.existingSecret              |

Referencing wins over pinning wherever both are set, and setting both fails the
render rather than picking for you.

Prefer referencing. A pinned value lives in your values file, in whatever
repository holds it, and in Helm's release history — `helm get values` returns
it to anyone who can read the release. Referencing is also how you feed the
console from External Secrets Operator, Vault or Sealed Secrets: those create
the Secret, and the chart only points at it.

Whichever you choose, no secret material reaches a pod spec: every credential is
bound with `secretKeyRef`.

`consoleApi.auth.adminSalt` is the exception — it is not secret material, so it
takes no Secret reference.

### Rotating secrets

Change the value, then `helm upgrade`. config-controller notices and evicts the
consuming pods.

Rotating the admin password is the **only** way to revoke outstanding sessions:
the session signing key derives from the password and salt together, so there is
no per-session revocation. Generated values are never rotated by an upgrade; to
force a new one, delete its key from the `thoras-console-config-controller`
Secret and let the controller regenerate it and restart the pods that read it.

Delete only the key, and leave config-controller alone: it keeps the baseline it
diffs against in memory, so restarting it makes the regenerated value look like
the starting state and no rollout follows.

That procedure is safe for `local-admin-password`. Do **not** use it on
`postgres-password` or `postgresql-dsn` with the bundled database. The running
Postgres still only accepts the password baked into its data directory at first
start, so a regenerated one authenticates against nothing; regenerate the DSN as
well and the next `console-api` pod can never connect, failing its startup probe
until the rollout gives up. To change the bundled database password, set it on
the database first and then match the Secret to it:

```
NEW='choose-a-strong-password'

kubectl exec -n thoras-console sts/thoras-console-db -- \
  psql -U postgres -c "ALTER USER postgres PASSWORD '$NEW'"

kubectl patch secret thoras-console-config-controller -n thoras-console \
  --type=merge -p "{\"stringData\":{
    \"postgres-password\":\"$NEW\",
    \"postgresql-dsn\":\"postgres://postgres:$NEW@thoras-console-db:5432/thoras_cloud?sslmode=disable\"}}"
```

config-controller rolls `console-api` onto the new DSN on its own, and only ever
generates keys that are absent, so the values you set by hand are left alone.
With `externalDatabase` none of this applies: the DSN is read from a Secret you
manage, and the database password is yours to rotate.

### Authentication

`consoleApi.auth.mode` selects how operators sign in:

- `local` — a single shared admin password, no external identity provider. The
  default, and intended for self-hosted installs.
- `oidc` — an identity provider you already run. Requires
  `consoleApi.auth.oidc.issuer` and `.audiences`; the chart refuses to render
  without them, because the defaults compiled into `console-api` point at
  Thoras' own hosted console and would validate your users' tokens against the
  wrong tenant.
- `both` — accept either.

Set `consoleApi.auth.oidc.jwksUri` only when the issuer URL is unreachable from
inside the cluster: the `iss` claim must stay the browser-facing URL while keys
are fetched from somewhere routable.

#### The admin salt

`consoleApi.auth.adminSalt` makes the session signing key unique to your
install. It is **not a secret** — it only has to be unique and stable — so it
travels as plain configuration. Two rules:

- Minimum 16 characters. Leaving it empty falls back to a value shared by every
  install that does the same, and warns at startup.
- Never change it once set. The signing key derives from it, so changing it
  signs every operator out.

### NetworkPolicy

Set `networkPolicy.enabled: true` to render per-component policies.
`networkPolicy.flavor: kubernetes` (default) emits standard
`networking.k8s.io/v1` `NetworkPolicy` for any NetworkPolicy-capable CNI;
`cilium` emits `CiliumNetworkPolicy` (`cilium.io/v2`) and requires
[Cilium](https://cilium.io/).

`networkPolicy.apiServerPorts` (default `[443, 6443]`) must list the port the
API server actually listens on post-DNAT — set it to `8443` on minikube, etc.
Only config-controller uses it; `console-api` makes no Kubernetes API calls. The
`cilium` flavor ignores the key and targets the API server by identity.

Three policies render: one per component, plus one for the bundled database when
it is in use. Ingress to `console-api` is open on `consoleApi.containerPort`
from any source, because tenant clusters push metrics to it from outside the
cluster. The bundled database admits only `console-api`, by pod selector.

Two egress rules are deliberately broad, because standard NetworkPolicy cannot
name a host whose address may drift:

- `0.0.0.0/0:5432` from `console-api` when the database is external
- `0.0.0.0/0:443` from `console-api` in `oidc` or `both` mode, for the JWKS fetch

Each component block accepts `extraIngressRules` / `extraEgressRules`, appended
verbatim to both flavors — that is where to narrow the two rules above to an
`ipBlock` CIDR, or a layered `CiliumNetworkPolicy` scoped by `toFQDNs`.

## Troubleshooting

**Pods stuck in `CreateContainerConfigError` right after install.** Expected,
and brief: they are waiting for config-controller to generate the credentials
they read. It clears without intervention. If it persists, check the controller
is running and read its logs.

**config-controller crashes with `executable file not found`.** The image
predates config-controller being built into it. Pin `consoleVersion` to a
release that includes it rather than relying on `latest`, which a node may have
cached.

**A generated password stops working after reinstalling.** Only possible on
Kubernetes older than 1.27, where the old database volume survives uninstall and
keeps its original password while a new one is generated. Delete the claim and
reinstall:

```
kubectl delete pvc data-thoras-console-db-0 -n thoras-console
```

**Rendering fails with a message naming a value.** Deliberate — the chart
validates configuration at render time rather than letting it surface as a
`CrashLoopBackOff`. The message names the values path and what to set.

**`console-api` restarts in a loop with no clear error.** Check it can reach the
database. It waits up to 300s before opening its listener, and the startup probe
allows 360s, so a database that is merely slow will still come up; one that is
unreachable logs a timeout.

## Values

### Global

| Key                             | Type   | Default                                          | Description                                                |
| ------------------------------- | ------ | ------------------------------------------------ | ---------------------------------------------------------- |
| consoleVersion                  | String | latest                                           | Image tag for the console components. Pin this in production |
| imageCredentials.registry       | String | us-east4-docker.pkg.dev/thoras-registry/platform | Container registry name                                    |
| imageCredentials.username       | String | \_json_key_base64                                | Container registry username                                |
| imageCredentials.password       | String | ""                                               | License key. Mutually exclusive with secretRef             |
| imageCredentials.secretRef      | String | ""                                               | Name of a dockerconfigjson Secret already in the namespace |
| imageCredentials.imagePullSecretInDeployment | Bool | false                              | Also set imagePullSecrets on the pod spec, not just the ServiceAccount |
| imagePullPolicy                 | String | IfNotPresent                                     | Image pull policy for all components                       |
| logLevel                        | String | info                                             | Default log level                                          |
| env                             | list   | []                                               | Additional environment variables passed to all components  |
| proxy.httpProxy                 | String | ""                                               | HTTP proxy for all components                              |
| proxy.httpsProxy                | String | ""                                               | HTTPS proxy for all components                             |
| proxy.noProxy                   | String | ""                                               | Proxy exclusions for all components                        |
| labels                          | object | {}                                               | Labels added to every rendered resource                    |
| podAnnotations                  | object | {}                                               | Annotations added to every console pod                     |
| nodeSelector                    | object | {}                                               | Node selector for all components                           |
| tolerations                     | list   | []                                               | Tolerations for all components                             |
| affinity                        | object | {}                                               | Applied to components that set useGlobalAffinity           |
| priorityClassName               | String | ""                                               | Global priority class, overridden per component            |
| topologySpreadConstraints       | list   | []                                               | Global spread, overridden per component                    |
| networkPolicy.enabled           | Bool   | false                                            | Render per-component network policies                      |
| networkPolicy.flavor            | String | kubernetes                                       | kubernetes or cilium                                       |
| networkPolicy.apiServerPorts    | list   | [443, 6443]                                      | API server ports post-DNAT. Set 8443 on minikube           |
| serviceMonitor.enabled          | Bool   | false                                            | Scrape config-controller. Needs the Prometheus Operator    |
| serviceMonitor.interval         | String | ""                                               | Empty defers to the Prometheus default                     |
| serviceMonitor.additionalLabels | object | {}                                               | Extra labels on the ServiceMonitor                         |

### Console API

| Key                                          | Type   | Default              | Description                                                      |
| -------------------------------------------- | ------ | -------------------- | ---------------------------------------------------------------- |
| consoleApi.enabled                           | Bool   | true                 | Deploy console-api                                               |
| consoleApi.replicas                          | Number | 1                    | Replica count. The login rate limit is per-process               |
| consoleApi.image.repository                  | String | console-api          | Joined to imageCredentials.registry                              |
| consoleApi.containerPort                     | Number | 8080                 | Port the container listens on                                    |
| consoleApi.port                              | Number | 80                   | Service port                                                     |
| consoleApi.externalUrl                       | String | ""                   | URL the console is reachable on. Read by install notes only      |
| consoleApi.serviceAccount.name               | String | thoras-console-api   | ServiceAccount name                                              |
| consoleApi.service.annotations               | object | {}                   | Annotations on the Service                                       |
| consoleApi.labels                            | object | {}                   | Component labels                                                 |
| consoleApi.podAnnotations                    | object | {}                   | Component pod annotations                                        |
| consoleApi.pdb.enabled                       | Bool   | false                | Render a PodDisruptionBudget                                     |
| consoleApi.pdb.maxUnavailable                | Number | 1                    | minAvailable takes precedence if both are set                    |
| consoleApi.resources                         | object | 100m/256Mi, 1Gi      | Requests and limits. No CPU limit by default                     |
| consoleApi.migrateOnStart                    | Bool   | true                 | Run migrations at startup, under a Postgres advisory lock        |
| consoleApi.singleOrg.enabled                 | Bool   | true                 | Auto-provision and implicitly use one organization               |
| consoleApi.singleOrg.name                    | String | Default Organization | Renames the existing organization if changed after install       |
| consoleApi.bootstrapAdminEmail               | String | admin@localhost      | Label on the seeded admin user. Nothing authenticates against it |
| consoleApi.auth.mode                         | String | local                | local, oidc, or both                                             |
| consoleApi.auth.oidc.issuer                  | String | ""                   | Required for oidc/both. Must match the iss claim exactly         |
| consoleApi.auth.oidc.audiences               | String | ""                   | Required for oidc/both. Comma-separated                          |
| consoleApi.auth.oidc.jwksUri                 | String | ""                   | Only when the issuer URL is unreachable from the cluster         |
| consoleApi.auth.adminPassword                | String | ""                   | Minimum 12 characters. Generated when empty                      |
| consoleApi.auth.existingSecret.secretName    | String | ""                   | Read the admin password from your own Secret                     |
| consoleApi.auth.existingSecret.passwordKey   | String | local-admin-password | Key within that Secret                                           |
| consoleApi.auth.adminSalt                    | String | ""                   | Minimum 16 characters. Not secret. Never change it once set      |
| consoleApi.webhook.secret                    | String | ""                   | Shared secret for the identity-provider user-created webhook     |
| consoleApi.webhook.existingSecret.secretName | String | ""                   | Read the webhook secret from your own Secret                     |
| consoleApi.webhook.existingSecret.secretKey  | String | webhook-secret       | Key within that Secret                                           |
| consoleApi.useGlobalAffinity                 | Bool   | false                | Merge the global affinity into this component's                  |
| consoleApi.affinity                          | object | {}                   | Component affinity                                               |
| consoleApi.priorityClassName                 | String | ""                   | Takes precedence over the global priority class                  |
| consoleApi.topologySpreadConstraints         | list   | []                   | Replaces the global list when non-empty                          |
| consoleApi.extraEgressRules                  | list   | []                   | Appended verbatim to both NetworkPolicy flavors                  |
| consoleApi.extraIngressRules                 | list   | []                   | Appended verbatim to both NetworkPolicy flavors                  |

### Config Controller

Generates any credential you do not supply into the
`thoras-console-config-controller` Secret, and evicts the pods that consume them
when they change. It writes a value only when that value is absent, so an
upgrade never rotates a generated password.

Disabling it is only valid when every credential is pinned or referenced;
otherwise the chart fails to render, because nothing else creates the Secret.

| Key                                           | Type   | Default                          | Description                                            |
| --------------------------------------------- | ------ | -------------------------------- | ------------------------------------------------------ |
| consoleConfigController.enabled               | Bool   | true                             | Deploy config-controller                               |
| consoleConfigController.serviceAccount.name   | String | thoras-console-config-controller | ServiceAccount name                                    |
| consoleConfigController.replicas              | Number | 1                                | Leader-elected, so more than one is safe but pointless |
| consoleConfigController.resources             | object | 10m/64Mi, 256Mi                  | Requests and limits                                    |
| consoleConfigController.prometheus.enabled    | Bool   | true                             | Expose /metrics                                        |
| consoleConfigController.prometheus.port       | Number | 9103                             | Metrics port                                           |
| consoleConfigController.pprof.enabled         | Bool   | false                            | Enable pprof endpoints                                 |
| consoleConfigController.enableSeeding         | Bool   | true                             | Off means it only drives rollouts                      |
| consoleConfigController.enableRestartRollouts | Bool   | true                             | Off means it logs evictions but never evicts           |
| consoleConfigController.pollInterval          | String | 30s                              | Interval between reconcile ticks                       |
| consoleConfigController.rolloutDebounce       | String | 10s                              | Coalescing window before a rollout starts              |
| consoleConfigController.rolloutTimeout        | String | 5m                               | Per-workload deadline for eviction and readiness       |
| consoleConfigController.restartOrder          | list   | [thoras-console-api]             | Strict sequential restart tiers                        |
| consoleConfigController.restartExclude        | list   | controller and database          | Never restarted                                        |
| consoleConfigController.logLevel              | String | ""                               | Empty inherits the global logLevel                     |
| consoleConfigController.labels                | object | {}                               | Component labels                                       |
| consoleConfigController.podAnnotations        | object | {}                               | Component pod annotations                              |
| consoleConfigController.service.annotations   | object | {}                               | Annotations on the Service                             |
| consoleConfigController.pdb.enabled           | Bool   | false                            | Render a PodDisruptionBudget                           |
| consoleConfigController.pdb.maxUnavailable    | Number | 1                                | minAvailable takes precedence if both are set          |
| consoleConfigController.useGlobalAffinity     | Bool   | false                            | Merge the global affinity into this component's        |
| consoleConfigController.affinity              | object | {}                               | Component affinity                                     |
| consoleConfigController.priorityClassName     | String | ""                               | Takes precedence over the global priority class        |
| consoleConfigController.topologySpreadConstraints | list | []                            | Replaces the global list when non-empty                |
| consoleConfigController.extraEgressRules      | list   | []                               | Appended verbatim to both NetworkPolicy flavors        |
| consoleConfigController.extraIngressRules     | list   | []                               | Appended verbatim to both NetworkPolicy flavors        |

### Bundled Database

| Key                                          | Type   | Default           | Description                                                                                                                                                        |
| -------------------------------------------- | ------ | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| bundledDatabase.enabled                      | Bool   | true, unwritten   | Absent from values.yaml so the chart can tell unset from explicit. Setting externalDatabase is enough to switch over; setting this to true as well fails the render |
| bundledDatabase.image.repository             | String | timescaledb       | Joined to imageCredentials.registry                                                                                                                                |
| bundledDatabase.image.tag                    | String | 2.28.2-pg16       | TimescaleDB image tag                                                                                                                                              |
| bundledDatabase.extensionVersion             | String | 2.28.2            | Extension version console-api upgrades to                                                                                                                          |
| bundledDatabase.containerPort                | Number | 5432              | Postgres port                                                                                                                                                      |
| bundledDatabase.databaseName                 | String | thoras_cloud      | Created on first start                                                                                                                                             |
| bundledDatabase.resources                    | object | 250m/512Mi, 2Gi   | Sized for evaluation, not for load                                                                                                                                 |
| bundledDatabase.persistence.size             | String | 10Gi              | Claim size. The claim is deleted with the StatefulSet                                                                                                              |
| bundledDatabase.persistence.storageClassName | String | ""                | Empty uses the cluster default                                                                                                                                     |
| bundledDatabase.serviceAccount.name          | String | thoras-console-db | ServiceAccount name                                                                                                                                                |
| bundledDatabase.labels                       | object | {}                | Component labels                                                                                                                                                   |
| bundledDatabase.podAnnotations               | object | {}                | Component pod annotations                                                                                                                                          |
| bundledDatabase.useGlobalAffinity            | Bool   | false             | Merge the global affinity into this component's                                                                                                                    |
| bundledDatabase.affinity                     | object | {}                | Component affinity                                                                                                                                                 |
| bundledDatabase.priorityClassName            | String | ""                | Takes precedence over the global priority class                                                                                                                    |
| bundledDatabase.extraEgressRules             | list   | []                | Appended verbatim to both NetworkPolicy flavors                                                                                                                    |
| bundledDatabase.extraIngressRules            | list   | []                | Appended verbatim to both NetworkPolicy flavors                                                                                                                    |

### External Database

| Key                                        | Type   | Default        | Description                                        |
| ------------------------------------------ | ------ | -------------- | -------------------------------------------------- |
| externalDatabase.existingSecret.secretName | String | ""             | Secret holding the DSN. The only way to supply one  |
| externalDatabase.existingSecret.dsnKey     | String | postgresql-dsn | Key within that Secret                              |

### Slack

| Key                                | Type   | Default           | Description                               |
| ---------------------------------- | ------ | ----------------- | ----------------------------------------- |
| slack.errorsEnabled                | Bool   | false             | Report console errors to Slack            |
| slack.webhookUrl                   | String | ""                | Incoming webhook URL. Secret material     |
| slack.existingSecret.secretName    | String | ""                | Read the webhook URL from your own Secret |
| slack.existingSecret.webhookUrlKey | String | slack-webhook-url | Key within that Secret                    |
