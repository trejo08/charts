{{/*
Expand the name of the chart.
*/}}
{{- define "marble.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "marble.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart label value.
*/}}
{{- define "marble.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "marble.labels" -}}
helm.sh/chart: {{ include "marble.chart" . }}
{{ include "marble.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "marble.selectorLabels" -}}
app.kubernetes.io/name: {{ include "marble.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .component }}
app.kubernetes.io/component: {{ .component }}
{{- end }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "marble.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "marble.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Deterministic secret name — always "<fullname>-secrets".
All deployments and the ExternalSecret use this same name.
*/}}
{{- define "marble.secretName" -}}
{{- printf "%s-secrets" (include "marble.fullname" .) }}
{{- end }}

{{/*
ExternalSecret apiVersion — auto-detected from cluster capabilities.
ESO >= 0.17.0 uses external-secrets.io/v1 (GA since v1.0.0, Nov 2025).
ESO < 0.17.0 uses external-secrets.io/v1beta1 (legacy).
*/}}
{{- define "marble.externalSecretApiVersion" -}}
{{- if .Capabilities.APIVersions.Has "external-secrets.io/v1" -}}
external-secrets.io/v1
{{- else -}}
external-secrets.io/v1beta1
{{- end -}}
{{- end }}

{{/*
Namespace — single source of truth.
When namespace.create=true the chart owns the namespace and uses namespace.name.
Otherwise falls back to .Release.Namespace (set by --namespace flag or ArgoCD destination).
*/}}
{{- define "marble.namespace" -}}
{{- if .Values.namespace.create -}}
{{- .Values.namespace.name -}}
{{- else -}}
{{- .Release.Namespace -}}
{{- end -}}
{{- end }}

{{/*
GCP service account JSON secret name — resolves which K8s Secret holds firebase.json.
Priority: gcpServiceAccountProperty (ESO-managed) > credentialsSecretName (externally managed).
Returns empty string when neither is configured (no volume mounted, GOOGLE_APPLICATION_CREDENTIALS not set).
*/}}
{{- define "marble.gcpSASecretName" -}}
{{- if .Values.marble.firebase.gcpServiceAccountProperty -}}
{{- printf "%s-firebase-sa" (include "marble.fullname" .) -}}
{{- else if .Values.marble.firebase.credentialsSecretName -}}
{{- .Values.marble.firebase.credentialsSecretName -}}
{{- end -}}
{{- end }}

{{/*
JWT signing key mount path — gate logic:

jwtSigningKeyProperty (default: "JWT_SIGNING_KEY_B64"):
  Controls which key in the remote secret contains the base64-encoded PEM.
  If empty → no second ExternalSecret is created, no volume is mounted, chart injects nothing.

AUTHENTICATION_JWT_SIGNING_KEY_FILE:
  If defined in the remote secret → arrives via envFrom and dictates the mount path.
  If NOT defined in the remote secret → chart injects it via env[] with default /secrets/jwt.pem.
  marble.auth.jwtSigningKeyFile overrides the mount path explicitly if set.

Result:
  - jwtSigningKeyProperty non-empty → return mount path (jwtSigningKeyFile override or /secrets/jwt.pem)
  - jwtSigningKeyProperty empty     → return empty (nothing mounted, nothing injected)
*/}}
{{- define "marble.jwtMountPath" -}}
{{- if .Values.marble.externalSecret.jwtSigningKeyProperty -}}
{{- if .Values.marble.auth.jwtSigningKeyFile -}}
{{- .Values.marble.auth.jwtSigningKeyFile -}}
{{- else -}}
/secrets/jwt.pem
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Secret management gate — fails loudly at render time if neither ESO nor an existing secret is configured.
*/}}
{{- define "marble.validateSecrets" -}}
{{- if and (not .Values.marble.externalSecret.enabled) (not .Values.marble.existingSecret.enabled) -}}
{{- fail "marble: secret configuration required. Set marble.externalSecret.enabled=true (with clusterSecretStore and remoteSecretName) or marble.existingSecret.enabled=true with a pre-existing K8s Secret named '<release>-secrets'." -}}
{{- end -}}
{{- if and .Values.marble.externalSecret.enabled (not .Values.marble.externalSecret.clusterSecretStore) -}}
{{- fail "marble: marble.externalSecret.clusterSecretStore is required when externalSecret.enabled=true." -}}
{{- end -}}
{{- if and .Values.marble.externalSecret.enabled (not .Values.marble.externalSecret.remoteSecretName) -}}
{{- fail "marble: marble.externalSecret.remoteSecretName is required when externalSecret.enabled=true." -}}
{{- end -}}
{{- end }}

{{/*
Backend envFrom — secret ref rendered as a separate block from env:.
*/}}
{{- define "marble.backendEnvFrom" -}}
{{- if or .Values.marble.externalSecret.enabled .Values.marble.existingSecret.enabled }}
- secretRef:
    name: {{ include "marble.secretName" . }}
{{- end }}
{{- end }}

{{/*
Backend env vars — shared by api, worker, analytics, and migrations.
*/}}
{{- define "marble.backendEnv" -}}
- name: PORT
  value: {{ .Values.marble.port | quote }}
- name: ENV
  value: {{ .Values.marble.env | quote }}
- name: APP_URL
  value: {{ .Values.marble.appUrl | quote }}
{{- if .Values.marble.apiUrl }}
- name: MARBLE_API_URL
  value: {{ .Values.marble.apiUrl | quote }}
{{- end }}
{{- if .Values.marble.licenseKey }}
- name: LICENSE_KEY
  value: {{ .Values.marble.licenseKey | quote }}
{{- end }}
- name: DISABLE_SEGMENT
  value: {{ .Values.marble.disableSegment | quote }}
- name: LOGGING_FORMAT
  value: {{ .Values.marble.loggingFormat | quote }}
{{- if .Values.marble.requestLoggingLevel }}
- name: REQUEST_LOGGING_LEVEL
  value: {{ .Values.marble.requestLoggingLevel | quote }}
{{- end }}
{{- if .Values.marble.postgres.connectionString }}
- name: PG_CONNECTION_STRING
  value: {{ .Values.marble.postgres.connectionString | quote }}
{{- else if .Values.marble.postgres.hostname }}
- name: PG_HOSTNAME
  value: {{ .Values.marble.postgres.hostname | quote }}
- name: PG_PORT
  value: {{ .Values.marble.postgres.port | quote }}
- name: PG_USER
  value: {{ .Values.marble.postgres.user | quote }}
- name: PG_PASSWORD
  value: {{ .Values.marble.postgres.password | quote }}
- name: PG_SSL_MODE
  value: {{ .Values.marble.postgres.sslMode | quote }}
{{- end }}
- name: PG_MAX_POOL_SIZE
  value: {{ .Values.marble.postgres.maxPoolSize | quote }}
{{- if .Values.marble.postgres.clientDbConfigSecretName }}
- name: CLIENT_DB_CONFIG_FILE
  value: {{ printf "%s/config.json" .Values.marble.postgres.clientDbConfigMountPath | quote }}
{{- end }}
{{- if .Values.marble.auth.jwtSigningKey }}
- name: AUTHENTICATION_JWT_SIGNING_KEY
  value: {{ .Values.marble.auth.jwtSigningKey | quote }}
{{- else }}
{{- $jwtPath := include "marble.jwtMountPath" . }}
{{- if $jwtPath }}
{{/* env[] takes precedence over envFrom[] — if AUTHENTICATION_JWT_SIGNING_KEY_FILE is also
     present in the remote secret it is overridden by this explicit value, which is correct. */}}
- name: AUTHENTICATION_JWT_SIGNING_KEY_FILE
  value: {{ $jwtPath | quote }}
{{- end }}
{{- end }}
{{- if .Values.marble.firebase.enabled }}
{{- if .Values.marble.firebase.apiKey }}
- name: FIREBASE_API_KEY
  value: {{ .Values.marble.firebase.apiKey | quote }}
{{- end }}
{{- if .Values.marble.firebase.projectId }}
- name: FIREBASE_PROJECT_ID
  value: {{ .Values.marble.firebase.projectId | quote }}
{{- end }}
{{- if .Values.marble.firebase.googleCloudProject }}
- name: GOOGLE_CLOUD_PROJECT
  value: {{ .Values.marble.firebase.googleCloudProject | quote }}
{{- end }}
{{- if .Values.marble.firebase.authDomain }}
- name: FIREBASE_AUTH_DOMAIN
  value: {{ .Values.marble.firebase.authDomain | quote }}
{{- end }}
{{- $gcpSASecret := include "marble.gcpSASecretName" . }}
{{- if $gcpSASecret }}
- name: GOOGLE_APPLICATION_CREDENTIALS
  value: {{ printf "%s/%s" .Values.marble.firebase.credentialsMountPath .Values.marble.firebase.credentialsKey | quote }}
{{- end }}
{{- end }}
{{- if .Values.marble.screeningIndexerToken }}
- name: SCREENING_INDEXER_TOKEN
  value: {{ .Values.marble.screeningIndexerToken | quote }}
{{- end }}
{{- if .Values.marble.oidc.enabled }}
- name: OIDC_ISSUER
  value: {{ .Values.marble.oidc.issuer | quote }}
- name: OIDC_CLIENT_ID
  value: {{ .Values.marble.oidc.clientId | quote }}
- name: OIDC_CLIENT_SECRET
  value: {{ .Values.marble.oidc.clientSecret | quote }}
- name: OIDC_SCOPE
  value: {{ .Values.marble.oidc.scope | quote }}
{{- if .Values.marble.oidc.allowedDomains }}
- name: OIDC_ALLOWED_DOMAINS
  value: {{ .Values.marble.oidc.allowedDomains | quote }}
{{- end }}
{{- end }}
{{- if .Values.marble.storage.ingestionBucketUrl }}
- name: INGESTION_BUCKET_URL
  value: {{ .Values.marble.storage.ingestionBucketUrl | quote }}
{{- end }}
{{- if .Values.marble.storage.caseManagerBucketUrl }}
- name: CASE_MANAGER_BUCKET_URL
  value: {{ .Values.marble.storage.caseManagerBucketUrl | quote }}
{{- end }}
{{- if .Values.marble.storage.analyticsBucketUrl }}
- name: ANALYTICS_BUCKET_URL
  value: {{ .Values.marble.storage.analyticsBucketUrl | quote }}
{{- end }}
{{- if .Values.marble.storage.offloading.enabled }}
- name: OFFLOAD_ENABLED
  value: "true"
- name: OFFLOAD_BUCKET_URL
  value: {{ .Values.marble.storage.offloading.bucketUrl | quote }}
- name: OFFLOAD_JOB_INTERVAL
  value: {{ .Values.marble.storage.offloading.jobInterval | quote }}
- name: OFFLOAD_BEFORE
  value: {{ .Values.marble.storage.offloading.before | quote }}
- name: OFFLOAD_BATCH_SIZE
  value: {{ .Values.marble.storage.offloading.batchSize | quote }}
- name: OFFLOAD_SAVE_PINS
  value: {{ .Values.marble.storage.offloading.savePins | quote }}
- name: OFFLOAD_WRITES_PER_SEC
  value: {{ .Values.marble.storage.offloading.writesPerSec | quote }}
{{- end }}
{{- if .Values.marble.bootstrap.orgName }}
- name: BOOTSTRAP_ORG_NAME
  value: {{ .Values.marble.bootstrap.orgName | quote }}
{{- end }}
{{- if .Values.marble.bootstrap.orgAdminEmail }}
- name: BOOTSTRAP_ORG_ADMIN_EMAIL
  value: {{ .Values.marble.bootstrap.orgAdminEmail | quote }}
{{- end }}
{{- if .Values.sanctions.enabled }}
{{- if .Values.sanctions.opensanctions.apiHost }}
- name: OPENSANCTIONS_API_HOST
  value: {{ .Values.sanctions.opensanctions.apiHost | quote }}
- name: OPENSANCTIONS_AUTH_METHOD
  value: {{ .Values.sanctions.opensanctions.authMethod | quote }}
{{- if .Values.sanctions.opensanctions.apiKey }}
- name: OPENSANCTIONS_API_KEY
  value: {{ .Values.sanctions.opensanctions.apiKey | quote }}
{{- end }}
{{- else }}
- name: OPENSANCTIONS_API_HOST
  value: {{ printf "http://%s-motiva:%d" (include "marble.fullname" .) (.Values.sanctions.motiva.port | int) | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Backend volumes — GCP SA JSON, JWT PEM, client DB config.
*/}}
{{- define "marble.backendVolumes" -}}
{{- $gcpSASecret := include "marble.gcpSASecretName" . }}
{{- if $gcpSASecret }}
- name: firebase-credentials
  secret:
    secretName: {{ $gcpSASecret }}
    items:
      - key: {{ .Values.marble.firebase.credentialsKey }}
        path: {{ .Values.marble.firebase.credentialsKey }}
{{- end }}
{{- $jwtPath := include "marble.jwtMountPath" . }}
{{- if $jwtPath }}
- name: jwt-signing-key
  secret:
    secretName: {{ include "marble.secretName" . }}-jwt
    items:
      - key: jwt.pem
        path: jwt.pem
{{- end }}
{{- if .Values.marble.postgres.clientDbConfigSecretName }}
- name: client-db-config
  secret:
    secretName: {{ .Values.marble.postgres.clientDbConfigSecretName }}
    items:
      - key: config.json
        path: config.json
{{- end }}
{{- end }}

{{/*
Backend volume mounts.
*/}}
{{- define "marble.backendVolumeMounts" -}}
{{- $gcpSASecret := include "marble.gcpSASecretName" . }}
{{- if $gcpSASecret }}
- name: firebase-credentials
  mountPath: {{ .Values.marble.firebase.credentialsMountPath }}
  readOnly: true
{{- end }}
{{- $jwtPath := include "marble.jwtMountPath" . }}
{{- if $jwtPath }}
- name: jwt-signing-key
  mountPath: {{ dir $jwtPath }}
  readOnly: true
{{- end }}
{{- if .Values.marble.postgres.clientDbConfigSecretName }}
- name: client-db-config
  mountPath: {{ .Values.marble.postgres.clientDbConfigMountPath }}
  readOnly: true
{{- end }}
{{- end }}
