{{/*
Every helper is prefixed: template names are global to a rendering, so an
unprefixed one would collide with the thoras chart's if the two are composed.
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
The supported way to read networkPolicy.flavor. Every network-policy template
branches on the result, so an unknown value fails the render here rather than
falling through every branch and emitting no policy at all.
*/}}
{{- define "thoras-console.networkPolicyFlavor" -}}
{{- $flavor := .Values.networkPolicy.flavor -}}
{{- if not (or (eq $flavor "kubernetes") (eq $flavor "cilium")) -}}
{{- fail (printf "networkPolicy.flavor must be either \"kubernetes\" or \"cilium\", got %q" $flavor) -}}
{{- end -}}
{{- $flavor -}}
{{- end -}}

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
Labels for the bundled database's volumeClaimTemplates, as JSON. Kubernetes
forbids changing volumeClaimTemplates in place, so these are frozen for the
life of every install: nothing here may vary with the chart version or values.
Built as a dict so a numeric-looking release name stays a string.
*/}}
{{- define "thoras-console.databaseVolumeLabels" -}}
{{- dict "app.kubernetes.io/name" .Chart.Name "app.kubernetes.io/instance" .Release.Name | toJson -}}
{{- end -}}

{{/*
True when the chart should deploy its own database.

bundledDatabase.enabled is absent from values.yaml so hasKey can tell unset
from explicit: configuring externalDatabase alone switches over, while asking
for both fails in thoras-console.validate. Returns "true" or "".
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
auth.oidc.audiences as the comma-separated string console-api reads. Accepts a
list or, for a single audience or an existing value, a string.
*/}}
{{- define "thoras-console.oidcAudiences" -}}
{{- $a := .Values.auth.oidc.audiences -}}
{{- if kindIs "slice" $a -}}
{{- join "," $a -}}
{{- else -}}
{{- $a | default "" -}}
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
{{- $auth := .Values.auth -}}
{{- $local := $auth.local -}}
{{- $localMode := or (eq $auth.mode "local") (eq $auth.mode "both") -}}
{{- $bundled := include "thoras-console.bundledDatabaseEnabled" . -}}
{{- $managed := "thoras-console-config-controller" -}}
{{- $pinned := "thoras-console-helm-values" -}}
{{- $plan := list -}}

{{- /* The admin password only exists in a mode that compares one. */ -}}
{{- if $localMode -}}
{{- if $local.existingSecret.secretName -}}
{{- $plan = append $plan (dict "name" "local-admin-password" "mode" "existing" "secret" $local.existingSecret.secretName "key" $local.existingSecret.passwordKey) -}}
{{- else if $local.adminPassword -}}
{{- $plan = append $plan (dict "name" "local-admin-password" "mode" "values" "secret" $pinned "key" "local-admin-password" "value" $local.adminPassword) -}}
{{- else -}}
{{- $plan = append $plan (dict "name" "local-admin-password" "mode" "seed" "secret" $managed "key" "local-admin-password" "generate" (dict "type" "alphanumeric" "length" 24)) -}}
{{- end -}}
{{- end -}}

{{- /* No human types it, so it is generated longer than the admin password. */ -}}
{{- $join := .Values.consoleApi.clusterJoin -}}
{{- if $join.enabled -}}
{{- if $join.existingSecret.secretName -}}
{{- $plan = append $plan (dict "name" "cluster-join-secret" "mode" "existing" "secret" $join.existingSecret.secretName "key" $join.existingSecret.secretKey) -}}
{{- else if $join.secret -}}
{{- $plan = append $plan (dict "name" "cluster-join-secret" "mode" "values" "secret" $pinned "key" "cluster-join-secret" "value" $join.secret) -}}
{{- else -}}
{{- $plan = append $plan (dict "name" "cluster-join-secret" "mode" "seed" "secret" $managed "key" "cluster-join-secret" "generate" (dict "type" "alphanumeric" "length" 48)) -}}
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
{{- /* Never pinned in values: it carries a password. */ -}}
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

{{- define "thoras-console.clusterJoinSecretRef" -}}
{{- include "thoras-console.secretRef" (dict "root" . "name" "cluster-join-secret") -}}
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
{{- /* Every network-policy template validates the flavor as it reads it, but each
       is also gated on its component, so check here too: this renders whatever is
       enabled. */ -}}
{{- if .Values.networkPolicy.enabled -}}
{{- $_ := include "thoras-console.networkPolicyFlavor" . -}}
{{- end -}}
{{- /* console-api refuses this combination at startup; catching it here turns a
       crash loop into a message. */ -}}
{{- if and .Values.consoleApi.clusterJoin.enabled (not .Values.consoleApi.singleOrg.enabled) -}}
{{- fail "consoleApi.clusterJoin.enabled requires consoleApi.singleOrg.enabled: a joining cluster presents no user identity, so the organization has to be implicit" -}}
{{- end -}}
{{- $auth := .Values.auth -}}
{{- $local := $auth.local -}}
{{- $localMode := or (eq $auth.mode "local") (eq $auth.mode "both") -}}
{{- $oidcMode := or (eq $auth.mode "oidc") (eq $auth.mode "both") -}}

{{- if not (or $localMode $oidcMode) -}}
{{- fail (printf "auth.mode must be \"local\", \"oidc\", or \"both\", got %q" $auth.mode) -}}
{{- end -}}

{{- /* console-api's compiled defaults point at Thoras' hosted console, so an
       unset issuer would check tokens against the wrong provider. */}}
{{- if $oidcMode -}}
{{- $missing := list -}}
{{- if not $auth.oidc.issuer -}}{{- $missing = append $missing "issuer" -}}{{- end -}}
{{- if not (include "thoras-console.oidcAudiences" .) -}}{{- $missing = append $missing "audiences" -}}{{- end -}}
{{- if $missing -}}
{{- fail (printf "auth.mode %q requires auth.oidc: %s. Leaving these empty falls back to values that point at Thoras' hosted console, which will not accept your users." $auth.mode (join ", " $missing)) -}}
{{- end -}}
{{- end -}}

{{- /* Without a client ID the dashboard shows an error page instead of a
       login. */}}
{{- if and $oidcMode .Values.consoleDashboard.enabled (not $auth.oidc.client.id) -}}
{{- fail (printf "auth.mode %q requires auth.oidc.client.id, the OAuth client ID the dashboard signs in with. Register https://<dashboard-host>/landing as a callback URL for it too." $auth.mode) -}}
{{- end -}}

{{- if $localMode -}}
{{- if and $local.adminPassword $local.existingSecret.secretName -}}
{{- fail "auth.local.adminPassword and auth.local.existingSecret.secretName are mutually exclusive" -}}
{{- end -}}
{{- if and (not $local.adminPassword) (not $local.existingSecret.secretName) (not .Values.consoleConfigController.enabled) -}}
{{- fail (printf "auth.mode %q needs an admin password, but none is pinned, no existing Secret is referenced, and consoleConfigController.enabled is false so nothing can generate one. Set auth.local.adminPassword, point auth.local.existingSecret at a Secret, or re-enable the controller." $auth.mode) -}}
{{- end -}}
{{- /* console-api refuses a shorter one at startup. */}}
{{- if and $local.adminPassword (lt (len $local.adminPassword) 12) -}}
{{- fail (printf "auth.local.adminPassword must be at least 12 characters; got %d" (len $local.adminPassword)) -}}
{{- end -}}
{{- end -}}

{{- /* The signing key derives from it, so a short salt weakens every token. */}}
{{- if and $local.adminSalt (lt (len $local.adminSalt) 16) -}}
{{- fail (printf "auth.local.adminSalt must be at least 16 characters when set; got %d" (len $local.adminSalt)) -}}
{{- end -}}

{{- /* Exactly one database. */}}
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
{{- if and $local.existingSecret.secretName (not $local.existingSecret.passwordKey) -}}
{{- fail "auth.local.existingSecret.passwordKey is required when secretName is set" -}}
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

{{- /* A value both set and referenced is ambiguous. The admin password is
       checked above. */}}
{{- if and .Values.consoleApi.webhook.secret .Values.consoleApi.webhook.existingSecret.secretName -}}
{{- fail "consoleApi.webhook.secret and consoleApi.webhook.existingSecret.secretName are mutually exclusive" -}}
{{- end -}}
{{- if and .Values.slack.webhookUrl .Values.slack.existingSecret.secretName -}}
{{- fail "slack.webhookUrl and slack.existingSecret.secretName are mutually exclusive" -}}
{{- end -}}
{{- $join := .Values.consoleApi.clusterJoin -}}
{{- if and $join.secret $join.existingSecret.secretName -}}
{{- fail "consoleApi.clusterJoin.secret and consoleApi.clusterJoin.existingSecret.secretName are mutually exclusive" -}}
{{- end -}}
{{- if and $join.secret (lt (len $join.secret) 32) -}}
{{- fail (printf "consoleApi.clusterJoin.secret must be at least 32 characters; got %d" (len $join.secret)) -}}
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

{{/*
Ingress for a component. Two components need one -- the dashboard for browsers
and console-api for cluster agents posting ingest -- so the shape lives here
rather than being copied.
Usage: include "thoras-console.ingress" (dict "root" . "ingress" .Values.consoleDashboard.ingress "name" "thoras-console-dashboard" "port" .Values.consoleDashboard.port "labels" .Values.consoleDashboard.labels)
*/}}
{{- define "thoras-console.ingress" -}}
{{- if .ingress.enabled -}}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .name }}
  namespace: {{ .root.Release.Namespace }}
  {{- with .ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  labels:
    {{- include "thoras-console.resourceLabels" (dict "root" .root "component" .labels) | nindent 4 }}
spec:
  {{- with .ingress.ingressClassName }}
  ingressClassName: {{ . }}
  {{- end }}
  {{- with .ingress.tls }}
  tls:
    {{- range . }}
    - hosts:
        {{- range .hosts }}
        - {{ . | quote }}
        {{- end }}
      {{- with .secretName }}
      secretName: {{ . }}
      {{- end }}
    {{- end }}
  {{- end }}
  rules:
    {{- $name := .name }}
    {{- $port := .port }}
    {{- range .ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType | default "Prefix" }}
            backend:
              service:
                name: {{ $name }}
                port:
                  number: {{ $port }}
          {{- end }}
    {{- end }}
{{- end -}}
{{- end -}}

{{/*
HTTPRoute for a component, for clusters standardised on Gateway API. Without
it such a cluster has no way to route ingest at all.
Usage: include "thoras-console.httpRoute" (dict "root" . "gatewayAPI" .Values.consoleDashboard.gatewayAPI "name" "thoras-console-dashboard" "port" .Values.consoleDashboard.port "labels" .Values.consoleDashboard.labels)
*/}}
{{- define "thoras-console.httpRoute" -}}
{{- if .gatewayAPI.enabled -}}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ .name }}
  namespace: {{ .root.Release.Namespace }}
  {{- with .gatewayAPI.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  labels:
    {{- include "thoras-console.resourceLabels" (dict "root" .root "component" .labels) | nindent 4 }}
spec:
  {{- with .gatewayAPI.parentRefs }}
  parentRefs:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .gatewayAPI.hostnames }}
  hostnames:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  rules:
    - matches:
        - path:
            type: {{ .gatewayAPI.pathType | default "PathPrefix" }}
            value: {{ .gatewayAPI.path | default "/" }}
      backendRefs:
        - name: {{ .name }}
          port: {{ .port }}
{{- end -}}
{{- end -}}
