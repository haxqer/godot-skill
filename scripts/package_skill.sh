#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill_root="$repo_root/skill/godot"
dist_root="$repo_root/dist"
stage_root="$dist_root/godot"
zip_path="$dist_root/godot.zip"

if [[ ! -f "$skill_root/SKILL.md" ]]; then
  echo "Missing skill payload at $skill_root" >&2
  exit 1
fi

rm -rf "$stage_root" "$zip_path"
mkdir -p "$stage_root"
cp -R "$skill_root"/. "$stage_root"/

python3 - "$stage_root" "$zip_path" <<'PY'
import os
import shutil
import sys
import zipfile

stage_root = os.path.abspath(sys.argv[1])
zip_path = os.path.abspath(sys.argv[2])
skip_dirs = {"__pycache__", ".git", ".pytest_cache"}
skip_files = {".DS_Store"}
skip_suffixes = (".pyc", ".pyo")

for root, dirs, files in os.walk(stage_root):
    for dir_name in list(dirs):
        if dir_name in skip_dirs:
            shutil.rmtree(os.path.join(root, dir_name))
            dirs.remove(dir_name)
    for file_name in files:
        if file_name in skip_files or file_name.endswith(skip_suffixes):
            os.remove(os.path.join(root, file_name))

with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for root, _, files in os.walk(stage_root):
        for file_name in files:
            file_path = os.path.join(root, file_name)
            rel_path = os.path.relpath(file_path, stage_root)
            zf.write(file_path, os.path.join("godot", rel_path))
PY

echo "Staged skill payload at $stage_root"
echo "Wrote release archive to $zip_path"
