#!/usr/bin/env python3
"""Prepare the Tauri frontend-dist directory by copying web frontend files."""

import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "web")
DST_DIR = os.path.join(ROOT, "src-tauri", "frontend-dist")

# Directories/files inside web/ that should NOT be shipped in the native app.
EXCLUDE = {"downloads"}


def should_exclude(name):
    return name in EXCLUDE


def copy_tree(src, dst):
    os.makedirs(dst, exist_ok=True)
    for name in os.listdir(src):
        if should_exclude(name):
            continue
        src_path = os.path.join(src, name)
        dst_path = os.path.join(dst, name)
        if os.path.isdir(src_path):
            copy_tree(src_path, dst_path)
        else:
            shutil.copy2(src_path, dst_path)


def main():
    if not os.path.isdir(SRC_DIR):
        print(f"ERROR: web directory not found at {SRC_DIR}", file=sys.stderr)
        return 1

    # Clean previous build
    if os.path.isdir(DST_DIR):
        shutil.rmtree(DST_DIR)

    copy_tree(SRC_DIR, DST_DIR)
    print(f"Prepared frontend-dist at {DST_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
