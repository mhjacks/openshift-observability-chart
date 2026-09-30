#!/usr/bin/env python3
import importlib.util
import pathlib
import unittest

PATH = pathlib.Path(__file__).with_name("merge_monitoring_config.py")
SPEC = importlib.util.spec_from_file_location("merge_monitoring_config", PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

LIVE = """\
enableUserWorkload: true
nodeExporter:
  collectors:
    buddyinfo: {}
    cpufreq: {}
prometheusK8s:
  additionalAlertmanagerConfigs:
  - apiVersion: v2
    scheme: https
    staticConfigs:
    - alertmanager.example.com
    tlsConfig:
      ca:
        key: service-ca.crt
        name: hub-alertmanager-router-ca
      insecureSkipVerify: false
  externalLabels:
    managed_cluster: abcdef
"""

DESIRED = """\
enableUserWorkload: true
prometheusK8s:
  retention: 15d
"""

HELM = """\
enableUserWorkload: true
prometheusK8s:
  retention: 15d
namespacesWithoutLabelEnforcement:
  - dr-observability
"""


class MergeMonitoringConfigTest(unittest.TestCase):
    def test_go_style_round_trip_keeps_structure(self):
        loaded = MODULE.load_yaml(LIVE)
        self.assertTrue(loaded["enableUserWorkload"])
        self.assertEqual(loaded["nodeExporter"]["collectors"]["buddyinfo"], {})
        configs = loaded["prometheusK8s"]["additionalAlertmanagerConfigs"]
        self.assertEqual(configs[0]["staticConfigs"], ["alertmanager.example.com"])
        self.assertFalse(configs[0]["tlsConfig"]["insecureSkipVerify"])
        self.assertEqual(MODULE.load_yaml(MODULE.dump_yaml(loaded)), loaded)

    def test_helm_style_list_indent(self):
        loaded = MODULE.load_yaml(HELM)
        self.assertEqual(loaded["namespacesWithoutLabelEnforcement"], ["dr-observability"])
        self.assertEqual(MODULE.load_yaml(MODULE.dump_yaml(loaded)), loaded)

    def test_merge_keeps_operator_keys_and_replaces_lists(self):
        merged = MODULE.merge(MODULE.load_yaml(LIVE), MODULE.load_yaml(DESIRED))
        self.assertEqual(merged["prometheusK8s"]["retention"], "15d")
        self.assertEqual(merged["prometheusK8s"]["externalLabels"]["managed_cluster"], "abcdef")
        self.assertIn("buddyinfo", merged["nodeExporter"]["collectors"])
        self.assertEqual(len(merged["prometheusK8s"]["additionalAlertmanagerConfigs"]), 1)
        replaced = MODULE.merge(merged, {"prometheusK8s": {"additionalAlertmanagerConfigs": []}})
        self.assertEqual(replaced["prometheusK8s"]["additionalAlertmanagerConfigs"], [])
        self.assertEqual(replaced["prometheusK8s"]["retention"], "15d")

    def test_multiline_and_quoted_strings(self):
        text = 'note: |-\n  one\n  two\nquoted: "true"\nplain: 15d\n'
        loaded = MODULE.load_yaml(text)
        self.assertEqual(loaded["note"], "one\ntwo")
        self.assertEqual(loaded["quoted"], "true")
        self.assertEqual(loaded["plain"], "15d")
        self.assertEqual(MODULE.load_yaml(MODULE.dump_yaml(loaded)), loaded)

    def test_url_list_item_is_not_a_map(self):
        loaded = MODULE.load_yaml("staticConfigs:\n- https://alerts.example.com\n")
        self.assertEqual(loaded["staticConfigs"], ["https://alerts.example.com"])

    def test_reconcile_skips_identical_document(self):
        calls = []
        live = {
            "apiVersion": "v1",
            "kind": "ConfigMap",
            "metadata": {"name": "cluster-monitoring-config", "namespace": "openshift-monitoring", "resourceVersion": "1"},
            "data": {"config.yaml": LIVE},
        }

        def getter():
            return live

        def saver(obj, create):
            calls.append((obj, create))

        MODULE.reconcile(
            "openshift-monitoring",
            "cluster-monitoring-config",
            {"enableUserWorkload": True},
            getter,
            saver,
        )
        self.assertEqual(calls, [])

    def test_reconcile_drops_chart_tracking_annotation(self):
        saved = []
        live = {
            "apiVersion": "v1",
            "kind": "ConfigMap",
            "metadata": {
                "name": "cluster-monitoring-config",
                "namespace": "openshift-monitoring",
                "resourceVersion": "3",
                "annotations": {
                    "argocd.argoproj.io/tracking-id": "observability:/ConfigMap:openshift-monitoring/cluster-monitoring-config",
                    "argocd.argoproj.io/sync-wave": "1",
                    "keep": "yes",
                },
            },
            "data": {"config.yaml": "enableUserWorkload: true\n"},
        }

        MODULE.reconcile(
            "openshift-monitoring",
            "cluster-monitoring-config",
            {"enableUserWorkload": True},
            lambda: live,
            lambda obj, create: saved.append((obj, create)),
        )
        annotations = saved[0][0]["metadata"]["annotations"]
        self.assertEqual(annotations, {"keep": "yes"})
        self.assertNotIn("managedFields", saved[0][0]["metadata"])

    def test_reconcile_retries_conflict_then_creates(self):
        state = {"n": 0}

        def getter():
            return None

        def saver(obj, create):
            state["n"] += 1
            if state["n"] == 1:
                raise MODULE.AlreadyExists("exists")
            self.assertTrue(create)
            self.assertEqual(obj["data"]["config.yaml"].strip(), "enableUserWorkload: true")

        MODULE.reconcile("openshift-monitoring", "cluster-monitoring-config", {"enableUserWorkload": True}, getter, saver)
        self.assertEqual(state["n"], 2)


if __name__ == "__main__":
    unittest.main()
