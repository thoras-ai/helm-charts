---
# helm-zl83osgp
title: "Bundled TimescaleDB in thoras favours restarting over retaining recent data"
status: accepted
type: design
tags:
    - backfill
    - chart
    - timescaledb
    - data-loss
    - bundled-database
    - upgrade
created_at: 2026-11-07T02:18:27Z
updated_at: 2026-11-07T02:56:40Z
decided_at: 2026-07-29
refs:
    - "pr:thoras-ai/helm-charts#377"
    - "pr:thoras-ai/helm-charts#430"
    - "pr:thoras-ai/helm-charts#560"
    - "pr:thoras-ai/helm-charts#561"
    - "pr:thoras-ai/helm-charts#593"
    - "pr:thoras-ai/helm-charts#609"
    - "pr:thoras-ai/helm-charts#688"
    - "pr:thoras-ai/helm-charts#726"
    - "pr:thoras-ai/helm-charts#747"
    - "pr:thoras-ai/helm-charts#824"
    - "pr:thoras-ai/helm-charts#830"
    - "pr:thoras-ai/helm-charts#831"
    - "code:charts/thoras/templates/collector/deployment.yaml"
    - "code:charts/thoras/values.yaml"
---

## Context
The metrics collector runs TimescaleDB and blob-service in one pod. OOM-induced WAL corruption needed manual debug-pod recovery (#609). Installs could also silently run without persistence when `persistence.enabled` was forgotten next to PV settings (#824).

## Decision
- The pod is a single Deployment with the `Recreate` strategy.
- `persistence.enabled` is tri-state: explicit values win, and unset means on if a PV setting is present (#824). Otherwise the database lives on an `emptyDir` set up like a PV (#560, #561).
- `preStop` runs `pg_ctl stop -m fast` to reduce corruption on restart (#593).
- An init container always runs the WAL check at startup, and forced reset defaults to on. `walRecovery.enabled` only decides whether a failure may force `pg_resetwal -f`, which discards WAL after the last valid checkpoint (#830).
- The reset fires only when the startup log matches known corruption signatures; other failures stay as they are for investigation (#831).
- The startup window defaults to 300s, because a healthy database replaying a lot of WAL could otherwise trip a false reset (#831).
- `imageTag` and `extensionVersion` move together, using the official `timescaledb` image rather than `-ha` (#377). `ALTER EXTENSION` began in init containers (#430). The version now goes to the Go services through `SERVICE_TIMESCALE_EXTENSION_VERSION` (#688), and those containers were removed (#726, #747).

## Options considered
`walRecovery` shipped off by default (#609); #830's diff turned it on, which its description doesn't mention. A 60 or 120 second window was suggested before 300s was picked in #831; 300s had been the original value.

## Consequences
- Default installs lose metrics when the pod moves, and collector rollouts mean database downtime.
- Recovery trades recent data for availability, and setting `walRecovery.enabled: false` means manual recovery.
- A TimescaleDB bump has to update both values. The README says they should match; no template check enforces it.
- The tags are `-pg16`. No Postgres major upgrade path is recorded.
- The bundled database has no FIPS build (#970).

## Provenance
Stated: the cited PRs. Platform `go/cmd/database.go` holds the `ALTER EXTENSION` statement.
Inferred: that #726 and #747 removed the `ALTER EXTENSION` init step along with the rest, the title's framing, the data-loss consequence for default installs, and the "no enforcement" and "no major upgrade path" points, from reading the code and history. No source explains why reset is on by default. The values comment on `walRecovery` says any start failure assumes corruption, while the script checks signatures; the script is what runs.
