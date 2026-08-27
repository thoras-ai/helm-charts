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
Secret+key that carries the shared api-client secret. Returns the user's
existingSecret when configured, else the centralized `thoras-shared` Secret.
Usage: {{- $ref := include "thoras.apiClientSecretRef" . | fromYaml }}
*/}}
{{- define "thoras.apiClientSecretRef" -}}
{{- if .Values.apiClientSecret.existingSecret.secretName -}}
name: {{ .Values.apiClientSecret.existingSecret.secretName }}
key: {{ .Values.apiClientSecret.existingSecret.secretKey }}
{{- else -}}
name: thoras-shared
key: api-client-secret
{{- end -}}
{{- end -}}

{{/*
Body of the centralized `thoras-shared` Secret. Rotating a value pinned in
this Secret requires a manual `kubectl rollout restart` of dependent
workloads - the chart does not add a rotation checksum. See README >
"Rotating chart-managed credentials".
*/}}
{{- define "thoras.sharedSecret" -}}
{{- $auth := .Values.thorasDashboard.auth -}}
{{- $htpasswdMode := eq $auth.mode "htpasswd" -}}
{{- $apiClientEnabled := and (eq (include "thoras.apiClientEnabled" .) "true") (not .Values.apiClientSecret.existingSecret.secretName) -}}
{{- $dashboardAuthEnabled := and .Values.thorasDashboard.enabled $auth.enabled $htpasswdMode (not $auth.htpasswd.existingSecret.secretName) -}}
{{- if or $apiClientEnabled $dashboardAuthEnabled }}
{{- $sharedSecret := (lookup "v1" "Secret" .Release.Namespace "thoras-shared") }}
{{- $sharedData := (get $sharedSecret "data") | default dict }}
---
apiVersion: v1
kind: Secret
metadata:
  name: thoras-shared
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "thoras.resourceLabels" (dict "root" . "component" dict) | nindent 4 }}
data:
  {{- if $apiClientEnabled }}
  {{- $legacyApiClient := (lookup "v1" "Secret" .Release.Namespace "api-client-secret") }}
  {{- $legacyApiClientData := (get $legacyApiClient "data") | default dict }}
  {{- $apiClient := "" }}

  {{- /* pinned in values */}}
  {{- if .Values.apiClientSecret.secret }}
  {{- $apiClient = .Values.apiClientSecret.secret | b64enc }}

  {{- /* preserve existing thoras-shared value */}}
  {{- else if hasKey $sharedData "api-client-secret" }}
  {{- $apiClient = index $sharedData "api-client-secret" }}

  {{- /* legacy per-key Secret (pre thoras-shared) */}}
  {{- else if hasKey $legacyApiClientData "secret" }}
  {{- $apiClient = index $legacyApiClientData "secret" }}

  {{- /* first install: generate */}}
  {{- else }}
  {{- $apiClient = randAlphaNum 32 | b64enc }}
  {{- end }}
  api-client-secret: {{ $apiClient | quote }}
  {{- end }}

  {{- if $dashboardAuthEnabled }}
  {{- $legacyDash := (lookup "v1" "Secret" .Release.Namespace "thoras-dashboard-auth") }}
  {{- $legacyDashData := (get $legacyDash "data") | default dict }}
  {{- $password := "" }}

  {{- /* pinned in values */}}
  {{- if $auth.htpasswd.password }}
  {{- $password = $auth.htpasswd.password | b64enc }}

  {{- /* preserve existing thoras-shared value */}}
  {{- else if hasKey $sharedData "dashboard-auth-password" }}
  {{- $password = index $sharedData "dashboard-auth-password" }}

  {{- /* legacy per-key Secret (pre thoras-shared) */}}
  {{- else if hasKey $legacyDashData "password" }}
  {{- $password = index $legacyDashData "password" }}

  {{- /* first install: generate */}}
  {{- else }}
  {{- $password = randAlphaNum 24 | b64enc }}
  {{- end }}

  {{- $cookieSecret := "" }}

  {{- /* pinned in values */}}
  {{- if $auth.htpasswd.cookieSecret }}
  {{- $cookieSecret = $auth.htpasswd.cookieSecret | b64enc }}

  {{- /* preserve existing thoras-shared value */}}
  {{- else if hasKey $sharedData "dashboard-auth-cookie-secret" }}
  {{- $cookieSecret = index $sharedData "dashboard-auth-cookie-secret" }}

  {{- /* legacy per-key Secret (pre thoras-shared) */}}
  {{- else if hasKey $legacyDashData "cookie-secret" }}
  {{- $cookieSecret = index $legacyDashData "cookie-secret" }}

  {{- /* first install: generate */}}
  {{- else }}
  {{- $cookieSecret = randAlphaNum 32 | b64enc }}
  {{- end }}
  dashboard-auth-password: {{ $password | quote }}
  dashboard-auth-cookie-secret: {{ $cookieSecret | quote }}
  {{- end }}
{{- end }}
{{- end }}

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
