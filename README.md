# openshift-observability

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

Publish OpenShift console dashboards, Prometheus rules, and scrape configs from values

A default install creates `MultiClusterObservability` and runs a bootstrap Job and a CronJob that set `openshift.io/cluster-monitoring=true` on `openshift-operators`. That is the Regional-DR monitoring label. Set `clusterMonitoringLabel.enabled` to `false` to skip the label. Set `acmObservability.multiClusterObservability.enabled` to `false` to skip the observability object.

Thanos Ruler storage follows `clusterPlatform` when that is set, otherwise `global.clusterPlatform` from the patterns operator. AWS, Azure, and GCP use `gp3-csi`, `managed-csi`, and `standard-csi`. Other platforms get no storage class unless you set `monitoring.thanos.storageClassName`. Set `monitoring.thanos.enabled` to `false` to skip it.

The chart does not adopt `cluster-monitoring-config`. A bootstrap Job and a CronJob merge `enableUserWorkload: true` into that ConfigMap and leave keys they do not set, including the endpoint observability operator's Alertmanager and label entries. The same Job waits until `openshift-user-workload-monitoring` exists, then merges `user-workload-monitoring-config` the same way. Set `monitoring.cluster.config.enableUserWorkload` to `false` to skip both.

Dashboards, rules, and the RHACM allowlist stay off until you set them. Disaster recovery on the hub follows the two OpenShift Data Foundation 4.22 usages in
[Monitoring disaster recovery health](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.22/html/configuring_openshift_data_foundation_disaster_recovery_for_openshift_workloads/monitoring_disaster_recovery_health).

Both usages need OpenShift 4.17, the Data Foundation Multicluster Orchestrator console plugin, and RHACM. `MultiClusterObservability` turns the disaster recovery Overview cards on.

An ExternalSecret writes secret `thanos-object-storage` key `thanos.yaml` in `open-cluster-management-observability`. AWS, Azure, and GCP set the StatefulSet storage class to `gp3-csi`, `managed-csi`, or `standard-csi`.

## Thanos object storage

Add the object storage file to the pattern `values-secret.yaml` (version 2.0). Keep that file out of Git. With no `vaultPrefixes`, the loader stores it at `secret/hub/thanos-object-storage`, which External Secrets reads as `secret/data/hub/thanos-object-storage`.

```yaml
secrets:
  - name: thanos-object-storage
    fields:
      - name: thanos.yaml
        path: ~/thanos.yaml
        onMissingValue: error
```

`~/thanos.yaml` is the Thanos object storage file. The same `values-secret.yaml` entry is used for every cloud. These shapes match the [RHACM object-storage secret](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/observability/observing-environments-intro).

Amazon S3. `endpoint` has no scheme:

```yaml
type: s3
config:
  bucket: BUCKET
  endpoint: s3.REGION.amazonaws.com
  insecure: false
  access_key: ACCESS_KEY
  secret_key: SECRET_KEY
```

Google Cloud Storage. Create a bucket and a service account with `roles/storage.objectAdmin` on that bucket, then download a JSON key. `service_account` is that JSON, not a file path:

```yaml
type: GCS
config:
  bucket: BUCKET
  service_account: |-
    {
      "type": "service_account",
      "project_id": "PROJECT_ID",
      "private_key_id": "KEY_ID",
      "private_key": "-----BEGIN PRIVATE KEY-----\nPRIVATE_KEY\n-----END PRIVATE KEY-----\n",
      "client_email": "thanos@PROJECT_ID.iam.gserviceaccount.com",
      "client_id": "CLIENT_ID",
      "auth_uri": "https://accounts.google.com/o/oauth2/auth",
      "token_uri": "https://oauth2.googleapis.com/token",
      "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
      "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/thanos%40PROJECT_ID.iam.gserviceaccount.com"
    }
```

Microsoft Azure. Create a storage account and blob container that are separate from the account attached to the cluster. `endpoint` has no scheme. Sovereign clouds use their own host, such as `blob.core.usgovcloudapi.net`:

```yaml
type: AZURE
config:
  storage_account: STORAGE_ACCOUNT
  storage_account_key: STORAGE_ACCOUNT_KEY
  container: CONTAINER
  endpoint: blob.core.windows.net
  max_retries: 0
```

A user-assigned managed identity omits the account key. `user_assigned_id` is the identity client id, and that identity needs Storage Blob Data Contributor on the container:

```yaml
type: AZURE
config:
  storage_account: STORAGE_ACCOUNT
  container: CONTAINER
  endpoint: blob.core.windows.net
  user_assigned_id: USER_ASSIGNED_CLIENT_ID
  max_retries: 0
```

From the pattern repository, run `make load-secrets`. The chart ExternalSecret uses ClusterSecretStore `vault-backend`. Override `secretStore` or `acmObservability.multiClusterObservability.metricObjectStorage.externalSecret.vaultKey` when the store or path is different. Set `externalSecret.enabled` to `false` to supply the Kubernetes secret yourself.

## Regional-DR

The dashboard shows operator health, cluster health, metrics, alerts, and application count. The bootstrap Job sets `openshift.io/cluster-monitoring=true` on `openshift-operators`, and the CronJob keeps that label set:

```bash
helm upgrade --install observability . \
  --namespace open-cluster-management-observability \
  -f examples/regional-dr-values.yaml
```

`examples/regional-dr-values.yaml` is the allowlist from
[Enabling disaster recovery dashboard on Hub cluster](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.22/html/configuring_openshift_data_foundation_disaster_recovery_for_openshift_workloads/monitoring_disaster_recovery_health#enabling-dr-dashboard-on-hub-cluster_monitor-dr).
The label is the previous section of that chapter, and it is required for Regional-DR. The chart does not create the `openshift-operators` Namespace.

## Metro-DR

The dashboard shows ramen setup health and application count:

```bash
helm upgrade --install observability . \
  --namespace open-cluster-management-observability \
  -f examples/metro-dr-values.yaml
```

`examples/metro-dr-values.yaml` keeps the OpenShift DR cluster operator match from that allowlist. It omits the Ceph mirror metrics and the VolSync pod match, and it turns `clusterMonitoringLabel` off. Application count comes from RHACM observability.

Refresh the hub console and select Fleet Management. Open Data Services, click Disaster recovery, then the Overview tab. Protected applications and Topology show the same workloads.

## Add another dashboard or metric set

Layer a second values file, or add keys beside the allowlist:

- `dashboards.<name>` publishes a console ConfigMap. Set `file` to a JSON file in this chart, or set an inline document. Use Grafana schema version 14 and datasource `cluster-prometheus-proxy`. The map key is the ConfigMap name. `admin` and `developer` choose the console perspective.
- `prometheusRules.<name>` adds recording rules and alerts. Use namespace `openshift-monitoring` for platform metrics. Platform monitoring loads rules from namespaces labeled `openshift.io/cluster-monitoring=true`. For rules that query across projects, use a user project listed in `monitoring.userWorkload.namespacesWithoutLabelEnforcement`.
- `serviceMonitors.<name>` and `podMonitors.<name>` copy `spec` through as written.
- Extra managed-cluster metrics belong on `acmObservability.names` or `acmObservability.matches`.

## Notable changes

### 0.1.0

First release. Generic console dashboards, Prometheus rules, ServiceMonitors, PodMonitors, and an RHACM metrics allowlist. A default install creates `MultiClusterObservability`. A bootstrap Job and CronJob keep `openshift.io/cluster-monitoring=true` on `openshift-operators` unless `clusterMonitoringLabel.enabled` is false.

Thanos Ruler persistent storage follows `clusterPlatform` or `global.clusterPlatform` for AWS, Azure, and GCP. A Job merges that Thanos Ruler storage into `user-workload-monitoring-config` after its namespace exists, and merges `enableUserWorkload` into `cluster-monitoring-config` without replacing the observability operator's keys.

An ExternalSecret loads Thanos object storage from the pattern `values-secret.yaml` entry `thanos-object-storage`. `examples/regional-dr-values.yaml` and `examples/metro-dr-values.yaml` enable the hub disaster recovery dashboard.

**Homepage:** <https://github.com/mhjacks/openshift-observability-chart>

## Source Code

- <https://github.com/mhjacks/openshift-observability-chart>

## Values

| Key                                                                                           | Type   | Default                                         | Description                                                                                                                                                                                                                                 |
| --------------------------------------------------------------------------------------------- | ------ | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| acmObservability.annotations                                                                  | object | `{}`                                            | Annotations for the allowlist ConfigMap                                                                                                                                                                                                     |
| acmObservability.enabled                                                                      | bool   | `false`                                         | Render the RHACM observability custom metrics allowlist                                                                                                                                                                                     |
| acmObservability.matches                                                                      | list   | `[]`                                            | Metric match expressions collected from managed clusters                                                                                                                                                                                    |
| acmObservability.multiClusterObservability.enabled                                            | bool   | `true`                                          | Create MultiClusterObservability. The console shows the disaster recovery Overview cards only when this object exists.                                                                                                                      |
| acmObservability.multiClusterObservability.metricObjectStorage.externalSecret.enabled         | bool   | `true`                                          | Create an ExternalSecret from the values-secret.yaml entry thanos-object-storage                                                                                                                                                            |
| acmObservability.multiClusterObservability.metricObjectStorage.externalSecret.refreshInterval | string | `"15s"`                                         | How often External Secrets refreshes the secret                                                                                                                                                                                             |
| acmObservability.multiClusterObservability.metricObjectStorage.externalSecret.vaultKey        | string | `"secret/data/hub/thanos-object-storage"`       | Vault path. Field thanos.yaml is the secret key.                                                                                                                                                                                            |
| acmObservability.multiClusterObservability.metricObjectStorage.key                            | string | `"thanos.yaml"`                                 | Key in the object storage secret                                                                                                                                                                                                            |
| acmObservability.multiClusterObservability.metricObjectStorage.name                           | string | `"thanos-object-storage"`                       | Secret written by the ExternalSecret. Advanced Cluster Management reads key thanos.yaml.                                                                                                                                                    |
| acmObservability.multiClusterObservability.name                                               | string | `"observability"`                               | Object name. Advanced Cluster Management expects observability.                                                                                                                                                                             |
| acmObservability.multiClusterObservability.storageClassName                                   | string | `""`                                            | StatefulSet storage class. Empty uses AWS gp3-csi, Azure managed-csi, or GCP standard-csi from clusterPlatform.                                                                                                                             |
| acmObservability.name                                                                         | string | `"observability-metrics-custom-allowlist"`      | Allowlist ConfigMap name                                                                                                                                                                                                                    |
| acmObservability.names                                                                        | list   | `[]`                                            | Metric names collected from managed clusters                                                                                                                                                                                                |
| acmObservability.namespace                                                                    | string | `"open-cluster-management-observability"`       | Namespace of the RHACM observability stack                                                                                                                                                                                                  |
| acmObservability.recordingRules                                                               | list   | `[]`                                            | Recording rules evaluated for managed-cluster metrics. Each item has record and expr.                                                                                                                                                       |
| clusterMonitoringLabel.activeDeadlineSeconds                                                  | int    | `120`                                           | Seconds before the Job or CronJob pod is killed                                                                                                                                                                                             |
| clusterMonitoringLabel.backoffLimit                                                           | int    | `99`                                            | Bootstrap Job retries while RBAC or the API is not ready yet                                                                                                                                                                                |
| clusterMonitoringLabel.enabled                                                                | bool   | `true`                                          | Run a bootstrap Job that labels the operators namespace, then a CronJob that keeps the label set                                                                                                                                            |
| clusterMonitoringLabel.image.pullPolicy                                                       | string | `"IfNotPresent"`                                | Image pull policy                                                                                                                                                                                                                           |
| clusterMonitoringLabel.image.repository                                                       | string | `"registry.redhat.io/openshift4/ose-cli-rhel9"` | Image repository for the label Job and CronJob                                                                                                                                                                                              |
| clusterMonitoringLabel.image.tag                                                              | string | `"v4.22"`                                       | Image tag                                                                                                                                                                                                                                   |
| clusterMonitoringLabel.jobNamespace                                                           | string | `"open-cluster-management-observability"`       | Namespace for the Job, CronJob, and ServiceAccount. Empty uses the release namespace.                                                                                                                                                       |
| clusterMonitoringLabel.key                                                                    | string | `"openshift.io/cluster-monitoring"`             | Label key                                                                                                                                                                                                                                   |
| clusterMonitoringLabel.namespace                                                              | string | `"openshift-operators"`                         | Namespace that receives the label. This chart does not create that namespace.                                                                                                                                                               |
| clusterMonitoringLabel.schedule                                                               | string | `"*/15 * * * *"`                                | CronJob schedule that re-applies the label after the bootstrap Job                                                                                                                                                                          |
| clusterMonitoringLabel.value                                                                  | string | `"true"`                                        | Label value                                                                                                                                                                                                                                 |
| clusterPlatform                                                                               | string | `""`                                            | Platform override. Empty uses global.clusterPlatform from the patterns operator.                                                                                                                                                            |
| dashboardDefaults.admin                                                                       | bool   | `true`                                          | Publish to the Administrator perspective when a dashboard omits admin                                                                                                                                                                       |
| dashboardDefaults.developer                                                                   | bool   | `false`                                         | Publish to the Developer perspective when a dashboard omits developer                                                                                                                                                                       |
| dashboardDefaults.namespace                                                                   | string | `"openshift-config-managed"`                    | Namespace that receives console dashboard ConfigMaps                                                                                                                                                                                        |
| dashboards                                                                                    | object | `{}`                                            | Console dashboards keyed by ConfigMap name. Each entry accepts enabled, namespace, file or an inline document, admin, developer, labels, and annotations. file is a path inside this chart. The inline document is a JSON string or object. |
| monitoring.cluster.annotations                                                                | object | `{}`                                            | Annotations for the desired cluster monitoring fragment                                                                                                                                                                                     |
| monitoring.cluster.config                                                                     | object | `{}`                                            | Extra keys merged into cluster-monitoring-config. These override enableUserWorkload. A list replaces the live list.                                                                                                                         |
| monitoring.cluster.enableUserWorkload                                                         | bool   | `false`                                         | enableUserWorkload field merged into cluster-monitoring-config                                                                                                                                                                              |
| monitoring.cluster.enabled                                                                    | bool   | `false`                                         | Merge a desired fragment into cluster-monitoring-config. The chart does not adopt that ConfigMap.                                                                                                                                           |
| monitoring.thanos.enabled                                                                     | bool   | `true`                                          | Give Thanos Ruler a PVC when a storage class is known                                                                                                                                                                                       |
| monitoring.thanos.storage                                                                     | string | `"10Gi"`                                        | Thanos Ruler PVC size                                                                                                                                                                                                                       |
| monitoring.thanos.storageClassName                                                            | string | `""`                                            | Thanos Ruler storage class. Empty uses AWS gp3-csi, Azure managed-csi, or GCP standard-csi from clusterPlatform.                                                                                                                            |
| monitoring.userWorkload.activeDeadlineSeconds                                                 | int    | `900`                                           | Seconds the apply Job may run while waiting for the namespace                                                                                                                                                                               |
| monitoring.userWorkload.annotations                                                           | object | `{}`                                            | Annotations stored on the desired user-workload config                                                                                                                                                                                      |
| monitoring.userWorkload.backoffLimit                                                          | int    | `99`                                            | Retries while the namespace or API is not ready                                                                                                                                                                                             |
| monitoring.userWorkload.config                                                                | object | `{}`                                            | Extra keys merged into user-workload-monitoring-config data.config.yaml                                                                                                                                                                     |
| monitoring.userWorkload.enabled                                                               | bool   | `false`                                         | Merge user-workload-monitoring-config after its namespace exists                                                                                                                                                                            |
| monitoring.userWorkload.namespacesWithoutLabelEnforcement                                     | list   | `[]`                                            | Projects whose PrometheusRules are not rewritten with their own namespace label                                                                                                                                                             |
| monitoring.userWorkload.schedule                                                              | string | `"*/15 * * * *"`                                | CronJob schedule that reapplies the config after the namespace exists                                                                                                                                                                       |
| monitoring.userWorkload.waitSeconds                                                           | int    | `600`                                           | Seconds to wait for openshift-user-workload-monitoring inside the Job                                                                                                                                                                       |
| nameOverride                                                                                  | string | `""`                                            | Chart name override used on standard labels                                                                                                                                                                                                 |
| namespaces                                                                                    | object | `{}`                                            | Namespaces to create for rules or monitors that need their own project. Each entry accepts enabled, labels, and annotations. The map key is the namespace name.                                                                             |
| podMonitors                                                                                   | object | `{}`                                            | PodMonitor objects keyed by name. spec is copied through as written.                                                                                                                                                                        |
| prometheusRules                                                                               | object | `{}`                                            | PrometheusRule objects keyed by name. Each entry accepts enabled, namespace, labels, annotations, and groups.                                                                                                                               |
| secretStore.kind                                                                              | string | `"ClusterSecretStore"`                          | External Secrets store kind                                                                                                                                                                                                                 |
| secretStore.name                                                                              | string | `"vault-backend"`                               | External Secrets store that holds pattern secrets                                                                                                                                                                                           |
| serviceMonitors                                                                               | object | `{}`                                            | ServiceMonitor objects keyed by name. spec is copied through as written.                                                                                                                                                                    |

---

Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
