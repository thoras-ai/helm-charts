{{- define "imagePullSecret" }}
{{- printf "{\"auths\": {\"%s\": {\"auth\": \"%s\"}}}" .Values.imageCredentials.registry (printf "%s:%s" .Values.imageCredentials.username .Values.imageCredentials.password | b64enc) | b64enc }}
{{- end }}

{{/*
Component labels - merges global + component labels (no Helm labels)
Usage: include "thoras.componentLabels" (dict "root" . "component" .Values.thorasWorker.labels)
*/}}
{{- define "thoras.componentLabels" -}}
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
Usage: include "thoras.resourceLabels" (dict "root" . "component" .Values.thorasWorker.labels)
*/}}
{{- define "thoras.resourceLabels" -}}
helm.sh/chart: {{ .root.Chart.Name }}-{{ .root.Chart.Version | replace "+" "_" }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- $componentLabels := include "thoras.componentLabels" . | trim }}
{{- if $componentLabels }}
{{ $componentLabels }}
{{- end }}
{{- end -}}

{{/*
Pod annotations - merges global podAnnotations with component-specific podAnnotations.
Component annotations override global ones (same key = component wins).
Usage: include "thoras.podAnnotations" (dict "root" . "component" .Values.thorasWorker.podAnnotations)
*/}}
{{- define "thoras.podAnnotations" -}}
{{- $merged := mergeOverwrite (deepCopy (.root.Values.podAnnotations | default dict)) (.component | default dict) }}
{{- if $merged }}
{{- toYaml $merged }}
{{- end }}
{{- end }}

{{/*
Default affinity for metricsCollector - anti-affinity with forecast-worker
*/}}
{{- define "thoras.metricsCollector.defaultAffinity" -}}
{{- if .Values.featureFlags.enableForecastCollectorAntiAffinity }}
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      labelSelector:
        matchExpressions:
        - key: app
          operator: In
          values:
          - thoras-forecast-worker
      topologyKey: kubernetes.io/hostname
{{- end }}
{{- end }}

{{/*
Default affinity for thorasOperator - soft anti-affinity with self to spread replicas across nodes
*/}}
{{- define "thoras.thorasOperator.defaultAffinity" -}}
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      labelSelector:
        matchExpressions:
        - key: app
          operator: In
          values:
          - thoras-operator
      topologyKey: kubernetes.io/hostname
{{- end }}

{{/*
Default affinity for thorasForecast - anti-affinity with metrics-collector and self
*/}}
{{- define "thoras.thorasForecast.defaultAffinity" -}}
{{- if or .Values.featureFlags.enableForecastCollectorAntiAffinity .Values.thorasForecast.enableSelfAntiAffinity }}
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
  {{- if .Values.featureFlags.enableForecastCollectorAntiAffinity }}
  - weight: 100
    podAffinityTerm:
      labelSelector:
        matchExpressions:
        - key: app
          operator: In
          values:
          - metrics-collector
      topologyKey: kubernetes.io/hostname
  {{- end }}
  {{- if .Values.thorasForecast.enableSelfAntiAffinity }}
  - weight: 95
    podAffinityTerm:
      labelSelector:
        matchExpressions:
        - key: app
          operator: In
          values:
          - thoras-forecast-worker
      topologyKey: kubernetes.io/hostname
  {{- end }}
{{- end }}
{{- end }}

{{/*
ClusterRole + ClusterRoleBinding for read-only access to cluster-scoped
resources (nodes, PVs, storageclasses) — a namespaced Role can never grant these.
Usage: include "thoras.clusterScopedReadRbac" (dict "root" . "name" "thoras-operator-cluster-scoped"
         "labels" .Values.thorasOperator.labels "serviceAccountName" .Values.thorasOperator.serviceAccount.name)
*/}}
{{- define "thoras.clusterScopedReadRbac" -}}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{ .name }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "thoras.resourceLabels" (dict "root" .root "component" .labels) | nindent 4 }}
rules:
- apiGroups:
  - ""
  resources:
  - nodes
  - persistentvolumes
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - storage.k8s.io
  resources:
  - storageclasses
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - metrics.k8s.io
  resources:
  - nodes
  verbs:
  - list
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    {{- include "thoras.resourceLabels" (dict "root" .root "component" .labels) | nindent 4 }}
  name: {{ .name }}
  namespace: {{ .root.Release.Namespace }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ .name }}
subjects:
- kind: ServiceAccount
  name: {{ .serviceAccountName }}
  namespace: {{ .root.Release.Namespace }}
{{- end -}}

{{/*
Explicit get/list/watch rules for the resources Thoras discovers and sizes,
in place of a blanket `apiGroups: ['*'] resources: ['*']` rule that would
also grant read access to Secrets. Shared by the api-server, operator, and
worker ClusterRoles/Roles.
Usage: {{ include "thoras.workloadReadRules" . }}
*/}}
{{- define "thoras.workloadReadRules" -}}
- apiGroups:
  - ""
  resources:
  - pods
  - nodes
  - namespaces
  - services
  - events
  - persistentvolumes
  - persistentvolumeclaims
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - apps
  resources:
  - deployments
  - statefulsets
  - daemonsets
  - replicasets
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - batch
  resources:
  - jobs
  - cronjobs
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - autoscaling
  resources:
  - horizontalpodautoscalers
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - autoscaling.k8s.io
  resources:
  - verticalpodautoscalers
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - policy
  resources:
  - poddisruptionbudgets
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - argoproj.io
  resources:
  - rollouts
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - karpenter.sh
  resources:
  - nodepools
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - metrics.k8s.io
  resources:
  - pods
  - nodes
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - external.metrics.k8s.io
  resources:
  - '*'
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - storage.k8s.io
  resources:
  - storageclasses
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - thoras.ai
  resources:
  - '*'
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - coordination.k8s.io
  resources:
  - leases
  verbs:
  - get
  - list
  - watch
{{- end -}}

{{/*
Global environment variables (proxy settings + user-defined env) injected into all containers.
*/}}
{{/*
Returns a YAML list of global env var entries (proxy + user-defined), or empty string.
Indent the output at the call site: {{- include "thoras.globalEnv" . | indent 10 }}
*/}}
{{/*
True when the chart should use an external TimescaleDB instead of deploying one.
*/}}
{{- define "thoras.externalTimescaleEnabled" -}}
{{- if or .Values.externalTimescale.dsn .Values.externalTimescale.secretRefName -}}
true
{{- end -}}
{{- end -}}

{{/*
Egress rule allowing components to reach the Kubernetes API server, for the
"kubernetes" NetworkPolicy flavor.

Standard NetworkPolicy cannot target the API server by label, so this permits
egress to any destination on the configured ports. Policy is enforced after
kube-proxy DNATs the service address to the real endpoint, so the ports must
match what the API server actually listens on rather than the service port.
Use the cilium flavor for precise scoping.

Emits nothing when the port list is empty, leaving the rule out entirely
instead of rendering a rule that would allow egress on every port.
*/}}
{{- define "thoras.apiServerEgressRule" -}}
{{- with .Values.networkPolicy.apiServerPorts -}}
- ports:
  {{- range . }}
  - port: {{ . }}
    protocol: TCP
  {{- end }}
{{- end -}}
{{- end -}}

{{/*
True when the metrics collector should use a persistent volume.
Tri-state: an explicit metricsCollector.persistence.enabled (true/false) is
always honored. When it is unset, infer "on" if the customer configured any
persistence knob (storageClassName, pvcStorageRequestSize, or a fileSystemId).
This avoids the silent footgun where knobs are set but enabled is forgotten.
*/}}
{{- define "thoras.persistenceEnabled" -}}
{{- $p := .Values.metricsCollector.persistence -}}
{{- if not (kindIs "invalid" $p.enabled) -}}
{{- if $p.enabled -}}true{{- end -}}
{{- else if or $p.storageClassName $p.pvcStorageRequestSize $p.createEFSStorageClass.fileSystemId -}}
true
{{- end -}}
{{- end -}}

{{- define "thoras.globalEnv" -}}
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
Resolution for every chart-managed credential, one entry per logical value:

  mode: provided  read from a Secret the customer manages
        shared    pinned in values, stored in `thoras-helm-shared`
        seed      generated by config-controller into `thoras-config-controller`

`secret`/`key` say where consumers read the value in every mode. `value` is
the plaintext, present only for mode=shared. `generate`/`migrateFrom` are the
config-controller seeding spec, present only for mode=seed. Values whose
feature is off are omitted entirely.

Sole source of truth for the ref helpers, `thoras-helm-shared`, the
controller's projected volume, and its config file. Resolve here, nowhere
else.

Generation lengths must stay equal to what the chart used to produce so that
migrated and generated values are indistinguishable.
*/}}
{{- define "thoras.secretPlan" -}}
{{- $auth := .Values.thorasDashboard.auth -}}
{{- $htpasswdMode := and .Values.thorasDashboard.enabled $auth.enabled (eq $auth.mode "htpasswd") -}}
{{- $oidcMode := and .Values.thorasDashboard.enabled $auth.enabled (eq $auth.mode "oidc") -}}
{{- $timescale := .Values.metricsCollector.timescale -}}
{{- $external := include "thoras.externalTimescaleEnabled" . -}}
{{- $plan := list -}}

{{- $ac := .Values.apiClientSecret -}}
{{- if eq (include "thoras.apiClientEnabled" .) "true" -}}
{{- if $ac.existingSecret.secretName -}}
{{- $plan = append $plan (dict "name" "api-client-secret" "mode" "provided" "secret" $ac.existingSecret.secretName "key" $ac.existingSecret.secretKey) -}}
{{- else if $ac.secret -}}
{{- $plan = append $plan (dict "name" "api-client-secret" "mode" "shared" "secret" "thoras-helm-shared" "key" "api-client-secret" "value" $ac.secret) -}}
{{- else -}}
{{- $plan = append $plan (dict "name" "api-client-secret" "mode" "seed" "secret" "thoras-config-controller" "key" "api-client-secret" "generate" (dict "type" "alphanumeric" "length" 32) "migrateFrom" (list (dict "secret" "api-client-secret" "key" "secret"))) -}}
{{- end -}}
{{- end -}}

{{- if $htpasswdMode -}}
{{- $existing := $auth.htpasswd.existingSecret -}}
{{- if $existing.secretName -}}
{{- $plan = append $plan (dict "name" "dashboard-auth-password" "mode" "provided" "secret" $existing.secretName "key" $existing.passwordKey) -}}
{{- $plan = append $plan (dict "name" "dashboard-auth-cookie-secret" "mode" "provided" "secret" $existing.secretName "key" $existing.cookieSecretKey) -}}
{{- else -}}
{{- if $auth.htpasswd.password -}}
{{- $plan = append $plan (dict "name" "dashboard-auth-password" "mode" "shared" "secret" "thoras-helm-shared" "key" "dashboard-auth-password" "value" $auth.htpasswd.password) -}}
{{- else -}}
{{- $plan = append $plan (dict "name" "dashboard-auth-password" "mode" "seed" "secret" "thoras-config-controller" "key" "dashboard-auth-password" "generate" (dict "type" "alphanumeric" "length" 24)) -}}
{{- end -}}
{{- if $auth.htpasswd.cookieSecret -}}
{{- $plan = append $plan (dict "name" "dashboard-auth-cookie-secret" "mode" "shared" "secret" "thoras-helm-shared" "key" "dashboard-auth-cookie-secret" "value" $auth.htpasswd.cookieSecret) -}}
{{- else -}}
{{- $plan = append $plan (dict "name" "dashboard-auth-cookie-secret" "mode" "seed" "secret" "thoras-config-controller" "key" "dashboard-auth-cookie-secret" "generate" (dict "type" "alphanumeric" "length" 32) "validate" (dict "byteLengths" (list 16 24 32))) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- if $oidcMode -}}
{{- $existing := $auth.oidc.existingSecret -}}
{{- $plan = append $plan (dict "name" "dashboard-oidc-client-id" "mode" "provided" "secret" $existing.secretName "key" $existing.clientIDKey) -}}
{{- $plan = append $plan (dict "name" "dashboard-oidc-client-secret" "mode" "provided" "secret" $existing.secretName "key" $existing.clientSecretKey) -}}
{{- $plan = append $plan (dict "name" "dashboard-oidc-cookie-secret" "mode" "provided" "secret" $existing.secretName "key" $existing.cookieSecretKey) -}}
{{- end -}}

{{- /* DSN and password are coupled: bundled seeds both, external has no
       password at all. The seeded DSN embeds the seeded password, which
       config-controller cross-checks when migrating both from the legacy
       Secret. */ -}}
{{- if $external -}}
{{- if .Values.externalTimescale.secretRefName -}}
{{- $plan = append $plan (dict "name" "timescale-dsn" "mode" "provided" "secret" .Values.externalTimescale.secretRefName "key" .Values.externalTimescale.secretRefKey) -}}
{{- else -}}
{{- $plan = append $plan (dict "name" "timescale-dsn" "mode" "shared" "secret" "thoras-helm-shared" "key" "timescale-dsn" "value" .Values.externalTimescale.dsn) -}}
{{- end -}}
{{- else -}}
{{- $plan = append $plan (dict "name" "timescale-password" "mode" "seed" "secret" "thoras-config-controller" "key" "timescale-password" "generate" (dict "type" "alphanumeric" "length" 16) "migrateFrom" (list (dict "secret" "thoras-timescale-password" "key" "password"))) -}}
{{- $format := printf "postgres://postgres:%%s@%s:%d" $timescale.name ($timescale.containerPort | int) -}}
{{- $plan = append $plan (dict "name" "timescale-dsn" "mode" "seed" "secret" "thoras-config-controller" "key" "timescale-dsn" "generate" (dict "type" "format" "format" $format "args" (list "timescale-password")) "migrateFrom" (list (dict "secret" "thoras-timescale-password" "key" "host"))) -}}
{{- end -}}

{{- /* Slack and cloud-sync are never seeded; unset means the consuming env
       var is omitted entirely. */ -}}
{{- if and .Values.slackWebhookUrlSecretRefName .Values.slackWebhookUrlSecretRefKey -}}
{{- $plan = append $plan (dict "name" "slack-webhook-url" "mode" "provided" "secret" .Values.slackWebhookUrlSecretRefName "key" .Values.slackWebhookUrlSecretRefKey) -}}
{{- else if .Values.slackWebhookUrl -}}
{{- $plan = append $plan (dict "name" "slack-webhook-url" "mode" "shared" "secret" "thoras-helm-shared" "key" "slack-webhook-url" "value" .Values.slackWebhookUrl) -}}
{{- end -}}

{{- if and .Values.cloudSync.clusterKeySecretRefName .Values.cloudSync.clusterKeySecretRefKey -}}
{{- $plan = append $plan (dict "name" "cloud-sync-cluster-key" "mode" "provided" "secret" .Values.cloudSync.clusterKeySecretRefName "key" .Values.cloudSync.clusterKeySecretRefKey) -}}
{{- else if .Values.cloudSync.clusterKey -}}
{{- $plan = append $plan (dict "name" "cloud-sync-cluster-key" "mode" "shared" "secret" "thoras-helm-shared" "key" "cloud-sync-cluster-key" "value" .Values.cloudSync.clusterKey) -}}
{{- end -}}

{{- toYaml $plan -}}
{{- end -}}

{{/*
Look up one entry in thoras.secretPlan. Fails when the value is unresolved,
which means the caller emitted a ref for a feature that is switched off.
Usage: include "thoras.secretPlanEntry" (dict "root" . "name" "api-client-secret") | fromYaml
*/}}
{{- define "thoras.secretPlanEntry" -}}
{{- $want := .name -}}
{{- $found := dict -}}
{{- range include "thoras.secretPlan" .root | fromYamlArray -}}
{{- if eq .name $want -}}
{{- $found = . -}}
{{- end -}}
{{- end -}}
{{- if not $found -}}
{{- fail (printf "thoras.secretPlanEntry: %q is not resolved; its feature is disabled" $want) -}}
{{- end -}}
{{- toYaml $found -}}
{{- end -}}

{{/*
Secret+key a consumer reads a logical value from.
Usage: {{- $ref := include "thoras.secretRef" (dict "root" . "name" "timescale-dsn") | fromYaml }}
*/}}
{{- define "thoras.secretRef" -}}
{{- $entry := include "thoras.secretPlanEntry" . | fromYaml -}}
name: {{ $entry.secret }}
key: {{ $entry.key }}
{{- end -}}

{{/*
Secret+key that carries the shared api-client secret.
Usage: {{- $ref := include "thoras.apiClientSecretRef" . | fromYaml }}
*/}}
{{- define "thoras.apiClientSecretRef" -}}
{{- include "thoras.secretRef" (dict "root" . "name" "api-client-secret") -}}
{{- end -}}

{{/*
Secret+key for the dashboard basic-auth password (htpasswd mode).
*/}}
{{- define "thoras.dashboardAuthPasswordRef" -}}
{{- include "thoras.secretRef" (dict "root" . "name" "dashboard-auth-password") -}}
{{- end -}}

{{/*
Secret+key for the oauth2-proxy cookie secret (htpasswd mode).
*/}}
{{- define "thoras.dashboardAuthCookieSecretRef" -}}
{{- include "thoras.secretRef" (dict "root" . "name" "dashboard-auth-cookie-secret") -}}
{{- end -}}

{{/*
Secret+key for the TimescaleDB DSN. Includes the database name only when the
customer supplied it; consumers append "/thoras" for the bundled database.
*/}}
{{- define "thoras.timescaleDsnRef" -}}
{{- include "thoras.secretRef" (dict "root" . "name" "timescale-dsn") -}}
{{- end -}}

{{/*
Secret+key for the bundled TimescaleDB superuser password. Unresolved under an
external TimescaleDB, where no chart-managed password exists.
*/}}
{{- define "thoras.timescalePasswordRef" -}}
{{- include "thoras.secretRef" (dict "root" . "name" "timescale-password") -}}
{{- end -}}

{{/*
Full env var for an optional credential, or nothing when it is unresolved.
Unset optional secrets must omit the var rather than bind a Secret key that
does not exist, which would wedge the pod in CreateContainerConfigError.
Wrap the call in `with` so an unresolved value emits no blank line.
*/}}
{{- define "thoras.optionalSecretEnv" -}}
{{- $want := .name -}}
{{- $env := .env -}}
{{- range include "thoras.secretPlan" .root | fromYamlArray -}}
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
Slack webhook env var, or nothing when no webhook is configured. "prefix" is
required: the Go services read SERVICE_-prefixed vars, the operator also needs
the unprefixed one.
Usage: {{- with include "thoras.slackEnv" (dict "root" . "prefix" "SERVICE_") }}{{- . | nindent 10 }}{{- end }}
*/}}
{{- define "thoras.slackEnv" -}}
{{- include "thoras.optionalSecretEnv" (dict "root" .root "name" "slack-webhook-url" "env" (printf "%sSLACK_WEBHOOK_URL" .prefix)) -}}
{{- end -}}

{{/*
Cloud-sync cluster key env var, or nothing when no key is configured.
Usage: {{- with include "thoras.cloudSyncEnv" (dict "root" . "prefix" "SERVICE_") }}{{- . | nindent 10 }}{{- end }}
*/}}
{{- define "thoras.cloudSyncEnv" -}}
{{- include "thoras.optionalSecretEnv" (dict "root" .root "name" "cloud-sync-cluster-key" "env" (printf "%sCLOUD_SYNC_CLUSTER_KEY" .prefix)) -}}
{{- end -}}

{{/*
Keys stored in `thoras-helm-shared`: every logical value pinned in values.
Empty when the customer pinned nothing.
*/}}
{{- define "thoras.helmSharedKeys" -}}
{{- $keys := dict -}}
{{- range include "thoras.secretPlan" . | fromYamlArray -}}
{{- if eq .mode "shared" -}}
{{- $_ := set $keys .key .value -}}
{{- end -}}
{{- end -}}
{{- if $keys -}}
{{- toYaml $keys -}}
{{- end -}}
{{- end -}}

{{/*
Projected-volume sources exposing every non-seeded value to config-controller
as a file, so it never needs API read access to customer-managed Secrets.
Grouped by Secret name because one Secret commonly carries several keys. The
file name is the logical value name, matching `path` in the config file.
*/}}
{{- define "thoras.providedSecretSources" -}}
{{- $bySecret := dict -}}
{{- $order := list -}}
{{- range include "thoras.secretPlan" . | fromYamlArray -}}
{{- if or (eq .mode "provided") (eq .mode "shared") -}}
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
Body of `config-controller.yaml`. Mirrors thoras.secretPlan: provided and
shared values become `source: provided` file reads, seeded values carry their
generator and legacy migration sources.
*/}}
{{- define "thoras.configControllerConfig" -}}
{{- $cc := .Values.thorasConfigController -}}
version: v1
managedSecret: thoras-config-controller
values:
{{- range include "thoras.secretPlan" . | fromYamlArray }}
  - name: {{ .name }}
  {{- if eq .mode "seed" }}
    source: seed
    generate:
      {{- toYaml .generate | nindent 6 }}
    {{- with .migrateFrom }}
    migrateFrom:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .validate }}
    validate:
      {{- toYaml . | nindent 6 }}
    {{- end }}
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
    {{- /* The controller does not hot-reload its own config; the chart rolls
           it with a checksum instead. */}}
    {{- range $cc.restartExclude }}
    - {{ . }}
    {{- end }}
{{- end -}}

{{/*
Secret+key refs for OIDC mode. Always read from the customer-managed Secret
(chart never generates these). Consumers should include only when
auth.mode == oidc; the secretName is required and gated by fail-guards in
thoras-helm-shared-secret.yaml.
*/}}
{{- define "thoras.dashboardOidcClientIDRef" -}}
name: {{ .Values.thorasDashboard.auth.oidc.existingSecret.secretName }}
key: {{ .Values.thorasDashboard.auth.oidc.existingSecret.clientIDKey }}
{{- end -}}

{{- define "thoras.dashboardOidcClientSecretRef" -}}
name: {{ .Values.thorasDashboard.auth.oidc.existingSecret.secretName }}
key: {{ .Values.thorasDashboard.auth.oidc.existingSecret.clientSecretKey }}
{{- end -}}

{{- define "thoras.dashboardOidcCookieSecretRef" -}}
name: {{ .Values.thorasDashboard.auth.oidc.existingSecret.secretName }}
key: {{ .Values.thorasDashboard.auth.oidc.existingSecret.cookieSecretKey }}
{{- end -}}

{{/*
Resolve the api-client-secret enable flag with deprecation-aware alias.
Precedence: legacy featureFlags.enableSimpleAuthSecret wins if set;
otherwise apiClientSecret.enabled is used; defaults to true when unset.
Explicit values that conflict hard-fail. Returns the string "true" or
"false"; consumers should compare via `eq "true"`.

apiClientSecret.enabled is intentionally not defaulted in values.yaml so
that hasKey can distinguish user intent from the chart default.
*/}}
{{- define "thoras.apiClientEnabled" -}}
{{- $ff := .Values.featureFlags -}}
{{- $ac := .Values.apiClientSecret -}}
{{- $ffSet := hasKey $ff "enableSimpleAuthSecret" -}}
{{- $acSet := hasKey $ac "enabled" -}}
{{- if and $ffSet $acSet (ne (toString (index $ff "enableSimpleAuthSecret")) (toString $ac.enabled)) -}}
{{- fail "apiClientSecret.enabled conflicts with the deprecated featureFlags.enableSimpleAuthSecret; set only one" -}}
{{- end -}}
{{- if $ffSet -}}
{{- index $ff "enableSimpleAuthSecret" | ternary "true" "false" -}}
{{- else if $acSet -}}
{{- $ac.enabled | ternary "true" "false" -}}
{{- else -}}
true
{{- end -}}
{{- end -}}

{{/*
Simple auth env vars injected into every Thoras component. The enable flag is
always emitted so the components have an explicit "false"; the secret itself is
only bound when the flag is on. "prefix" is required and must be passed
explicitly (an empty string is falsey, so it cannot be defaulted): the Go
services read SERVICE_-prefixed vars, the forecaster reads them unprefixed.
Usage: {{- include "thoras.simpleAuthEnv" (dict "root" . "prefix" "SERVICE_") | nindent 10 }}
*/}}
{{- define "thoras.simpleAuthEnv" -}}
{{- $enabled := eq (include "thoras.apiClientEnabled" .root) "true" -}}
- name: {{ .prefix }}ENABLE_SIMPLE_AUTH_SECRET
  value: {{ $enabled | ternary "true" "false" | quote }}
{{- if $enabled }}
{{- $ref := include "thoras.apiClientSecretRef" .root | fromYaml }}
- name: {{ .prefix }}SIMPLE_AUTH_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ $ref.name }}
      key: {{ $ref.key }}
{{- end }}
{{- end -}}

{{/*
PodDisruptionBudget for a component. Renders nothing when pdb.enabled is falsey.
Spec precedence: minAvailable wins if set, else maxUnavailable, else defaults to
maxUnavailable: 1. Uses kindIs "invalid" so an explicit 0 is honored.
Usage: include "thoras.pdb" (dict "root" . "pdb" .Values.thorasWorker.pdb
         "name" "thoras-worker" "app" "thoras-worker"
         "labels" .Values.thorasWorker.labels)
*/}}
{{- define "thoras.pdb" -}}
{{- if .pdb.enabled -}}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .name }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "thoras.resourceLabels" (dict "root" .root "component" .labels) | nindent 4 }}
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
Topology spread constraints - component list takes precedence over the global list.
A non-empty component list fully replaces the global one; lists are not merged.
Usage: include "thoras.topologySpreadConstraints" (dict "root" . "component" .Values.thorasWorker.topologySpreadConstraints)
*/}}
{{- define "thoras.topologySpreadConstraints" -}}
{{- $constraints := .component | default .root.Values.topologySpreadConstraints }}
{{- with $constraints -}}
topologySpreadConstraints:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Scheduling constraints for the chart's hook jobs (webhook cert-gen, pre-delete).
Global nodeSelector and tolerations always apply, as they do on the deployments -
affinity alone cannot place a hook on a tainted node pool. Global affinity applies
only when the operator opts into it. The jobs are one-shot, so they carry neither a
default nor a component-specific affinity.
Usage:
  {{- with (include "thoras.hookJobScheduling" . | trim) }}
  {{- . | nindent 6 }}
  {{- end }}
*/}}
{{- define "thoras.hookJobScheduling" -}}
{{- with .Values.nodeSelector }}
nodeSelector:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- if .Values.thorasOperator.useGlobalAffinity }}
{{- with .Values.affinity }}
affinity:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Nil-safe thorasOperator.webhookCertGen.certManager.enabled ("true" or "").
Releases older than the certManager block (chart < 4.124.0) upgraded with
--reuse-values have no certManager key, so a direct traversal panics.
*/}}
{{- define "thoras.webhookCertManagerEnabled" -}}
{{- if ((.Values.thorasOperator.webhookCertGen).certManager).enabled -}}true{{- end -}}
{{- end -}}

{{/* Loopback port for nginx behind the oauth2-proxy sidecar. */}}
{{- define "thoras.dashboard.internalNginxPort" -}}8181{{- end -}}
