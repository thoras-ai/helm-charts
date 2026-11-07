---
# helm-rgu071yo
title: "Issue webhook certs from a long-lived CA, with certgen as the default path"
status: accepted
type: decision
tags:
    - backfill
    - chart
    - webhooks
    - tls
    - cert-manager
created_at: 2026-11-07T02:18:27Z
updated_at: 2026-11-07T02:18:27Z
decided_at: 2026-08-20
refs:
    - "pr:thoras-ai/helm-charts#510"
    - "pr:thoras-ai/helm-charts#741"
    - "pr:thoras-ai/helm-charts#842"
    - "pr:thoras-ai/helm-charts#871"
    - "github:thoras-ai/platform#4976"
    - "code:charts/thoras/templates/operator/webhooks-certmanager.yaml"
    - "code:charts/thoras/templates/operator/deployment.yaml"
---

## Context
The chart first generated certs in templates with `genCA` and `genSignedCert`, which caused regeneration problems on upgrade, so #510 moved to `kube-webhook-certgen` Jobs. #741 added cert-manager for customers with existing PKI. That first cert-manager path issued the leaf from a `selfSigned` Issuer, so each renewal minted a new trust root, and cainjector swapped `caBundle` with no overlap. Any replica still on the old cert failed TLS handshakes (#871).

## Decision
- `kube-webhook-certgen` remains the default. cert-manager is opt-in through `webhookCertGen.certManager.enabled`.
- With cert-manager, the chain is selfSigned Issuer, then CA Certificate, then CA Issuer, then leaf. `caBundle` carries the CA, so it stays byte-identical across leaf renewals.
- The CA pins `privateKey.rotationPolicy: Never`. cert-manager 1.18+ defaults to `Always`, which would re-key at renewal and bring the zero-overlap swap back.
- CA duration defaults to `87600h`, and is quoted so a numeric override fails in cert-manager rather than failing the release apply.
- Certs mount as a whole directory, not with `subPath`. Kubelet never updates `subPath` mounts, so controller-runtime's certwatcher would not see a rotation (#842).

## Options considered
Template-generated certs: replaced in #510. cert-manager as the default: not adopted; #913 records that the chart can't assume it is installed.

## Consequences
- `certManager.enabled` is the chart's only signal that cert-manager exists, so bundled database TLS and FIPS mode key off it too.
- Moving an install off the old leaf chain brings a brief fail-open window (#871).
- A deliberate CA key rotation is manual: delete the `thoras-webhooks-ca` Secret and Certificate.
- Argo CD users ignore `caBundle`, since it is injected after apply (chart README).

## Provenance
Stated: #510, #741, #842, #871, #913. The current templates match.
Inferred: nothing beyond linking the PRs in sequence.
