---
name: sles4sap-catalog
description: Adds a standard Perldoc header to a SLES4SAP test module and audits it. Use this when a user asks to "add header" or "document" a SLES4SAP perl module. This skill is about creating documentation for the test catalog initiative.
---

<instructions>
You are an expert in openQA SLES4SAP test module documentation. Your goal is to ensure the provided Perl module has a correct Perldoc header.

**Process:**

1.  **Identify File**: The user should have provided a filename (e.g., `tests/sles4sap/foo.pm`). If not, ask for it. Verify the file exists.
2.  **Analyze File**: Read the content of the target file (`read_file`).
      a. Understand its purpose to generate a "Summary" (1 line) and a "Description" (detailed).
      b. Summary could be already available as perl comment at the file beginning: reuse it for the perldoc.
      c. Identify used openQA variables searching for get_var, get_required_var or check_var.
      d. Explore dependency, look for called methods that are imported using `use` and are implemented in files in `lib/` folder.`
3.  **Load Template**: Read the header template from `assets/template.md`.
4.  **Construct Header**:
    *   **Copyright/License**: Keep as is.
    *   **Summary**: Insert your generated 1-line summary.
    *   **Maintainer**: Ensure both the comment line `# Maintainer: QE-SAP <qe-sap@suse.de>` and the POD section `=head1 MAINTAINER` with `QE-SAP <qe-sap@suse.de>` are present.
    *   **NAME**: Format as `[directory]/[filename].pm - [Short Description]`. (e.g., `sles4sap/foo.pm - Frobnicate the bar`).
    *   **DESCRIPTION**: Insert your generated detailed description. Ensure you list primary tasks as bullet points.
    *   **SETTINGS**:
        *   List all identified variables (from step 2c) using the `=item B<VAR_NAME>` format inside the `=over` / `=back` block.
        *   Provide a brief description for each variable based on its usage in the code.
        *   If the code implies a default value (e.g., `get_var('FOO', 0)`), mention it (e.g., "Defaults to 0.").
        *   If *no* variables are used, replace the entire `=over ... =back` block with: "This module does not require any specific configuration variables for its core functionality.""
        *   Please also mention settings used in the used lib/ functions
5.  **Apply Header**:
    *   Check if the file already has a header.
    *   If it has a partial/incorrect header, replace it.
    *   If it has no header, prepend the new header to the top of the file.
    *   **Important**: Use `read_file` to ensure you don't overwrite code. Use `write_file` with the full content (header + original code) to apply changes.
6.  **Verify**: Run the audit script on the file:
    ```bash
    .gemini/skills/sles4sap-catalog/scripts/audit.sh <path_to_file>
    ```
    Additionally, perform project-standard verification:
    *   Check metadata (Summary, Maintainer, Copyright): `tools/check_metadata <path_to_file>`
    *   Check POD whitespace: `make test_pod_whitespace_rule`
    *   Check for POD errors: `perldoc -T -D <path_to_file>` (Verify that the output does not contain a "POD ERRORS" section)

7.  **Refine**: If the audit script fails (returns exit code 1) or any of the checks above show issues, read the output, fix the header in the file, and re-run step 6 until it passes.

**Rules:**
*   Do NOT modify the actual Perl code logic, only the documentation header.
*   The `NAME` section must include the directory relative to `tests/`.
*   The `Maintainer` must be exactly `QE-SAP <qe-sap@suse.de>`.
</instructions>
