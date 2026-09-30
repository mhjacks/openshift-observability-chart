"""Build the Thanos object-storage Secret from an ObjectBucketClaim."""

import base64
import json
import os


def yaml_double_quote(value):
    text = str(value)
    escaped = (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
    )
    return '"' + escaped + '"'


def endpoint(host, port):
    host = (host or "").strip()
    port = (port or "").strip()
    if port and ":" not in host:
        return host + ":" + port
    return host


def decode_secret_value(data, key):
    raw = (data or {}).get(key) or ""
    if not raw:
        raise SystemExit("object bucket secret is missing " + key)
    return base64.b64decode(raw).decode()


def thanos_yaml(bucket, endpoint_value, access_key, secret_key, insecure):
    # Thanos config.insecure selects plain HTTP. NooBaa serves HTTPS on port 443
    # and closes a plain HTTP connection. Skip verification instead: the
    # in-cluster certificate is not in the Thanos trust store.
    lines = [
        "type: s3",
        "config:",
        "  bucket: " + yaml_double_quote(bucket),
        "  endpoint: " + yaml_double_quote(endpoint_value),
        "  insecure: false",
        "  access_key: " + yaml_double_quote(access_key),
        "  secret_key: " + yaml_double_quote(secret_key),
    ]
    if insecure:
        lines.extend(
            [
                "  http_config:",
                "    insecure_skip_verify: true",
            ]
        )
    lines.append("")
    return "\n".join(lines)


def build_secret(configmap, secret, target_name, target_namespace, target_key, insecure):
    data = configmap.get("data") or {}
    host = (data.get("BUCKET_HOST") or "").strip()
    bucket = (data.get("BUCKET_NAME") or "").strip()
    if not host or not bucket:
        raise SystemExit("object bucket configmap is missing BUCKET_HOST or BUCKET_NAME")
    secret_data = secret.get("data") or {}
    body = thanos_yaml(
        bucket,
        endpoint(host, data.get("BUCKET_PORT") or ""),
        decode_secret_value(secret_data, "AWS_ACCESS_KEY_ID"),
        decode_secret_value(secret_data, "AWS_SECRET_ACCESS_KEY"),
        insecure,
    )
    encoded = base64.b64encode(body.encode()).decode()
    return {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {
            "name": target_name,
            "namespace": target_namespace,
        },
        "type": "Opaque",
        "data": {target_key: encoded},
    }


def main():
    with open(os.environ["CLAIM_CONFIGMAP_FILE"], encoding="utf-8") as handle:
        configmap = json.load(handle)
    with open(os.environ["CLAIM_SECRET_FILE"], encoding="utf-8") as handle:
        secret = json.load(handle)
    insecure = os.environ.get("INSECURE", "true").lower() in ("1", "true", "yes")
    document = build_secret(
        configmap,
        secret,
        os.environ["TARGET_NAME"],
        os.environ["TARGET_NAMESPACE"],
        os.environ["TARGET_KEY"],
        insecure,
    )
    with open(os.environ["OUTPUT_FILE"], "w", encoding="utf-8") as handle:
        json.dump(document, handle)


if __name__ == "__main__":
    main()
