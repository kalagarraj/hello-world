{{/* Chart name, overridable with --set nameOverride */}}
{{- define "b2c-web.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Release-scoped resource name, so two releases in one namespace do not collide.
Collapses to the chart name when the release is called after the chart.
*/}}
{{- define "b2c-web.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else if contains (include "b2c-web.name" .) .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "b2c-web.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "b2c-web.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "b2c-web.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: web
app.kubernetes.io/part-of: b2c
{{- end -}}

{{/* Only these two go in the Deployment's selector: a selector is immutable. */}}
{{- define "b2c-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "b2c-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Which Secret the pod reads: yours if you brought one, otherwise ours. */}}
{{- define "b2c-web.secretName" -}}
{{- default (include "b2c-web.fullname" .) .Values.existingSecret -}}
{{- end -}}

{{/*
The session secret, in order of preference: the value you set, the one already
in the cluster from a previous install, or a fresh random string. Reusing the
installed one matters -- regenerating it on every `helm upgrade` would sign
every user out. `lookup` returns nothing during `helm template`, so rendering
without a cluster always shows a fresh value; that is expected.
*/}}
{{- define "b2c-web.sessionSecret" -}}
{{- if .Values.sessionSecret -}}
{{- .Values.sessionSecret -}}
{{- else -}}
{{- $existing := lookup "v1" "Secret" .Release.Namespace (include "b2c-web.fullname" .) -}}
{{- if and $existing $existing.data (index $existing.data "SESSION_SECRET") -}}
{{- index $existing.data "SESSION_SECRET" | b64dec -}}
{{- else -}}
{{- randAlphaNum 32 -}}
{{- end -}}
{{- end -}}
{{- end -}}
