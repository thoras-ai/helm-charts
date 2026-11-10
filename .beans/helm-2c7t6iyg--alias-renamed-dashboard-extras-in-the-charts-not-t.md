---
# helm-2c7t6iyg
title: "Alias renamed dashboard extras in the charts, not the dashboard"
status: accepted
type: decision
tags:
    - chart
    - thoras-console
    - dashboard
    - values
    - compatibility
created_at: 2026-11-09T22:53:57Z
updated_at: 2026-11-09T22:53:57Z
decided_at: 2026-11-09
refs:
    - "doc:AGENTS.md"
    - "code:charts/thoras/templates/_helpers.tpl"
    - "code:charts/thoras-console/templates/_helpers.tpl"
---

## Context
The `cluster_daily_cost` dashboard extra turns on the whole Billed cost tab, so it was renamed to `billed_cost` (Linear THO-83). Customers already set the old key in both charts' values, and the guides told them to. The old key has to keep working, with no removal date.

## Decision
- The charts own the alias. `thoras.aliasBilledCostExtra` and `thoras-console.aliasBilledCostExtra` copy whichever key is set to the other, so `config.json` always carries both. Values that conflict fail the render, and `NOTES.txt` names the deprecated key. This follows the `enableSimpleAuthSecret` precedent recorded in helm-fvswe1cx.
- The dashboard reads only the new key.
- Both keys are written because the dashboard image can lag or lead the chart: `consoleDashboard.imageTag` and image overrides pin older bundles, which read only the old key. Writing both means the chart and the dashboard change can ship in either order.
- The extras map is deep-copied before it is changed, so values stay the same between the renders that include the payload (the ConfigMap and its checksum annotation).

## Options considered
- **Alias in the dashboard** (read the new key, fall back to the old): it covers hand-written `config.json` files too, but it keeps the deprecated name in app code with no end date, and it needs the image and the docs to change in lockstep. Rejected because customers set extras only through these charts.
- **Map only old to new:** an older image pinned under a new chart would lose the tab when values use the new key. Rejected for writing both.

## Consequences
- Each chart has its own copy of the alias helper, because the charts share no templates (helm-cr00mg71).
- `config.json` carries a deprecated key for as long as the alias stays. Older dashboards ignore keys they don't know, and newer ones ignore the old key.
- A later rename of another extra can reuse the same pattern.
