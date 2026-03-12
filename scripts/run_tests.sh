#!/usr/bin/env bash
set -euo pipefail

INPUT_JSON="${1:-}"
if [[ -z "${INPUT_JSON}" ]]; then
  INPUT_JSON="$(cat)"
fi

python3 - "$INPUT_JSON" <<'PY'
import json
import re
import shlex
import subprocess
import sys
from pathlib import Path


RULES = [
    ("lint", re.compile(r"eslint|prettier", re.IGNORECASE)),
    ("type", re.compile(r"TS\d{4}|type error", re.IGNORECASE)),
    ("import", re.compile(r"Cannot find module|Module not found", re.IGNORECASE)),
    ("syntax", re.compile(r"SyntaxError|Unexpected token", re.IGNORECASE)),
    ("unit_test", re.compile(r"expected|received|AssertionError", re.IGNORECASE)),
]


def respond(**payload):
    print(json.dumps(payload, ensure_ascii=True))
    sys.exit(0)


data = json.loads(sys.argv[1])
repo_path = Path(data["repo_path"]).resolve()
test_command = data["test_command"]
allowed_test_commands = set(data.get("allowed_test_commands", []))
test_timeout_seconds = int(data.get("test_timeout_seconds", 300))
allowed_failure_types = set(data.get("allowed_failure_types", []))

if test_command not in allowed_test_commands:
    respond(
        ok=False,
        passed=False,
        executed_command=test_command,
        failure_type="environment",
        repairable=False,
        output_excerpt="test_command is not in allowed_test_commands",
    )

try:
    completed = subprocess.run(
        shlex.split(test_command),
        cwd=repo_path,
        text=True,
        capture_output=True,
        timeout=test_timeout_seconds,
    )
except subprocess.TimeoutExpired:
    respond(
        ok=True,
        passed=False,
        executed_command=test_command,
        failure_type="timeout",
        repairable=False,
        output_excerpt=f"test command timed out after {test_timeout_seconds} seconds",
    )
except FileNotFoundError:
    respond(
        ok=True,
        passed=False,
        executed_command=test_command,
        failure_type="environment",
        repairable=False,
        output_excerpt="test command executable not found",
    )

output = ((completed.stdout or "") + "\n" + (completed.stderr or "")).strip()
excerpt = output[-4000:] if output else ""

if completed.returncode == 0:
    respond(
        ok=True,
        passed=True,
        executed_command=test_command,
        failure_type="",
        repairable=False,
        output_excerpt=excerpt,
    )

failure_type = "unknown"
for name, pattern in RULES:
    if pattern.search(output):
        failure_type = name
        break

repairable = failure_type in allowed_failure_types
respond(
    ok=True,
    passed=False,
    executed_command=test_command,
    failure_type=failure_type,
    repairable=repairable,
    output_excerpt=excerpt,
)
PY
