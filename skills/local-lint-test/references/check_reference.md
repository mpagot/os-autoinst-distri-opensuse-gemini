# OSADO Local Check Reference

Complete reference of local commands, Makefile targets, and tools/ scripts
available in the os-autoinst-distri-opensuse repository.

## Single-File Commands (fastest)

| File type | Command |
|-----------|---------|
| Perl (.pm/.pl) | `PERL5LIB=.:lib:os-autoinst:os-autoinst/lib perl -c <file>` |
| Unit test (.t) | `prove -lv -Ios-autoinst/ <file>` |
| YAML schedule | `yamllint -c .yamllint <file>` |
| Jsonnet | `python3 -c "import _jsonnet; print(_jsonnet.evaluate_file('<file>'))"` |

## Makefile Targets (by speed)

| Target | Scope | Approximate Time |
|--------|-------|------------------|
| `make tidy` | Format changed files only | ~5s |
| `make tidy-check` | Check formatting (no write) | ~5s |
| `make test-compile-changed` | `perl -c` on git-changed .pm files | ~10s |
| `make test-code-style` | Project style rules | ~10s |
| `make perlcritic` | Static analysis (severity 4+) | ~30s |
| `make test TESTS=static` | Full static suite (YAML, metadata, POD, etc.) | ~1-2 min |
| `make test TESTS=compile` | All 2000+ .pm files via GNU parallel | ~3-5 min |
| `make test TESTS=unit` | All unit tests in t/ (~45 files) | ~2 min |
| `make test` | Everything | ~5-10 min |

## tools/ Scripts (called by Makefile targets)

| Script | Purpose |
|--------|---------|
| `tools/tidy` (symlink to `os-autoinst/tools/tidy`) | perltidy wrapper with version check |
| `tools/check_yaml` | yamllint + YAML schema validation for schedules |
| `tools/check_jsonnet` | Jsonnet file validation via Python |
| `tools/check_metadata` | Enforces `# Summary`, `# Maintainer`, `# Copyright` headers |
| `tools/check_pod_errors` | POD syntax checking via `perldoc` |
| `tools/check_pod_whitespace_rule` | Empty line between `=cut` and code |
| `tools/detect_code_dups` | Code::DRY — finds 13+ identical lines |
| `tools/detect_nonexistent_modules_in_yaml_schedule` | Schedule references → tests/ existence |
| `tools/detect_unused_modules` | Find test modules not in any schedule |
| `tools/check_invalid_syntax` | Grep for forbidden patterns (.pm in loadtest, etc.) |
| `tools/test_deleted_renamed_referenced_files` | Detect broken references after renames |
| `tools/update_spec` | Verify cpanfile ↔ .spec sync |
| `tools/check_code_style` | Project-specific check_screen usage rules |

## Verbose / Debug Variants

| Goal | Command |
|------|---------|
| Unit test (recommended) | `PERL5OPT=-MCarp::Always prove --time --verbose -l -Ios-autoinst/ <file>` |
| Unit test with coverage | `HARNESS_PERL_SWITCHES=-MDevel::Cover prove -l -Ios-autoinst/ <file>` |
| perltidy changed files (interactive) | `tidyall --refresh-cache -r -v $(git status \| grep "modified:" \| sed 's/.*modified://' \| fzf -m)` |
| perltidy single file | `tidyall --refresh-cache -r -v <file>` |
| perlcritic single file | `PERL5LIB=tools/lib/perlcritic:$PERL5LIB perlcritic --quiet <file>` |
| Compile single module (manual) | `PERL5LIB=.:lib:os-autoinst:os-autoinst/lib perl -c <file>` |

## Troubleshooting

### perltidy version mismatch

**Symptom:**
```
Wrong version of perltidy. Found '20260204', expected '20250912'.
```

**Root cause:** The `tools/tidy` script (symlinked from os-autoinst) checks
that your installed perltidy matches the version pinned in `os-autoinst/cpanfile`.
A stale `os-autoinst/` checkout is the usual cause.

**Fix:**
```bash
cd os-autoinst && git pull && cd ..
# Verify expected vs installed:
sed -n "s/^.*Perl::Tidy[^0-9]*\([0-9]*\).*['];$/\1/p" os-autoinst/cpanfile
perltidy -version | sed -n '1s/^.*perltidy, v\([0-9]*\)\s*$/\1/p'
# Install exact version if needed:
cpanm Perl::Tidy@<EXPECTED_VERSION>
```

### Missing perlcritic policies

**Symptom:**
```
Policy "Perl::Critic::Policy::OpenQA::HashKeyQuotes" is not installed.
```

**Root cause:** The custom perlcritic policies live in
`os-autoinst/tools/lib/perlcritic/Perl/Critic/Policy/`. OSADO accesses them
via a symlink chain:
- `tools/lib` → `../os-autoinst/tools/lib`
- `os-autoinst` → a separate clone (symlinked into the OSADO workspace)

This error means either:
1. The `tools/lib` symlink is broken or missing
2. The `os-autoinst` symlink/clone is missing or stale

**Fix (try in order):**
```bash
# 1. Quickest: let Makefile fix links
make check-links

# 2. If os-autoinst is not cloned/linked yet:
make prepare

# 3. Manual repair of just the symlink:
rm -f tools/lib && ln -s ../os-autoinst/tools/lib tools/lib
```

**Verify:**
```bash
ls tools/lib/perlcritic/Perl/Critic/Policy/
# Should show: HashKeyQuotes.pm (and possibly others)
```

### PERL5LIB path errors

**Symptom:**
```
Can't locate testapi.pm in @INC
Can't locate scheduler.pm in @INC
```

**Root cause:** Missing include paths. Requires `os-autoinst/` and wheels.

**Fix:**
```bash
make prepare
# Or just fix symlinks:
make check-links
```

### Unit test "No plan found"

**Symptom:**
```
t/37_publiccloud_gce.t ........................
No subtests run
Parse errors: No plan found in TAP output
```

**Root cause:** Some tests conditionally skip all assertions when specific
environment variables or mock setups are unavailable locally.

**Fix:** This is often expected locally. Check if the test requires specific
env vars. In CI, these tests pass because the full environment is available.

### Compilation timeout

**Symptom:** `make test TESTS=compile` takes > 5 minutes.

**Root cause:** Full parallel compilation of 2000+ `.pm` files is CPU-intensive.

**Fix:** Use the incremental variant:
```bash
make test-compile-changed
```

### GNU parallel not found

**Symptom:**
```
parallel: command not found
```

**Fix:**
```bash
sudo zypper in gnu_parallel
```

### yamllint not found

**Symptom:**
```
Command 'yamllint' not found
```

**Fix:**
```bash
pip install yamllint
# Or:
sudo zypper in python3-yamllint
```

## Environment Setup Checklist

Before running any checks, ensure your workspace is prepared:

```bash
# 1. Clone os-autoinst and install dependencies
make prepare

# 2. Verify os-autoinst is present
ls os-autoinst/testapi.pm

# 3. Verify symlinks
ls -la tools/tidy tools/lib

# 4. Verify perltidy version matches
sed -n "s/^.*Perl::Tidy[^0-9]*\([0-9]*\).*['];$/\1/p" os-autoinst/cpanfile
perltidy -version | sed -n '1s/^.*perltidy, v\([0-9]*\)\s*$/\1/p'
```

## PERL5LIB Reference

The full `PERL5LIB` used by the Makefile for compilation checks:

```
.:lib:os-autoinst:os-autoinst/lib:tests/installation:tests/x11:tests/qa_automation:tests/virt_autotest:tests/cpu_bugs:tests/sles4sap/saptune
```

For most single-file checks, the simplified version works:

```
.:lib:os-autoinst:os-autoinst/lib
```
