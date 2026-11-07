---
# helm-fvswe1cx
title: "Treat stored values and value names as a compatibility surface"
status: accepted
type: decision
tags:
    - backfill
    - chart
    - upgrade
    - values
    - compatibility
created_at: 2026-11-07T02:18:26Z
updated_at: 2026-11-07T02:56:40Z
decided_at: 2026-09-29
refs:
    - "pr:thoras-ai/helm-charts#871"
    - "pr:thoras-ai/helm-charts#913"
    - "pr:thoras-ai/helm-charts#917"
    - "pr:thoras-ai/helm-charts#925"
    - "pr:thoras-ai/helm-charts#927"
    - "pr:thoras-ai/helm-charts#949"
    - "pr:thoras-ai/helm-charts#967"
    - "pr:thoras-ai/helm-charts#970"
    - "doc:charts/thoras/UPGRADE.md"
    - "doc:AGENTS.md"
    - "code:charts/thoras/tests/reuse_values_smoke_test.yaml"
---

## Context
`helm upgrade --reuse-values` renders a new chart against stored values without merging new defaults. A direct traversal of a newer key panicked at render, including for installs that never used the feature: #871 found this on the default certgen path, and #949 reproduced it on a live cluster.

## Decision
- Templates read newer values nil-safely. Each new block gets a case in `reuse_values_smoke_test.yaml`, which renders every template with the block removed.
- Under `--reuse-values`, a missing key renders as off or as a safe fallback. That can differ from the new default, though some fallbacks equal it (`fipsImageTag`, `apiClientSecret.enabled`). READMEs recommend `--reset-then-reuse-values` where the default matters (#967).
- Opt-in features must render byte-identically when off. #871, #913 and #970 each verified this by diffing `helm template` output against `main`.
- `thoras-console` values are a semver contract from 1.0.0: a major may rename or remove, a minor only adds, a patch only fixes. #925 settled the names before that point, unguarded because the chart was unpublished.
- `thoras` breaking changes need a major bump and an `UPGRADE.md` entry; UPGRADE.md supports moving one major version at a time. A renamed value can stay as an alias, with conflicting settings failing the render (`enableSimpleAuthSecret` to `apiClientSecret.enabled`).
- Conditional requirements use `fail` in templates; there is no `values.schema.json`.

## Options considered
Making a half-set `clusterKeySecretRef` fail the render was declined as a behaviour change; `NOTES.txt` warns instead (#917). Other options weren't recorded.

## Consequences
- New keys cost a nil guard and a test, even when `values.yaml` defines a default.
- A feature with a default of on can stay off for `--reuse-values` users until they reset. #967 shows this for the autoscaler event collector.
- Removing a value from either chart is a major change.

## Provenance
Stated: the cited PRs, AGENTS.md, UPGRADE.md and the comment at the top of the smoke test.
Inferred: grouping these rules as one compatibility surface, and reading the byte-identical checks as a rule. No single source sets them out together.
