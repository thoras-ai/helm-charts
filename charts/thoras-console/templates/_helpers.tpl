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
