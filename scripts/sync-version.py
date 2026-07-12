#!/usr/bin/env python3
"""Sync version number across all project files from the single source (tauri.conf.json).

Usage:
    python3 scripts/sync-version.py [new-version]

Without arguments: validates that all version references are in sync.
With a version argument: updates all files to the specified version.

Version source of truth: src-tauri/tauri.conf.json -> "version" field
Files kept in sync:
    - src-tauri/Cargo.toml -> [package].version
    - package.json -> "version" (if present)
    - web/static/js/core/config.js -> APP_VERSION
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TAURI_CONF = ROOT / "src-tauri" / "tauri.conf.json"
CARGO_TOML = ROOT / "src-tauri" / "Cargo.toml"
PACKAGE_JSON = ROOT / "package.json"
CONFIG_JS = ROOT / "web" / "static" / "js" / "core" / "config.js"

VERSION_RE = re.compile(r'^v?\d+\.\d+\.\d+(?:[-.][0-9A-Za-z.-]+)?$', re.IGNORECASE)


def read_tauri_version():
    with open(TAURI_CONF, "r", encoding="utf-8") as f:
        return json.load(f)["version"]


def update_cargo_toml(version):
    content = CARGO_TOML.read_text(encoding="utf-8")
    new_content = re.sub(
        r'^(\[package\][\s\S]*?version\s*=\s*")([^"]*)(")',
        rf'\g<1>{version}\g<3>',
        content,
        count=1,
        flags=re.MULTILINE,
    )
    if new_content == content:
        raise RuntimeError(f"Failed to update version in {CARGO_TOML}")
    CARGO_TOML.write_text(new_content, encoding="utf-8")


def update_package_json(version):
    if not PACKAGE_JSON.exists():
        return
    with open(PACKAGE_JSON, "r", encoding="utf-8") as f:
        data = json.load(f)
    if "version" not in data:
        return
    data["version"] = version
    with open(PACKAGE_JSON, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def update_config_js(version):
    if not CONFIG_JS.exists():
        return
    content = CONFIG_JS.read_text(encoding="utf-8")
    new_content = re.sub(
        r"(export\s+const\s+APP_VERSION\s*=\s*)'v?[^']*'",
        rf"\g<1>'v{version}'",
        content,
    )
    if new_content != content:
        CONFIG_JS.write_text(new_content, encoding="utf-8")


def get_config_js_version():
    if not CONFIG_JS.exists():
        return None
    content = CONFIG_JS.read_text(encoding="utf-8")
    match = re.search(r"export\s+const\s+APP_VERSION\s*=\s*'v?([^']*)'", content)
    return match.group(1) if match else None


def get_cargo_version():
    content = CARGO_TOML.read_text(encoding="utf-8")
    match = re.search(r'^version\s*=\s*"([^"]*)"', content, re.MULTILINE)
    return match.group(1) if match else None


def get_package_json_version():
    if not PACKAGE_JSON.exists():
        return None
    with open(PACKAGE_JSON, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data.get("version")


def main():
    tauri_version = read_tauri_version()

    if not VERSION_RE.match(tauri_version):
        print(f"ERROR: tauri.conf.json version '{tauri_version}' is invalid", file=sys.stderr)
        return 1

    if len(sys.argv) > 1:
        new_version = sys.argv[1].lstrip("v")
        if not VERSION_RE.match(new_version):
            print(f"ERROR: version '{new_version}' is invalid", file=sys.stderr)
            return 1

        with open(TAURI_CONF, "r", encoding="utf-8") as f:
            conf = json.load(f)
        conf["version"] = new_version
        with open(TAURI_CONF, "w", encoding="utf-8") as f:
            json.dump(conf, f, indent=2, ensure_ascii=False)
            f.write("\n")

        update_cargo_toml(new_version)
        update_package_json(new_version)
        update_config_js(new_version)

        print(f"Version synced to {new_version} across all files")
        return 0

    cargo_version = get_cargo_version()
    pkg_version = get_package_json_version()
    config_version = get_config_js_version()

    errors = []
    if cargo_version != tauri_version:
        errors.append(f"  Cargo.toml: {cargo_version} (expected {tauri_version})")
    if pkg_version and pkg_version != tauri_version:
        errors.append(f"  package.json: {pkg_version} (expected {tauri_version})")
    if config_version and config_version != tauri_version:
        errors.append(f"  config.js APP_VERSION: {config_version} (expected {tauri_version})")

    if errors:
        print(f"Version mismatch! Source: tauri.conf.json = {tauri_version}", file=sys.stderr)
        for e in errors:
            print(e, file=sys.stderr)
        print(f"\nRun: python3 scripts/sync-version.py {tauri_version}", file=sys.stderr)
        return 1

    print(f"Version OK: {tauri_version} (all files in sync)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
