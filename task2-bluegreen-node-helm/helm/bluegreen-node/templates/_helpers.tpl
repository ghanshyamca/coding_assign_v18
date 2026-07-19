{{/*
Chart name.
*/}}
{{- define "bluegreen-node.name" -}}
{{- default .Chart.Name .Values.appName | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fullname for a colored release. Uses the app base name and the color suffix so
resource names are deterministic (bluegreen-node-blue / bluegreen-node-green)
regardless of the Helm release name, letting app-blue / app-green coexist.
*/}}
{{- define "bluegreen-node.fullname" -}}
{{- $base := include "bluegreen-node.name" . -}}
{{- if .Values.nameSuffix -}}
{{- printf "%s-%s" $base .Values.nameSuffix | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $base | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Stable production Service name — shared across colors, never suffixed.
*/}}
{{- define "bluegreen-node.productionServiceName" -}}
{{- printf "%s-active" .Values.appName | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "bluegreen-node.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "bluegreen-node.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end -}}

{{/*
Selector labels for a colored Deployment / preview Service. Includes the
`track` label so blue and green pods are distinguishable.
*/}}
{{- define "bluegreen-node.selectorLabels" -}}
app.kubernetes.io/name: {{ include "bluegreen-node.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
track: {{ .Values.track }}
{{- end -}}

{{/*
ServiceAccount name.
*/}}
{{- define "bluegreen-node.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "bluegreen-node.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
