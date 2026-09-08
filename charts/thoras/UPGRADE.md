# Upgrading Helm Chart (Breaking changes)

A major chart version change (like v1.2.3 -> v2.0.0) indicates that there is an incompatible breaking change needing manual actions.

**WARNING:** only migrating one major version at a time is supported (v1.x.x to v2.x.x).

This doc provides detailed upgrade and migration instructions.

## To 6.x

All users should read the following [Changes Overview](#changes-overview).

Users with a Thoras deployment that matches any of the following should also
work through the matching section in [Breaking Changes](#breaking-changes).

- [Runs an API server on a port other than 443, 6443 or 8443](#api-server-port)
- [Uses an external TimescaleDB](#external-timescaledb)
- [Scrapes the API server's metrics](#scraping-the-api-server)
- [Routes component egress through an HTTP proxy](#egress-through-an-http-proxy)
- [Uses `networkPolicy.flavor: cilium`](#cilium-flavor-and-outbound-https)

### Changes Overview

#### Network Policies Enabled by Default

`networkPolicy.enabled` now defaults to `true`. A `helm upgrade` that does not
set it applies eight `NetworkPolicy` objects to the release namespace, moving
the selected pods from "allow everything" to "allow only what the policy
lists".

Before 6.0.0 a default install had no in-cluster segmentation: any pod in the
cluster could reach the Thoras API server (`:80`) and TimescaleDB (`:5432`)
directly. The API server's only other control is a shared bearer token held in
a Secret in the same cluster.

To keep pre-6.0 behavior:

```yaml
networkPolicy:
  enabled: false
```

That render is byte-identical to the 5.x default.

If connectivity breaks mid-rollout, deleting the policies restores it
immediately. Substitute your release name and namespace:

```
kubectl delete networkpolicy -l app.kubernetes.io/instance=thoras -n thoras
```

Set `networkPolicy.enabled: false` afterwards so the next upgrade does not
re-create them.

The policies allow ingress from, and egress to, other pods in the release
namespace, plus DNS, the Kubernetes API, Prometheus scrapes, and an external
TimescaleDB when one is configured. See [README >
NetworkPolicy](README.md#networkpolicy) for the full list and for the
per-component `extraIngressRules` / `extraEgressRules` escape hatches.

#### New NetworkPolicy Values

| Key | Default | Purpose |
| --- | --- | --- |
| `networkPolicy.apiServerCIDRs` | `[]` | Scopes the API server egress rule to these ipBlocks. Left empty, that rule carries ports but no destination, which Kubernetes evaluates as any destination on those ports. Ignored by the `cilium` flavor, which scopes by identity. |
| `networkPolicy.externalDatabasePorts` | `[5432]` | Ports an external TimescaleDB listens on. |
| `networkPolicy.allowMetricsScraping` | `true` | Opens each component's Prometheus port to all namespaces. |
| `networkPolicy.allowDnsToAnyDestination` | `true` | Allows port 53 to any destination alongside the kube-dns rule. Required by NodeLocal DNSCache, which answers on a link-local address owned by the node rather than a pod. |

`networkPolicy.apiServerPorts` also gains `8443` by default.

### Breaking Changes

#### API Server Port

NetworkPolicy is enforced after kube-proxy translates the service address to
the real endpoint, so `networkPolicy.apiServerPorts` must list the port the API
server actually listens on. Check with:

```
kubectl get endpoints kubernetes -n default
```

If the port is not 443, 6443 or 8443, add it:

```yaml
networkPolicy:
  apiServerPorts:
  - 443
  - 6443
  - 8443
  - 9443
```

The certgen policy is a `pre-install`/`pre-upgrade` hook. If the certgen Job
cannot reach the API server the hook fails, and the release fails with it.

#### External TimescaleDB

An external database is outside the release namespace, so the in-namespace
egress rule does not cover it. The host is not knowable at render time, so
egress is scoped by port. If your database does not listen on 5432:

```yaml
networkPolicy:
  externalDatabasePorts:
  - 6432
```

#### Scraping the API Server

Components with a dedicated Prometheus port accept scrapes from any namespace
by default. The API server is excluded: its `/metrics` endpoint shares the API
port, so opening it would expose the API itself. To scrape it, allow your
monitoring namespace explicitly:

```yaml
thorasApiServerV2:
  extraIngressRules:
    - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: monitoring
      ports:
      - port: 8080
        protocol: TCP
```

#### Egress Through an HTTP Proxy

`proxy.httpProxy` and `proxy.httpsProxy` are not modeled by the policies. If
the proxy is outside the release namespace on a port other than 443, 6443 or
8443, add an egress rule to each component that uses it:

```yaml
thorasWorker:
  extraEgressRules:
    - ports:
      - port: 3128
        protocol: TCP
```

#### Cilium Flavor and Outbound HTTPS

Under `networkPolicy.flavor: cilium`, egress is scoped by identity, and
`toEntities: [kube-apiserver]` does not cover the internet. Cloud sync
(`cloudSync.baseUrl`) and Slack notifications (`slackWebhookUrl`) need an
explicit rule on the components that use them (api-server-v2, worker, operator
for cloud sync; those plus collector and config-controller for Slack):

```yaml
thorasWorker:
  extraEgressRules:
    - toFQDNs:
      - matchName: "console.thoras.ai"
      toPorts:
      - ports:
        - port: "443"
          protocol: TCP
```

The `kubernetes` flavor permits this traffic through the ports-only API server
egress rule and needs no change.

## To 5.x

All users should read the following [Changes Overview](#changes-overview-1).

Users with a Thoras deployment that matches any of the following should also
work through the matching section in [Breaking Changes](#breaking-changes-1).

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
