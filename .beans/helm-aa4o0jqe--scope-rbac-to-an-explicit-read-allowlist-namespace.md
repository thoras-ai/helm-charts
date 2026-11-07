---
# helm-aa4o0jqe
title: "Scope RBAC to an explicit read allowlist; namespaced mode keeps some cluster-wide grants"
status: accepted
type: decision
tags:
    - backfill
    - chart
    - rbac
    - namespaced-mode
    - security
created_at: 2026-11-07T02:18:27Z
updated_at: 2026-11-07T07:30:31Z
decided_at: 2026-10-29
refs:
    - "pr:thoras-ai/helm-charts#309"
    - "pr:thoras-ai/helm-charts#364"
    - "pr:thoras-ai/helm-charts#382"
    - "pr:thoras-ai/helm-charts#752"
    - "pr:thoras-ai/helm-charts#836"
    - "pr:thoras-ai/helm-charts#896"
    - "pr:thoras-ai/helm-charts#964"
    - "pr:thoras-ai/helm-charts#967"
    - "pr:thoras-ai/helm-charts#970"
    - "github:thoras-ai/platform#5026"
    - "code:charts/thoras/templates/operator/rbac.yaml"
    - "code:charts/thoras/templates/_helpers.tpl"
    - "code:charts/thoras/templates/config-controller/rbac.yaml"
    - "code:charts/thoras/templates/api-server-v2/rbac.yaml"
    - "code:charts/thoras/templates/worker/rbac.yaml"
---

## Context
`rbac.namespaces` came from a customer request (#309): render a Role per namespace instead of ClusterRoles. Separately, `thoras-api`, `thoras-operator` and `thoras-worker` once had wildcard read on every resource, which included every Secret, though nothing reads Secrets. #896 fixed this after a security finding.

## Decision
- Read access comes from `thoras.workloadReadRules`, listing what Thoras discovers and sizes. Secrets and ConfigMaps are excluded. A test rejects any rule combining wildcard `apiGroups` and `resources`.
- Exceptions get their own grants: the worker reads one named ConfigMap, the api-server keeps `pods/log`, and a release-namespace Role lets the api-server read and write ConfigMaps, not limited by name, for the pause state (#964).
- `rbac.namespaces` scopes workload reads and sets `SERVICE_WATCH_NAMESPACES`. Grants that a Role can't express stay ClusterRoles in both modes: `*-cluster-scoped` covers Nodes, PVs, StorageClasses and Karpenter NodePools and NodeClaims (#836, #967).
- The worker reads Events cluster-wide while the collector flag is on, since Node and NodeClaim events are recorded in `default` (#967).
- `thoras.ai` access for the operator, worker and api-server stays a ClusterRole and ClusterRoleBinding in both modes. The worker and api-server get all resources and verbs. The operator gets all verbs on a listed set of resources.
- config-controller is the opposite case: a namespaced Role only, ignoring `rbac.namespaces`, with its informer pinned to the release namespace.

## Options considered
Not recorded for namespaced mode. #896 keeps the operator's `*/scale` and `*/status` rule on purpose: it can't expose Secrets, and it is needed to scale arbitrary `scaleTargetRef` kinds.

## Consequences
- Namespaced mode doesn't mean no cluster-level access. A resource that is cluster-scoped has to go in `clusterScopedReadRbac`, or it loses access in this mode.
- A new resource the code reads needs an allowlist entry, or it gets a forbidden error.
- #970 observed that narrowing the `thoras.ai` bindings further breaks the post-upgrade hook and the ClusterAIScaleTemplate watch.
- Reading a CRD that isn't installed is treated as harmless, so Karpenter rules aren't gated (#967).

## Provenance
Stated: the cited PRs and template comments, checked against the current RBAC templates.
Inferred: the Role and ClusterRole split as a single rule, and the first two consequences. The sources describe it case by case.
