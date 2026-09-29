{{- define "openshift-observability.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "openshift-observability.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "openshift-observability.labels" -}}
helm.sh/chart: {{ include "openshift-observability.chart" . }}
app.kubernetes.io/name: {{ include "openshift-observability.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: openshift-observability
{{- end -}}

{{- define "openshift-observability.dnsName" -}}
{{- if gt (len .) 63 -}}
{{- fail (printf "name %q is longer than 63 characters" .) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" .) -}}
{{- fail (printf "name %q must be a DNS-1123 label" .) -}}
{{- end -}}
{{- . -}}
{{- end -}}

{{/*
One metrics_list.yaml section. Caller passes a list: title, value.
*/}}
{{- define "openshift-observability.metricsSection" -}}
{{- printf "%s:\n%s\n" (index . 0) (trimSuffix "\n" (toYaml (index . 1) | indent 2)) -}}
{{- end -}}

{{/*
Standard metadata. Caller passes a dict: name, namespace, root, component, labels, annotations.
*/}}
{{- define "openshift-observability.metadata" -}}
metadata:
  name: {{ include "openshift-observability.dnsName" .name }}
  {{- with .namespace }}
  namespace: {{ . }}
  {{- end }}
  labels:
    {{- include "openshift-observability.labels" .root | nindent 4 }}
    app.kubernetes.io/component: {{ .component | quote }}
    {{- range $key, $value := .labels }}
    {{ $key }}: {{ $value | quote }}
    {{- end }}
  {{- with .annotations }}
  annotations:
    {{- range $key, $value := . }}
    {{ $key }}: {{ $value | quote }}
    {{- end }}
  {{- end }}
{{- end -}}
