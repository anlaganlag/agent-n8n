#!/usr/bin/env bash
set -euo pipefail

INPUT_JSON="${1:-}"
if [[ -z "${INPUT_JSON}" ]]; then
  INPUT_JSON="$(cat)"
fi

python3 - "$INPUT_JSON" <<'PY'
import json
import os
import sys
from pathlib import Path


def repo_summary(repo_path: Path) -> str:
    top_level = []
    for entry in sorted(repo_path.iterdir()):
        name = entry.name + ("/" if entry.is_dir() else "")
        if name in {".git/", "node_modules/"}:
            continue
        top_level.append(name)
        if len(top_level) >= 12:
            break
    return "Top level: " + ", ".join(top_level)


def normalize_hint(item):
    if isinstance(item, str):
        return item
    if isinstance(item, dict) and "path" in item:
        return item["path"]
    return None


data = json.loads(sys.argv[1])
repo_path = Path(data["repo_path"]).resolve()
file_hints = data.get("file_hints", [])
context_file_limit = int(data.get("context_file_limit", 6))
max_file_lines = int(data.get("max_file_lines_for_context", 1000))

selected_files = []
skipped_files = []

for hint in file_hints[:context_file_limit]:
    rel_path = normalize_hint(hint)
    if not rel_path:
        continue
    file_path = (repo_path / rel_path).resolve()
    try:
        file_path.relative_to(repo_path)
    except ValueError:
        skipped_files.append({"path": rel_path, "reason": "path escapes repo"})
        continue
    if not file_path.exists() or not file_path.is_file():
        skipped_files.append({"path": rel_path, "reason": "file not found"})
        continue
    text = file_path.read_text(encoding="utf-8")
    line_count = text.count("\n") + 1
    if line_count > max_file_lines:
        skipped_files.append(
            {"path": rel_path, "reason": "file exceeds max_file_lines_for_context"}
        )
        continue
    selected_files.append({"path": rel_path, "content": text})

print(
    json.dumps(
        {
            "ok": True,
            "repo_summary": repo_summary(repo_path),
            "selected_files": selected_files,
            "skipped_files": skipped_files,
        },
        ensure_ascii=True,
    )
)
PY
