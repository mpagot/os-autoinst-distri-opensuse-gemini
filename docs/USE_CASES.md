# Use Cases and Workflows

This document describes the practical situations where each skill and command
in the OSADO AI Assistant helps developers working on
[os-autoinst-distri-opensuse](https://github.com/os-autoinst/os-autoinst-distri-opensuse).

For a quick visual overview, see the
[See It in Action](../README.md#see-it-in-action) section of the README.

## Quick Reference

| Situation | Skill / Command |
|-----------|-----------------|
| "I changed `lib/foo.pm`, what do I test?" | `vr-planner` |
| "Give me an `openqa-clone-job` command for my change" | `vr-planner` (Phase 3) |
| "I have `autoinst-log.txt` from a failed job -- what happened?" | `openqa-log-analyzer` |
| "Was this timeout caused by a slow worker host?" | `openqa-log-analyzer` |
| "Which command in the log took the longest?" | `openqa-log-analyzer` |
| "Does my edited `.pm` file compile?" | `perl-test-compile` |
| "Add a Perldoc header to this SLES4SAP test module" | `sles4sap-catalog` |
| "Commit my staged changes and open a PR" | `/github_pr_create` |

## 1. Planning Verification Runs -- `vr-planner`

The `vr-planner` skill answers the question every OSADO developer faces after
making changes: **"How do I verify this?"**

It analyses your `git diff`, classifies touched files by category (`lib/`,
`tests/`, `data/`, `schedule/`), and produces a concrete testing plan. The
skill operates in three phases.

**Phase 1 -- Classify and plan (offline).** A single orchestrator script
(`classify_changes.pl`) reads the change set and chains the right helpers
automatically:

- `find_unit_test.pl` -- locates unit tests in `t/` for changed library modules.
- `find_affected_tests.pl` -- finds test modules in `tests/` that import
  changed libraries, with optional function-level caller analysis.
- `find_test_schedule.pl` -- resolves test modules to YAML schedule files.
- `find_data_consumers.pl` -- traces which Perl files reference changed data
  files.

**Phase 2 -- Targeted deep-dive (on request).** If you want more detail on one
category, the individual helpers can be called directly with specific files.

**Phase 3 -- Find a clonable openQA job (network, user-gated).**
`find_openqa_job.pl` queries a live openQA instance and produces copy-paste
`openqa-clone-job` commands with your fork and branch pre-filled as `CASEDIR`.
The skill always confirms the target host before making network calls.

### Practical situations

- **After editing a library module (`lib/*.pm`):** You changed
  `lib/sles4sap/azure_cli.pm`. The skill finds the matching unit test, lists
  all test modules that import the library, and identifies the YAML schedules
  to clone.

- **After editing a test module (`tests/*.pm`):** You modified
  `tests/sles4sap/hana_install.pm`. The skill locates which
  `schedule/*.yml` files include it, so you know exactly which openQA job to
  clone.

- **After editing data files (`data/*`):** You changed a template or config
  under `data/`. The skill finds all Perl files that reference that data file,
  so you can trace the impact.

- **Getting a clonable openQA job:** Once schedules are identified, the skill
  queries openqa.suse.de (for SLE) or openqa.opensuse.org (for Tumbleweed) and
  produces a ready-to-use `openqa-clone-job` command.

- **Deciding whether a VR is needed at all:** For changes limited to `t/`,
  `.github/`, `Makefile`, `variables.md`, or pure comment/lint fixes, the skill
  reports that no VR is required.

## 2. Understanding openQA Log Files -- `openqa-log-analyzer`

The `openqa-log-analyzer` skill helps developers make sense of the log files
produced by os-autoinst during test execution. It does not download or fetch
logs -- the developer provides local log files and the skill parses their
internal structure.

openQA jobs produce two key log files that this skill operates on:

| Log file | Content |
|----------|---------|
| `autoinst-log.txt` | Test module lifecycle, testapi calls, serial matching, timestamps, backtraces |
| `serial_terminal.txt` | Raw serial console I/O: command invocations and their stdout/stderr |

The skill provides six Perl scripts, each targeting a specific analysis need:

| Script | Purpose |
|--------|---------|
| `analyze_log_health.pl` | Quick triage: surfaces errors, timeouts, backtraces, and stress warnings |
| `detect_lag.pl` | Correlates backend loop counts with timeouts to identify infrastructure stress |
| `extract_log_section.pl` | Lists test modules or extracts a specific module's log slice |
| `measure_cmd_time.pl` | Per-command execution timing with duration filters |
| `extract_cmd_output.pl` | Extracts what a specific command printed from `serial_terminal.txt` |
| `compare_modules_time.pl` | Side-by-side module timing comparison across two log files |

### Practical situations

- **Quick triage of a failed job:** You have the `autoinst-log.txt` from a
  failed job. Run the health check to instantly surface all errors, timeouts,
  backtraces, and stress warnings in one structured report. Answers: "What
  went wrong?"

- **Distinguishing real failures from infrastructure flakiness:** When a
  timeout is detected, the lag detection script correlates backend loop counts.
  High counts (>100K) indicate the worker host was overloaded -- the test logic
  itself may be fine. Answers: "Is this a real bug or a flaky host?"

- **Finding slow commands:** The command timing script shows per-command
  execution durations. Filter with `--duration ">5"` to isolate commands that
  took more than 5 seconds. Answers: "Which step was the bottleneck?"

- **Seeing what a command actually printed:** When you need to inspect the
  stdout/stderr of a specific command (e.g., an `az` or `zypper` call), the
  output extraction script pulls it from `serial_terminal.txt` by regex match.

- **Comparing a passing run against a failing run:** The comparison script does
  a side-by-side module timing breakdown across two log files. Answers: "Which
  module regressed?" or "Where is the new overhead?"

- **Extracting a single module's log:** When you already know which module
  failed, extract just that module's log section for focused reading instead of
  scrolling through the full log.

## 3. Syntax Checking Perl Files -- `perl-test-compile`

The `perl-test-compile` skill provides a fast, targeted `perl -c` syntax check
that uses the correct OSADO `PERL5LIB` (`.:lib:os-autoinst:os-autoinst/lib`).
It is faster than a full `make test-compile` because it scopes to exactly the
files or directories you specify.

### Practical situations

- **Immediate feedback after editing a file:** Run the script on just the
  `.pm` or `.pl` file(s) you touched to catch syntax errors before committing.
  Much faster than running `make test-compile` across the entire codebase.

- **Checking a whole directory after a refactor:** When refactoring across a
  module family (e.g., all of `lib/sles4sap/`), pass the directory to
  recursively check every Perl file under it.

- **Post-edit verification gate:** After the AI assistant modifies Perl code,
  the skill serves as a quick sanity check. If `perl -c` fails, the error is
  read, the fix is applied, and the check is re-run automatically.

## 4. Documenting SLES4SAP Test Modules -- `sles4sap-catalog`

The `sles4sap-catalog` skill automates the creation and auditing of
standardised Perldoc headers for SLES4SAP test modules, supporting the test
catalog documentation initiative.

The workflow is template-driven: the skill reads the target Perl file,
understands its purpose, identifies openQA variables (`get_var`,
`get_required_var`, `check_var`), traces dependencies into `lib/`, and
generates a complete header from the template in `assets/template.md`. It then
runs the `audit.sh` script plus standard project checks (`tools/check_metadata`,
`make test_pod_whitespace_rule`, `perldoc -T -D`) to verify correctness.

### Practical situations

- **Adding a header to a new test module:** You wrote a new SLES4SAP test.
  The skill generates a complete Perldoc header including NAME, DESCRIPTION,
  SETTINGS (with all detected openQA variables and their defaults), and
  MAINTAINER sections.

- **Auditing an existing header:** A module has a partial or outdated header.
  The skill replaces it with a correct one and runs the full audit pipeline to
  confirm compliance.

- **Batch documentation effort:** When working through a backlog of
  undocumented SLES4SAP modules, this skill provides a repeatable, consistent
  workflow for each file -- analyse, generate, audit, fix, re-audit.

### Generated header sections

| Section | Content |
|---------|---------|
| `NAME` | `directory/filename.pm - Short description` |
| `DESCRIPTION` | Detailed explanation with bullet-point tasks |
| `SETTINGS` | All openQA variables with descriptions and defaults |
| `MAINTAINER` | `QE-SAP <qe-sap@suse.de>` |

## 5. Creating Pull Requests -- `/github_pr_create`

The `/github_pr_create` custom command (Gemini CLI only) orchestrates the
complete PR creation workflow from staged `git` changes to an open pull request
on `os-autoinst/os-autoinst-distri-opensuse`.

The command follows a six-step process:

1. **Inspect** -- runs `git diff --staged` and analyses the changes.
2. **Propose** -- drafts a commit message following OSADO conventions (no
   conventional-commit format, body explains "what" and "why").
3. **Approve** -- writes the message to a temp file for the developer to review
   and edit before proceeding.
4. **Commit** -- commits with the approved message.
5. **Push** -- pushes the branch to the remote with `--set-upstream`.
6. **Create PR** -- reads `.github/PULL_REQUEST_TEMPLATE.md`, merges the commit
   body into the template, asks for a ticket reference, and creates the PR via
   `gh pr create --repo os-autoinst/os-autoinst-distri-opensuse`.

### Practical situations

- **End-to-end PR creation from staged changes:** Instead of manually writing
  commit messages, filling PR templates, and running multiple `git` and `gh`
  commands, the developer stages files and runs a single command.

- **Consistent PR formatting:** The command ensures every PR follows the
  repository template, includes a ticket reference, and has a commit message
  that meets OSADO style guidelines.

- **Reduced context switching:** The developer stays in the terminal and
  interacts with the AI to finalize the commit message and PR description,
  without switching between editor, terminal, and the GitHub web UI.

## The Development Loop

The skills and commands in this extension cover the full OSADO development
cycle:

```
  edit code
      │
      ▼
  verify syntax ──────────── perl-test-compile
      │
      ▼
  plan verification run ──── vr-planner
      │
      ▼
  run openQA job
      │
      ▼
  analyse logs ───────────── openqa-log-analyzer
      │
      ▼
  document module ────────── sles4sap-catalog
      │
      ▼
  create PR ──────────────── /github_pr_create
      │
      ▼
  iterate
```

Each tool is independent -- you can use any subset that fits your workflow.
