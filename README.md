# openshift-observability

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

Publish OpenShift console dashboards, Prometheus rules, and scrape configs from values

The chart stays empty until you add dashboards, rules, or an allowlist. Disaster recovery on the hub follows the two OpenShift Data Foundation 4.22 usages in
[Monitoring disaster recovery health](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.22/html/configuring_openshift_data_foundation_disaster_recovery_for_openshift_workloads/monitoring_disaster_recovery_health).

Both usages need OpenShift 4.17, the ODF Multicluster Orchestrator console plugin, RHACM 2.11, and RHACM observability on the hub.

## Regional-DR

The dashboard shows operator health, cluster health, metrics, alerts, and application count. Label the operators namespace, then install the allowlist:

```bash
oc label namespace openshift-operators openshift.io/cluster-monitoring='true'
helm upgrade --install observability . \
  --namespace open-cluster-management-observability \
  -f examples/regional-dr-values.yaml
```

`examples/regional-dr-values.yaml` is the allowlist from
[Enabling disaster recovery dashboard on Hub cluster](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.22/html/configuring_openshift_data_foundation_disaster_recovery_for_openshift_workloads/monitoring_disaster_recovery_health#enabling-dr-dashboard-on-hub-cluster_monitor-dr).
The label is the previous section of that chapter, and it is required for Regional-DR.

## Metro-DR

The dashboard shows ramen setup health and application count:

```bash
helm upgrade --install observability . \
  --namespace open-cluster-management-observability \
  -f examples/metro-dr-values.yaml
```

`examples/metro-dr-values.yaml` keeps the OpenShift DR cluster operator match from that allowlist. It omits the Ceph mirror metrics and the VolSync pod match. Application count comes from RHACM observability.

Refresh the hub console and select All Clusters. Open Data Services, click Data policies, then the Disaster recovery tab.

## Add another dashboard or metric set

Layer a second values file, or add keys beside the allowlist:

- `dashboards.<name>` publishes a console ConfigMap. Set `file` to a JSON file in this chart, or set an inline document. Use Grafana schema version 14 and datasource `cluster-prometheus-proxy`. The map key is the ConfigMap name. `admin` and `developer` choose the console perspective.
- `prometheusRules.<name>` adds recording rules and alerts. Use namespace `openshift-monitoring` for platform metrics. Platform monitoring loads rules from namespaces labeled `openshift.io/cluster-monitoring=true`. For rules that query across projects, use a user project listed in `monitoring.userWorkload.namespacesWithoutLabelEnforcement`.
- `serviceMonitors.<name>` and `podMonitors.<name>` copy `spec` through as written.
- Extra managed-cluster metrics belong on `acmObservability.names` or `acmObservability.matches`.

## Notable changes

### 0.1.0

First release. Generic console dashboards, Prometheus rules, ServiceMonitors, PodMonitors, and an RHACM metrics allowlist. `examples/regional-dr-values.yaml` and `examples/metro-dr-values.yaml` enable the hub disaster recovery dashboard.

**Homepage:** <https://github.com/mhjacks/openshift-observability-chart>

## Source Code

- <https://github.com/mhjacks/openshift-observability-chart>

## Values

| Key                                                       | Type   | Default                                    | Description                                                                                                                                                                                                                                 |
| --------------------------------------------------------- | ------ | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| acmObservability.annotations                              | object | `{}`                                       | Annotations for the allowlist ConfigMap                                                                                                                                                                                                     |
| acmObservability.enabled                                  | bool   | `false`                                    | Render the RHACM observability custom metrics allowlist                                                                                                                                                                                     |
| acmObservability.matches                                  | list   | `[]`                                       | Metric match expressions collected from managed clusters                                                                                                                                                                                    |
| acmObservability.name                                     | string | `"observability-metrics-custom-allowlist"` | Allowlist ConfigMap name                                                                                                                                                                                                                    |
| acmObservability.names                                    | list   | `[]`                                       | Metric names collected from managed clusters                                                                                                                                                                                                |
| acmObservability.namespace                                | string | `"open-cluster-management-observability"`  | Namespace of the RHACM observability stack                                                                                                                                                                                                  |
| acmObservability.recordingRules                           | list   | `[]`                                       | Recording rules evaluated for managed-cluster metrics. Each item has record and expr.                                                                                                                                                       |
| dashboardDefaults.admin                                   | bool   | `true`                                     | Publish to the Administrator perspective when a dashboard omits admin                                                                                                                                                                       |
| dashboardDefaults.developer                               | bool   | `false`                                    | Publish to the Developer perspective when a dashboard omits developer                                                                                                                                                                       |
| dashboardDefaults.namespace                               | string | `"openshift-config-managed"`               | Namespace that receives console dashboard ConfigMaps                                                                                                                                                                                        |
| dashboards                                                | object | `{}`                                       | Console dashboards keyed by ConfigMap name. Each entry accepts enabled, namespace, file or an inline document, admin, developer, labels, and annotations. file is a path inside this chart. The inline document is a JSON string or object. |
| monitoring.cluster.annotations                            | object | `{}`                                       | Annotations for the cluster-monitoring-config ConfigMap                                                                                                                                                                                     |
| monitoring.cluster.config                                 | object | `{}`                                       | Extra keys merged into cluster-monitoring-config data.config.yaml. These override enableUserWorkload.                                                                                                                                       |
| monitoring.cluster.enableUserWorkload                     | bool   | `false`                                    | enableUserWorkload field written into cluster-monitoring-config                                                                                                                                                                             |
| monitoring.cluster.enabled                                | bool   | `false`                                    | Render cluster-monitoring-config in openshift-monitoring. This replaces that ConfigMap.                                                                                                                                                     |
| monitoring.userWorkload.annotations                       | object | `{}`                                       | Annotations for the user-workload-monitoring-config ConfigMap                                                                                                                                                                               |
| monitoring.userWorkload.config                            | object | `{}`                                       | Extra keys merged into user-workload-monitoring-config data.config.yaml                                                                                                                                                                     |
| monitoring.userWorkload.enabled                           | bool   | `false`                                    | Render user-workload-monitoring-config. The openshift-user-workload-monitoring namespace must already exist.                                                                                                                                |
| monitoring.userWorkload.namespacesWithoutLabelEnforcement | list   | `[]`                                       | Projects whose PrometheusRules are not rewritten with their own namespace label                                                                                                                                                             |
| nameOverride                                              | string | `""`                                       | Chart name override used on standard labels                                                                                                                                                                                                 |
| namespaces                                                | object | `{}`                                       | Namespaces to create for rules or monitors that need their own project. Each entry accepts enabled, labels, and annotations. The map key is the namespace name.                                                                             |
| podMonitors                                               | object | `{}`                                       | PodMonitor objects keyed by name. spec is copied through as written.                                                                                                                                                                        |
| prometheusRules                                           | object | `{}`                                       | PrometheusRule objects keyed by name. Each entry accepts enabled, namespace, labels, annotations, and groups.                                                                                                                               |
| serviceMonitors                                           | object | `{}`                                       | ServiceMonitor objects keyed by name. spec is copied through as written.                                                                                                                                                                    |

---

Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
