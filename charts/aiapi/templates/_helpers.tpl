{{- define "aiapi.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "aiapi.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "aiapi.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "aiapi.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "aiapi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "aiapi.selectorLabels" -}}
app.kubernetes.io/name: {{ include "aiapi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "aiapi.dependencyFullname" -}}
{{- $root := index . "root" -}}
{{- $values := default dict (index . "values") -}}
{{- $name := default (index . "name") $values.nameOverride -}}
{{- if $values.fullnameOverride -}}
{{- $values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else if contains $name $root.Release.Name -}}
{{- $root.Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" $root.Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "aiapi.postgresql.fullname" -}}
{{- include "aiapi.dependencyFullname" (dict "root" . "values" .Values.postgresql "name" "postgresql") -}}
{{- end -}}

{{- define "aiapi.valkey.primaryFullname" -}}
{{- printf "%s-primary" (include "aiapi.dependencyFullname" (dict "root" . "values" .Values.valkey "name" "valkey")) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
