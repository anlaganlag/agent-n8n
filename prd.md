# n8n Coding Agent MVP PRD

## 1. Goal

Build a minimum viable coding agent with n8n for a single fixed repository.

Primary flow:

`PRD -> plan -> code edit -> test -> fix -> result`

This MVP explicitly does **not** include deploy.

The design goal is:

- minimum code
- controllable risk
- easy to debug
- easy to stop and inspect by a human

## 2. Product Positioning

This is **not** a fully autonomous software engineer.

This is a workflow agent that:

1. reads a structured requirement
2. gathers a small amount of repository context
3. asks an LLM to generate a small code edit
4. applies the code edit
5. runs a fixed test command
6. if tests fail, sends failure context back to the LLM for limited repair
7. outputs summary, diff, and logs for human review

## 3. Scope

### In Scope

- one fixed repository only
- one fixed local execution environment
- input is a structured PRD / task description
- structured edit-based code changes
- one fixed test command
- automated repair with strict retry limit
- human review at the end

### Out of Scope

- deploy
- auto merge
- auto PR creation
- multi-repo support
- choosing tests dynamically
- long-running memory across tasks
- autonomous environment repair
- database migrations with no human review
- direct whole-file overwrite by default

## 4. Key Decisions For Minimum Code

To keep implementation small and stable, the MVP uses these constraints:

- single fixed repo, not arbitrary repos
- structured edit output, not full-file regeneration
- fixed test command, not agent-selected tests
- max 2 repair loops
- stop on unsafe or ambiguous situations
- n8n handles orchestration only
- local scripts handle repo inspection, code edit application, and test execution

## 5. User Story

As a developer, I want to submit a requirement and let an n8n-based agent propose and apply a small code edit, run tests, and attempt a small number of fixes, so that I can speed up implementation while keeping final review in human hands.

## 6. Success Criteria

The MVP is successful if it can reliably do the following on the target repo:

- accept a structured requirement
- generate a focused implementation plan
- modify only relevant files
- apply a generated code edit successfully
- run the configured test command
- attempt automatic repair up to 2 times when test output is actionable
- stop safely and provide logs, edit result, and summary for human review

## 7. Non-Goals

The MVP should not try to:

- replace engineering judgment
- understand any repository with no setup
- repair infrastructure or secret-management issues
- resolve flaky tests automatically
- decide when production is safe to deploy

## 8. Assumptions

- the repository path is fixed in configuration
- git is installed
- dependencies are already installed
- the test command already works when code is correct
- the execution environment has all required env vars
- there is an available LLM endpoint
- a human will inspect the result before any deployment action

## 9. Workflow Overview

### Step 1. Receive Task

Input includes:

- task title
- structured requirement
- acceptance criteria
- optional file hints

### Step 2. Validate Preconditions

The workflow checks:

- repo path exists
- working tree is clean
- required commands exist
- configured test command is available

If any check fails, stop immediately.

### Step 3. Gather Minimal Context

Collect only small, useful context:

- repo tree summary
- relevant files
- test command
- coding instructions if available

Do not dump the whole repository into the prompt.

### Step 4. Generate Plan

LLM produces:

- concise task understanding
- target files
- change strategy
- expected risks

If the plan is too broad or too uncertain, stop for review.

### Step 5. Generate Code Edit

LLM outputs structured edits only.

Preferred format for MVP:

- `SEARCH/REPLACE` blocks

Fallback format:

- unified diff

Do not allow unrestricted freeform whole-repo rewrites.

### Step 6. Apply Code Edit

A local script applies the generated edit.

If edit application fails, stop and return the error.

### Step 7. Run Tests

Run one fixed command only, for example:

`npm test`

or

`pnpm test`

This is configured once for the target repo.

### Step 8. Repair Loop

If tests fail and the error looks repairable:

- send failure summary, relevant logs, and current diff to the LLM
- ask for an updated code edit
- re-apply the edit
- re-run tests

Maximum repair attempts: `2`

Each repair attempt should only include the latest failure output.
Do not carry the full failure history forward.

### Step 9. Final Output

Return:

- status: success / failed / stopped
- implementation summary
- files changed
- final diff or edit summary
- test result summary
- repair attempts used
- stop reason if incomplete

## 10. Recommended Architecture

### n8n Responsibilities

- trigger workflow
- manage state between steps
- call LLM
- call local scripts
- store run metadata
- send final notification / result

### Local Script Responsibilities

Use scripts for the parts n8n is bad at:

- inspect repository state
- extract targeted file context
- apply code edits safely
- run tests
- collect and trim logs
- classify failure as repairable or non-repairable

This keeps n8n prompts smaller and reduces node complexity.

## 11. Minimal Components

The MVP likely needs:

- 1 n8n workflow
- 1 configuration file
- 3 to 5 local scripts

Suggested scripts:

- `check_repo`
- `collect_context`
- `apply_patch`
- `run_tests`
- `summarize_result`

## 12. State Model

Each run should store:

- task id
- repo path
- branch name
- plan summary
- changed files
- current code edit
- test outputs
- repair count
- final status

Keep the state small and textual.

## 13. Guardrails

The workflow must stop when:

- working tree is dirty
- code edit touches too many files
- code edit application fails
- test command crashes because of environment issues
- repair count exceeds limit
- LLM output is ambiguous or malformed
- requirement is too vague to implement safely

## 14. Repairable vs Non-Repairable Failures

### Repairable

- lint failures
- type errors
- deterministic unit test failures
- missing imports
- small syntax errors

### Non-Repairable

- missing secrets
- service outage
- database unavailable
- flaky tests
- broken local environment
- package install problems not caused by the patch
- migration or destructive data issues

Non-repairable failures should stop the workflow instead of looping.

## 15. Main Risks And Pitfalls

### 1. Edit Format Fragility

Strict unified diff application is often brittle because LLMs may hallucinate line numbers or context.

Mitigation:

- use `SEARCH/REPLACE` blocks as the default edit format
- support unified diff only as a fallback mode
- use bounded fuzzy matching when applying text edits

### 2. Too Much Context

If too many files are sent to the LLM, cost rises and code quality drops.

Mitigation:

- send only targeted files
- include summaries instead of raw large files

### 3. Unsafe File Rewrites

Whole-file regeneration can overwrite valid code.

Mitigation:

- structured edit-only changes
- file count and diff-size limits

### 4. Infinite Fix Loops

Repeated repair attempts can waste time and damage code quality.

Mitigation:

- hard retry cap of 2
- stop on repeated same failure pattern
- only send the latest failure into the next repair prompt

### 5. Full Test Cost And Noise

Running the full test suite on every loop can make the workflow slow and expose unrelated flaky failures.

Mitigation:

- keep one fixed default test command in MVP
- allow optional future optimization to run hinted tests first
- stop if failures appear unrelated or flaky

### 6. False Success

Tests may pass even if the requirement is not truly implemented.

Mitigation:

- require acceptance criteria in input
- include implementation summary for human review

### 7. Environment Problems Masquerading As Code Problems

The agent may try to "fix code" when the real issue is the runtime environment.

Mitigation:

- preflight checks
- classify non-repairable failures

### 8. Oversized File Truncation

Blind truncation can hide critical code structure and cause the model to misunderstand the file.

Mitigation:

- reject oversized files instead of naive truncation
- ask for narrower `file_hints`
- include a clear note when a file was skipped for size

## 16. Input Contract

Suggested task input:

```json
{
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
}
```

## 17. Output Contract

Suggested final output:

```json
{
  "status": "success",
  "summary": "Added email validation in user creation flow and updated tests.",
  "files_changed": [
    "src/routes/users.ts",
    "tests/users.test.ts"
  ],
  "repair_attempts": 1,
  "test_command": "pnpm test",
  "test_result": "passed"
}
```

## 18. MVP Implementation Notes

To minimize code, prefer this execution pattern:

- n8n webhook or manual trigger receives task
- n8n calls a local script to validate repo state
- n8n calls LLM with a compact prompt and targeted context
- n8n receives patch text
- n8n calls local patch script
- n8n calls local test script
- n8n either loops once or twice for repair, or exits

Avoid building:

- custom UI first
- complex memory store
- vector database
- multi-agent decomposition
- autonomous deployment logic

## 19. Open Configuration Items

These should be fixed in config, not generated dynamically:

- repo path
- default branch
- working branch naming rule
- test command
- max repair attempts
- max changed files
- max diff size
- LLM model selection

## 20. Definition of Done

The MVP is done when:

- a user can submit one structured task
- the workflow creates a safe working branch
- the workflow generates and applies a patch
- the workflow runs the fixed test command
- the workflow optionally performs up to 2 repair attempts
- the workflow returns a clear final result package for human review
- no deploy action is performed automatically

## 21. Recommended Next Phase After MVP

Only after MVP is stable, consider:

- PR creation
- partial test selection
- better context selection
- per-repo configuration profiles
- human approval checkpoint before patch apply
- deployment workflow as a separate controlled pipeline
