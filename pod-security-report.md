# Pod Security Standards Compliance Report

## Baseline Profile (things that would FAIL today)

Only **one** issue:

- [ ] **Agent DaemonSet: `privileged: true` + `hostNetwork: true`** — Violates Baseline. Intentional for eBPF, so it needs a namespace-level exemption or must run in a separate namespace with a Privileged policy. No template changes needed, but document the exemption.

Everything else already passes Baseline.

---

## Restricted Profile Checklist (beyond running as non-root)

These gaps apply to **all workloads except the webhook certgen jobs** (which are already fully compliant).

### 1. `allowPrivilegeEscalation` must be `false`

| Component | Containers needing fix |
| --- | --- |
| operator | `wait-for-api-service` (init), `thoras-operator` |
| api-server-v2 | `wait-for-postgres` (init), `thoras-api-server-v2` |
| collector | `fix-dir-ownership` (init), `timescaledb`, `thoras-blob-api` |
| dashboard | `wait-for-api-service` (init), `thoras-dashboard`, `thoras-api-proxy` |
| forecast-worker | `wait-for-api-service` (init), `thoras-forecast-worker` |
| worker | `wait-for-postgres` (init), `thoras-worker` |
| monitor | `wait-for-api-service` (init), `thoras-monitor` |
| slm-api | `thoras-slm-api` |
| pre-delete-hook | `thoras-delete-asts` |

### 2. `capabilities.drop: [ALL]` required

| Component | Containers needing fix |
| --- | --- |
| operator | `wait-for-api-service` (init), `thoras-operator` |
| api-server-v2 | `wait-for-postgres` (init), `thoras-api-server-v2` |
| collector | `fix-dir-ownership` (init), `timescaledb`, `thoras-blob-api` |
| dashboard | `wait-for-api-service` (init), `thoras-dashboard`, `thoras-api-proxy` |
| forecast-worker | `wait-for-api-service` (init), `thoras-forecast-worker` |
| worker | `wait-for-postgres` (init), `thoras-worker` |
| monitor | `wait-for-api-service` (init), `thoras-monitor` |
| slm-api | `thoras-slm-api` |
| pre-delete-hook | `thoras-delete-asts` |

### 3. `seccompProfile.type: RuntimeDefault` required

Can be set at pod-level to cover all containers. Currently missing on every pod except certgen jobs.

| Component | Needs seccompProfile |
| --- | --- |
| operator deployment | Yes |
| api-server-v2 deployment | Yes |
| collector deployment | Yes |
| dashboard deployment | Yes |
| forecast-worker deployment | Yes |
| worker deployment | Yes |
| monitor deployment | Yes |
| slm-api deployment | Yes |
| pre-delete-hook job | Yes |

### 4. `runAsNonRoot: true` required

Every pod except certgen jobs is missing it. Can be set at pod-level.

---

## Concise Fix Checklist

| # | Fix | Scope | Notes |
| --- | --- | --- | --- |
| 1 | Add pod-level `securityContext` with `runAsNonRoot: true` and `seccompProfile.type: RuntimeDefault` | Every deployment and job | Covers items 3 and 4 for all containers at once |
| 2 | Add container-level `allowPrivilegeEscalation: false` and `capabilities.drop: [ALL]` | Every container and initContainer | Must be per-container (can't be set at pod-level) |
| 3 | Collector `fix-dir-ownership` init: add back `capabilities.add: [CHOWN, DAC_OVERRIDE, FOWNER]` | collector init only | Allowed under Baseline but NOT under strict Restricted — may need exemption or redesign |
| 4 | Collector `timescaledb` + `thoras-blob-api`: add `allowPrivilegeEscalation: false` and `capabilities.drop: [ALL]` alongside existing `runAsUser`/`runAsGroup` | collector containers | Already has partial securityContext |
| 5 | Consider `readOnlyRootFilesystem: true` | All containers | Not required by Restricted, but recommended. May need `emptyDir` mounts for `/tmp` |
| 6 | Document Agent DaemonSet exemption | agent namespace | Requires `PodSecurity: privileged` or policy exception |

---

## What's Already Compliant

| Control | Status |
| --- | --- |
| Host namespaces (hostPID, hostIPC) | Not used anywhere |
| HostPath volumes | Not used anywhere |
| Host ports | Not used |
| Volume types | Only `secret`, `configMap`, `persistentVolumeClaim` — all allowed |
| `/proc` mount type | Not overridden anywhere |
| Sysctls | None defined |
| SELinux overrides | None defined |
| AppArmor overrides | None defined |
