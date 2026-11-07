---
# helm-899hp5y5
title: "Resolve every credential through one secret plan, seeded by config-controller"
status: accepted
type: decision
tags:
    - backfill
    - chart
    - secrets
    - config-controller
    - argo-cd
    - upgrade
created_at: 2026-11-07T02:18:26Z
updated_at: 2026-11-07T02:18:26Z
decided_at: 2026-09-04
refs:
    - "pr:thoras-ai/helm-charts#869"
    - "pr:thoras-ai/helm-charts#888"
    - "pr:thoras-ai/helm-charts#895"
    - "pr:thoras-ai/helm-charts#907"
    - "pr:thoras-ai/helm-charts#917"
    - "pr:thoras-ai/helm-charts#961"
    - "github:thoras-ai/platform#5047"
    - "doc:charts/thoras/UPGRADE.md"
    - "code:charts/thoras/templates/_helpers.tpl"
    - "code:charts/thoras/templates/thoras-helm-values-secret.yaml"
---

## Context
The chart generated secrets with `lookup` and `randAlphaNum`. That drifts under Argo CD and `helm template`, because `lookup` isn't available there. #869 tried a chart-managed `thoras-shared` Secret, which still needed `ignoreDifferences` and required manual restarts on rotation. It was reverted a day later (#888) and the work returned in 5.0.0 as #895.

## Decision
`thoras.secretPlan` is the only place a credential is resolved. Ref helpers, the pinned-values Secret, the controller's projected volume, its config and its RBAC all derive from it.

| Configured as | Stored in | Written by |
|---|---|---|
| existing Secret ref | your Secret | you |
| plain value | `thoras-helm-values` | Helm |
| nothing | `thoras-config-controller` | config-controller |

A fourth mode, `exchange`, covers cluster auto-join (#917). The console chart follows the same shape, and its external DSN comes only from a Secret, so it never lands in `helm get values` (#907).

## Options considered
- Chart-seeded shared Secret (#869): reverted. The revert PR gives no reason.
- `fail` when both a pinned key and a join secret are set: rejected, so adding a join secret to an existing install stops sync rather than breaking the upgrade. Sync turns off and `NOTES.txt` warns (#917).

## Consequences
- Generated lengths must match the old chart output, so migrated and generated values look the same.
- The bundled database password can't be pinned; the render fails, because it can't be rotated in place.
- Unset optional secrets omit the env var. The two exchange refs use `optional: true` instead, because the key doesn't exist until first join (#917).
- Pre-5.0 Secrets still render by default (`enableLegacySecretSeeding: true`), with `resource-policy: keep`, so the controller can migrate them. Removal is planned for 6.0. The policy has to be on the live object before the release that stops rendering them (`collector/secret.yaml` comment).
- #895's "no `ignoreDifferences`" applies once legacy seeding is off. The README still lists that step, plus `caBundle` and forecast-worker replicas.
- Generated Secrets survive uninstall, so a reinstall reuses them (#907).

## Provenance
Stated: #869, #895, #907, #917, UPGRADE.md, and comments in `_helpers.tpl` and `collector/secret.yaml`.
Inferred: that #869's Argo and rotation costs motivated the redesign. #895 lists the benefits but doesn't compare the two. #895 calls the pinned Secret `thoras-helm-shared`; the code name is `thoras-helm-values`.
