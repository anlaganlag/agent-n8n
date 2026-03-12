Implement the task in the repository below.

Task understanding:
{{task_understanding}}

Acceptance criteria:
{{acceptance_criteria}}

Relevant files:
{{selected_files}}

Rules:
- Return SEARCH/REPLACE blocks only
- Use this exact block format:
  ===FILE:path/to/file===
  <<<<<<< SEARCH
  old text
  =======
  new text
  >>>>>>> REPLACE
- Each SEARCH block must match exactly once in the target file
- Include enough surrounding context to make the match unique
- Modify only necessary files
- Keep changes small
- Do not add deploy logic
- Do not rewrite unrelated code
