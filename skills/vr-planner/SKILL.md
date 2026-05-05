---
name: vr-planner
description: Plans how to verify changes to an os-autoinst-distri-opensuse (OSADO) checkout. Use this skill when the user asks "how do I test my change", "what verification run (VR) should I do", "which openQA job should I clone", or "what's affected by my edit". Classifies staged/unstaged/committed files into testing categories (tests/, lib/, t/, data/, schedule/, no-VR), surfaces affected unit tests and downstream test modules, resolves test modules to YAML schedules, and prepares ready-to-paste openqa-clone-job commands.
---

<instructions>
You help an OSADO developer figure out how to verify their changes to
`os-autoinst-distri-opensuse`. Use the Perl helpers in `scripts/` to do the
work — never duplicate their logic in shell or in your own reasoning.

## Pipeline overview

```
classify_changes.pl                 (orchestrator — call first)
  ├── tests/    → find_test_schedule.pl
  ├── lib/      → find_unit_test.pl + find_affected_tests.pl
  ├── data/     → find_data_consumers.pl
  └── schedule/ → find_openqa_job.pl  (NETWORK — confirm host first)
```

All scripts accept `--repo /path/to/osado`, `--json`, `--verbose`, and `--help`.

## Process

### Phase 1 — Classify and produce the testing plan

1. **Identify the OSADO repo path.** If the user did not state it, ask them.
   Verify it exists and contains both `lib/` and `tests/`.
2. **Identify the change set.** By default `classify_changes.pl` reads
   `git diff --cached` (staged). Honour the user if they ask for a different
   source:
   * unstaged working tree → `--git-diff`
   * a specific commit     → `--git-commit <hash>`
   * an explicit list      → pass file paths as positional args
3. **Run the orchestrator with all helpers chained:**
   ```bash
   perl .gemini/skills/vr-planner/scripts/classify_changes.pl \
     --repo /path/to/osado --helpers
   ```
   This single call also runs `find_test_schedule.pl`, `find_unit_test.pl`,
   `find_affected_tests.pl`, and `find_data_consumers.pl` for the right
   buckets. It does NOT contact openQA.
4. **Summarise the plan to the user.** Report per category:
   * file count and whether VR is needed,
   * the concrete next action (unit-test command, affected tests, data
     consumers, or schedule files to clone from).

### Phase 2 — Targeted deep-dive (only when the user asks)

If the user wants more detail on one category, call the matching helper
directly with the specific files. Examples:

* "Which unit tests cover lib/foo.pm?" →
  `perl .gemini/skills/vr-planner/scripts/find_unit_test.pl --repo REPO --verbose lib/foo.pm`
* "What's affected by my lib change?" →
  `perl .gemini/skills/vr-planner/scripts/find_affected_tests.pl --repo REPO --verbose lib/foo.pm`
  Add `--git-commit HASH` to also get function-level analysis (which subs
  changed, who calls them).
* "Where is tests/X/Y.pm scheduled?" →
  `perl .gemini/skills/vr-planner/scripts/find_test_schedule.pl --repo REPO --verbose tests/X/Y.pm`
* "Who consumes data/foo/bar.yaml?" →
  `perl .gemini/skills/vr-planner/scripts/find_data_consumers.pl --repo REPO --verbose data/foo/bar.yaml`

### Phase 3 — Find a clonable openQA job (network call — gated)

`find_openqa_job.pl` queries a live openQA instance. Before invoking it:

1. **Always confirm the host with the user.** Do not guess. Ask which
   instance to query — the canonical options are:
   * `--osd` → `http://openqa.suse.de` (SLE, SLE Micro, SLES4SAP)
   * `--o3`  → `http://openqa.opensuse.org` (Tumbleweed, Leap)
   * `--host URL` → custom worker (e.g. dedicated cloud workers)
2. **Resolve test files to schedules first.** `find_openqa_job.pl` accepts
   `schedule/*.yml` paths only. For test modules, pipe through
   `find_test_schedule.pl --json`:
   ```bash
   perl .gemini/skills/vr-planner/scripts/find_test_schedule.pl \
     --repo REPO --json tests/X/Y.pm \
   | jq -r '.results[].matches[] | select(.type=="yaml_schedule") | .file' \
   | xargs perl .gemini/skills/vr-planner/scripts/find_openqa_job.pl --osd --repo REPO
   ```
3. **Run the script and present the clone commands.** Output is copy-paste
   ready: a `openqa-clone-job` line with auto-detected CASEDIR (your fork +
   branch) and BUILD (your username). Override with `--casedir` / `--build`
   if the user requests it.

## Rules

* Do NOT modify any OSADO source code. This skill only analyses and reports.
* Do NOT run `openqa-cli` or `find_openqa_job.pl` without first confirming
  the openQA host with the user.
* Do NOT re-implement the helpers' logic in shell, grep, or file exploration
  tools (ReadFile, SearchText, FindFiles). Always call the Perl scripts.
* When `classify_changes.pl --helpers` already produced output for a
  category, do not run the same helper again unless the user asks for more
  detail. In particular, when it has already resolved test modules to schedule
  files, pass those schedule paths directly to `find_openqa_job.pl` — do NOT
  explore schedule directories with file tools to verify or supplement the
  output.
* When `find_affected_tests.pl` output includes a section labelled
  **"VR-CONFIRMED TARGETS — function-level callers"**, use ONLY those test
  files for schedule and job lookups. The "Module-level candidates"
  (conservative blast radius) section may contain false positives — tests
  that import the changed library but do not call the modified functions.
  Never pass module-level candidates to `find_test_schedule.pl` or
  `find_openqa_job.pl` when function-level data is available.
* Resolve `--repo` to an absolute path before passing it. The scripts also
  accept relative paths but absolute paths make the output easier to read.

## Known limitations to surface to the user when relevant

* **Schedule fan-out cap.** `find_openqa_job.pl` refuses to query when a
  change touches more than 25 schedule files (e.g. `lib/virt_autotest/common.pm`,
  `lib/hacluster.pm`). Report the cap and ask the user to pick 1–3
  schedules manually.
* **Dynamic/runtime loaders.** publiccloud and parts of kernel/LTP load tests
  via `lib/main_*.pm` with runtime conditions that `find_test_schedule.pl`
  cannot resolve statically. When `find_test_schedule.pl` reports a
  `loadtest` match inside a `lib/main_*.pm` file, the user must browse the
  openQA web UI to find a passing job.
* **Private workers.** Hosts like `vh012.qa2.suse.asia` or
  `openqaworker15.qe.prg2.suse.org` are VPN-only and not auto-detected;
  the user must pass them with `--host`.
* **Function-level analysis** in `find_affected_tests.pl` requires
  `--git-commit HASH`. Without it, only module-level blast radius is shown.
* Changes scoped to `t/`, `.github/`, `Makefile`, `variables.md`, or pure
  comment/lint fixes typically do NOT require a VR.

## Output expectations

Keep the user-facing summary short:

1. One line per category (count + VR needed).
2. The exact `prove` command for each touched `t/` file or `lib/` module
   that has a unit test.
3. The schedule file(s) the user should clone from (or the loader to
   inspect for programmatic tests).
4. A note that running `find_openqa_job.pl` requires confirming the host.

Reference the source docs only if the user asks for context:
`ideas/USER_QUESTIONS_HOW_CAN_I_TEST_MY_CHANGED_CODE.md` and
`ideas/OPENQA_TECH.md` (these live in the development repo, not in the
installed skill).
</instructions>
