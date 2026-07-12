#!/usr/bin/env python3
"""Prepare the Tauri frontend-dist directory by copying web frontend files."""

import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "web")
DST_DIR = os.path.join(ROOT, "src-tauri", "frontend-dist")

# Directories inside web/ that should NOT be shipped in the native app.
EXCLUDE_DIRS = {"downloads"}

# File extensions that should NOT be shipped in the native app.
EXCLUDE_EXTENSIONS = {".md", ".map", ".ts", ".scss", ".sass", ".less"}

# Specific files to exclude.
EXCLUDE_FILES = {".gitkeep", ".DS_Store", "Thumbs.db"}


def should_exclude(name, is_dir=False):
    if is_dir:
        return name in EXCLUDE_DIRS
    if name in EXCLUDE_FILES:
        return True
    _, ext = os.path.splitext(name)
    return ext.lower() in EXCLUDE_EXTENSIONS


def copy_tree(src, dst):
    os.makedirs(dst, exist_ok=True)
    for name in os.listdir(src):
        src_path = os.path.join(src, name)
        dst_path = os.path.join(dst, name)
        if os.path.isdir(src_path):
            if should_exclude(name, is_dir=True):
                continue
            copy_tree(src_path, dst_path)
        else:
            if should_exclude(name):
                continue
            shutil.copy2(src_path, dst_path)


def main():
    if not os.path.isdir(SRC_DIR):
        print(f"ERROR: web directory not found at {SRC_DIR}", file=sys.stderr)
        return 1

    # Clean previous build
    if os.path.isdir(DST_DIR):
        shutil.rmtree(DST_DIR)

    copy_tree(SRC_DIR, DST_DIR)

    # Report size
    total_size = 0
    for dirpath, _dirnames, filenames in os.walk(DST_DIR):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            total_size += os.path.getsize(fp)
    print(f"Prepared frontend-dist at {DST_DIR}")
    print(f"Total size: {total_size / 1024:.1f} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
