#!/usr/bin/env bash
set -euo pipefail

INPUT_JSON="${1:-}"
if [[ -z "${INPUT_JSON}" ]]; then
  INPUT_JSON="$(cat)"
fi

python3 - "$INPUT_JSON" <<'PY'
import json
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
checkpoint_ref = data["checkpoint_ref"]

run(["git", "reset", "--hard", checkpoint_ref], cwd=repo_path)

print(
    json.dumps(
        {
            "ok": True,
            "rolled_back": True,
            "checkpoint_ref": checkpoint_ref,
            "stop_reason": "",
        },
        ensure_ascii=True,
    )
)
PY
