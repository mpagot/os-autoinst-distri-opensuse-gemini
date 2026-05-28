---
name: unit-test-wizard
description: >
  Writes and reviews OSADO Perl unit tests for library modules in lib/.
  Activate when the user asks to "write a
  test", "add unit tests", "scaffold a test file", "review this test",
  "check test quality", or needs help with Test::MockModule, dies_ok
  assertions, or subtest structure.
---

<instructions>
You help an OSADO developer write and review unit tests for Perl library
modules. Tests follow established patterns documented in
`references/ut_rules.md` -- read it when you need the full pattern catalog.

## Tools

Script paths are relative to this skill's installed directory.

* `scripts/scaffold_test.pl` -- Analyzes a `.pm` module and generates a
  complete `.t` test file skeleton with proper imports, mocking, and subtests.
* `scripts/review_test.pl` -- Audits an existing `.t` file against the
  best practices checklist and reports pass/fail per item.

Both scripts accept `--repo`, `--json`, `--verbose`, and `--help`.

## Generate Mode

Use when the user asks to write tests for a library module.

1. **Identify the module path.** Ask if unclear. Must be relative to the
   OSADO repo root (e.g., `lib/mypackage/module.pm`).
2. **Run the scaffold script:**
   ```bash
   perl scripts/scaffold_test.pl --repo /path/to/osado lib/mypackage/module.pm
   ```
   This outputs a complete `.t` file to stdout. Use `--output` to write
   directly to a file, or `--json` to get structured module info.
3. **Review and customize the output.** The skeleton is a starting point:
   * Verify the fake values are distinctive and traceable.
   * Add conditional `script_output` mocks if the function branches on
     command output.
   * Add assertions specific to the function's behavior (not just argument
     presence).
   * Ensure optional args have their own subtests.
4. **Write the file** to `t/NN_<module_name>.t` (the script suggests the
   next available number).
5. **Run the test:**
   ```bash
   prove -v -l -Ios-autoinst/ t/NN_<module_name>.t
   ```

## Review Mode

Use when the user asks to review or audit an existing test file.

1. **Run the review script:**
   ```bash
   perl scripts/review_test.pl --repo /path/to/osado t/NN_foo.t
   ```
2. **Present findings** grouped as PASS/FAIL/WARN.
3. **For each failure**, explain what's wrong and propose the fix, citing
   the relevant section from `references/ut_rules.md`.
4. **Optionally re-run** after applying fixes to confirm the check passes.

## Key Patterns (quick reference)

### File skeleton
```perl
use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Warnings;
use Test::MockModule;
use Test::Mock::Time;
use List::Util qw(any none uniq all)

use mypackage::module_name;

subtest '[function_name]' => sub { ... };

done_testing;
```

### The @calls capture pattern
```perl
subtest '[function_name]' => sub {
    my @calls;
    my $mock = Test::MockModule->new('mypackage::module_name', no_auto => 1);
    $mock->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
    $mock->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    function_name(arg1 => 'Agamemnon', arg2 => 'Mycenaeans');

    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /expected_pattern/ } @calls), 'Descriptive assertion message');
};
```

### Mandatory arg testing
```perl
subtest '[function_name] missing arguments' => sub {
    dies_ok { function_name(arg2 => 'X') } 'Die for missing argument arg1';
    dies_ok { function_name(arg1 => 'X') } 'Die for missing argument arg2';
};
```

## Rules

* Always use `no_auto => 1` in Test::MockModule constructors.
* Always use `redefine()`, never `mock()`.
* Each subtest must be self-contained: own `@calls`, own mocks, no shared state.
* Always mock `record_info` (redirect to `note`).
* Clean up `set_var` with `undef` at end of subtests.
* Use distinctive fake values (mythology, Italian, mushrooms) -- never
  "foo", "bar", "test".
* Test behavior (what commands are generated), not implementation (internal
  call order).
* Assertion messages must be specific, unique, and informative on failure.
* Use regex matching (`any { /pattern/ } @calls`) not exact string equality
  for command assertions.
* Do NOT modify the library code -- this skill only creates/edits test files.
* After generating tests, suggest running them via `local-lint-test` or
  directly with `prove`.
</instructions>
