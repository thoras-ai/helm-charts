# Upgrading Helm Chart (Breaking changes)

A major chart version change (like v1.2.3 -> v2.0.0) indicates that there is an incompatible breaking change needing manual actions.

This doc provides detailed upgrade and migration instructions.

## To 5.0.0

### ArgoCD ignoreDifferences:

5.0.0 introduces `Secret/thoras-shared` as the centralized store for
chart-generated random values (dashboard password/cookie secret, API
client secret). Add it to your `Application`'s `spec.ignoreDifferences`
alongside your existing entries:

```yaml
ignoreDifferences:
  - jsonPointers:
      - /data
    kind: Secret
    name: thoras-shared
```

If you carried a manual entry for `Secret/api-client-secret`, drop it —
that Secret is no longer emitted by the chart.

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

### api-client-secret moved to thoras-shared

`Secret/api-client-secret` is no longer emitted by the chart; the value
now lives in `Secret/thoras-shared` under key `api-client-secret`.
`helm upgrade` handles this transparently for the default chart-seeded
pattern — no manual action needed.

Action required only if you:

* Referenced `Secret/api-client-secret` by name from outside the chart
  (e.g. custom workloads, external tooling): update the reference to
  read `Secret/thoras-shared` key `api-client-secret`, or point the
  chart at a user-managed Secret via
  `apiClientSecret.existingSecret.secretName` and read from there.
* Already upgraded to 4.141.0 or later and use ArgoCD. ArgoCD does not
  execute `lookup` at render time, so the transparent migration above
  does not run and `api-client-secret` is rotated on upgrade. Restart
  every consumer after the sync completes:

  ```bash
  kubectl rollout restart deployment -n <namespace> \
    -l app.kubernetes.io/name=thoras
  ```
