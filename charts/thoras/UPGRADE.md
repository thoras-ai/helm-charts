# Upgrading Helm Chart (Breaking changes)

A major chart version change (like v1.2.3 -> v2.0.0) indicates that there is an incompatible breaking change needing manual actions.

This doc provides detailed upgrade and migration instructions.

## To 5.0.0

Users who manage Thoras via `helm install` and `helm upgrade` with a
simple values file, and whose deployment matches all of the following,
only need to read the [Dashboard Auth Enabled by Default](#dashboard-auth-enabled-by-default)
and [Migrating from 4.x](#migrating-from-4x) sections below:

- `thorasDashboard.extraContainers` is unset (no hand-rolled
  oauth2-proxy sidecar)
- `thorasDashboard.service.targetPort` is unset (Service targets the
  chart's containerPort)
- `featureFlags.enableSimpleAuthSecret` is unset (only added between
  4.141.0 and 5.0.0)

Any deployment that deviates from one or more of the above must also
work through the matching section below.

### Dashboard Auth Enabled by Default

Chart 5.0.0 fronts the dashboard with an oauth2-proxy sidecar in
`htpasswd` mode by default. Sign in with:

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

The password is generated on first install and never rotated. To pin a
known value instead, set `thorasDashboard.auth.htpasswd.password` — the
pinned value lives in `thoras-helm-values` and takes precedence over
anything config-controller might seed. To front the dashboard with your
own auth instead, see [Externally Managed Auth](#externally-managed-auth).

### Migrating from the standalone oauth2-proxy sidecar

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

### Externally Managed Auth

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
interfaces, and the dashboard's `/v1/` block reverse-proxies to the API
server with the `apiClientSecret` bearer token injected server-side. Any
workload in the cluster that can reach the `thoras-dashboard` Service
therefore reaches both the dashboard UI and the allow-listed `/v1/` API
endpoints without authentication — the external ingress-/gateway-level
auth only protects the path through the ingress.

### Feature flag deprecation

`featureFlags.enableSimpleAuthSecret` is deprecated. Rename it to
`apiClientSecret.enabled` in your `values.yaml`. The legacy field still
works as an alias but will be removed in a future major release.
Setting both to conflicting values will cause the helm chart to fail.

### Migrating from 4.x

5.x moves secret seeding out of the chart and into config-controller. Your
existing API client token and TimescaleDB password are migrated for you, but
only if you go through 5.x. The supported path is **4.x -> 5.x -> 6.x**;
jumping straight from 4.x to 6.x loses both values.

Helm refreshes an object from the cluster before it checks
`helm.sh/resource-policy: keep`, so a single release cannot both stop
rendering a Secret and protect it. That is why the retention spans two
releases.

#### Upgrading from 4.x

1. Upgrade to 5.x with `legacySecretSeeding: true` (the default). The chart
   keeps rendering `api-client-secret` and `thoras-timescale-password` purely
   as migration sources; nothing consumes them. config-controller copies their
   values into `thoras-config-controller` on its first reconcile.
2. Confirm the migration landed:

   ```bash
   kubectl get secret thoras-config-controller -n <namespace> \
     -o jsonpath='{.metadata.annotations.thoras\.ai/migrated-keys}'
   ```

3. Set `legacySecretSeeding: false` and upgrade again. The two legacy Secrets
   stay in the cluster, orphaned, and you can delete them at your leisure.

Do not skip step 1. Upgrading from 4.x straight to `legacySecretSeeding:
false` prunes both Secrets before anything has read them, which rotates the
API client token and desynchronises the chart from the running database.

#### New installs

Set `legacySecretSeeding: false`. There is nothing to migrate.

#### Argo CD

Nothing the chart renders needs `ignoreDifferences` any more.
`thoras-helm-values` contains only what you pinned in values, and
`thoras-config-controller` is created by the controller rather than by
Helm, so Argo CD neither tracks nor prunes it. If you carry an
`ignoreDifferences` entry for a chart Secret today, you can drop it
once this migration is complete.

The two legacy Secrets are the exception, for the duration of 5.x only.
`lookup` returns nothing under Argo CD, so the chart regenerates their
values on every render; without this, Argo would apply a fresh random
password that does not match the running database.

```yaml
spec:
  ignoreDifferences:
    - group: ""
      kind: Secret
      name: api-client-secret
      jsonPointers: [/data]
    - group: ""
      kind: Secret
      name: thoras-timescale-password
      jsonPointers: [/data]
```

Drop both entries once you set `legacySecretSeeding: false`. See the
chart README's [ArgoCD](./README.md#argocd) section for the wider
Argo CD `ignoreDifferences` set (webhook `caBundle`, forecast worker
replicas).
