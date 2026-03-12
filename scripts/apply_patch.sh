#!/usr/bin/env bash
set -euo pipefail

INPUT_JSON="${1:-}"
if [[ -z "${INPUT_JSON}" ]]; then
  INPUT_JSON="$(cat)"
fi

python3 - "$INPUT_JSON" <<'PY'
import json
import re
import subprocess
import sys
from pathlib import Path


BLOCK_RE = re.compile(
    r"===FILE:(?P<path>[^\n]+)===\n<<<<<<< SEARCH\n(?P<search>.*?)\n=======\n(?P<replace>.*?)\n>>>>>>> REPLACE",
    re.DOTALL,
)


def run(cmd, cwd=None, check=True):
    return subprocess.run(
        cmd,
        cwd=cwd,
        check=check,
        text=True,
        capture_output=True,
    )


def respond(**payload):
    print(json.dumps(payload, ensure_ascii=True))
    sys.exit(0)


def create_checkpoint(repo_path: Path) -> str:
    status = run(["git", "status", "--porcelain"], cwd=repo_path).stdout.strip()
    if status:
        run(["git", "add", "-A"], cwd=repo_path)
        run(
            ["git", "commit", "-m", "agent checkpoint", "--no-verify"],
            cwd=repo_path,
        )
    return run(["git", "rev-parse", "HEAD"], cwd=repo_path).stdout.strip()


data = json.loads(sys.argv[1])
repo_path = Path(data["repo_path"]).resolve()
edit_format = data.get("edit_format", "search_replace")
edit_text = data.get("edit_text", "")
max_changed_files = int(data.get("max_changed_files", 5))
max_diff_lines = int(data.get("max_diff_lines", 400))
checkpoint_ref = create_checkpoint(repo_path)

if edit_format != "search_replace":
    respond(
        ok=False,
        applied=False,
        applied_format=edit_format,
        checkpoint_ref=checkpoint_ref,
        changed_files=[],
        stop_reason="only search_replace is implemented in MVP skeleton",
    )

blocks = list(BLOCK_RE.finditer(edit_text))
if not blocks:
    respond(
        ok=False,
        applied=False,
        applied_format=edit_format,
        checkpoint_ref=checkpoint_ref,
        changed_files=[],
        stop_reason="no valid SEARCH/REPLACE blocks found",
    )

pending_writes = {}

for block in blocks:
    rel_path = block.group("path").strip()
    search = block.group("search")
    replace = block.group("replace")
    file_path = (repo_path / rel_path).resolve()
    try:
        file_path.relative_to(repo_path)
    except ValueError:
        respond(
            ok=False,
            applied=False,
            applied_format=edit_format,
            checkpoint_ref=checkpoint_ref,
            changed_files=[],
            stop_reason=f"path escapes repo: {rel_path}",
        )
    if not file_path.exists():
        respond(
            ok=False,
            applied=False,
            applied_format=edit_format,
            checkpoint_ref=checkpoint_ref,
            changed_files=[],
            stop_reason=f"target file not found: {rel_path}",
        )
    original = pending_writes.get(file_path)
    if original is None:
        original = file_path.read_text(encoding="utf-8")
    match_count = original.count(search)
    if match_count != 1:
        respond(
            ok=False,
            applied=False,
            applied_format=edit_format,
            checkpoint_ref=checkpoint_ref,
            changed_files=[],
            stop_reason=f"SEARCH block must match exactly once: {rel_path} ({match_count} matches)",
        )
    pending_writes[file_path] = original.replace(search, replace, 1)

for file_path, content in pending_writes.items():
    file_path.write_text(content, encoding="utf-8")

changed_files = [
    line.strip()
    for line in run(["git", "diff", "--name-only"], cwd=repo_path).stdout.splitlines()
    if line.strip()
]
diff_lines = run(["git", "diff", "--numstat"], cwd=repo_path).stdout.splitlines()
total_diff_lines = 0
for line in diff_lines:
    parts = line.split()
    if len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit():
        total_diff_lines += int(parts[0]) + int(parts[1])

if len(changed_files) > max_changed_files or total_diff_lines > max_diff_lines:
    run(["git", "reset", "--hard", checkpoint_ref], cwd=repo_path)
    respond(
        ok=False,
        applied=False,
        applied_format=edit_format,
        checkpoint_ref=checkpoint_ref,
        changed_files=[],
        stop_reason="edit exceeds max_changed_files or max_diff_lines",
    )

respond(
    ok=True,
    applied=True,
    applied_format=edit_format,
    checkpoint_ref=checkpoint_ref,
    changed_files=changed_files,
    stop_reason="",
)
PY
