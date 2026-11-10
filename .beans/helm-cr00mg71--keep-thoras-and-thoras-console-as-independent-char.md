---
# helm-cr00mg71
title: "Keep thoras and thoras-console as independent charts that can share a namespace"
status: accepted
type: design
tags:
    - backfill
    - chart
    - thoras-console
    - packaging
created_at: 2026-11-07T02:18:26Z
updated_at: 2026-11-07T02:18:26Z
decided_at: 2026-09-08
refs:
    - "pr:thoras-ai/helm-charts#905"
    - "pr:thoras-ai/helm-charts#907"
    - "pr:thoras-ai/helm-charts#914"
    - "pr:thoras-ai/helm-charts#924"
    - "pr:thoras-ai/helm-charts#929"
    - "pr:thoras-ai/helm-charts#970"
    - "doc:AGENTS.md"
    - "code:charts/thoras-console/templates/_helpers.tpl"
---

## Context
Self-hosted customers needed to install the console from a chart. `thoras` installs the platform on an observed cluster; `thoras-console` installs the console those clusters report into. The console chart was created in #905.

## Decision
The charts stay separate: neither declares the other as a dependency, and each has its own chart version and app version value. They may run in one namespace, so console helpers carry a `thoras-console.` prefix (including `imagePullSecret`, which `thoras` leaves unprefixed) and console resources carry console-specific names such as `thoras-console-secret-registry`.

The console reuses `thoras-dashboard-v2` unchanged; the bundle enters console mode when the chart-written `config.json` has a `console` key (#914). console-api and config-controller share one image, so the chart tracks one version (#907). Clusters connect over the network through `cloudSync`, not through chart wiring. The documented floor is console images 4.123.0 and `thoras` 5.4.0 on tenant clusters (#924).

## Options considered
Not recorded. #905 notes only that template names are global to a rendering, so unprefixed duplicates would collide if the charts are ever composed.

## Consequences
- A new template or resource name has to be checked against the other chart.
- Binary defaults can assume the tenant chart. `SERVICE_WORKLOAD_SELECTOR` had to be overridden in the console, or seeding would work while rollouts silently never happened (#907).
- The two charts differ in instance count: a second console in another namespace was exercised in #929, while a second `thoras` release collides on CRDs, webhook configurations and ClusterRoles (#970 test notes).

## Provenance
Stated: #905, #907, #914, #924 and AGENTS.md give the prefixing, shared image and minimum versions. #970 and #929 describe the instance behaviour as observed in testing.
Inferred: "independent" as a deliberate design is read from the lack of a Chart.yaml dependency and from separate release handling (#924). The choice against a subchart wasn't recorded.
