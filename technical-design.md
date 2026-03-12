# n8n Coding Agent MVP Technical Design

## 1. Objective

Translate the MVP PRD into an implementation-friendly design with:

- one n8n workflow
- a small set of local scripts
- one config file
- compact LLM prompts
- explicit stop conditions

This design optimizes for minimum code and operational simplicity.

## 2. High-Level Architecture

### Components

1. `n8n workflow`
2. `agent config file`
3. `local runner scripts`
4. `LLM endpoint`
5. `target repository`

### Responsibility Split

#### n8n

- receive task input
- load config
- orchestrate step order
- call scripts
- call LLM
- persist per-run state
- decide loop / stop / finish

#### Local scripts

- inspect repo state
- create working branch
- collect targeted context
- apply code edits safely
- run tests
- rollback to a checkpoint when needed
- release repo locks on terminal paths
- summarize diffs and logs

#### LLM

- generate plan
- generate code edits
- propose repair edits
- summarize implementation

## 3. Recommended File Layout

```text
agent-n8n/
  prd.md
  technical-design.md
  config/
    agent.json
  prompts/
    plan.md
    patch.md
    repair.md
    summary.md
  scripts/
    check_repo.sh
    collect_context.sh
    apply_patch.sh
    run_tests.sh
    rollback_checkpoint.sh
    release_lock.sh
    summarize_result.sh
```

## 4. Workflow Shape

Use one workflow with a bounded repair loop.

### Node Sequence

1. Manual Trigger or Webhook
2. Set Task Payload
3. Read Config
4. Run `check_repo.sh`
5. If precheck failed -> Finish
6. Run `collect_context.sh`
7. Call LLM with `plan.md`
8. Validate plan
9. Call LLM with `patch.md`
10. Run `apply_patch.sh`
11. If code edit failed -> Finish
12. Run `run_tests.sh`
13. If tests passed -> Run `summarize_result.sh` -> Finish
14. If tests failed and repair count < max -> Call LLM with `repair.md`
15. Run `apply_patch.sh`
16. Run `run_tests.sh`
17. Repeat until pass or retry cap reached
18. Run `summarize_result.sh`
19. Finish

## 5. Workflow State

Keep workflow state in a compact JSON object.

### State Shape

```json
{
  "task": {
    "id": "task-20260312-001",
    "title": "Add validation to create user endpoint",
    "requirement": "Reject invalid email input and return 400 with error message",
    "acceptance_criteria": [
      "invalid email returns 400",
      "valid email still creates user",
      "existing tests continue to pass"
    ],
    "file_hints": [
      "src/routes/users.ts",
      "tests/users.test.ts"
    ]
  },
  "config": {
    "repo_path": "/path/to/repo",
    "default_branch": "main",
    "test_command": "pnpm test",
    "max_repair_attempts": 2
  },
  "run": {
    "branch_name": "agent/task-20260312-001",
    "repair_attempts": 0,
    "status": "running"
  },
  "artifacts": {
    "context_summary": "",
    "plan_text": "",
    "edit_text": "",
    "test_output": "",
    "diff_summary": ""
  }
}
```

## 6. Config File

Use one JSON file to avoid extra dependencies.

### Example

File: `config/agent.json`

```json
{
  "repo_path": "/absolute/path/to/target-repo",
  "default_branch": "main",
  "branch_prefix": "agent/",
  "workspace_lock_file": ".agent-run.lock",
  "test_command": "pnpm test",
  "allowed_test_commands": [
    "pnpm test"
  ],
  "test_timeout_seconds": 300,
  "max_repair_attempts": 2,
  "max_changed_files": 5,
  "max_diff_lines": 400,
  "context_file_limit": 6,
  "max_file_lines_for_context": 1000,
  "edit_format": "search_replace",
  "fallback_edit_format": "unified_diff",
  "search_replace_context_lines": 3,
  "prefer_targeted_tests_from_hints": false,
  "allowed_failure_types": [
    "lint",
    "type",
    "unit_test",
    "syntax",
    "import"
  ]
}
```

## 7. Script Interfaces

All scripts should:

- accept JSON input through stdin or first argument
- return JSON output only
- use exit code `0` for handled responses
- use exit code `1` only for unexpected script crashes

This makes n8n integration much easier.

## 8. Script Contract Details

### `scripts/check_repo.sh`

Purpose:

- verify repo exists
- verify git available
- verify worktree clean
- acquire repo-level lock
- create working branch
- verify test command executable

Input:

```json
{
  "repo_path": "/path/to/repo",
  "default_branch": "main",
  "branch_prefix": "agent/",
  "workspace_lock_file": ".agent-run.lock",
  "task_id": "task-20260312-001",
  "test_command": "pnpm test",
  "allowed_test_commands": [
    "pnpm test"
  ]
}
```

Output:

```json
{
  "ok": true,
  "repo_clean": true,
  "lock_acquired": true,
  "lock_file": "/path/to/repo/.git/.agent-run.lock",
  "branch_name": "agent/task-20260312-001",
  "stop_reason": ""
}
```

### `scripts/collect_context.sh`

Purpose:

- build repo tree summary
- resolve file hints
- collect selected file contents
- reject oversized files instead of naive truncation

Input:

```json
{
  "repo_path": "/path/to/repo",
  "file_hints": [
    "src/routes/users.ts",
    "tests/users.test.ts"
  ],
  "context_file_limit": 6,
  "max_file_lines_for_context": 1000
}
```

Output:

```json
{
  "ok": true,
  "repo_summary": "Node API with src/, tests/, package.json",
  "selected_files": [
    {
      "path": "src/routes/users.ts",
      "content": "..."
    },
    {
      "path": "tests/users.test.ts",
      "content": "..."
    }
  ],
  "skipped_files": [
    {
      "path": "src/large-module.ts",
      "reason": "file exceeds max_file_lines_for_context"
    }
  ]
}
```

### `scripts/apply_patch.sh`

Purpose:

- validate edit payload exists
- reject oversized diffs
- apply `SEARCH/REPLACE` blocks by default
- fallback to unified diff only when configured
- require unique `SEARCH` match per block
- require enough surrounding context in each block
- create a git checkpoint before each apply attempt
- return changed files

Input:

```json
{
  "repo_path": "/path/to/repo",
  "edit_format": "search_replace",
  "edit_text": "<<<<<<< SEARCH ... ======= ... >>>>>>> REPLACE",
  "search_replace_context_lines": 3,
  "max_changed_files": 5,
  "max_diff_lines": 400
}
```

Output:

```json
{
  "ok": true,
  "applied": true,
  "applied_format": "search_replace",
  "checkpoint_ref": "HEAD",
  "changed_files": [
    "src/routes/users.ts",
    "tests/users.test.ts"
  ],
  "stop_reason": ""
}
```

### `scripts/run_tests.sh`

Purpose:

- run the fixed default test command
- optionally prefer a targeted hinted test command in future iterations
- capture stdout/stderr
- classify failure
- trim logs

Input:

```json
{
  "repo_path": "/path/to/repo",
  "test_command": "pnpm test",
  "allowed_test_commands": [
    "pnpm test"
  ],
  "test_timeout_seconds": 300,
  "prefer_targeted_tests_from_hints": false,
  "file_hints": [
    "tests/users.test.ts"
  ],
  "allowed_failure_types": [
    "lint",
    "type",
    "unit_test",
    "syntax",
    "import"
  ]
}
```

Output:

```json
{
  "ok": true,
  "passed": false,
  "executed_command": "pnpm test",
  "failure_type": "unit_test",
  "repairable": true,
  "output_excerpt": "Expected status 400 but received 200"
}
```

### `scripts/summarize_result.sh`

Purpose:

- collect final git diff
- create changed file list
- create concise summary input for final LLM summary or direct output

Input:

```json
{
  "repo_path": "/path/to/repo"
}
```

Output:

```json
{
  "ok": true,
  "changed_files": [
    "src/routes/users.ts",
    "tests/users.test.ts"
  ],
  "diff_excerpt": "..."
}
```

## 9. Prompt Design

Prompts should be short, explicit, and role-specific.

### `prompts/plan.md`

Purpose:

- turn the task into a small execution plan

Template:

```md
You are working inside one existing repository.

Task title:
{{title}}

Requirement:
{{requirement}}

Acceptance criteria:
{{acceptance_criteria}}

Repository summary:
{{repo_summary}}

Relevant files:
{{selected_files}}

Return JSON with:
- task_understanding
- target_files
- change_strategy
- risks
- should_stop
- stop_reason
```

### `prompts/patch.md`

Purpose:

- generate initial patch

Template:

```md
Implement the task in the repository below.

Task understanding:
{{task_understanding}}

Acceptance criteria:
{{acceptance_criteria}}

Relevant files:
{{selected_files}}

Rules:
- Return `SEARCH/REPLACE` blocks only
- Modify only necessary files
- Keep changes small
- Do not add deploy logic
- Do not rewrite unrelated code
```

### `prompts/repair.md`

Purpose:

- generate targeted repair patch after failure

Template:

```md
The previous code edit did not pass tests.

Acceptance criteria:
{{acceptance_criteria}}

Current changed files:
{{changed_files}}

Test failure type:
{{failure_type}}

Test failure excerpt:
{{output_excerpt}}

Current diff:
{{diff_excerpt}}

Rules:
- Return `SEARCH/REPLACE` blocks only
- Fix only the observed failure
- Keep changes minimal
- Do not touch unrelated files
- Only use the latest failure excerpt provided here
```

### `prompts/summary.md`

Purpose:

- produce final human-readable summary

Template:

```md
Summarize this coding run for a developer.

Task title:
{{title}}

Acceptance criteria:
{{acceptance_criteria}}

Changed files:
{{changed_files}}

Diff excerpt:
{{diff_excerpt}}

Test result:
{{test_result}}

Repair attempts:
{{repair_attempts}}

Return JSON with:
- summary
- risks
- follow_up_checks
```

## 10. Decision Logic In n8n

### Stop Immediately If

- `check_repo.ok` is false
- `plan.should_stop` is true
- `apply_patch.applied` is false
- `run_tests.ok` is false
- `run_tests.repairable` is false
- `repair_attempts >= max_repair_attempts`

### Continue If

- code edit applied successfully
- tests failed in a repairable way
- repair attempts still available

## 11. Branch Strategy

Use a branch per run.

Recommended format:

`agent/<task-id>`

Rules:

- branch from configured default branch
- do not reuse an old branch
- stop if branch already exists unless explicit overwrite is allowed

## 12. Logging Strategy

Keep logs concise.

Store:

- one-line step status
- trimmed command outputs
- final stop reason

Do not store:

- full repository contents
- unbounded test logs
- every intermediate prompt version unless debugging is enabled

## 13. Failure Classification Rules

Use simple heuristics in `run_tests.sh`.

### Example Mapping

- contains `eslint` -> `lint`
- contains `TS2322` or `Type error` -> `type`
- contains `Cannot find module` -> `import`
- contains `SyntaxError` -> `syntax`
- contains `expected` and `received` -> `unit_test`

Classify as non-repairable when:

- command not found
- missing env var
- connection refused to required service
- test process timeout caused by environment boot failure

## 14. Context And Edit Guardrails

### Edit Format

Default edit format:

- `SEARCH/REPLACE`

Fallback edit format:

- unified diff

Reason:

- LLMs often generate brittle line-numbered diffs
- text-anchor replacement is usually more tolerant in MVP conditions
- unique-match enforcement is simpler and safer than aggressive fuzzy matching in MVP

### Search/Replace Match Rules

Each `SEARCH/REPLACE` block must:

- identify exactly one match in the target file
- include enough surrounding context to disambiguate common snippets
- stop immediately if zero or multiple matches are found

MVP should prefer deterministic exact matching over fuzzy replacement.

### Oversized Files

Do not trim large source files by raw character count.

Rule:

- if a selected file exceeds `max_file_lines_for_context`, skip it
- include the skipped path and reason in the context payload
- stop if too few useful files remain to implement safely

### Repair Context

Each repair prompt should contain only:

- latest failure excerpt
- latest current diff
- latest changed file list

Do not include the full history of previous failures.

### Checkpoints And Rollback

Before every apply attempt:

- create a checkpoint commit if there are pending changes
- record the checkpoint ref in workflow state

If a repair attempt makes the workspace worse or exceeds retry limits:

- reset back to the last known good checkpoint or initial branch state
- keep the failed diff as an artifact for review

## 15. Recommended n8n Nodes

Use the smallest set possible:

- Manual Trigger or Webhook
- Set
- Read Binary File or Code node for config
- Execute Command
- HTTP Request for LLM API
- If
- Merge
- Loop or repeated branch with counter

Avoid complex custom node development in MVP.

## 16. Security And Safety

Minimum safeguards:

- fixed repo path only
- fixed command allowlist only
- no deploy command
- no arbitrary shell from model output
- code edit application only through script
- branch isolation for each run
- repo-level lock before any write operation

## 17. First Implementation Order

Build in this sequence:

1. `config/agent.json`
2. `scripts/check_repo.sh`
3. `scripts/run_tests.sh`
4. `scripts/collect_context.sh`
5. `scripts/apply_patch.sh`
6. prompt files
7. n8n workflow
8. `scripts/summarize_result.sh`

This order gets the risky plumbing stable before prompt tuning.

## 18. Simplest Viable Version

If we want to reduce code even more for version `0.1`, use this compromise:

- skip final LLM summary
- use shell scripts only, with optional small Python helper for robust `SEARCH/REPLACE` application
- use file hints as the main context selector
- stop after 1 repair attempt instead of 2

That version is less capable but much faster to build.

## 19. Recommended Next Deliverables

The next concrete artifacts to create are:

- `config/agent.json`
- stub versions of all shell scripts
- `prompts/*.md`
- exported `workflow.json` for n8n
