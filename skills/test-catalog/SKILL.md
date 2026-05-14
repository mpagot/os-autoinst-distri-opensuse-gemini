---
name: test-catalog
description: Add or audit a Perldoc documentation header on an OSADO test module following the test catalog standard. Use when a user asks to "add header", "document", or "add catalog header" to a Perl test module.
---

<instructions>
You are an expert in openQA test module documentation. Your goal is to ensure the provided Perl module has a correct Perldoc header following the test catalog documentation standard.

**Process:**

1.  **Identify File**: The user should have provided a filename (e.g., `tests/console/foo.pm`). If not, ask for it. Verify the file exists.
2.  **Analyze File**: Read the content of the target file (`read_file`).
      a. Understand its purpose to generate a "Summary" (1 line) and a "Description" (detailed).
      b. Summary could be already available as perl comment at the file beginning: reuse it for the perldoc.
      c. Identify used openQA variables searching for get_var, get_required_var or check_var.
      d. Explore dependency, look for called methods that are imported using `use` and are implemented in files in `lib/` folder.
3.  **Detect Maintainer**: Run the maintainer detection script:
    ```bash
    .gemini/skills/test-catalog/scripts/maintainer-detect.sh <path_to_file>
    ```
    If it exits 0, use the stdout value. If it exits 1, ask the user for the maintainer in format `Team Name <email@domain>`.
4.  **Load Template**: Read the header template from `assets/template.md`.
5.  **Construct Header**:
    *   **Copyright/License**: Keep as is.
    *   **Summary**: Insert your generated 1-line summary.
    *   **Maintainer**: Use the value from step 3. Ensure both the comment line `# Maintainer: <VALUE>` and the POD section `=head1 MAINTAINER` with the same value are present.
    *   **NAME**: Format as `[directory]/[filename].pm - [Short Description]`. The directory is relative to `tests/` (e.g., `console/foo.pm - Frobnicate the bar`).
    *   **DESCRIPTION**: Insert your generated detailed description. Ensure you list primary tasks as bullet points.
    *   **SETTINGS**:
        *   List all identified variables (from step 2c) using the `=item B<VAR_NAME>` format inside the `=over` / `=back` block.
        *   Provide a brief description for each variable based on its usage in the code.
        *   If the code implies a default value (e.g., `get_var('FOO', 0)`), mention it (e.g., "Defaults to 0.").
        *   If *no* variables are used, replace the entire `=over ... =back` block with: "This module does not require any specific configuration variables for its core functionality."
        *   Please also mention settings used in the used lib/ functions
6.  **Apply Header**:
    *   Check if the file already has a header.
    *   If it has a partial/incorrect header, replace it.
    *   If it has no header, prepend the new header to the top of the file.
    *   **Important**: Use `read_file` to ensure you don't overwrite code. Use `write_file` with the full content (header + original code) to apply changes.
7.  **Verify**: Run the audit script on the file:
    ```bash
    .gemini/skills/test-catalog/scripts/audit.sh <path_to_file>
    ```
    Additionally, perform project-standard verification:
    *   Check metadata (Summary, Maintainer, Copyright): `tools/check_metadata <path_to_file>`
    *   Check POD whitespace: `make test_pod_whitespace_rule`
    *   Check for POD errors: `perldoc -T -D <path_to_file>` (Verify that the output does not contain a "POD ERRORS" section)

8.  **Refine**: If the audit script fails (returns exit code 1) or any of the checks above show issues, read the output, fix the header in the file, and re-run step 7 until it passes.

**Rules:**
*   Do NOT modify the actual Perl code logic, only the documentation header.
*   The `NAME` section must include the directory relative to `tests/`.
*   The Maintainer value must be consistent between the comment line and the POD section.
</instructions>
