# Agent Guidelines for os-autoinst-distri-opensuse-gemini

This repository develops and maintains **AI coding assistant skills and
commands** for the `os-autoinst-distri-opensuse` (OSADO) project. It is
packaged as a Gemini CLI extension and also supports OpenCode, Claude Code,
and Pi Agent via the [Agent Skills open standard](https://agentskills.io).

As an agent working in *this* repository, your focus is on creating, refining,
and validating skills that help OSADO developers.

## 1. Build, Lint, and Test

### Test Suite

*   **Run overlay installer tests:**
    ```bash
    ./t/test_install.sh
    ```
    *Note: Creates a temporary `fake_osado` directory to simulate the target.*

*   **Run integration tests (requires podman or docker):**
    The CI container image is maintained in a separate repository:
    [`mpagot/osado-gemini-tester`](https://github.com/mpagot/osado-gemini-tester)
    (published to `ghcr.io/mpagot/osado-gemini-tester:latest`).
    It includes gemini-cli, opencode, claude-code, git, perl, jq, and gh.
    ```bash
    podman run --rm -v "$PWD:/src:ro" -w /src \
        ghcr.io/mpagot/osado-gemini-tester:latest ./t/test_integration.sh
    ```

### Development Workflow

To test the extension locally with Gemini CLI:
```bash
gemini extensions link .
# Then start a new gemini session: skills/commands/context load automatically
```

To test the legacy manual installer:
```bash
./tools/install.sh /path/to/local/os-autoinst-distri-opensuse
./tools/install.sh --uninstall /path/to/local/os-autoinst-distri-opensuse
```

### Linting
*   **Bash:** Use `shellcheck` for all `.sh` files.
    ```bash
    shellcheck tools/*.sh t/*.sh skills/*/scripts/*.sh
    ```
*   **Markdown:** Ensure valid YAML frontmatter in `SKILL.md` files.

## 2. Code Style & Conventions

### Bash Scripts (`*.sh`)
*   **Shebang:** Always use `#!/bin/bash`.
*   **Error Handling:**
    *   Start every script with `set -e` to fail fast.
    *   Validate arguments at the beginning of the script.
    *   Exit with `exit 1` on failure and `exit 0` on success.
*   **Formatting:**
    *   Indentation: 4 spaces.
    *   Lines should generally not exceed 80-100 characters.
    *   Use `[[ ... ]]` for conditions instead of `[ ... ]`.
*   **Naming:**
    *   Variables/Functions: `snake_case` (e.g., `link_files`, `target_dir`).
    *   Globals/Constants: `UPPER_CASE` (e.g., `REPO_ROOT`, `OVERLAY_DIR`).
*   **Scoping:** Use `local` for variables inside functions to avoid polluting the global namespace.
*   **Logging:** Use color-coded helper functions for output (see `tools/install.sh` for reference):
    *   `log_info` (Blue)
    *   `log_success` (Green)
    *   `log_warn` (Yellow)
    *   `log_error` (Red)
*   **Paths:**
    *   **Absolute Paths:** Always resolve paths to absolute paths using `$(cd ... && pwd)`.
    *   **Self-Location:** Never assume the script is run from a specific directory; use `dirname "${BASH_SOURCE[0]}"`.
*   **Text Processing:** Prefer `awk` or `sed` for complex log parsing or text manipulation over Bash loops (see `extract_log_section.sh` or `audit.sh` for examples).

### Perl Scripts (`*.pl`)
*   **Pragmas:** Always start with `use strict; use warnings;`.
*   **CLI Arguments:** Use `Getopt::Long` for option parsing. All scripts must support `--help`, `--repo`, `--json`, and `--verbose`.
*   **Documentation:**
    *   Each function (except `print_usage`) gets a POD `=head2` block describing purpose, arguments, and return value.
    *   `print_usage()` is the canonical usage reference — do not duplicate its content in header comments.
*   **Naming:** `snake_case` for variables and functions (e.g., `get_git_files`, `$commit_hash`).
*   **Dependencies:** Standard library only (`JSON::PP`, `Getopt::Long`, `File::Basename`, `Cwd`). No external CPAN modules.
*   **Structured Output:** Use `JSON::PP` for `--json` mode. Use `JSON::PP::true`/`JSON::PP::false` for booleans.
*   **Comments:** Keep comments that explain cryptic Perl syntax (e.g., `\Q\E` for regex literal quoting, `$? >> 8` for exit code extraction). Remove comments that merely restate what the code does.
*   **Error Handling:** `die` with a descriptive message on unrecoverable errors. Validate inputs early.
*   **Self-Location:** Use `dirname(abs_path($0))` to find sibling scripts, never hardcoded paths.

### Skill Definitions (`SKILL.md`)
1.  **YAML Frontmatter:** Must contain `name` and `description`.
    ```yaml
    ---
    name: my-skill
    description: Action-oriented description of what the skill does.
    ---
    ```
2.  **Instructions:** Wrap the main prompt in `<instructions>` XML tags to clearly separate it from context.
3.  **Be Action-Oriented:** Use clear, imperative language. Prefer scripts over inline logic.
4.  **Directory Structure:**
    *   Root: `skills/<skill-name>/`
    *   Logic: `scripts/` (for complex Bash/Python/Perl logic). **Do not put logic in Markdown.**
    *   Assets: `assets/` (templates, static files).

### Custom Commands (`commands/`)
*   Defined in TOML files (e.g., `github_pr_create.toml`).
*   Must contain `description` and `prompt`.
*   Use `"""` for multi-line prompts.
*   Use placeholders like `!{shell command}` for dynamic context injection.
*   **Note:** Custom commands are Gemini CLI-only (TOML format is not portable).

## 3. Architecture

### Distribution Model
This repository supports multiple installation strategies:

| Method | For whom | Mechanism |
|--------|----------|-----------|
| `gemini extensions install` | End users (Gemini CLI) | Native extension |
| `tools/install.sh` | End users (legacy) | Symlink overlay |
| `gemini extensions link .` | Developers of this repo | Local dev testing |
| Manual copy to `.agents/skills/` | OpenCode/Pi Agent users | File-based |
| Manual copy to `.claude/skills/` | Claude Code users | File-based |

### Key Files

| File | Purpose | Audience |
|------|---------|----------|
| `gemini-extension.json` | Extension manifest | Gemini CLI (native install) |
| `skills/` | Agent skills (SKILL.md + scripts) | All tools |
| `commands/` | Custom slash commands (TOML) | Gemini CLI only |
| `AGENTS.md` (this file) | Dev guidelines for THIS repo | Developers |

### Common Tasks
*   **Adding a new Skill:**
    1.  Create directory `skills/<name>/`.
    2.  Add `SKILL.md` with YAML frontmatter.
    3.  Add `scripts/` if needed.
    4.  Run `./t/test_install.sh` to verify it links correctly.
    5.  Test with `gemini extensions link .` and start a new session.
*   **Modifying the Install Script:**
    *   Edit `tools/install.sh`.
    *   **MUST** run `./t/test_install.sh` to verify no regression in safety checks.

## 4. Safety Rules

1.  **Non-Destructive:** The install script will *never* overwrite a file in the target that is not a symlink to this repo.
2.  **Conflict Awareness:** When adding new files, ensure they don't conflict with common user filenames.
3.  **Symlink Logic:** The installer mirrors the directory structure (using `mkdir -p`) but symlinks individual files. This allows users to add their own files alongside ours.
4.  **No Secrets:** Never hardcode API keys or credentials.
5.  **Injection Prevention:** Be mindful of how user input is passed to shell scripts to prevent command injection.
6.  **No PII:** Do not mention specific users (names or GitHub handles) or name specific teams.
