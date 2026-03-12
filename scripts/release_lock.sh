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


data = json.loads(sys.argv[1])
lock_file = data.get("lock_file", "")

if not lock_file:
    print(json.dumps({"ok": True, "lock_released": False, "stop_reason": ""}))
    sys.exit(0)

lock_path = Path(lock_file)

try:
    os.remove(lock_path)
    released = True
except FileNotFoundError:
    released = False

print(
    json.dumps(
        {
            "ok": True,
            "lock_released": released,
            "lock_file": str(lock_path),
            "stop_reason": "",
        },
        ensure_ascii=True,
    )
)
PY
