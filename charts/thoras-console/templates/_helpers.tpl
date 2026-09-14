{{/*
Helpers are prefixed even where the thoras chart leaves one unprefixed
(imagePullSecret): template names are global to a rendering, so an unprefixed
duplicate would collide if the two charts are ever composed.
*/}}
{{- define "thoras-console.imagePullSecret" }}
{{- printf "{\"auths\": {\"%s\": {\"auth\": \"%s\"}}}" .Values.imageCredentials.registry (printf "%s:%s" .Values.imageCredentials.username .Values.imageCredentials.password | b64enc) | b64enc }}
{{- end }}

{{/*
Component labels - merges global + component labels (no Helm labels)
Usage: include "thoras-console.componentLabels" (dict "root" . "component" .Values.consoleApi.labels)
*/}}
{{- define "thoras-console.componentLabels" -}}
app.kubernetes.io/name: {{ .root.Chart.Name }}
{{- $globalLabels := .root.Values.labels | default dict }}
{{- $componentLabels := .component | default dict }}
{{- $merged := mustMerge (deepCopy $componentLabels) $globalLabels }}
{{- if $merged -}}
{{- toYaml $merged | nindent 0 -}}
{{- end -}}
{{- end -}}

{{/*
Resource labels - includes Helm labels + component labels (for Deployment/Service/etc metadata)
Usage: include "thoras-console.resourceLabels" (dict "root" . "component" .Values.consoleApi.labels)
*/}}
{{- define "thoras-console.resourceLabels" -}}
helm.sh/chart: {{ .root.Chart.Name }}-{{ .root.Chart.Version | replace "+" "_" }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- $componentLabels := include "thoras-console.componentLabels" . | trim }}
{{- if $componentLabels }}
{{ $componentLabels }}
{{- end }}
{{- end -}}

{{/*
Pod annotations - merges global podAnnotations with component-specific podAnnotations.
Component annotations override global ones (same key = component wins).
Usage: include "thoras-console.podAnnotations" (dict "root" . "component" .Values.consoleApi.podAnnotations)
*/}}
{{- define "thoras-console.podAnnotations" -}}
{{- $merged := mergeOverwrite (deepCopy (.root.Values.podAnnotations | default dict)) (.component | default dict) }}
{{- if $merged }}
{{- toYaml $merged }}
{{- end }}
{{- end }}

{{/*
Proxy settings and .Values.env, for every component's env block.
Usage: {{- with (include "thoras-console.globalEnv" . | trim) }}{{- . | nindent 12 }}{{- end }}
*/}}
{{- define "thoras-console.globalEnv" -}}
{{- $out := list -}}
{{- with .Values.proxy.httpProxy -}}
{{- $out = append $out (dict "name" "HTTP_PROXY" "value" .) -}}
{{- $out = append $out (dict "name" "http_proxy" "value" .) -}}
{{- end -}}
{{- with .Values.proxy.httpsProxy -}}
{{- $out = append $out (dict "name" "HTTPS_PROXY" "value" .) -}}
{{- $out = append $out (dict "name" "https_proxy" "value" .) -}}
{{- end -}}
{{- with .Values.proxy.noProxy -}}
{{- $out = append $out (dict "name" "NO_PROXY" "value" .) -}}
{{- $out = append $out (dict "name" "no_proxy" "value" .) -}}
{{- end -}}
{{- range .Values.env -}}
{{- $out = append $out . -}}
{{- end -}}
{{- if $out -}}
{{ toYaml $out -}}
{{- end -}}
{{- end }}

{{/*
PodDisruptionBudget for a component. Renders nothing when pdb.enabled is falsey.
Spec precedence: minAvailable wins if set, else maxUnavailable, else defaults to
maxUnavailable: 1. Uses kindIs "invalid" so an explicit 0 is honored.
Usage: include "thoras-console.pdb" (dict "root" . "pdb" .Values.consoleApi.pdb
         "name" "thoras-console-api" "app" "thoras-console-api"
         "labels" .Values.consoleApi.labels)
*/}}
{{- define "thoras-console.pdb" -}}
{{- if .pdb.enabled -}}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .name }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "thoras-console.resourceLabels" (dict "root" .root "component" .labels) | nindent 4 }}
spec:
  {{- if not (kindIs "invalid" .pdb.minAvailable) }}
  minAvailable: {{ .pdb.minAvailable }}
  {{- else if not (kindIs "invalid" .pdb.maxUnavailable) }}
  maxUnavailable: {{ .pdb.maxUnavailable }}
  {{- else }}
  maxUnavailable: 1
  {{- end }}
  selector:
    matchLabels:
      app: {{ .app }}
{{- end -}}
{{- end -}}

{{/*
Topology spread for a component, falling back to the global value.
Usage: include "thoras-console.topologySpreadConstraints" (dict "root" . "component" .Values.consoleApi.topologySpreadConstraints)
*/}}
{{- define "thoras-console.topologySpreadConstraints" -}}
{{- $constraints := .component | default .root.Values.topologySpreadConstraints }}
{{- with $constraints -}}
topologySpreadConstraints:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Egress rule allowing config-controller to reach the Kubernetes API server, for
the "kubernetes" NetworkPolicy flavor.

Standard NetworkPolicy cannot target the API server by label, so this permits
egress to any destination on the configured ports. Policy is enforced after
kube-proxy DNATs the service address to the real endpoint, so the ports must
match what the API server actually listens on rather than the service port.
Use the cilium flavor for precise scoping.

Emits nothing when the port list is empty, leaving the rule out entirely
instead of rendering a rule that would allow egress on every port.
*/}}
{{- define "thoras-console.apiServerEgressRule" -}}
{{- with .Values.networkPolicy.apiServerPorts -}}
- ports:
  {{- range . }}
  - port: {{ . }}
    protocol: TCP
  {{- end }}
{{- end -}}
{{- end -}}

{{/*
True when the chart should deploy its own database.

bundledDatabase.enabled is deliberately absent from values.yaml so hasKey can
tell an unset value from an explicit one: configuring externalDatabase is enough
to switch over, while asking for both is ambiguous and rejected in
helm-values-secret.yaml. Returns "true" or "".
*/}}
{{- define "thoras-console.bundledDatabaseEnabled" -}}
{{- $bundled := .Values.bundledDatabase -}}
{{- if hasKey $bundled "enabled" -}}
{{- if index $bundled "enabled" -}}true{{- end -}}
{{- else if not (include "thoras-console.externalDatabaseEnabled" .) -}}
true
{{- end -}}
{{- end -}}

{{/*
True when an external database is configured. Returns "true" or "".
*/}}
{{- define "thoras-console.externalDatabaseEnabled" -}}
{{- if .Values.externalDatabase.existingSecret.secretName -}}
true
{{- end -}}
{{- end -}}

{{/*
Resolution for every chart-managed credential, one entry per logical value:

  mode: existing  read from a Secret the customer manages
        values    pinned in values, stored in `thoras-console-helm-values`
        seed      generated by config-controller into
                  `thoras-console-config-controller`

`secret`/`key` say where consumers read the value in every mode. `value` is the
plaintext, present only for mode=values. `generate` is the config-controller
spec, present only for mode=seed. Values whose feature is off are omitted.

Sole source of truth for the ref helpers, `thoras-console-helm-values`, the
controller's projected volume, and its config file. Resolve here, nowhere else.

Unlike the thoras chart there is no `migrateFrom`: this chart has no pre-5.0
install to adopt values from.
*/}}
{{- define "thoras-console.secretPlan" -}}
{{- $auth := .Values.consoleApi.auth -}}
{{- $localMode := or (eq $auth.mode "local") (eq $auth.mode "both") -}}
{{- $bundled := include "thoras-console.bundledDatabaseEnabled" . -}}
{{- $managed := "thoras-console-config-controller" -}}
{{- $pinned := "thoras-console-helm-values" -}}
{{- $plan := list -}}

{{- /* The admin password only exists in a mode that compares one. */ -}}
{{- if $localMode -}}
{{- if $auth.existingSecret.secretName -}}
{{- $plan = append $plan (dict "name" "local-admin-password" "mode" "existing" "secret" $auth.existingSecret.secretName "key" $auth.existingSecret.passwordKey) -}}
{{- else if $auth.adminPassword -}}
{{- $plan = append $plan (dict "name" "local-admin-password" "mode" "values" "secret" $pinned "key" "local-admin-password" "value" $auth.adminPassword) -}}
{{- else -}}
{{- $plan = append $plan (dict "name" "local-admin-password" "mode" "seed" "secret" $managed "key" "local-admin-password" "generate" (dict "type" "alphanumeric" "length" 24)) -}}
{{- end -}}
{{- end -}}

{{- /* Bundled seeds a password and derives the DSN from it, so the plaintext
       exists in one place only. The database name is in the format string
       rather than appended by consumers, so both modes yield a complete DSN. */ -}}
{{- if $bundled -}}
{{- $db := .Values.bundledDatabase -}}
{{- $plan = append $plan (dict "name" "postgres-password" "mode" "seed" "secret" $managed "key" "postgres-password" "generate" (dict "type" "alphanumeric" "length" 16)) -}}
{{- $format := printf "postgres://postgres:%%s@%s:%d/%s?sslmode=disable" (include "thoras-console.databaseServiceName" .) ($db.containerPort | int) $db.databaseName -}}
{{- $plan = append $plan (dict "name" "postgresql-dsn" "mode" "seed" "secret" $managed "key" "postgresql-dsn" "generate" (dict "type" "format" "format" $format "args" (list "postgres-password"))) -}}
{{- else if .Values.externalDatabase.existingSecret.secretName -}}
{{- /* An external DSN is only ever read from a Secret the customer manages,
       never pinned in values: it carries a password, and a pinned value would
       land in `thoras-console-helm-values` and in `helm get values`. */ -}}
{{- $plan = append $plan (dict "name" "postgresql-dsn" "mode" "existing" "secret" .Values.externalDatabase.existingSecret.secretName "key" .Values.externalDatabase.existingSecret.dsnKey) -}}
{{- end -}}

{{- /* Webhook and Slack are never generated; unset means the consuming env var
       is omitted entirely. */ -}}
{{- $webhook := .Values.consoleApi.webhook -}}
{{- if $webhook.existingSecret.secretName -}}
{{- $plan = append $plan (dict "name" "webhook-secret" "mode" "existing" "secret" $webhook.existingSecret.secretName "key" $webhook.existingSecret.secretKey) -}}
{{- else if $webhook.secret -}}
{{- $plan = append $plan (dict "name" "webhook-secret" "mode" "values" "secret" $pinned "key" "webhook-secret" "value" $webhook.secret) -}}
{{- end -}}

{{- if .Values.slack.existingSecret.secretName -}}
{{- $plan = append $plan (dict "name" "slack-webhook-url" "mode" "existing" "secret" .Values.slack.existingSecret.secretName "key" .Values.slack.existingSecret.webhookUrlKey) -}}
{{- else if .Values.slack.webhookUrl -}}
{{- $plan = append $plan (dict "name" "slack-webhook-url" "mode" "values" "secret" $pinned "key" "slack-webhook-url" "value" .Values.slack.webhookUrl) -}}
{{- end -}}

{{- toYaml $plan -}}
{{- end -}}

{{/*
Look up one entry in the secret plan. Fails when the value is unresolved, which
means the caller emitted a ref for a feature that is switched off.
Usage: include "thoras-console.secretPlanEntry" (dict "root" . "name" "postgresql-dsn") | fromYaml
*/}}
{{- define "thoras-console.secretPlanEntry" -}}
{{- $want := .name -}}
{{- $found := dict -}}
{{- range include "thoras-console.secretPlan" .root | fromYamlArray -}}
{{- if eq .name $want -}}
{{- $found = . -}}
{{- end -}}
{{- end -}}
{{- if not $found -}}
{{- fail (printf "thoras-console.secretPlanEntry: %q is not resolved; its feature is disabled" $want) -}}
{{- end -}}
{{- toYaml $found -}}
{{- end -}}

{{/*
Secret+key a consumer reads a logical value from. Identical in every mode, so a
consumer never branches on how the value was supplied.
Usage: {{- $ref := include "thoras-console.secretRef" (dict "root" . "name" "postgresql-dsn") | fromYaml }}
*/}}
{{- define "thoras-console.secretRef" -}}
{{- $entry := include "thoras-console.secretPlanEntry" . | fromYaml -}}
name: {{ $entry.secret }}
key: {{ $entry.key }}
{{- end -}}

{{- define "thoras-console.adminPasswordRef" -}}
{{- include "thoras-console.secretRef" (dict "root" . "name" "local-admin-password") -}}
{{- end -}}

{{- define "thoras-console.databaseDsnRef" -}}
{{- include "thoras-console.secretRef" (dict "root" . "name" "postgresql-dsn") -}}
{{- end -}}

{{- define "thoras-console.postgresPasswordRef" -}}
{{- include "thoras-console.secretRef" (dict "root" . "name" "postgres-password") -}}
{{- end -}}

{{/*
Full env var for an optional credential, or nothing when it is unresolved.
Unset optional secrets must omit the var rather than bind a Secret key that does
not exist, which would wedge the pod in CreateContainerConfigError.
Wrap the call in `with` so an unresolved value emits no blank line.
*/}}
{{- define "thoras-console.optionalSecretEnv" -}}
{{- $want := .name -}}
{{- $env := .env -}}
{{- range include "thoras-console.secretPlan" .root | fromYamlArray -}}
{{- if eq .name $want -}}
- name: {{ $env }}
  valueFrom:
    secretKeyRef:
      name: {{ .secret }}
      key: {{ .key }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Usage: {{- with include "thoras-console.slackEnv" . }}{{- . | nindent 10 }}{{- end }}
*/}}
{{- define "thoras-console.slackEnv" -}}
{{- include "thoras-console.optionalSecretEnv" (dict "root" . "name" "slack-webhook-url" "env" "SERVICE_SLACK_WEBHOOK_URL") -}}
{{- end -}}

{{/*
Usage: {{- with include "thoras-console.webhookEnv" . }}{{- . | nindent 10 }}{{- end }}
*/}}
{{- define "thoras-console.webhookEnv" -}}
{{- include "thoras-console.optionalSecretEnv" (dict "root" . "name" "webhook-secret" "env" "SERVICE_WEBHOOK_SECRET") -}}
{{- end -}}

{{/*
Keys stored in `thoras-console-helm-values`: every logical value pinned in
values. Empty when the customer pinned nothing.
*/}}
{{- define "thoras-console.helmSecretValuesKeys" -}}
{{- $keys := dict -}}
{{- range include "thoras-console.secretPlan" . | fromYamlArray -}}
{{- if eq .mode "values" -}}
{{- $_ := set $keys .key .value -}}
{{- end -}}
{{- end -}}
{{- if $keys -}}
{{- toYaml $keys -}}
{{- end -}}
{{- end -}}

{{/*
Projected-volume sources exposing every non-generated value to
config-controller as a file, so it never needs API read access to
customer-managed Secrets. Grouped by Secret name because one Secret commonly
carries several keys. The file name is the logical value name, matching `path`
in the config file.
*/}}
{{- define "thoras-console.providedSecretSources" -}}
{{- $bySecret := dict -}}
{{- $order := list -}}
{{- range include "thoras-console.secretPlan" . | fromYamlArray -}}
{{- if or (eq .mode "existing") (eq .mode "values") -}}
{{- if not (hasKey $bySecret .secret) -}}
{{- $order = append $order .secret -}}
{{- $_ := set $bySecret .secret list -}}
{{- end -}}
{{- $_ := set $bySecret .secret (append (index $bySecret .secret) (dict "key" .key "path" .name)) -}}
{{- end -}}
{{- end -}}
{{- $sources := list -}}
{{- range $order -}}
{{- $sources = append $sources (dict "secret" (dict "name" . "optional" true "items" (index $bySecret .))) -}}
{{- end -}}
{{- if $sources -}}
{{- toYaml $sources -}}
{{- end -}}
{{- end -}}

{{/*
Body of `config-controller.yaml`. Mirrors the secret plan: existing and
values-pinned entries become `source: provided` file reads, generated values
carry their generator.
*/}}
{{- define "thoras-console.configControllerConfig" -}}
{{- $cc := .Values.consoleConfigController -}}
version: v1
managedSecret: thoras-console-config-controller
values:
{{- range include "thoras-console.secretPlan" . | fromYamlArray }}
  - name: {{ .name }}
  {{- if eq .mode "seed" }}
    source: seed
    generate:
      {{- toYaml .generate | nindent 6 }}
  {{- else }}
    source: provided
    path: /etc/thoras/provided/{{ .name }}
    consumedFrom:
      secret: {{ .secret }}
      key: {{ .key }}
  {{- end }}
{{- end }}
restart:
  order:
    {{- range $cc.restartOrder }}
    - {{ . }}
    {{- end }}
  exclude:
    {{- /* The controller does not hot-reload its own config; the chart rolls it
           with a checksum instead. */}}
    {{- range $cc.restartExclude }}
    - {{ . }}
    {{- end }}
{{- end -}}

{{/*
Headless Service fronting the bundled database. Named separately because it is
both the StatefulSet's required serviceName and the host in the generated DSN.
*/}}
{{- define "thoras-console.databaseServiceName" -}}
thoras-console-db
{{- end -}}

{{/*
Every render-time guard, in one place. Included by the templates that resolve
a secret ref as well as by helm-values-secret.yaml, so a misconfiguration is
reported with an actionable message rather than as an unresolved plan entry
from whichever template Helm happens to render first.
*/}}
{{- define "thoras-console.validate" -}}
{{- $auth := .Values.consoleApi.auth -}}
{{- $localMode := or (eq $auth.mode "local") (eq $auth.mode "both") -}}
{{- $oidcMode := or (eq $auth.mode "oidc") (eq $auth.mode "both") -}}

{{- /* Mode selector first: every guard below reads from it. */}}
{{- if not (or $localMode $oidcMode) -}}
{{- fail (printf "consoleApi.auth.mode must be \"local\", \"oidc\", or \"both\", got %q" $auth.mode) -}}
{{- end -}}

{{- /* OIDC companions. console-api's compiled defaults point at Thoras' own
       hosted console, so an unset issuer silently validates tokens against the
       wrong tenant rather than failing. Report both at once. */}}
{{- if $oidcMode -}}
{{- $missing := list -}}
{{- if not $auth.oidc.issuer -}}{{- $missing = append $missing "issuer" -}}{{- end -}}
{{- if not $auth.oidc.audiences -}}{{- $missing = append $missing "audiences" -}}{{- end -}}
{{- if $missing -}}
{{- fail (printf "consoleApi.auth.mode %q requires consoleApi.auth.oidc: %s. Leaving these empty falls back to values that point at Thoras' hosted console, which will not accept your users." $auth.mode (join ", " $missing)) -}}
{{- end -}}
{{- end -}}

{{- /* Local-admin password must be resolvable from somewhere. */}}
{{- if $localMode -}}
{{- if and $auth.adminPassword $auth.existingSecret.secretName -}}
{{- fail "consoleApi.auth.adminPassword and consoleApi.auth.existingSecret.secretName are mutually exclusive" -}}
{{- end -}}
{{- if and (not $auth.adminPassword) (not $auth.existingSecret.secretName) (not .Values.consoleConfigController.enabled) -}}
{{- fail (printf "consoleApi.auth.mode %q needs an admin password, but none is pinned, no existing Secret is referenced, and consoleConfigController.enabled is false so nothing can generate one. Set consoleApi.auth.adminPassword, point consoleApi.auth.existingSecret at a Secret, or re-enable the controller." $auth.mode) -}}
{{- end -}}
{{- /* Fail here rather than letting console-api reject it at startup and
       CrashLoopBackOff. */}}
{{- if and $auth.adminPassword (lt (len $auth.adminPassword) 12) -}}
{{- fail (printf "consoleApi.auth.adminPassword must be at least 12 characters; got %d" (len $auth.adminPassword)) -}}
{{- end -}}
{{- end -}}

{{- /* Not secret, but still validated: the signing key derives from it, so a
       too-short salt weakens every session token. */}}
{{- if and $auth.adminSalt (lt (len $auth.adminSalt) 16) -}}
{{- fail (printf "consoleApi.auth.adminSalt must be at least 16 characters when set; got %d" (len $auth.adminSalt)) -}}
{{- end -}}

{{- /* Exactly one database. bundledDatabase.enabled is unset by default so
       hasKey tells an explicit request from the chart default: configuring
       externalDatabase alone switches over silently, while asking for both is
       ambiguous. */}}
{{- $bundled := include "thoras-console.bundledDatabaseEnabled" . -}}
{{- $external := include "thoras-console.externalDatabaseEnabled" . -}}
{{- if and $bundled $external -}}
{{- fail "bundledDatabase.enabled and externalDatabase.existingSecret are both configured, and they are mutually exclusive. Remove bundledDatabase.enabled to use the external database, or clear externalDatabase.existingSecret to use the bundled one." -}}
{{- end -}}
{{- if not (or $bundled $external) -}}
{{- fail "no database is configured. Either leave bundledDatabase.enabled unset for the bundled evaluation database, or point externalDatabase.existingSecret at a Secret holding the DSN of your own." -}}
{{- end -}}

{{- /* Half-set refs. A name without its key reaches config-controller as a
       provided value with an empty consumedFrom.key, which it rejects at load
       time, so the controller pod would never go ready. The key fields all
       carry defaults, so only this direction is reachable. */}}
{{- if and $auth.existingSecret.secretName (not $auth.existingSecret.passwordKey) -}}
{{- fail "consoleApi.auth.existingSecret.passwordKey is required when secretName is set" -}}
{{- end -}}
{{- if and .Values.consoleApi.webhook.existingSecret.secretName (not .Values.consoleApi.webhook.existingSecret.secretKey) -}}
{{- fail "consoleApi.webhook.existingSecret.secretKey is required when secretName is set" -}}
{{- end -}}
{{- if and .Values.externalDatabase.existingSecret.secretName (not .Values.externalDatabase.existingSecret.dsnKey) -}}
{{- fail "externalDatabase.existingSecret.dsnKey is required when secretName is set" -}}
{{- end -}}
{{- if and .Values.slack.existingSecret.secretName (not .Values.slack.existingSecret.webhookUrlKey) -}}
{{- fail "slack.existingSecret.webhookUrlKey is required when secretName is set" -}}
{{- end -}}

{{- /* Mutually exclusive pins, for the values the plan resolves in priority
       order. auth is handled above, alongside its own required-somewhere check. */}}
{{- if and .Values.consoleApi.webhook.secret .Values.consoleApi.webhook.existingSecret.secretName -}}
{{- fail "consoleApi.webhook.secret and consoleApi.webhook.existingSecret.secretName are mutually exclusive" -}}
{{- end -}}
{{- if and .Values.slack.webhookUrl .Values.slack.existingSecret.secretName -}}
{{- fail "slack.webhookUrl and slack.existingSecret.secretName are mutually exclusive" -}}
{{- end -}}

{{- /* Nothing else creates the generated Secret, so disabling the controller
       while a value still needs generating leaves consumers pointing at a
       Secret that will never exist. */}}
{{- if not .Values.consoleConfigController.enabled -}}
{{- $seeded := list -}}
{{- range include "thoras-console.secretPlan" . | fromYamlArray -}}
{{- if eq .mode "seed" -}}
{{- $seeded = append $seeded .name -}}
{{- end -}}
{{- end -}}
{{- if $seeded -}}
{{- fail (printf "consoleConfigController.enabled is false but these values would have to be generated by it: %s. Pin them in values, point them at existing Secrets, or re-enable the controller." (join ", " $seeded)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
