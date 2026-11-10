---
# helm-mt1qdfni
title: "Thoras failures must not block customer workloads or Helm operations"
status: accepted
type: decision
tags:
    - backfill
    - chart
    - safety
    - webhooks
    - hooks
    - availability
created_at: 2026-11-07T02:18:27Z
updated_at: 2026-11-07T02:56:40Z
decided_at: 2026-10-23
refs:
    - "pr:thoras-ai/helm-charts#350"
    - "pr:thoras-ai/helm-charts#407"
    - "pr:thoras-ai/helm-charts#508"
    - "pr:thoras-ai/helm-charts#585"
    - "pr:thoras-ai/helm-charts#604"
    - "pr:thoras-ai/helm-charts#691"
    - "pr:thoras-ai/helm-charts#773"
    - "pr:thoras-ai/helm-charts#873"
    - "pr:thoras-ai/helm-charts#878"
    - "pr:thoras-ai/helm-charts#949"
    - "pr:thoras-ai/helm-charts#958"
    - "code:charts/thoras/templates/operator/webhooks.yaml"
    - "code:charts/thoras/templates/operator/pre-delete-hook.yaml"
    - "code:charts/thoras/templates/operator/post-upgrade-hook.yaml"
---

## Context
Thoras runs in customer clusters and can sit in the admission path of every Pod. Specific failures shaped these defaults: a do-not-disrupt annotation held nodes in drift (#407), a required anti-affinity blocked single-node clusters (#691), certgen Jobs stayed Pending on tainted pools (#873), and a large AST count hung the pre-delete hook (#958).

## Decision
- All webhook configurations use `failurePolicy: Ignore` with a 3 second timeout, and skip `kube-system` and `kube-node-lease` by default (#508). The selector can be overridden for admission enforcers that own the field (#585).
- The operator runs 2 replicas by default, because it serves the mutating webhook (#604), with soft anti-affinity (#691).
- PDBs default to `maxUnavailable: 1`, so a single replica doesn't block voluntary node drains (#773).
- Post-upgrade, pre-delete and pause-state hook Jobs are bounded with `backoffLimit` and `activeDeadlineSeconds`; the certgen Jobs set neither. All hook Jobs use `before-hook-creation` so a failed Job doesn't collide with a retry (#878, #958).
- Hook Jobs carry global `nodeSelector` and `tolerations` (#873), and resource settings (#949).
- `/app/operator post-upgrade` is one generic runner, so a new cleanup registers a step instead of adding a hook. `postUpgradeHook.enabled` is the escape hatch when a step fails (#878).

## Options considered
`minAvailable: 1` for PDBs was the earlier default; it blocked drains on single-replica installs (#604, #773). #878 prefers one runner to adding a hook per cleanup. The webhook choice dates to 2024 with no recorded alternatives.

## Consequences
- During an operator outage, Pods are admitted unmutated and AST validation doesn't run. That is the accepted cost.
- A bounded hook failing at its deadline fails the Helm operation rather than hanging it, so steps have to be idempotent.
- Uninstall deletes ASTs through the pre-delete hook (#350). The template comment records that the operator strips finalizers after a 5 minute grace period.

## Provenance
Stated: the cited PRs. Platform `docs/admission-webhooks.md` states the Pod webhook fails open so an unavailable operator never blocks scheduling.
Inferred: treating these as one principle. The sources address each case on its own, and the name is ours. The cost in the first consequence is worked out from the settings.
