{{- define "b2c-observability.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "b2c-observability.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else if contains (include "b2c-observability.name" .) .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "b2c-observability.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Two workloads in one release, so names and selectors carry the component. */}}
{{- define "b2c-observability.prometheus.fullname" -}}
{{- printf "%s-prometheus" (include "b2c-observability.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "b2c-observability.grafana.fullname" -}}
{{- printf "%s-grafana" (include "b2c-observability.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "b2c-observability.commonLabels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: b2c
{{- end -}}

{{/*
Selector labels, per component. A Deployment's selector is immutable, so these
carry nothing that changes between upgrades -- no chart version, no app version.
*/}}
{{- define "b2c-observability.prometheus.selectorLabels" -}}
app.kubernetes.io/name: prometheus
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "b2c-observability.grafana.selectorLabels" -}}
app.kubernetes.io/name: grafana
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Grafana's datasource is derived, never configured -- see values.yaml. */}}
{{- define "b2c-observability.prometheusUrl" -}}
http://{{ include "b2c-observability.prometheus.fullname" . }}:{{ .Values.prometheus.service.port }}
{{- end -}}
