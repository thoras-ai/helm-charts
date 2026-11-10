---
# helm-eu3yusak
title: "API server owns the scaling pause ConfigMap at runtime, not the chart"
status: accepted
type: decision
tags:
    - backfill
    - chart
    - upgrade
    - pause-state
    - argo-cd
    - data-ownership
created_at: 2026-11-07T02:18:27Z
updated_at: 2026-11-07T02:18:27Z
decided_at: 2026-10-28
refs:
    - "pr:thoras-ai/helm-charts#543"
    - "pr:thoras-ai/helm-charts#544"
    - "pr:thoras-ai/helm-charts#549"
    - "pr:thoras-ai/helm-charts#896"
    - "pr:thoras-ai/helm-charts#956"
    - "pr:thoras-ai/helm-charts#964"
    - "pr:thoras-ai/helm-charts#970"
    - "github:thoras-ai/platform#5341"
    - "doc:charts/thoras/UPGRADE.md"
    - "code:charts/thoras/templates/operator/pause-state-migration.yaml"
---

## Context
#543 added `thoras-operator-system-config` as a chart template rendering `scaling-paused: false`. That value is changed at runtime, so the chart and the API server both claimed it. Helm 4 hit an ownership conflict, and Helm 3 could silently unpause scaling during an upgrade (#964).

## Decision
- The chart no longer renders the ConfigMap. The API server creates it on the first pause change, and fresh installs start unpaused.
- Operator, worker and api-server mount it with `optional: true`, so a missing ConfigMap is fine.
- A `pre-install,pre-upgrade` hook, mapped to Argo CD `PreSync`, patches metadata only. It retains the object, removes Argo CD tracking metadata, and never touches `system-config.yaml`.
- `argocdInstanceLabelKey` handles custom Argo label tracking.
- UPGRADE.md says to resolve a hook failure and retry, not to force ownership of the pause field.

## Options considered
Not recorded.

## Consequences
- The ConfigMap survives uninstall, so a reinstall in the same namespace keeps its pause state. A clean start means deleting it.
- Rolling back to a chart that still declares it failed in #964's isolated Helm 3 and 4 tests, while keeping the paused value.
- Workflows that skip hooks and prune removed resources must protect the object first; UPGRADE.md gives the commands.
- The chart holds no value for this setting, so a pause can't be set from `values.yaml`.
- The hook needs a variant per image: `curl` normally, `/app/operator migrate-pause-state` in FIPS mode (#970).
- The same pattern applies to anything else written at runtime: rendering it from the chart makes upgrades reset or fight over it.

## Provenance
Stated: #964, #970, UPGRADE.md and the current templates. `api-server-v2/rbac.yaml` carries the ConfigMap grants.
Inferred: the point that a pause can't be set from values, and the last consequence, which is our generalization and not a statement in the sources.
