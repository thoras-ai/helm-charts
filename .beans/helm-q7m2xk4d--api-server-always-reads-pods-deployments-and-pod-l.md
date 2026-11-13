---
# helm-q7m2xk4d
title: "API server always reads pods, Deployments and pod logs in the release namespace"
status: accepted
type: decision
tags:
    - chart
    - rbac
    - namespaced-mode
    - component-health
created_at: 2026-11-13T17:30:00Z
updated_at: 2026-11-13T17:30:00Z
decided_at: 2026-11-13
refs:
    - "linear:THO-7"
    - "pr:thoras-ai/platform#5571"
    - "bean:helm-aa4o0jqe"
    - "code:charts/thoras/templates/api-server-v2/rbac.yaml"
---

## Context
The api-server reports the health of the Thoras components from the Deployments and pods in the release namespace (THO-7). The diagnostics export reads those pods' logs.
With `rbac.namespaces` set, workload reads are granted only in the listed namespaces (helm-aa4o0jqe). An install that does not list the release namespace gets a forbidden error on all three reads.

## Decision
- The api-server's release-namespace Role grants `get`, `list`, `watch` on `pods` and `apps/deployments`, and `get` on `pods/log`.
- The Role renders in both RBAC modes and does not depend on `rbac.namespaces`.

## Options considered
- Require namespaced installs to list the release namespace. Rejected: existing installs would report health as unknown until someone changes their values.
- Add the release namespace to `rbac.namespaces` implicitly. Rejected: it would also add the namespace to `SERVICE_WATCH_NAMESPACES` and grant the wider workload write rules there.

## Consequences
- In cluster-wide mode, and when the release namespace is listed, the grants duplicate ones the api-server already has.
- The reads cover every pod and Deployment in the release namespace, not only the Thoras ones.
- Without this chart version, the api-server reports component health as `unknown` on namespaced installs.

## Provenance
Stated: THO-7, platform#5571 and the current template.
Inferred: the second rejected option's effects, read from how `rbac.namespaces` is used in the templates.
