---
# helm-pj23nygk
title: "Keep bundled TimescaleDB TLS opt-in rather than defaulting it on"
status: accepted
type: decision
tags:
    - backfill
    - chart
    - timescaledb
    - tls
    - bundled-database
    - upgrade
created_at: 2026-11-07T02:18:27Z
updated_at: 2026-11-07T02:56:40Z
decided_at: 2026-09-16
refs:
    - "pr:thoras-ai/helm-charts#913"
    - "github:thoras-ai/platform#5037"
    - "code:charts/thoras/templates/collector/certificate.yaml"
    - "code:charts/thoras/values.yaml"
---

## Context
The bundled database had no TLS configuration and DSNs carried no `sslmode`, so database connections on the pod network were unencrypted. The issue asked for TLS by default.

## Decision
TLS is opt-in through `metricsCollector.timescale.tls.enabled`, and requires `thorasOperator.webhookCertGen.certManager.enabled`; the render fails otherwise. Defaults render byte-identically to before.

- The chain is a self-signed Issuer, a separate `thoras-timescale-ca`, a CA Issuer, and a server cert. The CA pins `rotationPolicy: Never`.
- Consumers mount `ca.crt` from the server Secret, not the CA Secret, so the CA private key isn't referenced from their pods.
- `sslmode` is added to the DSN in the pod spec, so migrated DSNs work unchanged.
- A sidecar reloads Postgres when the mounted Secret changes, so a renewal needs no pod restart.
- Existing installs roll in two steps: `sslmode=prefer`, then `verify-full`.

## Options considered
Default-on with `verify-full`: rejected for two reasons. The database (`Recreate`) and consumers roll in one release, so existing installs would lose connections until the database returned with `ssl=on`. And cert-manager is opt-in, so a default would break installs without it. A later release may flip the default once cert-manager is a stated requirement.

## Consequences
- By default, in-cluster database traffic isn't encrypted. #913 asks for this to be recorded in the platform security-review inventory as an opt-in control.
- The `prefer` step depends on dbmate's lib/pq handling `prefer` correctly; #913 cites platform's pin at v1.12.3, since older lib/pq treated it as `require`.
- #913 left blob-service and forecast-worker untouched, saying neither connects to Postgres. The blob-service container does run a `psql` bootstrap over localhost with the bundled database, and it gets the DSN under `externalTimescale`.
- External databases are out of scope here; FIPS mode sets its own `sslmode` rule for them (#970).

## Provenance
Stated: #913. `tls.enabled` still defaults to false in `values.yaml`.
Inferred: nothing material.
