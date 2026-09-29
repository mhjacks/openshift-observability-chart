# openshift-observability

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

Publish OpenShift console dashboards, Prometheus rules, and scrape configs from values

A default install runs a bootstrap Job and a CronJob that set `openshift.io/cluster-monitoring=true` on `openshift-operators`. That is the Regional-DR monitoring label. Set `clusterMonitoringLabel.enabled` to `false` to skip it.

Thanos Ruler storage follows `clusterPlatform` when that is set, otherwise `global.clusterPlatform` from the patterns operator. AWS, Azure, and GCP use `gp3-csi`, `managed-csi`, and `standard-csi`. Other platforms get no storage class unless you set `monitoring.thanos.storageClassName`. Set `monitoring.thanos.enabled` to `false` to skip it.

The chart writes `enableUserWorkload: true` into `cluster-monitoring-config`. A bootstrap Job waits until `openshift-user-workload-monitoring` exists, then applies `user-workload-monitoring-config`. A CronJob keeps that config applied. Set `monitoring.cluster.config.enableUserWorkload` to `false` to skip both.

Dashboards, rules, and the RHACM allowlist stay off until you set them. Disaster recovery on the hub follows the two OpenShift Data Foundation 4.22 usages in
[Monitoring disaster recovery health](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.22/html/configuring_openshift_data_foundation_disaster_recovery_for_openshift_workloads/monitoring_disaster_recovery_health).

Both usages need OpenShift 4.17, the ODF Multicluster Orchestrator console plugin, RHACM 2.11, and RHACM observability on the hub.

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

Refresh the hub console and select All Clusters. Open Data Services, click Data policies, then the Disaster recovery tab.

## Add another dashboard or metric set

Layer a second values file, or add keys beside the allowlist:

- `dashboards.<name>` publishes a console ConfigMap. Set `file` to a JSON file in this chart, or set an inline document. Use Grafana schema version 14 and datasource `cluster-prometheus-proxy`. The map key is the ConfigMap name. `admin` and `developer` choose the console perspective.
- `prometheusRules.<name>` adds recording rules and alerts. Use namespace `openshift-monitoring` for platform metrics. Platform monitoring loads rules from namespaces labeled `openshift.io/cluster-monitoring=true`. For rules that query across projects, use a user project listed in `monitoring.userWorkload.namespacesWithoutLabelEnforcement`.
- `serviceMonitors.<name>` and `podMonitors.<name>` copy `spec` through as written.
- Extra managed-cluster metrics belong on `acmObservability.names` or `acmObservability.matches`.

## Notable changes

### 0.1.0

First release. Generic console dashboards, Prometheus rules, ServiceMonitors, PodMonitors, and an RHACM metrics allowlist. A bootstrap Job and CronJob keep `openshift.io/cluster-monitoring=true` on `openshift-operators` unless `clusterMonitoringLabel.enabled` is false.

Thanos Ruler persistent storage follows `clusterPlatform` or `global.clusterPlatform` for AWS, Azure, and GCP. The user-workload ConfigMap is applied by a Job after its namespace exists. `examples/regional-dr-values.yaml` and `examples/metro-dr-values.yaml` enable the hub disaster recovery dashboard.

**Homepage:** <https://github.com/mhjacks/openshift-observability-chart>

## Source Code

- <https://github.com/mhjacks/openshift-observability-chart>

## Values

| Key                                                       | Type   | Default                                         | Description                                                                                                                                                                                                                                 |
| --------------------------------------------------------- | ------ | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| acmObservability.annotations                              | object | `{}`                                            | Annotations for the allowlist ConfigMap                                                                                                                                                                                                     |
| acmObservability.enabled                                  | bool   | `false`                                         | Render the RHACM observability custom metrics allowlist                                                                                                                                                                                     |
| acmObservability.matches                                  | list   | `[]`                                            | Metric match expressions collected from managed clusters                                                                                                                                                                                    |
| acmObservability.name                                     | string | `"observability-metrics-custom-allowlist"`      | Allowlist ConfigMap name                                                                                                                                                                                                                    |
| acmObservability.names                                    | list   | `[]`                                            | Metric names collected from managed clusters                                                                                                                                                                                                |
| acmObservability.namespace                                | string | `"open-cluster-management-observability"`       | Namespace of the RHACM observability stack                                                                                                                                                                                                  |
| acmObservability.recordingRules                           | list   | `[]`                                            | Recording rules evaluated for managed-cluster metrics. Each item has record and expr.                                                                                                                                                       |
| clusterMonitoringLabel.activeDeadlineSeconds              | int    | `120`                                           | Seconds before the Job or CronJob pod is killed                                                                                                                                                                                             |
| clusterMonitoringLabel.backoffLimit                       | int    | `99`                                            | Bootstrap Job retries while RBAC or the API is not ready yet                                                                                                                                                                                |
| clusterMonitoringLabel.enabled                            | bool   | `true`                                          | Run a bootstrap Job that labels the operators namespace, then a CronJob that keeps the label set                                                                                                                                            |
| clusterMonitoringLabel.image.pullPolicy                   | string | `"IfNotPresent"`                                | Image pull policy                                                                                                                                                                                                                           |
| clusterMonitoringLabel.image.repository                   | string | `"registry.redhat.io/openshift4/ose-cli-rhel9"` | Image repository for the label Job and CronJob                                                                                                                                                                                              |
| clusterMonitoringLabel.image.tag                          | string | `"v4.22"`                                       | Image tag                                                                                                                                                                                                                                   |
| clusterMonitoringLabel.jobNamespace                       | string | `"open-cluster-management-observability"`       | Namespace for the Job, CronJob, and ServiceAccount. Empty uses the release namespace.                                                                                                                                                       |
| clusterMonitoringLabel.key                                | string | `"openshift.io/cluster-monitoring"`             | Label key                                                                                                                                                                                                                                   |
| clusterMonitoringLabel.namespace                          | string | `"openshift-operators"`                         | Namespace that receives the label. This chart does not create that namespace.                                                                                                                                                               |
| clusterMonitoringLabel.schedule                           | string | `"*/15 * * * *"`                                | CronJob schedule that re-applies the label after the bootstrap Job                                                                                                                                                                          |
| clusterMonitoringLabel.value                              | string | `"true"`                                        | Label value                                                                                                                                                                                                                                 |
| clusterPlatform                                           | string | `""`                                            | Platform override. Empty uses global.clusterPlatform from the patterns operator.                                                                                                                                                            |
| dashboardDefaults.admin                                   | bool   | `true`                                          | Publish to the Administrator perspective when a dashboard omits admin                                                                                                                                                                       |
| dashboardDefaults.developer                               | bool   | `false`                                         | Publish to the Developer perspective when a dashboard omits developer                                                                                                                                                                       |
| dashboardDefaults.namespace                               | string | `"openshift-config-managed"`                    | Namespace that receives console dashboard ConfigMaps                                                                                                                                                                                        |
| dashboards                                                | object | `{}`                                            | Console dashboards keyed by ConfigMap name. Each entry accepts enabled, namespace, file or an inline document, admin, developer, labels, and annotations. file is a path inside this chart. The inline document is a JSON string or object. |
| monitoring.cluster.annotations                            | object | `{}`                                            | Annotations for the cluster-monitoring-config ConfigMap                                                                                                                                                                                     |
| monitoring.cluster.config                                 | object | `{}`                                            | Extra keys merged into cluster-monitoring-config data.config.yaml. These override enableUserWorkload.                                                                                                                                       |
| monitoring.cluster.enableUserWorkload                     | bool   | `false`                                         | enableUserWorkload field written into cluster-monitoring-config                                                                                                                                                                             |
| monitoring.cluster.enabled                                | bool   | `false`                                         | Render cluster-monitoring-config in openshift-monitoring. This replaces that ConfigMap.                                                                                                                                                     |
| monitoring.thanos.enabled                                 | bool   | `true`                                          | Give Thanos Ruler a PVC when a storage class is known                                                                                                                                                                                       |
| monitoring.thanos.storage                                 | string | `"10Gi"`                                        | Thanos Ruler PVC size                                                                                                                                                                                                                       |
| monitoring.thanos.storageClassName                        | string | `""`                                            | Thanos Ruler storage class. Empty uses AWS gp3-csi, Azure managed-csi, or GCP standard-csi from clusterPlatform.                                                                                                                            |
| monitoring.userWorkload.activeDeadlineSeconds             | int    | `900`                                           | Seconds the apply Job may run while waiting for the namespace                                                                                                                                                                               |
| monitoring.userWorkload.annotations                       | object | `{}`                                            | Annotations stored on the desired user-workload config                                                                                                                                                                                      |
| monitoring.userWorkload.backoffLimit                      | int    | `99`                                            | Retries while the namespace or API is not ready                                                                                                                                                                                             |
| monitoring.userWorkload.config                            | object | `{}`                                            | Extra keys merged into user-workload-monitoring-config data.config.yaml                                                                                                                                                                     |
| monitoring.userWorkload.enabled                           | bool   | `false`                                         | Apply user-workload-monitoring-config after its namespace exists                                                                                                                                                                            |
| monitoring.userWorkload.namespacesWithoutLabelEnforcement | list   | `[]`                                            | Projects whose PrometheusRules are not rewritten with their own namespace label                                                                                                                                                             |
| monitoring.userWorkload.schedule                          | string | `"*/15 * * * *"`                                | CronJob schedule that reapplies the config after the namespace exists                                                                                                                                                                       |
| monitoring.userWorkload.waitSeconds                       | int    | `600`                                           | Seconds to wait for openshift-user-workload-monitoring inside the Job                                                                                                                                                                       |
| nameOverride                                              | string | `""`                                            | Chart name override used on standard labels                                                                                                                                                                                                 |
| namespaces                                                | object | `{}`                                            | Namespaces to create for rules or monitors that need their own project. Each entry accepts enabled, labels, and annotations. The map key is the namespace name.                                                                             |
| podMonitors                                               | object | `{}`                                            | PodMonitor objects keyed by name. spec is copied through as written.                                                                                                                                                                        |
| prometheusRules                                           | object | `{}`                                            | PrometheusRule objects keyed by name. Each entry accepts enabled, namespace, labels, annotations, and groups.                                                                                                                               |
| serviceMonitors                                           | object | `{}`                                            | ServiceMonitor objects keyed by name. spec is copied through as written.                                                                                                                                                                    |

---

Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
