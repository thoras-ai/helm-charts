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
Simple auth env vars injected into every Thoras component. The enable flag is
always emitted so the components have an explicit "false"; the secret itself is
only bound when the flag is on. "prefix" is required and must be passed
explicitly (an empty string is falsey, so it cannot be defaulted): the Go
services read SERVICE_-prefixed vars, the forecaster reads them unprefixed.
Usage: {{- include "thoras.simpleAuthEnv" (dict "root" . "prefix" "SERVICE_") | nindent 10 }}
*/}}
{{- define "thoras.simpleAuthEnv" -}}
{{- $enabled := .root.Values.featureFlags.enableSimpleAuthSecret -}}
- name: {{ .prefix }}ENABLE_SIMPLE_AUTH_SECRET
  value: {{ $enabled | ternary "true" "false" | quote }}
{{- if $enabled }}
- name: {{ .prefix }}SIMPLE_AUTH_SECRET
  valueFrom:
    secretKeyRef:
      name: api-client-secret
      key: secret
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
