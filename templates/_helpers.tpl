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
Allowlist document body. Caller passes names, matches, and recordingRules.
Empty when none of those are set.
*/}}
{{- define "openshift-observability.allowlistBody" -}}
{{- $out := "" -}}
{{- if .names -}}
{{- $out = include "openshift-observability.metricsSection" (list "names" .names) -}}
{{- end -}}
{{- if .matches -}}
{{- $out = printf "%s%s" $out (include "openshift-observability.metricsSection" (list "matches" .matches)) -}}
{{- end -}}
{{- if .recordingRules -}}
{{- $out = printf "%s%s" $out (include "openshift-observability.metricsSection" (list "recording_rules" .recordingRules)) -}}
{{- end -}}
{{- $out -}}
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

{{/*
Release-scoped name for the cluster-monitoring label ServiceAccount and RBAC.
*/}}
{{- define "openshift-observability.clusterMonitoringLabel.base" -}}
{{- printf "%s-cluster-monitoring-label" .Release.Name | trunc 50 | trimSuffix "-" -}}
{{- end -}}

{{- define "openshift-observability.clusterMonitoringLabel.serviceAccount" -}}
{{- include "openshift-observability.dnsName" (include "openshift-observability.clusterMonitoringLabel.base" .) -}}
{{- end -}}

{{- define "openshift-observability.clusterMonitoringLabel.bootstrapName" -}}
{{- include "openshift-observability.dnsName" (printf "%s-bootstrap" (include "openshift-observability.clusterMonitoringLabel.base" .) | trunc 63 | trimSuffix "-") -}}
{{- end -}}

{{- define "openshift-observability.clusterMonitoringLabel.cronjobName" -}}
{{- include "openshift-observability.dnsName" (printf "%s-cronjob" (include "openshift-observability.clusterMonitoringLabel.base" .) | trunc 63 | trimSuffix "-") -}}
{{- end -}}

{{/*
ose-cli-rhel9 provides oc. Repository and tag stay separate, as in vp-manage-proxy-cluster-ca.
*/}}
{{- define "openshift-observability.clusterMonitoringLabel.imageRepository" -}}
{{- .Values.clusterMonitoringLabel.image.repository | default "registry.redhat.io/openshift4/ose-cli-rhel9" -}}
{{- end -}}

{{- define "openshift-observability.clusterMonitoringLabel.imageTag" -}}
{{- .Values.clusterMonitoringLabel.image.tag | default "v4.22" -}}
{{- end -}}

{{- define "openshift-observability.clusterMonitoringLabel.imagePullPolicy" -}}
{{- .Values.clusterMonitoringLabel.image.pullPolicy | default "IfNotPresent" -}}
{{- end -}}

{{- define "openshift-observability.monitoringLabel.policyName" -}}
{{- include "openshift-observability.dnsName" (printf "%s-monitoring-label" .Release.Name | trunc 63 | trimSuffix "-") -}}
{{- end -}}

{{/*
NooBaa ObjectBucketClaim path. Writes thanos.yaml and skips the ExternalSecret.
*/}}
{{- define "openshift-observability.noobaa.enabled" -}}
{{- if and .Values.acmObservability.multiClusterObservability.enabled .Values.acmObservability.multiClusterObservability.metricObjectStorage.noobaa.enabled -}}
true
{{- end -}}
{{- end -}}

{{- define "openshift-observability.noobaa.base" -}}
{{- printf "%s-noobaa" .Release.Name | trunc 50 | trimSuffix "-" -}}
{{- end -}}

{{- define "openshift-observability.noobaa.serviceAccount" -}}
{{- include "openshift-observability.dnsName" (include "openshift-observability.noobaa.base" .) -}}
{{- end -}}

{{- define "openshift-observability.noobaa.bootstrapName" -}}
{{- include "openshift-observability.dnsName" (printf "%s-bootstrap" (include "openshift-observability.noobaa.base" .) | trunc 63 | trimSuffix "-") -}}
{{- end -}}

{{- define "openshift-observability.noobaa.cronjobName" -}}
{{- include "openshift-observability.dnsName" (printf "%s-cronjob" (include "openshift-observability.noobaa.base" .) | trunc 63 | trimSuffix "-") -}}
{{- end -}}

{{- define "openshift-observability.noobaa.scriptName" -}}
{{- include "openshift-observability.dnsName" (printf "%s-script" (include "openshift-observability.noobaa.base" .) | trunc 63 | trimSuffix "-") -}}
{{- end -}}

{{- define "openshift-observability.noobaa.targetNamespace" -}}
{{- include "openshift-observability.dnsName" .Values.acmObservability.namespace -}}
{{- end -}}

{{- define "openshift-observability.noobaa.claimNamespace" -}}
{{- $configured := .Values.acmObservability.multiClusterObservability.metricObjectStorage.noobaa.namespace -}}
{{- if $configured -}}
{{- include "openshift-observability.dnsName" $configured -}}
{{- else -}}
{{- include "openshift-observability.noobaa.targetNamespace" . -}}
{{- end -}}
{{- end -}}

{{- define "openshift-observability.noobaa.claimName" -}}
{{- include "openshift-observability.dnsName" .Values.acmObservability.multiClusterObservability.metricObjectStorage.noobaa.name -}}
{{- end -}}

{{- define "openshift-observability.noobaa.imageRepository" -}}
{{- .Values.acmObservability.multiClusterObservability.metricObjectStorage.noobaa.image.repository | default "registry.redhat.io/openshift4/ose-cli-rhel9" -}}
{{- end -}}

{{- define "openshift-observability.noobaa.imageTag" -}}
{{- .Values.acmObservability.multiClusterObservability.metricObjectStorage.noobaa.image.tag | default "v4.22" -}}
{{- end -}}

{{- define "openshift-observability.noobaa.imagePullPolicy" -}}
{{- .Values.acmObservability.multiClusterObservability.metricObjectStorage.noobaa.image.pullPolicy | default "IfNotPresent" -}}
{{- end -}}

{{/*
Platform name. clusterPlatform wins when set, so a values file can override the
global.clusterPlatform Helm parameter injected by the patterns operator.
*/}}
{{- define "openshift-observability.platform" -}}
{{- $global := .Values.global | default dict -}}
{{- $fromGlobal := "" -}}
{{- if kindIs "map" $global -}}
{{- $fromGlobal = index $global "clusterPlatform" | default "" -}}
{{- end -}}
{{- .Values.clusterPlatform | default $fromGlobal | trim | lower -}}
{{- end -}}

{{/*
StatefulSet storage class for MultiClusterObservability.
AWS, Azure, and GCP have defaults. Every other platform has none unless
acmObservability.multiClusterObservability.storageClassName is set.
*/}}
{{- define "openshift-observability.acm.storageClassName" -}}
{{- if .Values.acmObservability.multiClusterObservability.storageClassName -}}
{{- .Values.acmObservability.multiClusterObservability.storageClassName -}}
{{- else -}}
{{- $platform := include "openshift-observability.platform" . -}}
{{- if eq $platform "aws" -}}
gp3-csi
{{- else if eq $platform "azure" -}}
managed-csi
{{- else if eq $platform "gcp" -}}
standard-csi
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Storage class for the Thanos Ruler PVC.
AWS, Azure, and GCP have defaults. Every other platform has none unless
monitoring.thanos.storageClassName is set.
*/}}
{{- define "openshift-observability.thanos.storageClassName" -}}
{{- if .Values.monitoring.thanos.enabled -}}
{{- if .Values.monitoring.thanos.storageClassName -}}
{{- .Values.monitoring.thanos.storageClassName -}}
{{- else -}}
{{- $platform := include "openshift-observability.platform" . -}}
{{- if eq $platform "aws" -}}
gp3-csi
{{- else if eq $platform "azure" -}}
managed-csi
{{- else if eq $platform "gcp" -}}
standard-csi
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
YAML for user-workload-monitoring-config. Empty when there is nothing to apply.
*/}}
{{- define "openshift-observability.userWorkload.config" -}}
{{- $thanosClass := include "openshift-observability.thanos.storageClassName" . | trim -}}
{{- $base := dict -}}
{{- if .Values.monitoring.userWorkload.namespacesWithoutLabelEnforcement -}}
{{- $_ := set $base "namespacesWithoutLabelEnforcement" .Values.monitoring.userWorkload.namespacesWithoutLabelEnforcement -}}
{{- end -}}
{{- if $thanosClass -}}
{{- $spec := dict "storageClassName" $thanosClass "resources" (dict "requests" (dict "storage" .Values.monitoring.thanos.storage)) -}}
{{- $_ := set $base "thanosRuler" (dict "volumeClaimTemplate" (dict "spec" $spec)) -}}
{{- end -}}
{{- $extra := fromYaml (toYaml (default (dict) .Values.monitoring.userWorkload.config)) | default dict -}}
{{- $cfg := mergeOverwrite $base $extra -}}
{{- if $cfg -}}
{{- toYaml $cfg -}}
{{- end -}}
{{- end -}}

{{/*
true when the chart should turn on user workload monitoring and apply its config.
monitoring.cluster.config.enableUserWorkload false suppresses that.
*/}}
{{- define "openshift-observability.userWorkload.shouldApply" -}}
{{- $uw := include "openshift-observability.userWorkload.config" . | trim -}}
{{- if $uw -}}
{{- $enable := true -}}
{{- $extra := fromYaml (toYaml (default (dict) .Values.monitoring.cluster.config)) | default dict -}}
{{- if hasKey $extra "enableUserWorkload" -}}
{{- $enable = index $extra "enableUserWorkload" -}}
{{- end -}}
{{- if $enable }}true{{- end -}}
{{- end -}}
{{- end -}}

{{- define "openshift-observability.userWorkload.base" -}}
{{- printf "%s-uwm" .Release.Name | trunc 50 | trimSuffix "-" -}}
{{- end -}}

{{- define "openshift-observability.userWorkload.serviceAccount" -}}
{{- include "openshift-observability.dnsName" (include "openshift-observability.userWorkload.base" .) -}}
{{- end -}}

{{- define "openshift-observability.userWorkload.desiredName" -}}
{{- include "openshift-observability.dnsName" (printf "%s-desired" (include "openshift-observability.userWorkload.base" .) | trunc 63 | trimSuffix "-") -}}
{{- end -}}

{{- define "openshift-observability.userWorkload.bootstrapName" -}}
{{- include "openshift-observability.dnsName" (printf "%s-bootstrap" (include "openshift-observability.userWorkload.base" .) | trunc 63 | trimSuffix "-") -}}
{{- end -}}

{{- define "openshift-observability.userWorkload.cronjobName" -}}
{{- include "openshift-observability.dnsName" (printf "%s-cronjob" (include "openshift-observability.userWorkload.base" .) | trunc 63 | trimSuffix "-") -}}
{{- end -}}

{{/*
true when a Job should merge cluster-monitoring-config.
User workload monitoring needs enableUserWorkload, so that path is included.
*/}}
{{- define "openshift-observability.clusterConfig.shouldApply" -}}
{{- if .Values.monitoring.cluster.enabled -}}
true
{{- else -}}
{{- include "openshift-observability.userWorkload.shouldApply" . -}}
{{- end -}}
{{- end -}}

{{- define "openshift-observability.clusterConfig.base" -}}
{{- printf "%s-cluster-monitoring" .Release.Name | trunc 45 | trimSuffix "-" -}}
{{- end -}}

{{- define "openshift-observability.clusterConfig.desiredName" -}}
{{- include "openshift-observability.dnsName" (printf "%s-desired" (include "openshift-observability.clusterConfig.base" .) | trunc 63 | trimSuffix "-") -}}
{{- end -}}

{{- define "openshift-observability.clusterConfig.scriptName" -}}
{{- include "openshift-observability.dnsName" (printf "%s-merge" (include "openshift-observability.clusterConfig.base" .) | trunc 63 | trimSuffix "-") -}}
{{- end -}}

{{/*
Fragment merged into cluster-monitoring-config. This is not the live object.
*/}}
{{- define "openshift-observability.clusterConfig.yaml" -}}
{{- $apply := include "openshift-observability.userWorkload.shouldApply" . | trim -}}
{{- $extra := fromYaml (toYaml (default (dict) .Values.monitoring.cluster.config)) | default dict -}}
{{- $enable := .Values.monitoring.cluster.enableUserWorkload -}}
{{- if $apply -}}
{{- $enable = true -}}
{{- end -}}
{{- toYaml (mergeOverwrite (dict "enableUserWorkload" $enable) $extra) -}}
{{- end -}}

{{/*
Pod template shared by the monitoring merge Job and CronJob.
The cluster fragment is merged first. User workload config is merged after
Cluster Monitoring Operator creates openshift-user-workload-monitoring.
*/}}
{{- define "openshift-observability.userWorkload.podTemplate" -}}
metadata:
  labels:
    {{- include "openshift-observability.labels" . | nindent 4 }}
    app.kubernetes.io/component: user-workload-monitoring
  annotations:
    openshift.io/required-scc: restricted-v2
spec:
  restartPolicy: Never
  serviceAccountName: {{ include "openshift-observability.userWorkload.serviceAccount" . }}
  automountServiceAccountToken: true
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  volumes:
    - name: merge
      configMap:
        name: {{ include "openshift-observability.clusterConfig.scriptName" . }}
    - name: cluster
      configMap:
        name: {{ include "openshift-observability.clusterConfig.desiredName" . }}
    {{- if include "openshift-observability.userWorkload.shouldApply" . | trim }}
    - name: uwm
      configMap:
        name: {{ include "openshift-observability.userWorkload.desiredName" . }}
    {{- end }}
    - name: tmp
      emptyDir: {}
  containers:
    - name: apply
      image: {{ printf "%s:%s" (include "openshift-observability.clusterMonitoringLabel.imageRepository" .) (include "openshift-observability.clusterMonitoringLabel.imageTag" .) | quote }}
      imagePullPolicy: {{ include "openshift-observability.clusterMonitoringLabel.imagePullPolicy" . }}
      env:
        - name: HOME
          value: /tmp
        - name: PYTHONDONTWRITEBYTECODE
          value: "1"
        - name: TARGET_NAMESPACE
          value: openshift-user-workload-monitoring
        - name: TARGET_NAME
          value: user-workload-monitoring-config
        - name: WAIT_SECONDS
          value: {{ .Values.monitoring.userWorkload.waitSeconds | quote }}
      command:
        - /bin/bash
        - -c
        - |
          set -euo pipefail
          if command -v oc >/dev/null 2>&1; then
            CLI=oc
          else
            CLI=kubectl
          fi
          export CLI
          merge_config() {
            local namespace="$1"
            local name="$2"
            local file="$3"
            if [[ ! -s "$file" ]]; then
              return 0
            fi
            TARGET_NAMESPACE="$namespace" TARGET_NAME="$name" DESIRED_FILE="$file" \
              python3 -B /etc/merge/merge.py
          }
          merge_config openshift-monitoring cluster-monitoring-config /etc/cluster/config.yaml
          if [[ -f /etc/uwm/config.yaml ]]; then
            deadline=$((SECONDS + WAIT_SECONDS))
            until "$CLI" get namespace "$TARGET_NAMESPACE" >/dev/null 2>&1; do
              if (( SECONDS >= deadline )); then
                echo "timed out waiting for namespace $TARGET_NAMESPACE" >&2
                exit 1
              fi
              echo "waiting for namespace $TARGET_NAMESPACE"
              sleep 10
            done
            merge_config "$TARGET_NAMESPACE" "$TARGET_NAME" /etc/uwm/config.yaml
          fi
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        capabilities:
          drop:
            - ALL
      resources:
        requests:
          cpu: 10m
          memory: 64Mi
        limits:
          cpu: 100m
          memory: 256Mi
      volumeMounts:
        - name: merge
          mountPath: /etc/merge
          readOnly: true
        - name: cluster
          mountPath: /etc/cluster
          readOnly: true
        {{- if include "openshift-observability.userWorkload.shouldApply" . | trim }}
        - name: uwm
          mountPath: /etc/uwm
          readOnly: true
        {{- end }}
        - name: tmp
          mountPath: /tmp
{{- end -}}

{{/*
Pod template shared by the bootstrap Job and the CronJob.
*/}}
{{- define "openshift-observability.clusterMonitoringLabel.podTemplate" -}}
metadata:
  labels:
    {{- include "openshift-observability.labels" . | nindent 4 }}
    app.kubernetes.io/component: cluster-monitoring-label
  annotations:
    openshift.io/required-scc: restricted-v2
spec:
  restartPolicy: Never
  serviceAccountName: {{ include "openshift-observability.clusterMonitoringLabel.serviceAccount" . }}
  automountServiceAccountToken: true
  securityContext:
    # OpenShift restricted SCC assigns the UID from the namespace range.
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  volumes:
    - name: tmp
      emptyDir: {}
  containers:
    - name: label
      image: {{ printf "%s:%s" (include "openshift-observability.clusterMonitoringLabel.imageRepository" .) (include "openshift-observability.clusterMonitoringLabel.imageTag" .) | quote }}
      imagePullPolicy: {{ include "openshift-observability.clusterMonitoringLabel.imagePullPolicy" . }}
      env:
        - name: HOME
          value: /tmp
        - name: NAMESPACE
          value: {{ .Values.clusterMonitoringLabel.namespace | quote }}
        - name: LABEL_KEY
          value: {{ .Values.clusterMonitoringLabel.key | quote }}
        - name: LABEL_VALUE
          value: {{ .Values.clusterMonitoringLabel.value | quote }}
      command:
        - /bin/bash
        - -c
        - |
          set -euo pipefail
          if command -v oc >/dev/null 2>&1; then
            cli=oc
          else
            cli=kubectl
          fi
          "$cli" label namespace "$NAMESPACE" "${LABEL_KEY}=${LABEL_VALUE}" --overwrite
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        capabilities:
          drop:
            - ALL
      resources:
        requests:
          cpu: 10m
          memory: 64Mi
        limits:
          cpu: 100m
          memory: 256Mi
      volumeMounts:
        - name: tmp
          mountPath: /tmp
{{- end -}}

{{/*
Pod template shared by the NooBaa bucket bootstrap Job and CronJob.
*/}}
{{- define "openshift-observability.noobaa.podTemplate" -}}
metadata:
  labels:
    {{- include "openshift-observability.labels" . | nindent 4 }}
    app.kubernetes.io/component: noobaa-bucket
  annotations:
    openshift.io/required-scc: restricted-v2
spec:
  restartPolicy: Never
  serviceAccountName: {{ include "openshift-observability.noobaa.serviceAccount" . }}
  automountServiceAccountToken: true
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  volumes:
    - name: script
      configMap:
        name: {{ include "openshift-observability.noobaa.scriptName" . }}
    - name: tmp
      emptyDir: {}
  containers:
    - name: bucket
      image: {{ printf "%s:%s" (include "openshift-observability.noobaa.imageRepository" .) (include "openshift-observability.noobaa.imageTag" .) | quote }}
      imagePullPolicy: {{ include "openshift-observability.noobaa.imagePullPolicy" . }}
      env:
        - name: HOME
          value: /tmp
        - name: PYTHONDONTWRITEBYTECODE
          value: "1"
        - name: CLAIM_NAMESPACE
          value: {{ include "openshift-observability.noobaa.claimNamespace" . | quote }}
        - name: CLAIM_NAME
          value: {{ include "openshift-observability.noobaa.claimName" . | quote }}
        - name: TARGET_NAMESPACE
          value: {{ include "openshift-observability.noobaa.targetNamespace" . | quote }}
        - name: TARGET_NAME
          value: {{ .Values.acmObservability.multiClusterObservability.metricObjectStorage.name | quote }}
        - name: TARGET_KEY
          value: {{ .Values.acmObservability.multiClusterObservability.metricObjectStorage.key | quote }}
        - name: INSECURE
          value: {{ .Values.acmObservability.multiClusterObservability.metricObjectStorage.noobaa.insecure | quote }}
        - name: WAIT_SECONDS
          value: {{ .Values.acmObservability.multiClusterObservability.metricObjectStorage.noobaa.waitSeconds | quote }}
      command:
        - /bin/bash
        - -c
        - |
          set -euo pipefail
          if command -v oc >/dev/null 2>&1; then
            CLI=oc
          else
            CLI=kubectl
          fi
          deadline=$((SECONDS + WAIT_SECONDS))
          host=""
          access=""
          while [[ -z "$host" || -z "$access" ]]; do
            host=$("$CLI" get configmap "$CLAIM_NAME" -n "$CLAIM_NAMESPACE" -o jsonpath='{.data.BUCKET_HOST}' 2>/dev/null || true)
            access=$("$CLI" get secret "$CLAIM_NAME" -n "$CLAIM_NAMESPACE" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' 2>/dev/null || true)
            if [[ -n "$host" && -n "$access" ]]; then
              break
            fi
            if (( SECONDS >= deadline )); then
              echo "timed out waiting for object bucket claim $CLAIM_NAMESPACE/$CLAIM_NAME" >&2
              exit 1
            fi
            echo "waiting for object bucket claim $CLAIM_NAMESPACE/$CLAIM_NAME"
            sleep 10
          done
          "$CLI" get configmap "$CLAIM_NAME" -n "$CLAIM_NAMESPACE" -o json > /tmp/bucket-cm.json
          "$CLI" get secret "$CLAIM_NAME" -n "$CLAIM_NAMESPACE" -o json > /tmp/bucket-secret.json
          CLAIM_CONFIGMAP_FILE=/tmp/bucket-cm.json \
            CLAIM_SECRET_FILE=/tmp/bucket-secret.json \
            OUTPUT_FILE=/tmp/thanos-secret.json \
            python3 -B /etc/noobaa/noobaa_thanos_secret.py
          if "$CLI" get externalsecret "$TARGET_NAME" -n "$TARGET_NAMESPACE" >/dev/null 2>&1; then
            echo "removing ExternalSecret $TARGET_NAMESPACE/$TARGET_NAME"
            owners=$("$CLI" get secret "$TARGET_NAME" -n "$TARGET_NAMESPACE" -o jsonpath='{.metadata.ownerReferences}' 2>/dev/null || true)
            if [[ -n "$owners" ]]; then
              "$CLI" patch secret "$TARGET_NAME" -n "$TARGET_NAMESPACE" --type=json \
                -p '[{"op":"remove","path":"/metadata/ownerReferences"}]'
            fi
            "$CLI" delete externalsecret "$TARGET_NAME" -n "$TARGET_NAMESPACE" --wait=true
          fi
          "$CLI" apply -f /tmp/thanos-secret.json
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        capabilities:
          drop:
            - ALL
      resources:
        requests:
          cpu: 10m
          memory: 64Mi
        limits:
          cpu: 100m
          memory: 256Mi
      volumeMounts:
        - name: script
          mountPath: /etc/noobaa
          readOnly: true
        - name: tmp
          mountPath: /tmp
{{- end -}}
