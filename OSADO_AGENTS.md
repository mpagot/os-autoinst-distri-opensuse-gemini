# openQA Tests for openSUSE - Agent Guidelines

This repository contains the openQA test distribution for openSUSE (`os-autoinst-distri-opensuse`). It is primarily written in Perl.

## 1. Build, Lint, and Test

### Setup
Before running tests, ensure dependencies are installed:
```bash
make prepare
```
This clones `os-autoinst` and installs CPAN dependencies.

**Important Environment Variable:**
To run perl scripts or check compilation manually, set `PERL5LIB`:
```bash
export PERL5LIB=".:lib:os-autoinst:os-autoinst/lib:$PERL5LIB"
```

### Running Tests
*   **Run all unit tests:**
    ```bash
    make unit-test
    ```
*   **Run a single unit test file:**
    ```bash
    prove -l -Ios-autoinst/ t/03_utils_systemd.t
    ```
*   **Check compilation of all `.pm` files:**
    ```bash
    make test-compile
    ```
*   **Check compilation of modified files (faster):**
    ```bash
    make test-compile-changed
    ```
    Alternatively, use the helper script: `.gemini/skills/test_compile.sh <file>`
*   **Run static analysis (YAML, metadata, etc.):**
    ```bash
    make test-static
    ```

### Linting and Formatting
*   **Format code (PerlTidy):**
    ```bash
    make tidy       # Formats changed files
    make tidy-full  # Formats all files
    ```
    *Always run `make tidy` before committing.*
*   **Lint code (PerlCritic):**
    ```bash
    make perlcritic
    ```
*   **Check code style:**
    ```bash
    make test-code-style
    ```

## 2. Code Style & Conventions

### General Perl
*   **Strictness:** Always use `use strict;` and `use warnings;`.
*   **Formatting:** Follow the `.perltidyrc` configuration (line length 160, no spaces before semicolons, etc.).
*   **Naming:** Use `snake_case` for subroutines and variables.
*   **Imports:** Explicitly import functions.
    ```perl
    use utils qw(fully_patch_system zypper_call);
    ```

### openQA Specifics
*   **Sleep:** **NEVER** use `sleep()`. Use synchronization primitives like `wait_serial`, `wait_screen_change`, or `assert_screen`.
*   **Tumbleweed First:** Assume openSUSE Tumbleweed is the default target. Use conditions for older products, not the other way around. Avoid `is_tumbleweed()`.
*   **Soft Failures:** usage of `record_soft_failure` **MUST** include a bug reference (e.g., `bsc#12345`, `poo#6789`).
*   **Screen Assertions:** Prefer multi-tag `assert_screen` with `match_has_tag` over `check_screen`.
    ```perl
    assert_screen([qw(yast2_console-finished yast2_missing_package)]);
    if (match_has_tag('yast2_missing_package')) { ... }
    ```
*   **Exec:** Use `grep -E` and `grep -F` instead of deprecated `egrep` and `fgrep`.

### Project Structure
*   `lib/`: Helper modules (e.g., `utils.pm`).
*   `tests/`: Integration/functional test modules.
*   `t/`: Unit tests for libraries.
*   `schedule/`: YAML schedule definitions.
*   `products/`: Product definitions.

### New Files
*   Use `SPDX-License-Identifier` for licensing.
*   Do not add copyright years to file headers.
*   Use `my ($self) = @_;` for method parameter parsing.

### Commit Messages
*   Subject line < 72 chars, starts with Capital letter, NO trailing dot.
*   Empty line between subject and body.
*   Include "why" in the body, not just "what".
*   **Do NOT use conventional commit format** (e.g., `feat(scope):`). Just use a descriptive subject.

## 3. Workflow for Agents
1.  **Understand:** Read related code in `lib/` or `tests/`. Search for existing patterns using `grep`.
2.  **Edit:** Apply changes.
3.  **Format:** Run `make tidy`.
4.  **Verify:**
    *   Run `make test-compile-changed` to catch syntax errors immediately.
    *   If editing a library with unit tests, run the specific test with `prove`.
    *   If no unit tests exist, consider adding one in `t/`.

## 4. Pull Request Workflow
When creating a PR, follow these steps:
1.  **Inspect Changes:** `git diff --staged`
2.  **Commit:**
    *   Message must NOT follow conventional commit format.
    *   Subject: Capitalized, no trailing dot, < 72 chars.
    *   Body: Explain "what" and "why".
    *   Get user approval for the message.
3.  **Push:** `git push --set-upstream origin <branch>`
