#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"


def run(cmd, cwd=None, check=True, env=None, timeout=None):
    return subprocess.run(
        cmd,
        cwd=cwd,
        check=check,
        text=True,
        capture_output=True,
        env=env,
        timeout=timeout,
    )


def run_json(script_name, payload):
    script_path = SCRIPTS / script_name
    completed = run([str(script_path), json.dumps(payload)])
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{script_name} did not return valid JSON: {completed.stdout}") from exc


def git(repo, *args):
    return run(["git", *args], cwd=repo)


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def setup_repo(base_dir: Path) -> Path:
    repo = base_dir / "repo"
    repo.mkdir()
    git(repo, "init", "-b", "main")
    git(repo, "config", "user.name", "Codex Demo")
    git(repo, "config", "user.email", "demo@example.com")

    write(
        repo / "src/app.js",
        "export function greet() {\n  return 'hello';\n}\n",
    )
    write(
        repo / "src/repeated.js",
        "export function flag() {\n  return true;\n}\n\nexport function flagAgain() {\n  return true;\n}\n",
    )
    write(repo / "tests/pass.sh", "#!/usr/bin/env bash\nexit 0\n")
    write(repo / "tests/slow.sh", "#!/usr/bin/env bash\nsleep 3\nexit 0\n")
    os.chmod(repo / "tests/pass.sh", 0o755)
    os.chmod(repo / "tests/slow.sh", 0o755)
    git(repo, "add", ".")
    git(repo, "commit", "-m", "initial")
    return repo


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def case(name):
    print(f"[RUN] {name}")


def ok(name):
    print(f"[OK]  {name}")


def edit_block(path, search, replace):
    return (
        f"===FILE:{path}===\n"
        f"<<<<<<< SEARCH\n{search}\n=======\n{replace}\n>>>>>>> REPLACE"
    )


def main():
    with tempfile.TemporaryDirectory(prefix="agent-n8n-demo-") as tmp:
        tmp_path = Path(tmp)
        repo = setup_repo(tmp_path)

        case("apply_patch unique match")
        unique = run_json(
            "apply_patch.sh",
            {
                "repo_path": str(repo),
                "edit_format": "search_replace",
                "edit_text": edit_block(
                    "src/app.js",
                    "export function greet() {\n  return 'hello';\n}",
                    "export function greet() {\n  return 'hello world';\n}",
                ),
                "max_changed_files": 5,
                "max_diff_lines": 20,
            },
        )
        require(unique["applied"] is True, f"expected apply success, got {unique}")
        require("hello world" in (repo / "src/app.js").read_text(encoding="utf-8"), "expected file to change")
        git(repo, "reset", "--hard", unique["checkpoint_ref"])
        ok("apply_patch unique match")

        case("apply_patch zero match")
        zero = run_json(
            "apply_patch.sh",
            {
                "repo_path": str(repo),
                "edit_format": "search_replace",
                "edit_text": edit_block("src/app.js", "return 'missing';", "return 'x';"),
                "max_changed_files": 5,
                "max_diff_lines": 20,
            },
        )
        require(zero["applied"] is False, f"expected apply failure, got {zero}")
        require("0 matches" in zero["stop_reason"], f"unexpected stop reason: {zero['stop_reason']}")
        ok("apply_patch zero match")

        case("apply_patch multi match")
        multi = run_json(
            "apply_patch.sh",
            {
                "repo_path": str(repo),
                "edit_format": "search_replace",
                "edit_text": edit_block("src/repeated.js", "  return true;", "  return false;"),
                "max_changed_files": 5,
                "max_diff_lines": 20,
            },
        )
        require(multi["applied"] is False, f"expected apply failure, got {multi}")
        require("2 matches" in multi["stop_reason"], f"unexpected stop reason: {multi['stop_reason']}")
        ok("apply_patch multi match")

        case("apply_patch threshold rollback")
        threshold = run_json(
            "apply_patch.sh",
            {
                "repo_path": str(repo),
                "edit_format": "search_replace",
                "edit_text": edit_block(
                    "src/app.js",
                    "export function greet() {\n  return 'hello';\n}",
                    "export function greet() {\n  return 'hello';\n  console.log('1');\n  console.log('2');\n  console.log('3');\n}",
                ),
                "max_changed_files": 5,
                "max_diff_lines": 1,
            },
        )
        require(threshold["applied"] is False, f"expected threshold failure, got {threshold}")
        require(
            (repo / "src/app.js").read_text(encoding="utf-8") == "export function greet() {\n  return 'hello';\n}\n",
            "expected file to be reset after threshold failure",
        )
        ok("apply_patch threshold rollback")

        case("run_tests whitelist pass")
        passed = run_json(
            "run_tests.sh",
            {
                "repo_path": str(repo),
                "test_command": "bash tests/pass.sh",
                "allowed_test_commands": ["bash tests/pass.sh"],
                "test_timeout_seconds": 5,
                "allowed_failure_types": ["lint", "type", "unit_test", "syntax", "import"],
            },
        )
        require(passed["passed"] is True, f"expected test success, got {passed}")
        ok("run_tests whitelist pass")

        case("run_tests whitelist blocked")
        blocked = run_json(
            "run_tests.sh",
            {
                "repo_path": str(repo),
                "test_command": "bash tests/pass.sh",
                "allowed_test_commands": ["bash tests/slow.sh"],
                "test_timeout_seconds": 5,
                "allowed_failure_types": ["lint", "type", "unit_test", "syntax", "import"],
            },
        )
        require(blocked["ok"] is False, f"expected whitelist block, got {blocked}")
        require("allowed_test_commands" in blocked["output_excerpt"], "expected whitelist stop reason")
        ok("run_tests whitelist blocked")

        case("run_tests timeout")
        timeout_case = run_json(
            "run_tests.sh",
            {
                "repo_path": str(repo),
                "test_command": "bash tests/slow.sh",
                "allowed_test_commands": ["bash tests/slow.sh"],
                "test_timeout_seconds": 1,
                "allowed_failure_types": ["lint", "type", "unit_test", "syntax", "import"],
            },
        )
        require(timeout_case["failure_type"] == "timeout", f"expected timeout, got {timeout_case}")
        require(timeout_case["repairable"] is False, "timeout should not be repairable")
        ok("run_tests timeout")

        case("run_tests command not found")
        missing = run_json(
            "run_tests.sh",
            {
                "repo_path": str(repo),
                "test_command": "missing-cmd",
                "allowed_test_commands": ["missing-cmd"],
                "test_timeout_seconds": 5,
                "allowed_failure_types": ["lint", "type", "unit_test", "syntax", "import"],
            },
        )
        require(missing["failure_type"] == "environment", f"expected environment failure, got {missing}")
        require(missing["repairable"] is False, "missing command should not be repairable")
        ok("run_tests command not found")

        case("checkpoint rollback")
        changed = run_json(
            "apply_patch.sh",
            {
                "repo_path": str(repo),
                "edit_format": "search_replace",
                "edit_text": edit_block(
                    "src/app.js",
                    "export function greet() {\n  return 'hello';\n}",
                    "export function greet() {\n  return 'checkpoint';\n}",
                ),
                "max_changed_files": 5,
                "max_diff_lines": 20,
            },
        )
        require(changed["applied"] is True, f"expected apply success, got {changed}")
        rollback = run_json(
            "rollback_checkpoint.sh",
            {
                "repo_path": str(repo),
                "checkpoint_ref": changed["checkpoint_ref"],
            },
        )
        require(rollback["rolled_back"] is True, f"expected rollback success, got {rollback}")
        require("checkpoint" not in (repo / "src/app.js").read_text(encoding="utf-8"), "expected rollback to restore file")
        require(git(repo, "status", "--porcelain").stdout.strip() == "", "expected clean repo after rollback")
        ok("checkpoint rollback")

        lock_payload = {
            "repo_path": str(repo),
            "default_branch": "main",
            "branch_prefix": "agent/",
            "workspace_lock_file": ".agent-run.lock",
            "task_id": "lock-one",
            "test_command": "bash tests/pass.sh",
            "allowed_test_commands": ["bash tests/pass.sh"],
        }

        case("lock acquisition and normal release")
        lock_result = run_json("check_repo.sh", lock_payload)
        lock_file = Path(lock_result["lock_file"])
        require(lock_result["lock_acquired"] is True and lock_file.exists(), f"expected active lock, got {lock_result}")
        second = run_json(
            "check_repo.sh",
            {
                **lock_payload,
                "task_id": "lock-two",
            },
        )
        require(second["ok"] is False, f"expected second process rejection, got {second}")
        require(second["stop_reason"] == "repository is busy", f"unexpected stop reason: {second}")
        released = run_json("release_lock.sh", {"lock_file": str(lock_file)})
        require(released["lock_released"] is True, f"expected release success, got {released}")
        require(not lock_file.exists(), "expected lock file to be removed")
        git(repo, "checkout", "main")
        ok("lock acquisition and normal release")

        case("lock auto-release on check_repo failure")
        branch_exists = run_json(
            "check_repo.sh",
            {
                **lock_payload,
                "task_id": "lock-one",
            },
        )
        require(branch_exists["ok"] is False, f"expected branch exists failure, got {branch_exists}")
        leaked_lock = repo / ".git" / ".agent-run.lock"
        require(not leaked_lock.exists(), "expected lock to be cleaned up on failure")
        ok("lock auto-release on check_repo failure")

        case("lock release on abnormal exit via trap")
        trap_lock = repo / ".git" / ".trap-demo.lock"
        env = os.environ.copy()
        env["LOCK_PATH"] = str(trap_lock)
        holder = subprocess.Popen(
            [
                "bash",
                "-lc",
                'cleanup(){ rm -f "$LOCK_PATH"; exit 0; }; trap cleanup EXIT INT TERM; echo $$ > "$LOCK_PATH"; sleep 30 & wait',
            ],
            env=env,
            text=True,
        )
        for _ in range(20):
            if trap_lock.exists():
                break
            time.sleep(0.1)
        require(trap_lock.exists(), "expected trap lock to be created")
        busy = run_json(
            "check_repo.sh",
            {
                **lock_payload,
                "workspace_lock_file": ".trap-demo.lock",
                "task_id": "lock-three",
            },
        )
        require(busy["ok"] is False and busy["stop_reason"] == "repository is busy", f"expected busy rejection, got {busy}")
        holder.terminate()
        holder.wait(timeout=5)
        for _ in range(20):
            if not trap_lock.exists():
                break
            time.sleep(0.1)
        require(not trap_lock.exists(), "expected trap to remove lock file after termination")
        ok("lock release on abnormal exit via trap")

        print("\nAll local demo validations passed.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"[FAIL] {exc}", file=sys.stderr)
        sys.exit(1)
