---
# helm-vaotczve
title: "Dashboard proxy denies by default; console browser and ingest traffic use separate hosts"
status: accepted
type: decision
tags:
    - backfill
    - chart
    - dashboard
    - nginx
    - thoras-console
    - trust-boundary
created_at: 2026-11-07T02:18:27Z
updated_at: 2026-11-07T02:56:40Z
decided_at: 2026-09-17
refs:
    - "pr:thoras-ai/helm-charts#760"
    - "pr:thoras-ai/helm-charts#914"
    - "pr:thoras-ai/helm-charts#944"
    - "github:thoras-ai/platform#4285"
    - "doc:AGENTS.md"
    - "code:charts/thoras/templates/_config-data.tpl"
    - "code:charts/thoras-console/templates/_config-data.tpl"
---

## Context
The dashboard's nginx proxied `/v1/` to the api-server with no route filter. #760 applied least privilege there with no API server changes. When the console chart gained a dashboard, it needed the same protection, plus a way for tenant clusters to reach ingest.

## Decision
- `thoras`: nginx enumerates each allowed `{method, path}` with a `map`, and everything else returns 403. The first list came from a sweep of dashboard API calls.
- `thoras-console`: deny by default too, but allow `/api/v1/` as a prefix, with `ingest/` and `hook/` refused first. It departs from the enumerated approach (#914).
- console-api gets its own Ingress or HTTPRoute for tenant ingest, so ingest isn't exposed on the browser-facing host.
- Console `mode` and `issuer` in `config.json` derive from the auth values, since the dashboard can't ask the server, and two values could disagree.
- The nginx config, including the `/config.json` handler, is templated. Without the handler, nginx would fall through to the developer config in the image and serve it without erroring; a test pins this (#914).

## Options considered
#914 considered deriving the console list from `go/openapi-console.yaml`, which the ticket suggested, and calls that unsafe. Its detailed reasoning isn't in the merged PR text. Keeping ingest on the dashboard host was rejected, since it would expose ingest publicly alongside the UI.

## Consequences
- A dashboard call to a new API route in `thoras` returns 403 under Helm until it's added to `_config-data.tpl`. Many later PRs exist only to do this (for example #798, #848, #953).
- Two console hostnames mean two DNS records and two certificates on first install, and tenant `cloudSync.baseUrl` must be the ingest address; the dashboard address refuses with 403 (#929).
- #760 describes the allowlist as raising the floor, not as full RBAC.
- `thorasDashboard.read_only` hides write features in the dashboard and leaves the API server flag unchanged (#944). It also drops the cost-alert write routes from the allowlist, but other write routes, such as the scaling pause, stay allowed.

## Provenance
Stated: #760, #914, #929, #944, AGENTS.md, and comments in both config templates.
Inferred: that `/v1/` had no filter before #760, from its diff description. The OpenAPI reasoning stays unknown; #914's text points to a reviewer note it doesn't contain.
