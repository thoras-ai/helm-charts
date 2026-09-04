# Upgrading Helm Chart (Breaking changes)

A major chart version change (like v1.2.3 -> v2.0.0) indicates that there is an incompatible breaking change needing manual actions.

**WARNING:** only migrating one major version at a time is supported (v1.x.x to v2.x.x).

This doc provides detailed upgrade and migration instructions.

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
