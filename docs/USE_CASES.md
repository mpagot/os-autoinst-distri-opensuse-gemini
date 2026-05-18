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
| "Which functions did I actually change, and who calls them?" | `vr-planner` (function-level) |
| "I edited a schedule YAML, which openQA job do I clone?" | `vr-planner` (Phase 3) |
| "Give me an `openqa-clone-job` command for my change" | `vr-planner` (Phase 3) |
| "I have `autoinst-log.txt` from a failed job -- what happened?" | `openqa-log-analyzer` |
| "Was this timeout caused by a slow worker host?" | `openqa-log-analyzer` |
| "Which command in the log took the longest?" | `openqa-log-analyzer` |
| "Does my edited `.pm` file compile?" | `local-lint-test` |
| "What's the fastest check for my change?" | `local-lint-test` |
| "How do I run a single unit test?" | `local-lint-test` |
| "Add a Perldoc header to this test module" | `test-catalog` |
| "Commit my staged changes and open a PR" | `/github_pr_create` |

## 1. Planning Verification Runs -- `vr-planner`

The `vr-planner` skill answers the question every OSADO developer faces after
making changes: **"How do I verify this?"**

It analyses your `git diff`, classifies touched files by category (`lib/`,
`tests/`, `data/`, `schedule/`, `t/`), and produces a concrete testing plan
with copy-paste commands. The skill operates in three phases:

1. **Classify and plan (offline)** -- analyses the change set, identifies
   affected unit tests, dependent test modules, YAML schedules, and data
   consumers. Produces ready-to-run `prove` commands and identifies the
   schedules you need to clone.
2. **Targeted deep-dive (on request)** -- provides more detail on a specific
   category when asked.
3. **Find a clonable openQA job (network, user-gated)** -- queries a live
   openQA instance and produces copy-paste `openqa-clone-job` commands with
   your fork and branch pre-filled. Always confirms the target host first.

For implementation details, pipeline diagrams, and JSON piping contracts, see
the [vr-planner README](../skills/vr-planner/README.md).

### Practical situations

- **After editing a library module (`lib/*.pm`):** You changed
  `lib/sles4sap/azure_cli.pm`. The skill finds the matching unit test and
  outputs the exact `prove` command, lists all test modules that depend on the
  library, and identifies the YAML schedules to clone. If there is no unit
  test yet, it suggests a filename for a new one.

- **Narrowing the blast radius of a lib change:** Your change touches a widely
  imported library. The skill can perform function-level analysis to identify
  which tests actually call the specific functions you changed, cutting a list
  of 40 candidates down to the 3 that matter.

- **After editing a test module (`tests/*.pm`):** You modified
  `tests/sles4sap/hana_install.pm`. The skill locates which
  `schedule/*.yml` files include it -- even through indirect scheduling -- so
  you know exactly which openQA job to clone.

- **After editing a schedule file (`schedule/*.yml`):** You changed a YAML
  schedule directly. The skill can take it straight to job lookup -- no
  intermediate test-to-schedule resolution needed.

- **After editing data files (`data/*`):** You changed a template or config
  under `data/`. The skill finds consumers even when the code references the
  file via a variable or partial path, going beyond what a literal grep would
  catch.

- **Getting a clonable openQA job:** Once schedules are identified, the skill
  queries openqa.suse.de (for SLE) or openqa.opensuse.org (for Tumbleweed) and
  produces a ready-to-use `openqa-clone-job` command.

- **Deciding whether a VR is needed at all:** For changes limited to `t/`,
  `.github/`, `Makefile`, `variables.md`, or pure comment/lint fixes, the skill
  reports that no VR is required -- though for `t/` changes it still outputs the
  `prove` commands to run the affected unit tests locally.

## 2. Understanding openQA Log Files -- `openqa-log-analyzer`

The `openqa-log-analyzer` skill helps developers make sense of the log files
produced by os-autoinst during test execution. It operates exclusively on
local log files that the developer has already downloaded -- the skill never
fetches or retrieves logs from any openQA instance. Obtaining and providing
the log files is the developer's responsibility.

openQA jobs produce two key log files that this skill operates on:

| Log file | Content |
|----------|---------|
| `autoinst-log.txt` | Test module lifecycle, testapi calls, serial matching, timestamps, backtraces |
| `serial_terminal.txt` | Raw serial console I/O: command invocations and their stdout/stderr |

For implementation details on the individual analysis scripts, their CLI
options, and usage examples, see the
[scripts README](../skills/openqa-log-analyzer/scripts/README.md).

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

## 3. Local Validation -- `local-lint-test`

The `local-lint-test` skill answers: **"What's the fastest local command to
validate my edit right now?"**

Where `vr-planner` answers *"What remote openQA jobs should I clone?"*, this
skill covers everything you can check **locally** without network access:
compilation, formatting, linting, unit tests, YAML validation, and static
analysis. It always recommends the lightest targeted command over a full-suite
run.

The skill operates in three tiers:

1. **Instant** -- per-file checks that complete in seconds (`perl -c`,
   `yamllint`, `prove` on a single unit test). Run these after every edit.
2. **Quick** -- checks that take under 30 seconds (`make tidy`, batch
   compile). Run before committing.
3. **Thorough** -- full-suite checks that take minutes (`make perlcritic`,
   `make test TESTS=static`). Run before opening a PR.

### Practical situations

- **Immediate feedback after editing a file:** The skill identifies the file
  type and suggests the single fastest check -- `perl -c` for Perl, `yamllint`
  for YAML schedules, jsonnet validation for data templates.

- **Finding the right unit test:** When you edit `lib/foo/bar.pm`, the skill
  locates the matching `t/*bar*.t` file and outputs the exact `prove` command
  with all include paths pre-filled.

- **Before committing:** Recommends `make tidy` for formatting and the
  specific unit test(s) that cover your change -- not the full test suite.

- **Before opening a PR:** Suggests the thorough checks (`make perlcritic`,
  `make test TESTS=static`) that CI will also run, so you catch issues early.

- **Triaging a local check failure:** When `make tidy` fails with a perltidy
  version mismatch, or `perlcritic` reports a missing policy, the skill
  explains the root cause and provides the fix command.

- **Running in isolation with verbose output:** Instead of memorising flags
  and `PERL5LIB` paths, the skill outputs complete copy-paste commands like
  `PERL5OPT=-MCarp::Always prove -lv -Ios-autoinst/ t/sles4sap/azure_cli.t`.

## 4. Documenting Test Modules -- `test-catalog`

The `test-catalog` skill automates the creation and auditing of
standardised Perldoc headers for OSADO test modules, supporting the test
catalog documentation standard.

The workflow is template-driven: the skill reads the target Perl file,
understands its purpose, identifies openQA variables (`get_var`,
`get_required_var`, `check_var`), traces dependencies into `lib/`, and
generates a complete header from the template in `assets/template.md`. It then
runs the `audit.sh` script plus standard project checks (`tools/check_metadata`,
`make test_pod_whitespace_rule`, `perldoc -T -D`) to verify correctness.

### Practical situations

- **Adding a header to a new test module:** You wrote a new test module.
  The skill generates a complete Perldoc header including NAME, DESCRIPTION,
  SETTINGS (with all detected openQA variables and their defaults), and
  MAINTAINER sections. The maintainer is auto-detected from existing file
  content or a directory-based lookup table.

- **Auditing an existing header:** A module has a partial or outdated header.
  The skill replaces it with a correct one and runs the full audit pipeline to
  confirm compliance.

- **Batch documentation effort:** When working through a backlog of
  undocumented modules, this skill provides a repeatable, consistent
  workflow for each file -- analyse, generate, audit, fix, re-audit.

### Generated header sections

| Section | Content |
|---------|---------|
| `NAME` | `directory/filename.pm - Short description` |
| `DESCRIPTION` | Detailed explanation with bullet-point tasks |
| `SETTINGS` | All openQA variables with descriptions and defaults |
| `MAINTAINER` | Auto-detected from file/directory or provided by user |

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
  validate locally ─────────── local-lint-test
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
  document module ────────── test-catalog
      │
      ▼
  create PR ──────────────── /github_pr_create
      │
      ▼
  iterate
```

Each tool is independent -- you can use any subset that fits your workflow.
