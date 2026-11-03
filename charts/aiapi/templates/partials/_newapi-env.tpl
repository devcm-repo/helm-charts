{{- define "aiapi.newapiEnv" -}}
{{- $sqlDsn := default .Values.newapi.sqlDsn .Values.newapi.database.dsn -}}
{{- $sqlDsnSecretName := .Values.newapi.database.existingSecret.name -}}
{{- $redisConnString := default .Values.newapi.redisConnString .Values.newapi.cache.redisConnString -}}
{{- $redisConnStringSecretName := .Values.newapi.cache.existingSecret.name -}}
{{- $postgresqlExistingSecret := dig "auth" "existingSecret" "" .Values.postgresql -}}
{{- $postgresqlPasswordKey := dig "auth" "secretKeys" "userPasswordKey" "password" .Values.postgresql -}}
{{- $valkeyExistingSecret := dig "auth" "existingSecret" "" .Values.valkey -}}
{{- $valkeyPasswordKey := dig "auth" "existingSecretPasswordKey" "valkey-password" .Values.valkey -}}
{{- if and (not .Values.postgresql.enabled) (empty $sqlDsn) (empty $sqlDsnSecretName) -}}
{{- fail "newapi.database.dsn or newapi.database.existingSecret.name is required when postgresql.enabled is false" -}}
{{- end -}}
{{- if and (not .Values.valkey.enabled) (empty $redisConnString) (empty $redisConnStringSecretName) -}}
{{- fail "newapi.cache.redisConnString or newapi.cache.existingSecret.name is required when valkey.enabled is false" -}}
{{- end -}}
- name: TZ
  value: {{ .Values.tz | quote }}
- name: SESSION_SECRET
  valueFrom:
    secretKeyRef:
      name: "{{ include "aiapi.fullname" . }}"
      key: newapi-session-secret
- name: FRONTEND_BASE_URL
  value: {{ include "aiapi.publicUrl" . | quote }}
{{- if $sqlDsnSecretName }}
- name: SQL_DSN
  valueFrom:
    secretKeyRef:
      name: {{ $sqlDsnSecretName | quote }}
      key: {{ default "SQL_DSN" .Values.newapi.database.existingSecret.key | quote }}
{{- else if $sqlDsn }}
- name: SQL_DSN
  value: {{ $sqlDsn | quote }}
{{- else }}
- name: POSTGRES_USER
  value: {{ .Values.postgresql.auth.username | quote }}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ default (include "aiapi.postgresql.fullname" .) $postgresqlExistingSecret | quote }}
      key: {{ $postgresqlPasswordKey | quote }}
- name: SQL_DSN
  value: "postgres://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@{{ include "aiapi.postgresql.fullname" . }}:5432/{{ .Values.postgresql.auth.database }}?sslmode=disable"
{{- end }}
{{- if $redisConnStringSecretName }}
- name: REDIS_CONN_STRING
  valueFrom:
    secretKeyRef:
      name: {{ $redisConnStringSecretName | quote }}
      key: {{ default "REDIS_CONN_STRING" .Values.newapi.cache.existingSecret.key | quote }}
{{- else if $redisConnString }}
- name: REDIS_CONN_STRING
  value: {{ $redisConnString | quote }}
{{- else }}
{{- if .Values.valkey.auth.enabled }}
- name: VALKEY_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ default (include "aiapi.dependencyFullname" (dict "root" . "values" .Values.valkey "name" "valkey")) $valkeyExistingSecret | quote }}
      key: {{ $valkeyPasswordKey | quote }}
- name: REDIS_CONN_STRING
  value: "redis://:$(VALKEY_PASSWORD)@{{ include "aiapi.valkey.primaryFullname" . }}:6379/0"
{{- else }}
- name: REDIS_CONN_STRING
  value: "redis://{{ include "aiapi.valkey.primaryFullname" . }}:6379/0"
{{- end }}
{{- end }}
{{- with .Values.newapi.extraEnv }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end -}}
