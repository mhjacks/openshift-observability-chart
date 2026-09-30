"""Unit tests for the NooBaa thanos.yaml builder."""

import base64
import json
import os
import tempfile
import unittest

import noobaa_thanos_secret as builder


def encode(value):
    return base64.b64encode(value.encode()).decode()


class NoobaaThanosSecretTest(unittest.TestCase):
    def claim(self, host="s3.openshift-storage.svc", port="443", bucket="metrics"):
        return {
            "data": {
                "BUCKET_HOST": host,
                "BUCKET_PORT": port,
                "BUCKET_NAME": bucket,
            }
        }

    def secret(self, access="access", key="secret"):
        return {
            "data": {
                "AWS_ACCESS_KEY_ID": encode(access),
                "AWS_SECRET_ACCESS_KEY": encode(key),
            }
        }

    def body(self, document):
        raw = base64.b64decode(document["data"]["thanos.yaml"])
        return raw.decode()

    def test_internal_endpoint_includes_port(self):
        document = builder.build_secret(
            self.claim(),
            self.secret(),
            "thanos-object-storage",
            "open-cluster-management-observability",
            "thanos.yaml",
            True,
        )
        text = self.body(document)
        self.assertIn('endpoint: "s3.openshift-storage.svc:443"', text)
        self.assertIn('bucket: "metrics"', text)
        self.assertIn("insecure: true", text)
        self.assertIn('access_key: "access"', text)
        self.assertIn('secret_key: "secret"', text)
        self.assertEqual(document["metadata"]["name"], "thanos-object-storage")

    def test_host_that_already_has_a_port_is_unchanged(self):
        document = builder.build_secret(
            self.claim(host="s3.example.com:8443", port="443"),
            self.secret(),
            "thanos-object-storage",
            "ns",
            "thanos.yaml",
            False,
        )
        text = self.body(document)
        self.assertIn('endpoint: "s3.example.com:8443"', text)
        self.assertIn("insecure: false", text)

    def test_secret_key_is_quoted(self):
        document = builder.build_secret(
            self.claim(),
            self.secret(key='a"b\\c'),
            "thanos-object-storage",
            "ns",
            "thanos.yaml",
            True,
        )
        text = self.body(document)
        self.assertIn(r'secret_key: "a\"b\\c"', text)

    def test_missing_host_fails(self):
        with self.assertRaises(SystemExit):
            builder.build_secret(
                self.claim(host=""),
                self.secret(),
                "thanos-object-storage",
                "ns",
                "thanos.yaml",
                True,
            )

    def test_main_writes_secret_json(self):
        with tempfile.TemporaryDirectory() as directory:
            configmap_path = os.path.join(directory, "cm.json")
            secret_path = os.path.join(directory, "secret.json")
            output_path = os.path.join(directory, "out.json")
            with open(configmap_path, "w", encoding="utf-8") as handle:
                json.dump(self.claim(), handle)
            with open(secret_path, "w", encoding="utf-8") as handle:
                json.dump(self.secret(), handle)
            os.environ["CLAIM_CONFIGMAP_FILE"] = configmap_path
            os.environ["CLAIM_SECRET_FILE"] = secret_path
            os.environ["OUTPUT_FILE"] = output_path
            os.environ["TARGET_NAME"] = "thanos-object-storage"
            os.environ["TARGET_NAMESPACE"] = "open-cluster-management-observability"
            os.environ["TARGET_KEY"] = "thanos.yaml"
            os.environ["INSECURE"] = "true"
            builder.main()
            with open(output_path, encoding="utf-8") as handle:
                document = json.load(handle)
        self.assertEqual(document["kind"], "Secret")
        self.assertIn("type: s3", self.body(document))


if __name__ == "__main__":
    unittest.main()
