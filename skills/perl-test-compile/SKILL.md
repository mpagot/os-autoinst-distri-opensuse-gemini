---
name: perl-test-compile
description: >
  Runs `perl -c` syntax checks on OSADO Perl files (.pm/.pl) with the
  project-correct PERL5LIB. Activate when the user asks to "check
  compilation", "verify syntax", "perl -c this file", or after editing
  modules in `lib/` or `tests/` to confirm they still parse. Faster than
  `make test-compile` because it scopes to the files or directories you
  pass in.
---

# Perl Test Compile

Quick syntax check for one or more Perl files (or every `.pm`/`.pl` under a
directory) using the OSADO conventional `PERL5LIB`:

```
.:lib:os-autoinst:os-autoinst/lib
```

## Tool

`scripts/test_compile.sh` — wraps `perl -c` per file and prints a
PASS/FAIL summary at the end. Exits non-zero if any file fails.

## Usage

```bash
# Single file
.gemini/skills/perl-test-compile/scripts/test_compile.sh lib/publiccloud/basetest.pm

# Multiple files
.gemini/skills/perl-test-compile/scripts/test_compile.sh tests/foo.pm lib/bar.pm

# Whole directory (recursive, skips dotdirs)
.gemini/skills/perl-test-compile/scripts/test_compile.sh lib/sles4sap/
```

Run from the OSADO repo root so the relative `PERL5LIB` resolves correctly
and `os-autoinst/` is reachable (i.e. after `make prepare`).

## Workflow

1. After editing `.pm`/`.pl` files, pass the changed paths to the script.
2. If a file fails, read the `perl -c` error, fix it, and re-run.
3. For repo-wide checks prefer `make test-compile` (or
   `make test-compile-changed` for the git-changed subset). This skill is
   for the targeted case where you already know which files to check.

## Rules

* Only `.pm` and `.pl` files are checked; other extensions are silently
  skipped.
* The script does not run unit tests (`prove`); it only validates that
  the file parses.
* Requires `make prepare` to have been run at least once so that the
  `os-autoinst/` directory exists.
