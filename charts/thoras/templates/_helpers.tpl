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

{{/*
Default affinity for thorasForecast - anti-affinity with metrics-collector and self
*/}}
{{- define "thoras.thorasForecast.defaultAffinity" -}}
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      labelSelector:
        matchExpressions:
        - key: app
          operator: In
          values:
          - metrics-collector
      topologyKey: kubernetes.io/hostname
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
Cluster pod count via lookup. Returns 0 when the dynamic-sizing feature flag is off,
or when lookup is unavailable (--dry-run, helm template, no RBAC). Caller treats 0
as "use fallback".
*/}}
{{- define "thoras.cluster.podCount" -}}
{{- if not .Values.featureFlags.dynamicResourceSizing.enabled -}}
0
{{- else -}}
{{- $pods := lookup "v1" "Pod" "" "" -}}
{{- if and $pods (kindIs "map" $pods) (hasKey $pods "items") -}}
{{- len $pods.items -}}
{{- else -}}
0
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Cluster workload count = Deployments + StatefulSets + Argo Rollouts.
Rollouts are guarded: if the CRD is not present, count 0 rollouts.
Returns 0 when the feature flag is off or lookup is unavailable.
*/}}
{{- define "thoras.cluster.workloadCount" -}}
{{- if not .Values.featureFlags.dynamicResourceSizing.enabled -}}
0
{{- else -}}
{{- $deploys := lookup "apps/v1" "Deployment" "" "" -}}
{{- $sts := lookup "apps/v1" "StatefulSet" "" "" -}}
{{- $deployCount := 0 -}}
{{- $stsCount := 0 -}}
{{- if and $deploys (hasKey $deploys "items") -}}{{- $deployCount = len $deploys.items -}}{{- end -}}
{{- if and $sts (hasKey $sts "items") -}}{{- $stsCount = len $sts.items -}}{{- end -}}
{{- $rolloutCount := 0 -}}
{{- $crd := lookup "apiextensions.k8s.io/v1" "CustomResourceDefinition" "" "rollouts.argoproj.io" -}}
{{- if $crd -}}
{{- $rollouts := lookup "argoproj.io/v1alpha1" "Rollout" "" "" -}}
{{- if and $rollouts (hasKey $rollouts "items") -}}{{- $rolloutCount = len $rollouts.items -}}{{- end -}}
{{- end -}}
{{- add $deployCount $stsCount $rolloutCount -}}
{{- end -}}
{{- end -}}

{{/*
Compute memory request bytes from cluster state using the configured coefficients.
Returns "" when the feature flag is off or both counts are 0 (caller substitutes
the per-component fallback).
*/}}
{{- define "thoras.sizing.memoryRequestBytes" -}}
{{- if .Values.featureFlags.dynamicResourceSizing.enabled -}}
{{- $pods := include "thoras.cluster.podCount" . | int -}}
{{- $workloads := include "thoras.cluster.workloadCount" . | int -}}
{{- if or (gt $pods 0) (gt $workloads 0) -}}
{{- $cfg := .Values.featureFlags.dynamicResourceSizing.memoryRequest -}}
{{- $perPodBytes := mulf $cfg.perPodKB 1024.0 -}}
{{- $perWorkloadBytes := mulf $cfg.perWorkloadKB 1024.0 -}}
{{- $baseBytes := mulf $cfg.baseMB 1048576.0 -}}
{{- $bytes := addf (mulf $perPodBytes $pods) (mulf $perWorkloadBytes $workloads) $baseBytes -}}
{{- printf "%d" (int64 $bytes) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Auto-sized memory request for thoras-api-server-v2. Falls back to
.Values.thorasApiServerV2.requests.memory when the formula has no cluster data.
*/}}
{{- define "thoras.apiServerV2.memoryRequest" -}}
{{- $computed := include "thoras.sizing.memoryRequestBytes" . -}}
{{- if $computed -}}{{- $computed -}}{{- else -}}{{- .Values.thorasApiServerV2.requests.memory -}}{{- end -}}
{{- end -}}

{{/*
Auto-sized memory request for thoras-operator. Falls back to
.Values.thorasOperator.requests.memory when the formula has no cluster data.
*/}}
{{- define "thoras.operator.memoryRequest" -}}
{{- $computed := include "thoras.sizing.memoryRequestBytes" . -}}
{{- if $computed -}}{{- $computed -}}{{- else -}}{{- .Values.thorasOperator.requests.memory -}}{{- end -}}
{{- end -}}

{{/*
Auto-sized memory request for thoras-worker. Falls back to
.Values.thorasWorker.requests.memory when the formula has no cluster data.
*/}}
{{- define "thoras.worker.memoryRequest" -}}
{{- $computed := include "thoras.sizing.memoryRequestBytes" . -}}
{{- if $computed -}}{{- $computed -}}{{- else -}}{{- .Values.thorasWorker.requests.memory -}}{{- end -}}
{{- end -}}

{{/*
Auto-scaled forecast-worker replicas. When the feature flag is off, returns the
configured .Values.thorasForecast.worker.replicas verbatim. When on, returns
ceil(workloadCount / workloadsPerForecastWorker) floored at the configured replicas.
*/}}
{{- define "thoras.forecastWorker.replicas" -}}
{{- $configured := .Values.thorasForecast.worker.replicas | int -}}
{{- if not .Values.featureFlags.dynamicResourceSizing.enabled -}}
{{- $configured -}}
{{- else -}}
{{- $workloads := include "thoras.cluster.workloadCount" . | int -}}
{{- $perWorker := .Values.featureFlags.dynamicResourceSizing.workloadsPerForecastWorker | int -}}
{{- $derived := 0 -}}
{{- if and (gt $workloads 0) (gt $perWorker 0) -}}
{{- $derived = div (add $workloads (sub $perWorker 1)) $perWorker -}}
{{- end -}}
{{- if gt $derived $configured -}}
{{- $derived -}}
{{- else -}}
{{- $configured -}}
{{- end -}}
{{- end -}}
{{- end -}}
