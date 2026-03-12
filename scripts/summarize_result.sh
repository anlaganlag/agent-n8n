#!/usr/bin/env bash
set -euo pipefail

INPUT_JSON="${1:-}"
if [[ -z "${INPUT_JSON}" ]]; then
  INPUT_JSON="$(cat)"
fi

python3 - "$INPUT_JSON" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path


def run(cmd, cwd=None):
    return subprocess.run(
        cmd,
        cwd=cwd,
        check=True,
        text=True,
        capture_output=True,
    )


data = json.loads(sys.argv[1])
repo_path = Path(data["repo_path"]).resolve()
lock_file = data.get("lock_file")

changed_files = [
    line.strip()
    for line in run(["git", "diff", "--name-only"], cwd=repo_path).stdout.splitlines()
    if line.strip()
]
diff_excerpt = run(["git", "diff", "--", "."], cwd=repo_path).stdout[-6000:]

if lock_file:
    try:
        os.remove(lock_file)
    except FileNotFoundError:
        pass

print(
    json.dumps(
        {
            "ok": True,
            "changed_files": changed_files,
            "diff_excerpt": diff_excerpt,
            "lock_released": bool(lock_file),
        },
        ensure_ascii=True,
    )
)
PY
