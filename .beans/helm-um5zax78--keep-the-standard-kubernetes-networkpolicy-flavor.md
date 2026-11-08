---
# helm-um5zax78
title: "Keep the standard Kubernetes NetworkPolicy flavor after trying Cilium-only"
status: accepted
type: decision
tags:
    - backfill
    - chart
    - network-policy
    - reversal
    - compatibility
    - security
created_at: 2026-11-07T02:18:27Z
updated_at: 2026-11-07T02:18:27Z
decided_at: 2026-08-28
refs:
    - "pr:thoras-ai/helm-charts#646"
    - "pr:thoras-ai/helm-charts#850"
    - "pr:thoras-ai/helm-charts#852"
    - "pr:thoras-ai/helm-charts#865"
    - "pr:thoras-ai/helm-charts#889"
    - "pr:thoras-ai/helm-charts#921"
    - "github:thoras-ai/platform#5081"
    - "code:charts/thoras/templates/_helpers.tpl"
    - "code:charts/thoras/values.yaml"
---

## Context
#646 added NetworkPolicies, off by default, in `kubernetes` and `cilium` flavors. The `kubernetes` flavor can't select the API server by label, so egress falls back to any destination on `apiServerPorts`. #865 removed that flavor as weak isolation, and for breaking on non-standard API ports, leaving Cilium as the only option.

## Decision
#889 reverted #865 eleven days later. Both flavors exist, and `kubernetes` is the default flavor. `networkPolicy.enabled` remains false by default.

- `apiServerPorts` is configurable, defaulting to 443 and 6443 (#852). An empty list drops the rule, because a rule with no ports would allow egress on every port.
- Unknown flavors fail the render. Before #921, `Cilium` or `calico` rendered no policy with a passing lint and dry run, silently dropping a control the operator asked for.
- Every policy template reads the flavor through a validating accessor, `thoras.networkPolicyFlavor`, so a new template can't reintroduce the gap (#921). Validation sits inside the `enabled` gate, so a stale flavor doesn't block an unrelated install.
- `extraIngressRules` lets monitoring stacks in without turning policies off (#850).

## Options considered
Cilium-only (#865): reversed. #889 says its premise was wrong, because the flavor never relied on pinned control-plane CIDRs. It says the flavor was enforced in production at a customer when deleted, and that Cilium-only leaves every non-Cilium cluster with no policy support.

## Consequences
- The `kubernetes` flavor keeps broader API server egress and an open webhook port, a tradeoff documented inline. Tightening it can't rely on Cilium features.
- Charts released between #865 and #889 had no `kubernetes` flavor. #865 called itself breaking but shipped in a minor; a future removal would need a major version under the values rule.
- New components need a policy in both flavors (#961 followed this).
- `apiServerPorts` is ignored by Cilium, which uses `toEntities: [kube-apiserver]`.

## Provenance
Stated: #646, #850, #852, #865, #889, #921. Current defaults checked in `values.yaml`.
Inferred: the "would need a major version" and "new components" points, from the compatibility rule and the existing templates.
