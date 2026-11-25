---
# helm-i4kuuk43
title: Mount the OIDC CA bundle from an existing Secret or ConfigMap at a fixed path
status: accepted
type: decision
tags:
    - chart
    - auth
    - oidc
    - console-api
decided_at: 2026-11-25
refs:
    - linear:THO-320
    - linear:THO-245
    - bean:plat-8h0cthgq
    - code:charts/thoras-console/templates/console-api/deployment.yaml
created_at: 2026-11-25T15:14:24Z
updated_at: 2026-11-25T15:14:24Z
---

## Context
console-api fetches OIDC discovery and JWKS only over HTTPS with a verified certificate, and takes a PEM CA bundle through `SERVICE_JWT_CA_FILE` (platform bean `plat-8h0cthgq`). A provider reached through an in-cluster Service usually has a certificate from a private CA. The thoras-console chart had no way to mount that bundle.

## Decision
- `auth.oidc.caBundle` reads the bundle from an existing Secret (`existingSecret.secretName`, `key`) or an existing ConfigMap (`existingConfigMap.configMapName`, `key`). Setting both fails at render.
- The chart mounts the chosen key read-only at the fixed path `/etc/thoras/oidc-ca/ca.crt` and sets `SERVICE_JWT_CA_FILE` to it.
- The mount and the variable render only when `auth.mode` is `oidc` or `both`, like the other `auth.oidc` values.
- The chart creates no Secret or ConfigMap for the bundle. It must already exist in the release namespace.

## Options considered
- Secret only: rejected. trust-manager and many installs publish CA bundles as ConfigMaps, and a CA certificate is not secret.
- ConfigMap only: rejected. cert-manager writes `ca.crt` into the issued certificate's Secret.
- A generic `extraVolumes` and `extraVolumeMounts` pair: not chosen. Users would also have to set `SERVICE_JWT_CA_FILE` to match the path, and nothing would validate the pairing.
- An inline PEM value that the chart renders into its own ConfigMap: not chosen. It duplicates a CA that already lives in the cluster and goes stale when that CA rotates.
- Fail at render when `auth.oidc.issuer` or `auth.oidc.jwksUri` is `http://`: rejected. `consoleVersion` can pin an older console-api that still accepts HTTP, and console-api already exits at startup with an error naming the setting.

## Consequences
- Rotating the CA needs a console-api restart, because console-api reads the file at startup.
- The chart has no dedicated value for console-api's `--jwt-allow-insecure-http`; only the generic `env` value can set it.
- `SERVICE_JWT_CA_FILE` and HTTPS-only discovery take effect only with a console-api that includes platform THO-245. Ship this with the chart release that bumps `consoleVersion` to it; older images ignore the variable.
- A plain `--reuse-values` upgrade that sets a source without its key fails validation, because the `ca.crt` default is not merged. `--reset-then-reuse-values` merges it.

## Provenance
Stated: THO-320, THO-245, platform `go/cmd/console-api/main.go` (`JWTCAFile`), platform `docs/console-api-local-development.md`.
Inferred: trust-manager and many installs publish CA bundles as ConfigMaps.
