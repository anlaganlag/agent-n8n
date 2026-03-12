#!/usr/bin/env bash
set -euo pipefail

INPUT_JSON="${1:-}"
if [[ -z "${INPUT_JSON}" ]]; then
  INPUT_JSON="$(cat)"
fi

# Write INPUT_JSON to a temp file to avoid shell expansion issues
TMP_JSON=$(mktemp)
echo "$INPUT_JSON" > "$TMP_JSON"

python3 - "$TMP_JSON" <<'PY'
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
    # Ensure we are in a clean state or commit what we have
    status = run(["git", "status", "--porcelain"], cwd=repo_path).stdout.strip()
    if status:
        run(["git", "add", "-A"], cwd=repo_path)
        run(
            ["git", "commit", "-m", "agent checkpoint", "--no-verify"],
            cwd=repo_path,
        )
    return run(["git", "rev-parse", "HEAD"], cwd=repo_path).stdout.strip()

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    
    repo_path = Path(data["repo_path"]).resolve()
    edit_format = data.get("edit_format", "search_replace")
    edit_text = data.get("edit_text", "")
    max_changed_files = int(data.get("max_changed_files", 5))
    max_diff_lines = int(data.get("max_diff_lines", 400))
    
    checkpoint_ref = create_checkpoint(repo_path)

    if edit_format != "search_replace":
        respond(ok=False, applied=False, stop_reason="Only search_replace supported", checkpoint_ref=checkpoint_ref)

    blocks = list(BLOCK_RE.finditer(edit_text))
    if not blocks:
        respond(ok=False, applied=False, stop_reason="No valid SEARCH/REPLACE blocks found", checkpoint_ref=checkpoint_ref)

    pending_writes = {}
    for block in blocks:
        rel_path = block.group("path").strip()
        search = block.group("search").strip("\r")
        replace = block.group("replace").strip("\r")
        file_path = (repo_path / rel_path).resolve()
        
        if not file_path.exists():
            respond(ok=False, applied=False, stop_reason=f"File not found: {rel_path}", checkpoint_ref=checkpoint_ref)
            
        original = pending_writes.get(file_path)
        if original is None:
            original = file_path.read_text(encoding="utf-8")
            
        # Standardize line endings for matching
        if original.count(search) != 1:
            respond(ok=False, applied=False, stop_reason=f"Match count mismatch for {rel_path}", checkpoint_ref=checkpoint_ref)
            
        pending_writes[file_path] = original.replace(search, replace, 1)

    for file_path, content in pending_writes.items():
        file_path.write_text(content, encoding="utf-8")

    changed_files = [
        line.strip()
        for line in run(["git", "diff", "--name-only"], cwd=repo_path).stdout.splitlines()
        if line.strip()
    ]
    
    respond(ok=True, applied=True, checkpoint_ref=checkpoint_ref, changed_files=changed_files)
except Exception as e:
    print(json.dumps({"ok": False, "error": str(e)}))
PY

rm "$TMP_JSON"
