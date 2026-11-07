---
# helm-1en0jr5p
title: "FIPS mode refuses configurations that would bring in non-approved crypto"
status: accepted
type: decision
tags:
    - backfill
    - chart
    - fips
    - images
    - security
    - compatibility
created_at: 2026-11-07T02:18:27Z
updated_at: 2026-11-07T07:30:31Z
decided_at: 2026-11-04
refs:
    - "pr:thoras-ai/helm-charts#970"
    - "github:thoras-ai/platform#5458"
    - "github:thoras-ai/platform#5460"
    - "code:charts/thoras/templates/_helpers.tpl"
    - "code:charts/thoras/templates/thoras-helm-values-secret.yaml"
---

## Context
`fips.enabled` runs FIPS variants of the Thoras images. Some chart defaults have no approved equivalent: bcrypt in `htpasswd` auth, the bundled TimescaleDB image, `kube-webhook-certgen`, and `alpine` and `curl` helpers.

## Decision
FIPS mode is off by default and fails the render rather than falling back. It requires OIDC when dashboard auth is on, `externalTimescale`, and cert-manager for webhook certs. The DSN can be inline or come from `externalTimescale.secretRefName` and `secretRefKey`. The chart checks for `sslmode=verify-full` exactly once only on an inline DSN that is in use. `secretRefName` takes precedence over an inline DSN.

- All Thoras image tags go through `thoras.imageTag`, which adds `-fips` unless already present.
- A digest in FIPS mode fails the render, since it can't take the suffix and may point at a non-FIPS image.
- oauth2-proxy has its own `fipsImageTag`, with a fallback for `--reuse-values`.
- `GODEBUG=fips140=on` renders before the global `env`, so a user value still wins.
- The collector pod reduces to blob-service, started directly rather than through `sh -c`.
- The pause-state hook runs `/app/operator migrate-pause-state`, because the FIPS image doesn't ship `curl`.
- The forecast image sets its own `OPENSSL_CONF`, and the chart must not override it.

## Options considered
`httpGet` probes in place of `curl` probes: not usable, because nginx listens on loopback only behind oauth2-proxy and the readiness probes call `thoras-api-server-v2`, which kubelet can't resolve. Other options weren't recorded.

## Consequences
- With FIPS off, output is byte-identical to before (#970 compared 14 value sets). Keeping that is part of the compatibility promise.
- A DSN from a Secret can't be checked at render time; the README documents the requirement.
- An older `thorasVersion` without `-fips` images fails at the pre-install hook.
- New image references and Go containers must use the helper and FIPS env, or they silently pull non-FIPS images.
- Open in #970: `verify-full` against a private CA needs `sslrootcert`, and the chart can't mount one for `externalTimescale`.
- #970 didn't test FIPS-mode nodes, the pre-delete hook, or network policies on a live cluster. No chart release included this when the bean was written.

## Provenance
Stated: #970, checked against `_helpers.tpl` and the guards in `thoras-helm-values-secret.yaml`. Who asked for FIPS isn't recorded.
Inferred: the "silently pull non-FIPS" consequence, from how tags resolve, and calling byte-identical output a compatibility promise; #970 reports the comparison, not a promise.
