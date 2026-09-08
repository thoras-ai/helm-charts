# Thoras Console

The Thoras console is the control plane that tenant clusters report into. This
Helm chart installs a self-hosted console onto Kubernetes, as an alternative to
the hosted console at `console.thoras.ai`.

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square)

To install the Thoras platform onto a cluster you want to *observe*, you want the
[thoras](../thoras/README.md) chart instead. The two are separate installs and
can share a namespace.

## Status

This chart currently renders the image-pull Secret and validates configuration.
It schedules no workloads: installing it creates no console pods. The console-api
Deployment, the dashboard, and the optional bundled database arrive in later
releases, and the value surface below will grow with them.

Values marked "not read yet" are declared so that configuration written against
this chart keeps working as those releases land.

## Requirements

* Thoras license key (email support@thoras.ai if you don't have one)
* Recommended Kubernetes Minimum: 1.24+
* Postgres with the `timescaledb` and `citext` extensions available. Stock
  Postgres will not work -- the console migrations create hypertables and
  continuous aggregates.

## Installing the Chart

Add the Thoras Helm repo:

```
helm repo add thoras https://thoras-ai.github.io/helm-charts
helm repo update thoras
```

Install, passing your license key:

```
helm install thoras-console thoras/thoras-console \
  -n thoras-console --create-namespace \
  --set imageCredentials.password=$(cat thoras_license.txt)
```

## Configuration

### Global

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `consoleVersion` | string | `"latest"` | Image tag for the console components |
| `imageCredentials.registry` | string | `"us-east4-docker.pkg.dev/thoras-registry/platform"` | Registry the console images are pulled from |
| `imageCredentials.username` | string | `"_json_key_base64"` | Registry username |
| `imageCredentials.password` | string | `""` | License key. Mutually exclusive with `secretRef` |
| `imageCredentials.secretRef` | string | `""` | Name of a dockerconfigjson Secret already in the namespace |
| `imagePullPolicy` | string | `"IfNotPresent"` | |
| `logLevel` | string | `"info"` | Not read yet |
| `env` | list | `[]` | Extra environment variables for every console component |
| `proxy.httpProxy` | string | `""` | |
| `proxy.httpsProxy` | string | `""` | |
| `proxy.noProxy` | string | `""` | |
| `labels` | object | `{}` | Labels added to every rendered resource |
| `podAnnotations` | object | `{}` | Annotations added to every console pod |
| `nodeSelector` | object | `{}` | Not read yet |
| `tolerations` | list | `[]` | Not read yet |
| `affinity` | object | `{}` | Applied to components that set `useGlobalAffinity` |
| `topologySpreadConstraints` | list | `[]` | Default, overridden per component |

### Console API

All keys below are declared but not read yet.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `consoleApi.enabled` | bool | `true` | |
| `consoleApi.replicaCount` | int | `1` | |
| `consoleApi.image.repository` | string | `"console-api"` | Joined to `imageCredentials.registry` |
| `consoleApi.externalUrl` | string | `""` | URL the console is reachable on. Read by NOTES only |
| `consoleApi.resources` | object | `{}` | |
| `consoleApi.singleOrg.enabled` | bool | `true` | Auto-provision and implicitly use one organization |
| `consoleApi.singleOrg.name` | string | `"Default Organization"` | Renames the existing organization if changed after install |
| `consoleApi.auth.mode` | string | `"local"` | `local`, `oidc`, or `both` |
| `consoleApi.auth.oidc.issuer` | string | `""` | Required for `oidc`/`both`. Must match the `iss` claim exactly |
| `consoleApi.auth.oidc.audiences` | string | `""` | Required for `oidc`/`both`. Comma-separated |
| `consoleApi.auth.oidc.jwksUri` | string | `""` | Only when the issuer URL is unreachable from the cluster |
| `consoleApi.auth.adminPassword` | string | `""` | Shared admin password, minimum 12 characters |
| `consoleApi.auth.existingSecret.secretName` | string | `""` | Read the admin password from a Secret you manage instead. Takes precedence |
| `consoleApi.auth.existingSecret.passwordKey` | string | `"local-admin-password"` | Key within that Secret |
| `consoleApi.auth.adminSalt` | string | `""` | See below |
| `consoleApi.webhookSecret` | string | `""` | Shared secret for the identity-provider user-created webhook |
| `consoleApi.webhookExistingSecret.secretName` | string | `""` | Read the webhook secret from a Secret you manage instead |
| `consoleApi.webhookExistingSecret.secretKey` | string | `"webhook-secret"` | Key within that Secret |
| `consoleApi.useGlobalAffinity` | bool | `false` | |
| `consoleApi.affinity` | object | `{}` | |
| `consoleApi.priorityClassName` | string | `""` | |
| `consoleApi.topologySpreadConstraints` | list | `[]` | |
| `consoleApi.extraEgressRules` | list | `[]` | |
| `consoleApi.extraIngressRules` | list | `[]` | |

### Database

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `externalDatabase.dsn` | string | `""` | Full DSN, pinned in values. Not read yet |
| `externalDatabase.migrateOnStart` | bool | `true` | Run migrations on startup. Disable only if you apply them yourself |
| `externalDatabase.existingSecret.secretName` | string | `""` | Read the DSN from a Secret you manage instead. Takes precedence |
| `externalDatabase.existingSecret.dsnKey` | string | `"postgresql-dsn"` | Key within that Secret |

### Slack

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `slack.errorsEnabled` | bool | `false` | Not read yet |
| `slack.webhookUrl` | string | `""` | Incoming webhook URL. Secret material. Not read yet |
| `slack.existingSecret.secretName` | string | `""` | Read the webhook URL from a Secret you manage instead |
| `slack.existingSecret.webhookUrlKey` | string | `"slack-webhook-url"` | Key within that Secret |

## Bring your own Secrets

Every secret-bearing value can be pinned in values or read from a Secret you
manage. Each pair follows the same shape -- `secretName` picks the Secret,
and the companion `*Key` picks the entry within it:

| Value | Pin it | Or reference it |
|---|---|---|
| Admin password | `consoleApi.auth.adminPassword` | `consoleApi.auth.existingSecret` |
| Webhook secret | `consoleApi.webhookSecret` | `consoleApi.webhookExistingSecret` |
| Database DSN | `externalDatabase.dsn` | `externalDatabase.existingSecret` |
| Slack webhook URL | `slack.webhookUrl` | `slack.existingSecret` |

Referencing wins over pinning wherever both are set.

Prefer referencing. A pinned value lives in your values file, in whatever
repository holds it, and in Helm's release history -- `helm get values` returns
it to anyone who can read the release. Referencing is also how you feed the
console from External Secrets Operator, Vault or Sealed Secrets: those create
the Secret, and the chart only points at it.

```bash
kubectl create secret generic console-admin -n thoras-console \
  --from-literal=local-admin-password='...'

helm upgrade thoras-console thoras/thoras-console -n thoras-console \
  --set consoleApi.auth.existingSecret.secretName=console-admin
```

`consoleApi.auth.adminSalt` is the exception: it is not secret material, so it
takes no Secret reference. See below.

## Authentication

`consoleApi.auth.mode` selects how operators sign in:

* `local` -- a single shared admin password, no external identity provider.
  Intended for self-hosted installs.
* `oidc` -- an identity provider you already run. Requires
  `consoleApi.auth.oidc.issuer` and `.audiences`. The defaults compiled into
  console-api point at Thoras' hosted console, so leaving these empty means
  your users' tokens are validated against the wrong tenant and rejected.
* `both` -- accept either.

In `local` mode the console does not put a proxy in front of itself. Operators
authenticate against the console API, which mints a short-lived session token;
the password itself is never a bearer token.

### The admin salt

`consoleApi.auth.adminSalt` makes the session signing key unique to your install.

It is **not a secret** -- it only has to be unique and stable, so it travels as
plain configuration rather than a Secret. Two rules:

* Minimum 16 characters. Leaving it empty falls back to a value shared by every
  install that does the same, and warns at startup.
* **Never change it once set.** The signing key derives from it, so changing it
  signs every operator out. The same is true of the admin password: rotating it
  is the only way to revoke outstanding sessions, and there is no per-session
  revocation.
