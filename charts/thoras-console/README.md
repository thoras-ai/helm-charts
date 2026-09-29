# Thoras Console

The Thoras console is where your clusters report in. This Helm chart installs a
self-hosted [Thoras](https://www.thoras.ai) console onto Kubernetes, as an
alternative to the hosted console at `console.thoras.ai`.

![Version: 1.0.0](https://img.shields.io/badge/Version-1.0.0-informational?style=flat-square) ![AppVersion: 4.123.0](https://img.shields.io/badge/AppVersion-4.123.0-informational?style=flat-square)

The chart installs the console dashboard, `console-api`, a `config-controller`
that generates any credential you do not supply, and — for evaluation only — a
bundled TimescaleDB. To install Thoras onto a cluster you want to *observe*, use
the [thoras](../thoras/README.md) chart instead; the two are separate installs.

```
people ──────────────▶ dashboard address ──▶ dashboard ──▶ console-api ──▶ database
                                                               ▲
tenant clusters ─────▶ ingest address ─────────────────────────┘
(thoras chart)
```

Three terms are used throughout:

- **Tenant cluster** — a cluster running the [thoras](../thoras/README.md) chart
  that reports to this console. The software it runs is the Thoras agent.
- **Dashboard address** — where people sign in (`consoleDashboard.ingress`). The
  dashboard serves the UI and proxies the API for browsers.
- **Ingest address** — where tenant clusters send data (`consoleApi.ingress`). It
  is never the dashboard address: the dashboard refuses ingest by design.

## Contents

- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Connecting a cluster](#connecting-a-cluster)
- [Production install](#production-install)
- [GitOps](#gitops)
- [Operations](#operations)
- [Troubleshooting](#troubleshooting)
- [Values](#values)

## Requirements

- A Thoras license key (email support@thoras.ai if you don't have one).
- Kubernetes 1.24 or later.
- For the bundled database: **Kubernetes 1.27 or later** and a default
  StorageClass. On older clusters the volume-retention policy is ignored, so the
  database volume survives `helm uninstall` instead of being removed with it.
- For an external database: Postgres with the `timescaledb` and `citext`
  extensions available. See [External database](#external-database).

### Version compatibility

- Console images (`consoleVersion`): `4.123.0` or later
- [thoras](../thoras/README.md) chart on each tenant cluster: `5.4.0` or later

## Quick start

A running console in a few minutes, with the bundled database and a generated
admin password. This is for evaluation: see [Production install](#production-install)
before relying on it.

**1. Install.** A license key is the only thing you must supply:

```
helm repo add thoras https://thoras-ai.github.io/helm-charts
helm repo update thoras

helm install thoras-console thoras/thoras-console \
  -n thoras-console --create-namespace \
  --set imageCredentials.password="$(cat thoras_license.txt)"
```

**2. Check the pods.** All four reach `Running`, usually within a minute:

```
kubectl get pods -n thoras-console
```

On a fresh install `console-api` and the database briefly show
`CreateContainerConfigError` while config-controller generates their
credentials. It clears on its own.

**3. Sign in.** Forward the dashboard to your workstation:

```
kubectl port-forward -n thoras-console svc/thoras-console-dashboard 8080:80
```

Open <http://localhost:8080> and sign in with the generated admin password:

```
kubectl get secret thoras-console-config-controller -n thoras-console \
  -o jsonpath='{.data.local-admin-password}' | base64 -d; echo
```

That is where a *generated* password lives. If you supplied one yourself, read
it from where you put it:

| How you supplied it                | Where to read it                                            |
| ---------------------------------- | ----------------------------------------------------------- |
| Left empty (default)               | `thoras-console-config-controller` → `local-admin-password` |
| `auth.local.adminPassword`         | `thoras-console-helm-values` → `local-admin-password`       |
| `auth.local.existingSecret`        | your own Secret, at the key you named                       |

To call the API directly rather than through the UI, exchange the password for a
bearer token, valid for one hour:

```
curl -s localhost:8080/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"password":"<the admin password>"}'
```

Next, [connect a cluster](#connecting-a-cluster).

## Connecting a cluster

A tenant cluster reports to the console through the Thoras agent, installed by
the [thoras](../thoras/README.md) chart. It can connect with a key you create in
the dashboard, or register itself with a shared join secret.

### Before you connect

On the tenant cluster:

- **The thoras chart, 5.4.0 or later.**
- **metrics-server, running.** The agent reads pod usage from the Kubernetes
  Metrics API. Without it the cluster still reports, but its targets show
  "Target workload missing" and no version. Check that this prints usage:

  ```
  kubectl top pods -n thoras
  ```

- **A route to the ingest address**, described next.

### The ingest address

Where tenant clusters send data depends on where they run:

| Tenant cluster                  | `cloudSync.baseUrl`                                                  |
| ------------------------------- | -------------------------------------------------------------------- |
| The same cluster as the console | `http://thoras-console-api.thoras-console.svc.cluster.local`         |
| Any other cluster               | `https://console-api.example.com`, served by `consoleApi.ingress`    |

For other clusters, give `console-api` its own host, separate from the
dashboard's, and serve it over TLS:

```yaml
consoleApi:
  ingress:
    enabled: true
    hosts:
      - host: console-api.example.com
        paths:
          - path: /
    tls:
      - hosts: [console-api.example.com]
        secretName: console-api-tls
```

`consoleApi.gatewayAPI` renders the same route as an HTTPRoute instead. See
[Routing](#routing) for why the two addresses must stay separate.

### With a key

1. In the dashboard, choose **Create cluster** and give it a name. The cluster's
   first key appears: a **Key ID** and a **Key**. Store the key now: it is shown
   only once.
2. On the tenant cluster, set three values on its thoras chart release. The
   dialog builds this command for you from the ingest address, release and
   namespace you give it. For a release named `thoras` in the `thoras`
   namespace:

   ```
   helm upgrade thoras thoras/thoras -n thoras --reset-then-reuse-values \
     --set cloudSync.baseUrl=https://console-api.example.com \
     --set cloudSync.clusterKeyID=<key ID> \
     --set cloudSync.clusterKey=<key>
   ```

   `helm list -A` shows the release name if yours differs.

Two things to avoid:

- **Leaving `cloudSync.baseUrl` unset.** Its default is `https://console.thoras.ai`,
  Thoras' hosted console, which rejects a key from this one.
- **Setting `cloudSync.joinSecret` as well.** With both a key and a join secret,
  the thoras chart can't tell which you meant and turns cloud sync off.

To replace a key, open **Keys** for the cluster, choose **Mint new key**, set it
the same way, then **Revoke** the old one. Minting a key does not revoke the
previous one.

### Joining by itself

Instead of creating each cluster in the dashboard, you can let clusters register
themselves with one secret shared across your fleet.

Enable it on the console:

```yaml
consoleApi:
  clusterJoin:
    enabled: true
```

and read the generated secret out:

```
kubectl get secret thoras-console-config-controller -n thoras-console \
  -o jsonpath='{.data.cluster-join-secret}' | base64 -d; echo
```

Then install each tenant cluster's thoras chart with the join secret and the
name to register under:

```
helm upgrade thoras thoras/thoras -n thoras --reset-then-reuse-values \
  --set cloudSync.baseUrl=https://console-api.example.com \
  --set cloudSync.joinSecret=<join secret> \
  --set cluster.name=production-eu
```

On its first sync the cluster registers under that name and receives a key of
its own. From then on it sends data with that key, like any other cluster:

- The join secret is only used to register. Revoking one cluster's key works as
  usual, and rotating the join secret does not affect clusters already joined.
- Renaming a cluster in the dashboard sticks: later upgrades don't rename it
  back.
- Two clusters can't register under the same name. The second is refused until
  you pick another `cluster.name`.

Requires `consoleApi.singleOrg.enabled`, the default: a joining cluster presents
no user identity, so the organization has to be implicit.

### Checking it works

In the dashboard, the cluster's **Last ingest** updates within a couple of
minutes, and its targets appear when you open it. If it doesn't, see
[Troubleshooting](#troubleshooting).

## Production install

Pin the chart version, use a database you manage, sign people in through your
identity provider or a password you control, and turn network policies on.

### Sample: OIDC

```yaml
# values.yaml
imageCredentials:
  secretRef: thoras-console-registry

auth:
  mode: oidc
  oidc:
    issuer: https://id.example.com/
    audiences: [https://console.example.com]
    client:
      # Register https://console.example.com/landing as a callback for it.
      id: your-oauth-client-id

consoleApi:
  replicas: 2
  pdb:
    enabled: true
  # The ingest address: tenant clusters sync here.
  ingress:
    enabled: true
    hosts:
      - host: console-api.example.com
        paths:
          - path: /
    tls:
      - hosts: [console-api.example.com]
        secretName: console-api-tls

consoleDashboard:
  externalUrl: https://console.example.com
  # The dashboard address: people sign in here.
  ingress:
    enabled: true
    hosts:
      - host: console.example.com
        paths:
          - path: /
    tls:
      - hosts: [console.example.com]
        secretName: console-tls

externalDatabase:
  existingSecret:
    secretName: console-db

networkPolicy:
  enabled: true

serviceMonitor:
  enabled: true
```

Create the two Secrets it refers to, then install:

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

Your identity provider needs setting up too: see [Authentication](#authentication).
`serviceMonitor` needs the Prometheus Operator: see [Monitoring](#monitoring).
With `replicas: 2` the login rate limit, which is per process, doubles; that
only matters in `local` and `both` modes.

### Sample: a password you control

The same, but people sign in with a shared password you set, kept in a Secret
you manage. Set a salt too: without one, the install falls back to a value
shared by every install that also leaves it empty.

```yaml
# values.yaml
imageCredentials:
  secretRef: thoras-console-registry

auth:
  mode: local
  local:
    existingSecret:
      secretName: console-admin
    adminSalt: "a-unique-string-for-this-install"

consoleDashboard:
  externalUrl: https://console.example.com

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

### The database

`bundledDatabase` and `externalDatabase` are mutually exclusive. The bundled one
is the default, so configuring `externalDatabase` is enough to switch over; you
don't also have to disable the bundled one. Configuring both, or disabling the
bundled one without an external one, fails the render.

#### Bundled database

A single-replica TimescaleDB StatefulSet with a PersistentVolumeClaim. It exists
so `helm install` works with nothing external, and it is **for evaluation
only**:

- no automatic backups and no point-in-time recovery
- no high availability, and no read replicas
- one replica, so every upgrade is downtime
- the volume is **deleted with the release**

That last point is deliberate: `helm uninstall`, or switching to
`externalDatabase`, destroys the data. For evaluation that is the right trade,
since uninstalling leaves no orphaned volume behind. Take a backup first if the
data matters — see [Backup and restore](#backup-and-restore).

Postgres fixes its password when the data directory is first created, and
restarting it does not change that. So the database is excluded from
config-controller's restarts, and regenerating `postgres-password` does not
change the password it accepts — see [Rotating secrets](#rotating-secrets).

#### External database

Put the DSN, including the database name, in a Secret and point the chart at
it:

```
kubectl create secret generic console-db -n thoras-console \
  --from-literal=postgresql-dsn='postgres://user:pass@db.example.com:5432/thoras_cloud'
```

```yaml
externalDatabase:
  existingSecret:
    secretName: console-db
```

**Stock Postgres will not work.** The console's migrations create TimescaleDB
hypertables and continuous aggregates, and run `CREATE EXTENSION` for
`timescaledb` and `citext`, so the database user must be allowed to create them
or they must exist already. Timescale Cloud, Azure Database for PostgreSQL, and
self-managed Postgres with TimescaleDB installed all work; Amazon RDS and Cloud
SQL do not offer TimescaleDB.

There is deliberately no way to put the DSN in values: it carries a password,
which would then sit in `thoras-console-helm-values` and in `helm get values`.

### Routing

The console needs two addresses, carrying different traffic:

| Address                                      | Who reaches it   | Values                                     |
| -------------------------------------------- | ---------------- | ------------------------------------------ |
| Dashboard address, e.g. `console.example.com` | people           | `consoleDashboard.ingress` / `.gatewayAPI` |
| Ingest address, e.g. `console-api.example.com` | tenant clusters | `consoleApi.ingress` / `.gatewayAPI`       |

Both are off by default. Ingress and Gateway API are independent switches on
each component; enable whichever your cluster uses.

The dashboard serves the UI and forwards `/api/` to `console-api`, so a browser
only ever talks to the dashboard address. That forwarding is deny-by-default:
everything under `/api/v1/` passes **except** `ingest/` and `hook/`, which
return 403, because they are not dashboard routes and this address is public.
So a tenant cluster pointed at the dashboard address fails every sync with a 403
from nginx. Point `cloudSync.baseUrl` at the ingest address instead — see
[The ingest address](#the-ingest-address).

`consoleDashboard.externalUrl` only sets the URL printed after install. It is
worked out from the dashboard's ingress when unset.

### Authentication

`auth.mode` selects how people sign in. The same `auth` block configures both
`console-api`, which checks tokens, and the dashboard, which obtains them.

| Mode    | Sign in with                                                        |
| ------- | ------------------------------------------------------------------- |
| `local` | one shared admin password, no identity provider. The default        |
| `oidc`  | an OIDC identity provider you already run                           |
| `both`  | either                                                              |

#### Local admin

There is a single admin. Its password is generated when you leave it empty, or
you can set it in values or keep it in a Secret you manage — see
[Secrets](#secrets). Minimum 12 characters.

`auth.local.adminSalt` makes the session signing key unique to your install. It
is **not secret**, only unique and stable, so it is plain configuration. Two
rules:

- Minimum 16 characters. Leaving it empty falls back to a value shared by every
  install that does the same, and warns at startup.
- Never change it once set: the signing key derives from it, so changing it
  signs everyone out.

#### OIDC

```yaml
auth:
  mode: oidc
  oidc:
    issuer: https://id.example.com/
    audiences: [https://console.example.com]
    client:
      id: your-oauth-client-id
```

The chart refuses to render without `issuer`, `audiences` and `client.id`:
`console-api`'s built-in defaults point at Thoras' hosted console and would check
your users' tokens against the wrong provider.

**What your provider must issue.** `console-api` checks each request's access
token, which must:

- carry an `iss` claim equal to `issuer` **exactly**, trailing slash included;
- be signed with **RS256**;
- carry one of `audiences` in its `aud` claim;
- carry the console's scopes in its **`scope` claim**, a space-separated
  string: `read:*` (or each `read:` scope), `write:clusters` and
  `write:cluster-tokens`. `read:*` covers every read scope but neither write
  scope, so without those, cluster and key management return 403.

A token that fails the first three checks gets a 401; a missing scope gets a
403, which is how to tell the two apart.

**Register the dashboard with your provider.** The dashboard signs in as an
OAuth client of its own, `auth.oidc.client.id`. Register these for it, or
sign-in fails at the redirect with an error from your provider:

| Provider setting     | Value                                 |
| -------------------- | ------------------------------------- |
| Allowed callback URL | `https://<dashboard address>/landing` |
| Allowed logout URL   | `https://<dashboard address>`         |

For a dashboard at `console.example.com` that is
`https://console.example.com/landing` and `https://console.example.com`. If you
sign in through a port-forward, register `http://localhost:8080/landing` too;
`both` mode still lets you in with the admin password.

The dashboard requests the scopes in `auth.oidc.client.scope`. Every one must be
defined and granted on your provider: some answer `invalid_scope` and fail the
redirect rather than ignore a scope they don't know.

Set `auth.oidc.jwksUri` only when the issuer URL is unreachable from inside the
cluster: the `iss` claim stays the browser-facing URL while signing keys are
fetched from the address you give.

**Provider notes.**

- **Auth0.** Define the console's scopes as permissions on the API and grant
  them. `audience` is an Auth0 extension: without it Auth0 issues an opaque
  access token, so sign-in appears to work and every later call fails with 401.
  The dashboard sends `auth.oidc.client.audience`, which defaults to the first
  of `audiences`. Auth0 issuers end with a slash.
- **Keycloak.** Keycloak issuers don't end with a slash. Its access tokens carry
  `account` in `aud` by default, so add an audience mapper to the client, and
  add client scopes named exactly `read:*`, `write:clusters` and
  `write:cluster-tokens`. A realm switched to a signing algorithm other than
  RS256 won't work.
- **Okta and Dex aren't supported yet.** The console reads scopes only from a
  `scope` string claim. Okta puts them in an `scp` list instead, and Dex can't
  issue custom scopes, so every call would return 403.

### NetworkPolicy

Set `networkPolicy.enabled: true` to render a policy per component.
`networkPolicy.flavor: kubernetes` (the default) emits standard
`networking.k8s.io/v1` `NetworkPolicy` for any NetworkPolicy-capable CNI;
`cilium` emits `CiliumNetworkPolicy` (`cilium.io/v2`) and needs
[Cilium](https://cilium.io/). Any other value fails the render rather than
quietly producing no policy; both names are lower-case.

`networkPolicy.apiServerPorts` (default `[443, 6443]`) must list the port the
API server actually listens on after DNAT — `8443` on minikube, for example.
To find it:

```
kubectl get endpointslice -n default -l kubernetes.io/service-name=kubernetes \
  -o jsonpath='{.items[0].ports[0].port}{"\n"}'
```

Only config-controller uses it; `console-api` makes no Kubernetes API calls. The
`cilium` flavor ignores it and targets the API server by identity.

Four policies render, one per component, including the bundled database when it
is in use:

- `console-api` accepts traffic on `consoleApi.containerPort` from any source,
  because tenant clusters reach it from outside through the ingest address. Its
  metrics port is reachable from this namespace only.
- The dashboard accepts traffic on its own port from any source, because
  browsers are outside the cluster.
- The bundled database admits only `console-api`.

Two egress rules are deliberately broad, because standard NetworkPolicy can't
name a host whose address may change:

- port 5432 to any address, from `console-api`, when the database is external
- port 443 to any address, from `console-api`, in `oidc` or `both` mode, to fetch
  the provider's signing keys

Every component accepts `extraIngressRules` and `extraEgressRules`, appended
verbatim to both flavors. That is where to narrow the two rules above to a CIDR,
or to layer a `CiliumNetworkPolicy` scoped with `toFQDNs`.

### Monitoring

`serviceMonitor.enabled: true` renders ServiceMonitors for `console-api` and
config-controller. It needs the Prometheus Operator: without its CRDs the
release fails to apply with `no matches for kind "ServiceMonitor"`.

`console-api` serves `/metrics` on its own port, `consoleApi.prometheus.port`
(9104), rather than on `containerPort`, which the ingest address publishes. With
`networkPolicy.enabled`, a Prometheus in this namespace already reaches it; one
in another namespace needs a rule in `consoleApi.extraIngressRules`.

### Secrets

Every secret-bearing value can be set in values, read from a Secret you manage,
or — where the chart can generate it — left empty. A reference names the Secret
with `secretName` and the entry within it with the matching `…Key`.

| Value               | Generated    | Set it                        | Or reference it                       |
| ------------------- | ------------ | ----------------------------- | ------------------------------------- |
| Admin password      | yes          | `auth.local.adminPassword`    | `auth.local.existingSecret`           |
| Cluster join secret | yes          | `consoleApi.clusterJoin.secret` | `consoleApi.clusterJoin.existingSecret` |
| Database DSN        | when bundled | — (never in values)           | `externalDatabase.existingSecret`     |
| Webhook secret      | no           | `consoleApi.webhook.secret`   | `consoleApi.webhook.existingSecret`   |
| Slack webhook URL   | no           | `slack.webhookUrl`            | `slack.existingSecret`                |

Set a value or reference it, not both: setting both fails the render rather
than picking one for you.

Prefer referencing. A value set directly lives in your values file, in whatever
repository holds it, and in Helm's release history, where `helm get values`
returns it to anyone who can read the release. Referencing is also how you feed
the console from External Secrets Operator, Vault or Sealed Secrets: they
create the Secret, and the chart only points at it.

Either way, no secret material reaches a pod spec: every credential is bound with
`secretKeyRef`. `auth.local.adminSalt` is the exception to all of this: it isn't
secret, so it takes no Secret reference.

## GitOps

The chart renders deterministically. There is no `lookup`, no value generated
inside a template, and nothing a mutating webhook rewrites after apply, so
`helm template` and a cluster apply produce the same manifests. With Argo CD **no
`ignoreDifferences` is needed**.

Credentials you don't supply are generated in the cluster by config-controller,
into the `thoras-console-config-controller` Secret. That Secret isn't part of the
release and carries no Argo CD tracking label, so Argo CD neither diffs nor
prunes it.

Rendering offline and applying with any other tool works the same way. The
generated Secret doesn't exist at first apply, so `console-api` and the database
show `CreateContainerConfigError` until config-controller creates it. They
recover on their own; no sync waves are needed.

## Operations

### Upgrading

```
helm repo update thoras
helm upgrade thoras-console thoras/thoras-console -n thoras-console --reset-then-reuse-values
```

The chart follows semantic versioning. A major version may rename or remove
values, a minor version only adds them, and a patch version only fixes. Read the
release notes before a major upgrade, and pin the chart version in production
by passing `--version` to `helm install` and `helm upgrade`.

Each chart version pins the console images it was released with, so upgrading
the chart upgrades the console. If you set `consoleVersion` yourself, it stays
where you set it through every upgrade until you change or remove it.

Use `--reset-then-reuse-values`, not `--reuse-values`. A new chart version often
adds values, and `--reuse-values` keeps the previous release's values *instead
of* the new chart's defaults, so a newly added value is missing and the upgrade
can fail on it. `--reset-then-reuse-values` applies your values on top of the
new defaults.

An upgrade never changes a generated credential: config-controller only writes a
value that is missing. Your admin password survives upgrades.

### Backup and restore

This section is for the bundled database. With an external database, use your
provider's backups.

**Back up** with `pg_dump`:

```
kubectl exec sts/thoras-console-db -n thoras-console -- \
  pg_dump -U postgres thoras_cloud > console-backup.sql
```

A warning about circular foreign-key constraints on `continuous_agg` is normal
for TimescaleDB and harmless.

**Restore** only into a new, empty install. Restoring into a console that is
already running is not an error `psql` reports: it exits successfully while
leaving clusters missing and the database damaged. The steps:

1. Install with `console-api` stopped, so it can't set up the empty database
   before the restore does. Pass the same values you installed with; `-f
   values.yaml` stands for them here:

   ```
   helm install thoras-console thoras/thoras-console -n thoras-console --create-namespace \
     -f values.yaml --set consoleApi.replicas=0
   kubectl rollout status sts/thoras-console-db -n thoras-console
   ```

2. Restore between TimescaleDB's two restore hooks:

   ```
   kubectl exec sts/thoras-console-db -n thoras-console -- \
     psql -U postgres -d thoras_cloud -c "SELECT timescaledb_pre_restore();"

   kubectl exec -i sts/thoras-console-db -n thoras-console -- \
     psql -U postgres -d thoras_cloud -v ON_ERROR_STOP=1 < console-backup.sql

   kubectl exec sts/thoras-console-db -n thoras-console -- \
     psql -U postgres -d thoras_cloud -c "SELECT timescaledb_post_restore();"
   ```

3. Start `console-api`:

   ```
   helm upgrade thoras-console thoras/thoras-console -n thoras-console \
     --reset-then-reuse-values --set consoleApi.replicas=1
   ```

The admin password isn't in the database: it lives in Kubernetes. If the
`thoras-console-config-controller` Secret is gone too, for example with the
namespace, the restored console generates a new admin password unless you set
one or [reference your own](#secrets).

### Rotating secrets

Change the value, then `helm upgrade`. config-controller notices and restarts the
pods that use it.

Rotating the admin password is the **only** way to revoke outstanding sessions:
the session signing key derives from the password and salt together, so there is
no per-session revocation.

Generated values are never rotated by an upgrade. To force a new one, delete its
key from the `thoras-console-config-controller` Secret; config-controller
generates a new value and restarts the pods that read it. Delete only the key,
and leave config-controller running: it keeps the previous values in memory to
compare against, so restarting it makes the new value look like the starting
state, and nothing restarts.

That is safe for `local-admin-password`. Do **not** do it to `postgres-password`
or `postgresql-dsn` with the bundled database: the database still accepts only
the password it was created with, so `console-api` could never connect again.
To change the bundled database's password, change it in the database first, then
make the Secret match:

```
NEW='choose-a-strong-password'

kubectl exec -n thoras-console sts/thoras-console-db -- \
  psql -U postgres -c "ALTER USER postgres PASSWORD '$NEW'"

kubectl patch secret thoras-console-config-controller -n thoras-console \
  --type=merge -p "{\"stringData\":{
    \"postgres-password\":\"$NEW\",
    \"postgresql-dsn\":\"postgres://postgres:$NEW@thoras-console-db:5432/thoras_cloud?sslmode=disable\"}}"
```

config-controller restarts `console-api` onto the new DSN by itself, and it only
generates values that are missing, so the ones you set by hand stay. With an
external database none of this applies: the DSN comes from your own Secret, and
the password is yours to rotate.

### Uninstalling

```
helm uninstall thoras-console -n thoras-console
```

This removes the console, and with it the bundled database's volume (on
Kubernetes 1.27 or later). It keeps the `thoras-console-config-controller`
Secret, because config-controller creates it at runtime rather than Helm. A
reinstall into the same namespace then reuses the same generated admin password
and database credentials against a new, empty database.

For a clean slate, delete that Secret too, or the whole namespace:

```
kubectl delete secret thoras-console-config-controller -n thoras-console
```

## Troubleshooting

**Pods stay in `CreateContainerConfigError` after install.** Expected briefly:
they are waiting for config-controller to generate their credentials. If it
persists, check config-controller is running and read its logs.

**Rendering fails with a message naming a value.** Deliberate: the chart checks
its configuration when it renders, rather than letting a mistake surface as a
crash loop. The message names the value and what to set.

**`console-api` logs `no webhook secret provided` at `ERROR`.** Harmless unless
you use the identity-provider user-created webhook, which needs
`consoleApi.webhook.secret`. Without one the webhook accepts nothing.

**`console-api` restarts in a loop with no clear error.** Check it can reach the
database. It waits up to five minutes for the database before starting, so a
slow one still comes up; one it can't reach logs a timeout.

**config-controller fails with `executable file not found`.** `consoleVersion`
is older than the console images this chart needs. Set it to a
[supported version](#version-compatibility).

**A tenant cluster never reports, and its worker logs show `401`.** The key is
wrong, or `cloudSync.baseUrl` still points at `console.thoras.ai`, whose default
rejects a key from this console. Set it to the [ingest address](#the-ingest-address).
Check the worker logs on the tenant cluster:

```
kubectl logs deploy/thoras-worker -n thoras | grep -i sync
```

**A tenant cluster never reports, and its worker logs show `403` from nginx.**
`cloudSync.baseUrl` points at the dashboard address, which refuses ingest by
design. Point it at the [ingest address](#the-ingest-address).

**A tenant cluster has a key but never reports, with no errors.** It also has
`cloudSync.joinSecret` set, which turns cloud sync off. Keep one: the key, or the
join secret.

**A cluster reports, but its targets show "Target workload missing", or it shows
no version and 0 onboarded.** The tenant cluster has no metrics-server, so the
agent can't read pod usage. Install metrics-server there; the next sync fills
the targets in.

**The target list stays empty after moving a tenant cluster to a new key.** The
agent sends each target once and doesn't send it again for a new key, so the
new cluster entry never receives them. Clear the marker and they are sent again
on the next pass:

```
kubectl annotate aiscaletargets --all -A thoras.ai/cloud-sync-generation-
```

**A cluster that joins by itself never appears in the dashboard.** Read the
tenant cluster's config-controller logs for `console refused the cluster join`.
A 401 means the join secret is wrong; a 409 means another cluster already has
that `cluster.name`.

**A restore left clusters missing, or the database unreadable.** It was restored
into a running install. Start again from an empty install and follow
[Backup and restore](#backup-and-restore).

**A reinstall comes back with the old data, or a generated password stops
working.** The old database volume survived the uninstall. That happens on
Kubernetes older than 1.27, and with some local storage provisioners, such as
minikube's, which leave the data directory behind. Delete the claim, and the
leftover volume if one remains, then reinstall:

```
kubectl delete pvc data-thoras-console-db-0 -n thoras-console
```

## Values

### Global

| Key                             | Type   | Default                                          | Description                                                |
| ------------------------------- | ------ | ------------------------------------------------ | ---------------------------------------------------------- |
| consoleVersion                  | String | 4.123.0                                          | Image tag for the console components. Defaults to the release this chart version ships with |
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
| networkPolicy.flavor            | String | kubernetes                                       | kubernetes or cilium; any other value fails the render     |
| networkPolicy.apiServerPorts    | list   | [443, 6443]                                      | API server ports post-DNAT. Set 8443 on minikube           |
| serviceMonitor.enabled          | Bool   | false                                            | Scrape console-api and config-controller. Needs the Prometheus Operator |
| serviceMonitor.interval         | String | ""                                               | Empty defers to the Prometheus default                     |
| serviceMonitor.additionalLabels | object | {}                                               | Extra labels on the ServiceMonitor                         |

### Auth

| Key                                   | Type   | Default                                                   | Description                                                        |
| ------------------------------------- | ------ | --------------------------------------------------------- | ------------------------------------------------------------------ |
| auth.mode                             | String | local                                                     | local, oidc, or both                                               |
| auth.local.adminEmail                 | String | admin@localhost                                           | Label on the seeded admin user. Nothing authenticates against it   |
| auth.local.adminPassword              | String | ""                                                        | Minimum 12 characters. Generated when empty                        |
| auth.local.existingSecret.secretName  | String | ""                                                        | Read the admin password from your own Secret                       |
| auth.local.existingSecret.passwordKey | String | local-admin-password                                      | Key within that Secret                                             |
| auth.local.adminSalt                  | String | ""                                                        | Minimum 16 characters. Not secret. Never change it once set        |
| auth.oidc.issuer                      | String | ""                                                        | Required for oidc/both. Must match the iss claim exactly           |
| auth.oidc.audiences                   | list   | []                                                        | Required for oidc/both. Accepted aud values. A comma-separated string also works |
| auth.oidc.jwksUri                     | String | ""                                                        | Only when the issuer URL is unreachable from the cluster           |
| auth.oidc.client.id                   | String | ""                                                        | The dashboard's OAuth client ID. Required for oidc/both            |
| auth.oidc.client.scope                | String | openid profile read:* write:clusters write:cluster-tokens | Scopes requested at sign-in. Must be defined on your provider      |
| auth.oidc.client.audience             | String | ""                                                        | Audience the dashboard requests (Auth0). Defaults to the first of audiences |

### Console API

| Key                                          | Type   | Default              | Description                                                      |
| -------------------------------------------- | ------ | -------------------- | ---------------------------------------------------------------- |
| consoleApi.enabled                           | Bool   | true                 | Deploy console-api                                               |
| consoleApi.replicas                          | Number | 1                    | Replica count. The login rate limit is per-process               |
| consoleApi.image.repository                  | String | console-api          | Joined to imageCredentials.registry                              |
| consoleApi.containerPort                     | Number | 8080                 | Port the container listens on                                    |
| consoleApi.port                              | Number | 80                   | Service port                                                     |
| consoleApi.prometheus.enabled                | Bool   | true                 | Expose /metrics on its own port                                  |
| consoleApi.prometheus.port                   | Number | 9104                 | Metrics port; kept off the ingress-published containerPort       |
| consoleApi.ingress.enabled                   | Bool   | false                | The ingest address. Its own host, never the dashboard's          |
| consoleApi.ingress.ingressClassName          | String | nginx                | Cleared renders no ingressClassName                              |
| consoleApi.ingress.annotations               | object | {}                   | Annotations on the Ingress                                       |
| consoleApi.ingress.hosts                     | list   | console-api.local    | Hosts and paths. pathType defaults to Prefix                     |
| consoleApi.ingress.tls                       | list   | []                   | Each entry is hosts plus an optional secretName                  |
| consoleApi.gatewayAPI.enabled                | Bool   | false                | The same route as an HTTPRoute. Independent of ingress           |
| consoleApi.gatewayAPI.annotations            | object | {}                   | Annotations on the HTTPRoute                                     |
| consoleApi.gatewayAPI.parentRefs             | list   | gateway/default      | Gateways to attach to                                            |
| consoleApi.gatewayAPI.hostnames              | list   | console-api.local    | Hostnames to match                                               |
| consoleApi.gatewayAPI.path                   | String | /                    | Path to match                                                    |
| consoleApi.gatewayAPI.pathType               | String | PathPrefix           | Match type                                                       |
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
| consoleApi.clusterJoin.enabled               | Bool   | false                | Let clusters register themselves. Requires singleOrg             |
| consoleApi.clusterJoin.secret                | String | ""                   | Minimum 32 characters. Generated when empty                      |
| consoleApi.clusterJoin.existingSecret.secretName | String | ""               | Read the join secret from your own Secret                        |
| consoleApi.clusterJoin.existingSecret.secretKey | String | cluster-join-secret | Key within that Secret                                        |
| consoleApi.webhook.secret                    | String | ""                   | Shared secret for the identity-provider user-created webhook     |
| consoleApi.webhook.existingSecret.secretName | String | ""                   | Read the webhook secret from your own Secret                     |
| consoleApi.webhook.existingSecret.secretKey  | String | webhook-secret       | Key within that Secret                                           |
| consoleApi.useGlobalAffinity                 | Bool   | false                | Merge the global affinity into this component's                  |
| consoleApi.affinity                          | object | {}                   | Component affinity                                               |
| consoleApi.priorityClassName                 | String | ""                   | Takes precedence over the global priority class                  |
| consoleApi.topologySpreadConstraints         | list   | []                   | Replaces the global list when non-empty                          |
| consoleApi.extraEgressRules                  | list   | []                   | Appended verbatim to both NetworkPolicy flavors                  |
| consoleApi.extraIngressRules                 | list   | []                   | Appended verbatim to both NetworkPolicy flavors                  |

### Console Dashboard

The web UI. It runs the same `thoras-dashboard-v2` image as the
[thoras](../thoras/README.md) chart — there is no console-specific build — and
switches into console mode because of the `console` block this chart writes into
the `config.json` it serves. Its sign-in settings are in [Auth](#auth).

| Key                                        | Type   | Default                  | Description                                              |
| ------------------------------------------ | ------ | ------------------------ | -------------------------------------------------------- |
| consoleDashboard.enabled                   | Bool   | true                     | Deploy the dashboard                                     |
| consoleDashboard.replicas                  | Number | 1                        | Replica count                                            |
| consoleDashboard.image.repository          | String | thoras-dashboard-v2      | Joined to imageCredentials.registry                      |
| consoleDashboard.imageTag                  | String | ""                       | Overrides consoleVersion for this component              |
| consoleDashboard.containerPort             | Number | 8080                     | Port nginx listens on                                    |
| consoleDashboard.port                      | Number | 80                       | Service port                                             |
| consoleDashboard.externalUrl               | String | ""                       | Dashboard URL printed after install. Worked out from ingress when unset |
| consoleDashboard.extras                    | object | {}                       | Merged into config.json's extra block                    |
| consoleDashboard.serviceAccount.name       | String | thoras-console-dashboard | ServiceAccount name                                      |
| consoleDashboard.service.type              | String | ""                       | Service type. Empty leaves it to Kubernetes              |
| consoleDashboard.service.annotations       | object | {}                       | Annotations on the Service                               |
| consoleDashboard.labels                    | object | {}                       | Component labels                                         |
| consoleDashboard.podAnnotations            | object | {}                       | Component pod annotations                                |
| consoleDashboard.resources                 | object | 50m/64Mi, 500m/256Mi     | Requests and limits                                      |
| consoleDashboard.pdb.enabled               | Bool   | false                    | Render a PodDisruptionBudget                             |
| consoleDashboard.pdb.maxUnavailable        | Number | 1                        | minAvailable takes precedence if both are set            |
| consoleDashboard.ingress.enabled           | Bool   | false                    | The dashboard address, for people                        |
| consoleDashboard.ingress.ingressClassName  | String | nginx                    | Cleared renders no ingressClassName                      |
| consoleDashboard.ingress.annotations       | object | {}                       | Annotations on the Ingress                               |
| consoleDashboard.ingress.hosts             | list   | console.local            | Hosts and paths. pathType defaults to Prefix             |
| consoleDashboard.ingress.tls               | list   | []                       | Each entry is hosts plus an optional secretName          |
| consoleDashboard.gatewayAPI.enabled        | Bool   | false                    | The same route as an HTTPRoute. Independent of ingress   |
| consoleDashboard.gatewayAPI.annotations    | object | {}                       | Annotations on the HTTPRoute                             |
| consoleDashboard.gatewayAPI.parentRefs     | list   | gateway/default          | Gateways to attach to                                    |
| consoleDashboard.gatewayAPI.hostnames      | list   | console.local            | Hostnames to match                                       |
| consoleDashboard.gatewayAPI.path           | String | /                        | Path to match                                            |
| consoleDashboard.gatewayAPI.pathType       | String | PathPrefix               | Match type                                               |
| consoleDashboard.useGlobalAffinity         | Bool   | false                    | Merge the global affinity into this component's          |
| consoleDashboard.affinity                  | object | {}                       | Component affinity                                       |
| consoleDashboard.priorityClassName         | String | ""                       | Takes precedence over the global priority class          |
| consoleDashboard.topologySpreadConstraints | list   | []                       | Replaces the global list when non-empty                  |
| consoleDashboard.extraEgressRules          | list   | []                       | Appended verbatim to both NetworkPolicy flavors          |
| consoleDashboard.extraIngressRules         | list   | []                       | Appended verbatim to both NetworkPolicy flavors          |

### Config Controller

Generates any credential you don't supply into the
`thoras-console-config-controller` Secret, and restarts the pods that use them
when they change. It only writes a value that is missing, so an upgrade never
changes a generated password.

Disabling it is only valid when every credential is set or referenced;
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
| bundledDatabase.imageTag                     | String | 2.28.2-pg16       | TimescaleDB image tag                                                                                                                                              |
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
