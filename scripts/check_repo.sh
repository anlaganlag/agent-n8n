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


def fail(stop_reason, **extra):
    payload = {"ok": False, "stop_reason": stop_reason}
    payload.update(extra)
    print(json.dumps(payload, ensure_ascii=True))
    sys.exit(0)


def run(cmd, cwd=None, check=True):
    return subprocess.run(
        cmd,
        cwd=cwd,
        check=check,
        text=True,
        capture_output=True,
    )


data = json.loads(sys.argv[1])
repo_path = Path(data["repo_path"]).resolve()
default_branch = data["default_branch"]
branch_prefix = data["branch_prefix"]
task_id = data["task_id"]
test_command = data["test_command"]
allowed_test_commands = set(data.get("allowed_test_commands", []))
workspace_lock_file = data.get("workspace_lock_file", ".agent-run.lock")
lock_path = repo_path / ".git" / workspace_lock_file
lock_acquired = False
success = False

if not repo_path.exists():
    fail("repo_path does not exist")

if not (repo_path / ".git").exists():
    fail("repo_path is not a git repository")

if test_command not in allowed_test_commands:
    fail("test_command is not in allowed_test_commands")

try:
    run(["git", "--version"], cwd=repo_path)
except Exception:
    fail("git is not available")

status = run(["git", "status", "--porcelain"], cwd=repo_path).stdout.strip()
if status:
    fail("working tree is not clean", repo_clean=False)

try:
    fd = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    os.write(fd, str(os.getpid()).encode("utf-8"))
    os.close(fd)
    lock_acquired = True
except FileExistsError:
    fail("repository is busy", repo_clean=True, lock_acquired=False, lock_file=str(lock_path))

try:
    branch_name = f"{branch_prefix}{task_id}"
    existing_branch = run(
        ["git", "branch", "--list", branch_name],
        cwd=repo_path,
    ).stdout.strip()
    if existing_branch:
        fail(
            "target branch already exists",
            repo_clean=True,
            lock_acquired=True,
            lock_file=str(lock_path),
            branch_name=branch_name,
        )

    run(["git", "checkout", default_branch], cwd=repo_path)
    run(["git", "checkout", "-b", branch_name], cwd=repo_path)
    success = True
    print(
        json.dumps(
            {
                "ok": True,
                "repo_clean": True,
                "lock_acquired": True,
                "lock_file": str(lock_path),
                "branch_name": branch_name,
                "stop_reason": "",
            },
            ensure_ascii=True,
        )
    )
finally:
    if lock_acquired and not success:
        try:
            os.remove(lock_path)
        except FileNotFoundError:
            pass
PY
