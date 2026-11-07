---
# helm-pt37si6d
title: "Bundled console database is evaluation-only, with frozen volume template labels"
status: accepted
type: decision
tags:
    - backfill
    - chart
    - thoras-console
    - bundled-database
    - timescaledb
    - upgrade
created_at: 2026-11-07T02:18:27Z
updated_at: 2026-11-07T07:30:31Z
decided_at: 2026-09-24
refs:
    - "pr:thoras-ai/helm-charts#907"
    - "pr:thoras-ai/helm-charts#922"
    - "pr:thoras-ai/helm-charts#925"
    - "doc:charts/thoras-console/README.md"
    - "doc:AGENTS.md"
    - "code:charts/thoras-console/templates/database/statefulset.yaml"
---

## Context
The console chart wanted a single-command evaluation install with no database to provision first (#907). Its StatefulSet first put the full label helper on `volumeClaimTemplates`, including `helm.sh/chart` and user labels. That field is immutable, so every chart bump failed with `Forbidden`, after Helm had already rolled the Deployments, leaving a `failed`, half-applied release (#922).

## Decision
- A single-replica TimescaleDB StatefulSet is enabled by default and documented as evaluation-only: no automatic backups, no HA, downtime on upgrade.
- Setting `externalDatabase` switches over. Setting both fails the render. `bundledDatabase.enabled` is deliberately absent from `values.yaml`, so `hasKey` can tell unset from explicit.
- The external DSN comes only from a Secret you manage.
- `thoras-console.databaseVolumeLabels` emits only `app.kubernetes.io/name` and `instance`. Nothing there may vary with chart version or values. The StatefulSet's own metadata and pod template keep the full labels.
- The volume retention policy is `whenDeleted: Delete`, so uninstalling or switching to an external database deletes the PVC. Whether the data goes too depends on the PV reclaim policy and the storage provisioner. `Retain` keeps it, and the README notes that some local provisioners leave the data directory behind. Treat the data as gone, but don't rely on it being erased. The README calls deletion the right trade for evaluation, since it leaves no orphaned volume.

## Options considered
An upgrade guard for pre-fix installs was skipped, because the chart was unpublished and affected installs were internal; a one-time `kubectl delete statefulset --cascade=orphan` is documented instead (#922). Other options weren't recorded.

## Consequences
- `persistence.size` and `storageClassName` feed the same template, so changing them still fails an upgrade. #922 treats this as inherent to StatefulSets.
- Generated credentials are written at runtime and survive uninstall, so a reinstall reuses passwords against a new, empty database (#907).
- Kubernetes older than 1.27 ignores the retention policy, so the volume survives there (#907, README).
- The `-pg16` tag and major upgrades carry the same limits as the `thoras` bundled database.

## Provenance
Stated: #907, #922, the console README and the helper comment. AGENTS.md repeats the label rule.
Inferred: the last consequence, by comparing the two charts' tags. The reclaim-policy point comes from Kubernetes persistent volume behaviour, not from a PR.
