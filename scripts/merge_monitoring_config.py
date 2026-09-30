#!/usr/bin/env python3
"""Merge a desired monitoring fragment into a live ConfigMap.

The chart does not adopt cluster-monitoring-config or
user-workload-monitoring-config. The endpoint observability operator also
writes those objects, and data.config.yaml is one string, so the last writer
would own every key. This program reads the live document, merges the chart
fragment, and writes it back.

Maps merge recursively. A list or scalar in the fragment replaces that key.
Keys the fragment does not set stay, including the operator's Alertmanager
and external label entries.
"""

import json
import os
import subprocess
import sys

RELEASE_ANNOTATIONS = (
    "argocd.argoproj.io/tracking-id",
    "argocd.argoproj.io/sync-wave",
    "kubectl.kubernetes.io/last-applied-configuration",
)


class AlreadyExists(Exception):
    pass


class Conflict(Exception):
    pass


class ParseError(Exception):
    pass


def load_yaml(text):
    if text is None:
        return {}
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]
    index = 0
    if index < len(lines) and lines[index].strip() == "---":
        index += 1
    value, index = _parse_block(lines, index, 0)
    index = _next_content(lines, index)
    if index < len(lines):
        raise ParseError("trailing content at line %d" % (index + 1))
    if value is None:
        return {}
    return value


def dump_yaml(value):
    rendered = _dump(value, 0).rstrip("\n")
    if rendered == "":
        return "{}\n"
    return rendered + "\n"


def merge(base, overlay):
    if isinstance(base, dict) and isinstance(overlay, dict):
        merged = dict(base)
        for key, item in overlay.items():
            if key in merged and isinstance(merged[key], dict) and isinstance(item, dict):
                merged[key] = merge(merged[key], item)
            else:
                merged[key] = item
        return merged
    return overlay


def annotations_to_drop(metadata, namespace, name):
    annotations = (metadata or {}).get("annotations") or {}
    tracking = annotations.get("argocd.argoproj.io/tracking-id", "")
    owned = "ConfigMap:%s/%s" % (namespace, name) in tracking
    drop = []
    for key in RELEASE_ANNOTATIONS:
        if key not in annotations:
            continue
        if key == "argocd.argoproj.io/tracking-id" and not owned:
            continue
        if key == "argocd.argoproj.io/sync-wave" and not owned:
            continue
        drop.append(key)
    return drop


def reconcile(namespace, name, desired, getter, saver):
    for _attempt in range(8):
        current = getter()
        if current is None:
            body = {
                "apiVersion": "v1",
                "kind": "ConfigMap",
                "metadata": {"name": name, "namespace": namespace},
                "data": {"config.yaml": dump_yaml(desired)},
            }
            try:
                saver(body, True)
            except AlreadyExists:
                continue
            print("created %s/%s" % (namespace, name))
            return
        data = current.get("data") or {}
        live_text = data.get("config.yaml", "")
        live = load_yaml(live_text) if live_text.strip() else {}
        if not isinstance(live, dict):
            raise ParseError("config.yaml must be a map")
        merged = merge(live, desired)
        metadata = current.setdefault("metadata", {})
        drop = annotations_to_drop(metadata, namespace, name)
        if merged == live and not drop:
            print("unchanged %s/%s" % (namespace, name))
            return
        data = dict(data)
        data["config.yaml"] = dump_yaml(merged)
        current["data"] = data
        metadata.pop("managedFields", None)
        annotations = dict(metadata.get("annotations") or {})
        for key in drop:
            annotations.pop(key, None)
        if annotations:
            metadata["annotations"] = annotations
        elif "annotations" in metadata:
            metadata.pop("annotations")
        current.pop("status", None)
        try:
            saver(current, False)
        except Conflict:
            continue
        print("merged %s/%s" % (namespace, name))
        return
    raise SystemExit("gave up updating %s/%s after conflicts" % (namespace, name))


def _indent_of(line):
    if "\t" in line[: len(line) - len(line.lstrip(" \t"))]:
        raise ParseError("tabs are not allowed")
    return len(line) - len(line.lstrip(" "))


def _next_content(lines, index):
    while index < len(lines):
        stripped = lines[index].strip()
        if stripped and not stripped.startswith("#"):
            return index
        index += 1
    return index


def _parse_block(lines, index, indent):
    index = _next_content(lines, index)
    if index >= len(lines) or _indent_of(lines[index]) < indent:
        return {}, index
    if _is_list_item(lines[index], indent):
        return _parse_list(lines, index, indent)
    return _parse_map(lines, index, indent)


def _is_list_item(line, indent):
    if _indent_of(line) != indent:
        return False
    rest = line[indent:]
    return rest == "-" or rest.startswith("- ")


def _parse_map(lines, index, indent):
    result = {}
    while True:
        index = _next_content(lines, index)
        if index >= len(lines) or _indent_of(lines[index]) < indent:
            break
        if _indent_of(lines[index]) != indent:
            raise ParseError("unexpected indent at line %d" % (index + 1))
        if _is_list_item(lines[index], indent):
            raise ParseError("list item in a map at line %d" % (index + 1))
        key, rest = _split_key(lines[index].strip())
        index += 1
        value, index = _parse_rest(lines, index, indent, rest)
        result[key] = value
    return result, index


def _parse_list(lines, index, indent):
    items = []
    while True:
        index = _next_content(lines, index)
        if index >= len(lines) or _indent_of(lines[index]) < indent:
            break
        if not _is_list_item(lines[index], indent):
            break
        rest = lines[index][indent + 1 :].strip()
        index += 1
        if rest == "":
            value, index = _parse_block(lines, index, indent + 2)
        elif rest in ("{}", "{ }"):
            value = {}
        elif rest in ("[]", "[ ]"):
            value = []
        elif _looks_like_key(rest):
            value, index = _parse_map_item(lines, index, indent + 2, rest)
        else:
            value = _parse_flow_or_scalar(rest)
        items.append(value)
    return items, index


def _parse_map_item(lines, index, indent, first):
    key, rest = _split_key(first)
    value, index = _parse_rest(lines, index, indent, rest)
    result = {key: value}
    while True:
        nxt = _next_content(lines, index)
        if nxt >= len(lines) or _indent_of(lines[nxt]) < indent:
            break
        if _is_list_item(lines[nxt], indent):
            break
        more, index = _parse_map(lines, nxt, indent)
        result.update(more)
        break
    return result, index


def _parse_rest(lines, index, indent, rest):
    if rest in ("", None):
        nxt = _next_content(lines, index)
        if nxt < len(lines):
            next_indent = _indent_of(lines[nxt])
            if next_indent == indent and _is_list_item(lines[nxt], next_indent):
                return _parse_list(lines, nxt, next_indent)
            if next_indent > indent:
                return _parse_block(lines, nxt, next_indent)
        return None, index
    if rest in ("{}", "{ }"):
        return {}, index
    if rest in ("[]", "[ ]"):
        return [], index
    if rest[0] in ("|", ">"):
        return _parse_block_scalar(lines, index, indent, rest)
    return _parse_flow_or_scalar(rest), index


def _parse_block_scalar(lines, index, parent_indent, style):
    chunks = []
    block_indent = None
    while index < len(lines):
        line = lines[index]
        if line.strip() == "":
            if block_indent is not None:
                chunks.append("")
            index += 1
            continue
        current = _indent_of(line)
        if current <= parent_indent:
            break
        if block_indent is None:
            block_indent = current
        if current < block_indent:
            break
        chunks.append(line[block_indent:])
        index += 1
    text = "\n".join(chunks)
    if "-" in style:
        text = text.rstrip("\n")
    elif "+" in style:
        if text and not text.endswith("\n"):
            text += "\n"
    else:
        text = text.rstrip("\n")
        if chunks:
            text += "\n"
    return text, index


def _parse_flow_or_scalar(text):
    if text in ("{}", "{ }"):
        return {}
    if text in ("[]", "[ ]"):
        return []
    return _parse_scalar(text)


def _looks_like_key(text):
    if not text or text[0] in "\"'[{|>":
        return False
    if text.startswith(("\"", "'")):
        return False
    colon = text.find(":")
    if colon <= 0 or text[colon : colon + 3] == "://":
        return False
    key = text[:colon]
    return " " not in key and "\t" not in key


def _split_key(stripped):
    if stripped.startswith(("\"", "'")):
        key, end = _parse_quoted(stripped, 0)
        rest = stripped[end:].lstrip()
        if not rest.startswith(":"):
            raise ParseError("expected colon after %r" % key)
        return key, rest[1:].strip()
    if ":" not in stripped:
        raise ParseError("expected key at %r" % stripped)
    key, rest = stripped.split(":", 1)
    if not key or key[0] in " \t":
        raise ParseError("invalid key at %r" % stripped)
    return key.strip(), rest.strip()


def _parse_scalar(text):
    if text.startswith(("\"", "'")):
        value, end = _parse_quoted(text, 0)
        if text[end:].strip():
            raise ParseError("trailing scalar text %r" % text[end:])
        return value
    lowered = text.lower()
    if lowered in ("true", "false"):
        return lowered == "true"
    if lowered in ("null", "~"):
        return None
    if _is_int(text):
        return int(text)
    if _is_float(text):
        return float(text)
    return text


def _parse_quoted(text, start):
    quote = text[start]
    chars = []
    index = start + 1
    while index < len(text):
        char = text[index]
        if quote == "'" and char == "'":
            if index + 1 < len(text) and text[index + 1] == "'":
                chars.append("'")
                index += 2
                continue
            return "".join(chars), index + 1
        if quote == "\"" and char == "\\":
            if index + 1 >= len(text):
                raise ParseError("dangling escape")
            escape = text[index + 1]
            chars.append({"n": "\n", "t": "\t", "r": "\r", "\\": "\\", "\"": "\""}.get(escape, escape))
            index += 2
            continue
        if char == quote:
            return "".join(chars), index + 1
        chars.append(char)
        index += 1
    raise ParseError("unterminated string")


def _is_int(text):
    if text in ("", "+", "-"):
        return False
    body = text[1:] if text[0] in "+-" else text
    return body.isdigit()


def _is_float(text):
    if text.count(".") != 1:
        return False
    left, right = text.split(".")
    return _is_int(left) and right.isdigit()


def _dump(value, indent):
    pad = " " * indent
    if isinstance(value, dict):
        if not value:
            return pad + "{}"
        lines = []
        for key, item in value.items():
            rendered_key = _dump_key(key)
            if isinstance(item, dict) and item:
                lines.append("%s%s:\n%s" % (pad, rendered_key, _dump(item, indent + 2)))
            elif isinstance(item, list) and item:
                lines.append("%s%s:\n%s" % (pad, rendered_key, _dump(item, indent + 2)))
            elif isinstance(item, str) and "\n" in item:
                lines.append("%s%s: |-\n%s" % (pad, rendered_key, _dump_block(item, indent + 2)))
            else:
                lines.append("%s%s: %s" % (pad, rendered_key, _dump_inline(item)))
        return "\n".join(lines)
    if isinstance(value, list):
        if not value:
            return pad + "[]"
        lines = []
        for item in value:
            if isinstance(item, dict) and item:
                body = _dump(item, indent + 2)
                first, _, rest = body.partition("\n")
                head = "- " + first.lstrip()
                if rest:
                    head = head + "\n" + rest
                lines.append(pad + head)
            elif isinstance(item, list) and item:
                lines.append("%s-\n%s" % (pad, _dump(item, indent + 2)))
            else:
                lines.append("%s- %s" % (pad, _dump_inline(item)))
        return "\n".join(lines)
    return pad + _dump_inline(value)


def _dump_block(text, indent):
    pad = " " * indent
    parts = []
    for line in text.split("\n"):
        parts.append(pad + line if line else "")
    return "\n".join(parts)


def _dump_key(key):
    text = str(key)
    if _plain_ok(text):
        return text
    return json.dumps(text)


def _dump_inline(value):
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, dict):
        return "{}"
    if isinstance(value, list):
        return "[]"
    if isinstance(value, str) and _plain_ok(value):
        return value
    return json.dumps("" if value is None else str(value))


def _plain_ok(text):
    if text == "" or text != text.strip():
        return False
    if text.lower() in ("true", "false", "null", "~", "yes", "no"):
        return False
    if _is_int(text) or _is_float(text):
        return False
    if text.startswith(("{", "[", "&", "*", "!", "|", ">", "'", "\"", "%", "@", "`", "#")):
        return False
    if any(char in text for char in ":#{}[]&*!|>'\"%@`,"):
        return False
    return True


def _run(args):
    completed = subprocess.run(args, capture_output=True, text=True)
    return completed.returncode, completed.stdout, completed.stderr


def _kubectl_get(namespace, name):
    cli = os.environ.get("CLI", "oc")
    code, out, err = _run([cli, "get", "configmap", name, "-n", namespace, "-o", "json"])
    if code != 0:
        if "NotFound" in err:
            return None
        sys.stderr.write(err)
        raise SystemExit(code or 1)
    return json.loads(out)


def _kubectl_save(obj, create):
    cli = os.environ.get("CLI", "oc")
    path = "/tmp/monitoring-configmap.json"
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(obj, handle)
    verb = "create" if create else "replace"
    code, _out, err = _run([cli, verb, "-f", path])
    if code == 0:
        return
    if create and "AlreadyExists" in err:
        raise AlreadyExists(err)
    if not create and ("Conflict" in err or "the object has been modified" in err):
        raise Conflict(err)
    sys.stderr.write(err)
    raise SystemExit(code or 1)


def main():
    namespace = os.environ["TARGET_NAMESPACE"]
    name = os.environ["TARGET_NAME"]
    with open(os.environ["DESIRED_FILE"], encoding="utf-8") as handle:
        desired = load_yaml(handle.read())
    if not isinstance(desired, dict):
        raise SystemExit("desired config must be a map")
    reconcile(namespace, name, desired, lambda: _kubectl_get(namespace, name), _kubectl_save)


if __name__ == "__main__":
    main()
