# Upgrading Helm Chart (Breaking changes)

A major chart version change (like v1.2.3 -> v2.0.0) indicates that there is an incompatible breaking change needing manual actions.

**WARNING:** only migrating one major version at a time is supported (v1.x.x to v2.x.x).

This doc provides detailed upgrade and migration instructions.

## Scaling pause state during upgrades

Scaling pause state is now owned by the API server rather than the chart. Upgrades
preserve the existing `thoras-operator-system-config` ConfigMap and its pause
value. Fresh installations start unpaused; the API server creates the ConfigMap
when the pause state is first changed.

A Helm `pre-install,pre-upgrade` hook, mapped to an Argo CD `PreSync` hook,
migrates existing installations before resources are applied or pruned. It only
patches metadata, retaining the ConfigMap and removing Argo CD tracking metadata.
It does not change `system-config.yaml`. If migration fails, resolve the hook
failure and retry the upgrade; do not force ownership of the pause field.

The hook uses the configured operator image, registry credentials, hook scheduling,
and network policy settings. It needs permission to create its namespaced hook
resources and to patch this ConfigMap. With Argo CD label tracking, set
`thorasOperator.pauseStateMigration.argocdInstanceLabelKey` to the value of
`application.instanceLabelKey` in `argocd-cm` if it differs from
`app.kubernetes.io/instance`.

The hook preserves the existing ConfigMap during the first Helm upgrade or Argo
CD sync that removes the old manifest. If hooks are skipped and that operation
deletes or prunes removed resources, preserve the live object first:

```bash
kubectl -n thoras annotate configmap thoras-operator-system-config \
  helm.sh/resource-policy=keep \
  argocd.argoproj.io/sync-options=Prune=false --overwrite
```

For Argo CD, also remove its tracking annotation and instance label from the
ConfigMap before syncing. Substitute the configured label key when using custom
label tracking:

```bash
kubectl -n thoras annotate configmap thoras-operator-system-config \
  argocd.argoproj.io/tracking-id-
kubectl -n thoras label configmap thoras-operator-system-config \
  app.kubernetes.io/instance-
```

These manual steps apply to existing ConfigMaps when skipping the migration
hook during removal or pruning. Substitute the release namespace for `thoras`.
Plain `helm template` emits no pause ConfigMap; applying its output without
pruning does not reset the pause value.

Older charts still declare `scaling-paused: false`. Restoring that older manifest
can fail when Helm attempts to manage the runtime ConfigMap again.

The runtime ConfigMap is retained across uninstall/reinstall; explicitly remove
it if a clean installation must start unpaused.

## To 5.x

All users should read the following [Changes Overview](#changes-overview).

Users with a Thoras deployment that matches any of the following should also
work through the matching section in [Breaking Changes](#breaking-changes).

- [Uses a hand-rolled oauth2-proxy sidecar](#migrating-from-the-standalone-oauth2-proxy-sidecar)
- [Has externally managed authentication in front of the dashboard](#externally-managed-auth)
- [`featureFlags.enableSimpleAuthSecret`](#feature-flag-deprecation)


### Changes Overview

#### Dashboard Auth Enabled by Default

Chart 5.0.0 adds authentication to the Thoras dashboard by default.
Sign in with:

- **Username**: `thoras` (`thorasDashboard.auth.htpasswd.username`)
- **Password**: seeded by config-controller into the
  `thoras-config-controller` Secret. Substitute your release namespace
  for `thoras` if you installed elsewhere:

  ```
  kubectl get secret thoras-config-controller -n thoras \
    -o jsonpath='{.data.dashboard-auth-password}' | base64 -d
  ```

  The Secret appears once config-controller has finished its first
  reconcile. On a fresh install the dashboard pod briefly reports
  `CreateContainerConfigError` until then.

The password is generated on first install. To provide a
known value instead, set `thorasDashboard.auth.htpasswd.password` or
`thorasDashboard.auth.htpasswd.existingSecret`
To front the dashboard with your
own auth instead, see [Externally Managed Auth](#externally-managed-auth).

#### In Cluster Secret Seeding and Update Monitoring

5.x moves secret seeding out of the chart and into a new Thoras service: config-controller.
If you leveraged the Charts secret seeding (default behavior) upgrading to 5.x will automatically
migrate the existing seeded secrets in cluster, no intervention needed.

Upgrading from 4.x renders the pre-5.0 `api-client-secret` and `thoras-timescale-password`
Secrets again so config-controller can migrate them. The migration is complete when
`thoras-config-controller` carries the keys: `timescale-password` and `timescale-dsn` for the
bundled database, and `api-client-secret` when the API client is enabled and its value is neither
pinned in values nor supplied by your own Secret (those two never go through the managed Secret):

```sh
kubectl -n thoras get secret thoras-config-controller -o json | jq -r '.data | keys[]'
```

With Argo CD or `helm template` the chart cannot see the cluster, so it cannot tell that a
migration is pending, and it renders the pre-5.0 Secrets with fresh random values on every
render. `featureFlags.enableLegacySecretSeeding` therefore stays `true` by default through 5.x,
so the migration source is never pruned, and the live values must not be overwritten before
config-controller has read them:

- Argo CD: add `ignoreDifferences` entries for `/data` on both Secrets and
  `RespectIgnoreDifferences=true` to the Application's `syncOptions` before the upgrade (see the
  README's ArgoCD section), and keep them until the flag is `false`.
- `helm template` pipelines: apply the rendered `api-client-secret` and
  `thoras-timescale-password` only when they do not already exist.

Once the keys are in `thoras-config-controller`, the rendered values no longer matter: nothing
reads the pre-5.0 Secrets.

Once `thoras-config-controller` carries the migrated keys, set the flag to `false`. On
`helm upgrade` the chart then renders the Secrets only while a migration is pending; with
Argo CD or `helm template` it stops rendering them, so confirm the keys first. An existing
5.x install that has already migrated keeps its credentials either way; the old Secrets stay
on the cluster, unused, and can be deleted. The default flips in 6.0, when the templates are
removed.

#### Rotating the generated credentials after upgrading

Helm keeps the values of rendered Secrets in its release history, and the pre-5.0 Secrets stay
on the cluster after migration. An install that used the chart's default seeding before 5.x
therefore still has its generated API client secret and database password in earlier release
revisions, until Helm's history limit (10 revisions by default) prunes them, and in those
Secrets. Rotate both once the upgrade is healthy. config-controller restarts the workloads that
use each value, so no manual rollout is needed.

**API client secret** (`apiClientSecret.enabled`, with no pinned or external value): delete the
pre-5.0 Secret, then remove the key from the managed Secret. config-controller seeds a new value
on its next tick, within about 30 seconds.

```sh
kubectl -n thoras delete secret api-client-secret
kubectl -n thoras patch secret thoras-config-controller --type=json \
  -p='[{"op":"remove","path":"/data/api-client-secret"}]'
```

**Database password** (bundled TimescaleDB): set a new password on the database, then store it
and the DSN that embeds it in the managed Secret. The two keys must change together, and the
database must accept the new password before the Secret changes.

Changing these keys restarts `metrics-collector`, which runs the database. With
`metricsCollector.persistence.enabled: false` (the default) the database lives on an `emptyDir`,
so that restart deletes the stored metrics, as any restart of that pod does. If you need them,
take a backup first and restore it after the rotation; turning persistence on for an existing
install does not carry the `emptyDir` data over.

```sh
kubectl -n thoras exec deploy/metrics-collector -c timescaledb -- \
  pg_dump -U postgres -h localhost -Fc thoras > thoras-metrics.dump
```

Restore it with `pg_restore` between `SELECT timescaledb_pre_restore();` and
`SELECT timescaledb_post_restore();`, as the TimescaleDB backup documentation describes.

Run the rotation as one script, so the Secret changes only after the database accepted the new
password. Both values travel on stdin: the password never appears in a process argument, locally
or in the exec request that API audit logs record.

```sh
set -e
NEW_PASSWORD=$(openssl rand -hex 16)

kubectl -n thoras exec -i deploy/metrics-collector -c timescaledb -- \
  psql -U postgres -h localhost -q -v ON_ERROR_STOP=1 <<SQL
ALTER ROLE postgres PASSWORD '${NEW_PASSWORD}';
SQL

kubectl -n thoras patch secret thoras-config-controller --type=merge --patch-file /dev/stdin <<JSON
{"stringData":{"timescale-password":"${NEW_PASSWORD}","timescale-dsn":"postgres://postgres:${NEW_PASSWORD}@timescale:5432"}}
JSON
```

If the patch fails after the database update succeeded, run the patch again with the same
`NEW_PASSWORD`; the database already has it. Use your own values for the host and port in the DSN
if `metricsCollector.timescale.name` or `containerPort` is customised. The pre-5.0
`thoras-timescale-password` Secret keeps the old value; nothing reads it, and you can delete it.

Pinned values (`apiClientSecret.secret`) and externally managed Secrets rotate as described in
the README under "Rotating secrets".

If you leverage any of the chart's [Externally Managed Auth](#externally-managed-auth) options,
config-controller will handle a rolling restart of any Thoras workloads that depend on the secrets when a change is detected.

### Breaking Changes

#### Externally Managed Auth

If you already terminate authentication at the ingress or gateway (a
custom SSO sidecar, edge-level auth plugin, service-mesh policy, ...),
disable the chart's built-in oauth2-proxy sidecar:

```yaml
thorasDashboard:
  auth:
    enabled: false
```

**In-cluster exposure warning.** With `auth.enabled: false`, the
dashboard's nginx binds `thorasDashboard.containerPort` on all
interfaces, meaning any workload in the cluster that can reach the `thoras-dashboard` Service
can access part of the Thoras API without authentication.

#### Migrating from the standalone oauth2-proxy sidecar

Customers who previously ran their own oauth2-proxy as
`thorasDashboard.extraContainers` and retargeted the Service at port `4180`
can migrate onto the chart-shipped sidecar without touching the IdP app
registration or the existing `oauth2-proxy-secrets` Secret:

**Delete** from `values.yaml`, noting your existing oauth2-proxy `--` arg
values for the next step:

```yaml
thorasDashboard:
  service:
    targetPort: 4180        # remove
  extraContainers:          # remove the entire oauth2-proxy container
    - name: oauth2-proxy
      # ...
```

**Add** — substitute the values you noted above into the corresponding
`thorasDashboard.auth.oidc` fields:

```yaml
thorasDashboard:
  auth:
    mode: oidc
    oidc:
      issuerURL: <your existing --oidc-issuer-url flag value>
      redirectURL: https://thoras.example.com/oauth2/callback
      emailDomains: [example.com]
      existingSecret:
        secretName: oauth2-proxy-secrets
```

The chart reuses the existing `oauth2-proxy-secrets` Secret as-is (default
key names: `client-id`, `client-secret`, `cookie-secret`). The Service goes
back to targeting `containerPort` (now owned by the chart's sidecar), so
drop any `service.targetPort` override.

#### Feature flag deprecation

`featureFlags.enableSimpleAuthSecret` is deprecated. Rename it to
`apiClientSecret.enabled` in your `values.yaml`. The legacy field still
works as an alias but will be removed in a future major release.
Setting both to conflicting values will cause the helm chart to fail.
