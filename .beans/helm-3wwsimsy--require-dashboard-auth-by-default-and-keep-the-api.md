---
# helm-3wwsimsy
title: "Require dashboard auth by default and keep the api-server unaware of users"
status: accepted
type: decision
tags:
    - backfill
    - chart
    - auth
    - oidc
    - dashboard
    - trust-boundary
created_at: 2026-11-07T02:18:26Z
updated_at: 2026-11-07T07:30:31Z
decided_at: 2026-09-04
refs:
    - "pr:thoras-ai/helm-charts#851"
    - "pr:thoras-ai/helm-charts#854"
    - "pr:thoras-ai/helm-charts#856"
    - "pr:thoras-ai/helm-charts#869"
    - "pr:thoras-ai/helm-charts#888"
    - "pr:thoras-ai/helm-charts#895"
    - "pr:thoras-ai/helm-charts#918"
    - "pr:thoras-ai/helm-charts#925"
    - "github:thoras-ai/platform#5029"
    - "doc:charts/thoras/UPGRADE.md"
    - "code:charts/thoras/templates/_config-data.tpl"
---

## Context
The dashboard was reachable without sign-in unless a customer added their own proxy, and some ran oauth2-proxy by hand through `extraContainers` (UPGRADE.md). The api-server has no user model (#918). Shared-secret auth between services arrived in #851 and was defaulted on in #856.

## Decision
- `thorasDashboard.auth.enabled` defaults to true, using a chart-shipped oauth2-proxy sidecar. The default mode is `htpasswd` with a generated password. `oidc` reads client credentials from a Secret the customer manages.
- nginx adds the shared secret as `Authorization: Bearer` server-side through envsubst, so it never reaches the nginx ConfigMap or the browser (#854).
- Identity reaches the api-server as `X-Forwarded-Email` and `X-Forwarded-User`, for best-effort audit attribution. When auth is off, nginx strips both, so a client can't supply them (#918).
- `cookieSecure` defaults to false, because Secure cookies break Safari over `kubectl port-forward` (#869 comment, values comment).
- `thoras-console` differs: `auth.mode` is `local`, `oidc` or `both`, handled by console-api with no oauth2-proxy. Its OIDC issuer and audiences are required in `oidc` and `both` modes, since binary defaults point at the hosted console (#905, #925).

## Options considered
A first version merged as #869 and was reverted the next day (#888, no reason given), before any release included it. It returned in 5.0.0 with #895. Other options weren't recorded.

## Consequences
- 5.0.0 is breaking for anyone with auth at the edge; they set `auth.enabled: false` (UPGRADE.md).
- `htpasswd` has one shared username, so per-person attribution needs `oidc` (#918).
- The header guarantee relies on oauth2-proxy defaults. `auth.extraArgs` can change them; the values file warns about this (#918).
- Production setups are expected to enable `cookieSecure` with TLS at the edge.
- `enableSimpleAuthSecret` is deprecated in favour of `apiClientSecret.enabled`.

## Provenance
Stated: the cited PRs, UPGRADE.md and values comments.
Inferred: the first Context sentence is drawn from UPGRADE.md's migration section. The reason for choosing on-by-default isn't written down beyond #869's description, and the sidecar choice over other proxies isn't recorded.
