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
- Return SEARCH/REPLACE blocks only
- Use the same exact block format as the initial patch prompt
- Fix only the observed failure
- Keep changes minimal
- Do not touch unrelated files
- Only use the latest failure excerpt provided here
