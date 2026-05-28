# Unit Test Patterns and Best Practices

Best practices, patterns, and conventions for writing unit tests in this repository.
Extracted from analysis of existing test files in `t/` folder of the os-autoinst-distri-opensuse codebase.

---

## 1. File Skeleton

Every test file follows this exact boilerplate:

```perl
use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Warnings;
use Test::MockModule;
use Test::Mock::Time;
use List::Util qw(any none);
use testapi qw(set_var);

use mypackage::module_name;

subtest '[function_name]' => sub {
    # ...
};

done_testing;
```

Rules:
- **No test plan** (`plan tests => N`) -- always use `done_testing` at the end.
- `Test::Warnings` is always imported (it adds an implicit test that no unexpected warnings fired).
- `Test::Mock::Time` is always imported to make `sleep` calls instant.
- `List::Util qw(any none uniq all)` is imported for assertion idioms (add `all` if needed).
- `testapi` is imported only when `set_var`/`get_var` is needed.

---

## 2. Subtest Naming Convention

```perl
subtest '[function_name]' => sub { ... };
subtest '[function_name] missing arguments' => sub { ... };
subtest '[function_name] with optional arg X' => sub { ... };
subtest '[function_name] timeout' => sub { ... };
subtest '[function_name] integration test' => sub { ... };
```

Rules:
- Function name goes in **square brackets**: `[function_name]`.
- Variant description follows after a space.
- Common variants: `missing arguments`, `with <optional_arg>`, `error path`, `success`, `timeout`.
- Each subtest is **completely self-contained** (own mocks, own assertions, no shared state).

---

## 3. Mocking with Test::MockModule

### Creation

```perl
my $mock = Test::MockModule->new('mypackage::module_name', no_auto => 1);
```

Rules:
- **Always** use `no_auto => 1` to prevent auto-mocking of imported functions.
- Declare the mock **inside** the subtest -- lexical scoping auto-restores originals when the subtest ends.
- No explicit teardown or cleanup needed.

### Multi-module mocking

```perl
my $ipaddr2 = Test::MockModule->new('mypackage::ipaddr2', no_auto => 1);
my $azcli = Test::MockModule->new('mypackage::azure_cli', no_auto => 1);
```

When testing a function that calls into another library, mock both modules in the same subtest.

### Redefining functions

```perl
$mock->redefine(function_name => sub { ... });
```

Never use `$mock->mock()` -- always `redefine`.

---

## 4. The `@calls` Capture Pattern

This is the **core testing idiom** of this repository. It intercepts commands that the library would send to the SUT via openQA's test API.

```perl
subtest '[az_vm_create]' => sub {
    my @calls;
    my $mock = Test::MockModule->new('mypackage::azure_cli', no_auto => 1);
    $mock->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
    $mock->redefine(script_run => sub { push @calls, $_[0]; return 0; });
    $mock->redefine(script_output => sub { push @calls, $_[0]; return '{}'; });
    $mock->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    az_vm_create(resource_group => 'Gondor', name => 'Aragorn', image => 'SLES');

    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /az vm create/ } @calls), 'Main az command is called');
    ok((any { /--resource-group Gondor/ } @calls), 'Resource group passed correctly');
};
```

Rules:
- Declare `my @calls;` fresh in every subtest.
- Push `$_[0]` (the command string) for `assert_script_run`, `script_run`, `script_output`.
- Always mock `record_info` to silence it (redirect to `note`).
- Use `note("\n  -->  " . join("\n  -->  ", @calls));` before assertions for debug output.

---

## 5. Assertion Idioms

### Positive match (command was composed correctly)

All three approaches below are valid for matching patterns against `@calls`:

```perl
# Approach 1: List::Util any/none (most common in this repo)
ok((any { /az vm create/ } @calls), 'az vm create command was executed');
ok((any { /--resource-group Mycenaeans/ } @calls), 'RG arg is correct');

# Approach 2: Perl grep (equally valid, native Perl)
ok(grep(/az vm create/, @calls), 'az vm create command was executed');

# Approach 3: scalar grep for counting
is(scalar(grep { /az vm create/ } @calls), 1, 'Command executed exactly once');
```

All three are acceptable. `any`/`none` from `List::Util` is the most prevalent idiom in this codebase, but `grep` is standard Perl and works identically on lists. Choose whichever reads most clearly for the specific assertion.

### Negative match (argument was NOT included)

```perl
ok((none { /allocation-method/ } @calls), 'No --allocation-method when not requested');
```

### Exact value comparison

```perl
is($result, 'expected_value', 'Return value matches');
is(scalar @calls, 3, 'Exactly 3 commands executed');
```

### Deep structure comparison

```perl
is_deeply(\@got, \@expected, 'List matches expected');
```

### Death/exception testing

```perl
dies_ok { function_call() } 'Dies when mandatory arg missing';
```

### Survival testing

```perl
lives_ok { function_call() } 'Graceful handling of edge case';
```

---

## 6. Mandatory Argument Validation

Libraries validate mandatory args with `croak`. Tests must verify this systematically:

### Library pattern

```perl
sub az_vm_create(%args) {
    foreach (qw(resource_group name image)) {
        croak("Argument < $_ > missing") unless $args{$_};
    }
    ...
}
```

### Test pattern

```perl
subtest '[az_vm_create] missing arguments' => sub {
    dies_ok { az_vm_create(name => 'X', image => 'Y') }
        'Die for missing argument resource_group';
    dies_ok { az_vm_create(resource_group => 'X', image => 'Y') }
        'Die for missing argument name';
    dies_ok { az_vm_create(resource_group => 'X', name => 'Y') }
        'Die for missing argument image';
};
```

Rules:
- One `dies_ok` per mandatory argument.
- Call the function with **all args except the one being tested**.
- Description format: `'Die for missing argument <name>'` or `'Dies without <name>'`.
- Group all mandatory arg tests in a single subtest named `[function] missing arguments`.

---

## 7. Testing Optional Arguments

Use **separate subtests** for the base case (no optional args) and each optional variant:

```perl
subtest '[az_network_publicip_create]' => sub {
    my @calls;
    # ... setup mocks ...
    az_network_publicip_create(resource_group => 'RG', name => 'IP1');
    ok((none { /allocation-method/ } @calls), 'No --allocation-method by default');
};

subtest '[az_network_publicip_create] with allocation_method' => sub {
    my @calls;
    # ... setup mocks ...
    az_network_publicip_create(resource_group => 'RG', name => 'IP1', allocation_method => 'Static');
    ok((any { /--allocation-method Static/ } @calls), '--allocation-method included');
};
```

---

## 8. Mock Recipes

### `assert_script_run` -- run and die on failure

```perl
$mock->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
```

### `script_run` -- run and return exit code

```perl
$mock->redefine(script_run => sub { push @calls, $_[0]; return 0; });
```

### `script_output` -- run and return stdout

```perl
# Simple string
$mock->redefine(script_output => sub { push @calls, $_[0]; return 'some_output'; });

# JSON return
$mock->redefine(script_output => sub { push @calls, $_[0]; return '[{"Id":"x","Name":"y"}]'; });

# Conditional return based on command
$mock->redefine(script_output => sub {
    push @calls, $_[0];
    if ($_[0] =~ /az group list/) { return '["rg1","rg2"]'; }
    if ($_[0] =~ /az vm list/) { return '["vm1"]'; }
    return '[]';
});
```

### `record_info` -- redirect to TAP notes

```perl
$mock->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });
```

### `Test::MockObject` -- for OO instances (e.g., publiccloud::instance)

```perl
use Test::MockObject;
use publiccloud::instance;

my $mock_instance = Test::MockObject->new();
$mock_instance->set_true('wait_for_ssh');
$mock_instance->mock('run_ssh_command', sub { return 'output'; });
$mock_instance->{instance_id} = 'i-12345';
$mock_instance->{public_ip} = '1.2.3.4';
```

### Multi-module call tracking with source tagging

```perl
$ipaddr2->redefine(assert_script_run => sub { push @calls, ['ipaddr2', $_[0]]; });
$azcli->redefine(assert_script_run => sub { push @calls, ['azure_cli', $_[0]]; });
```

---

## 9. Variable Management (`set_var` / `get_var`)

```perl
subtest '[function] uses REGION var' => sub {
    set_var('PUBLIC_CLOUD_REGION', 'eu-west-1');

    # ... test logic ...

    set_var('PUBLIC_CLOUD_REGION', undef);    # always clean up
};
```

Rules:
- Set variables **inside** the subtest that needs them.
- **Always reset to `undef`** at the end of the subtest.
- Never rely on variables set in a previous subtest.

---

## 10. Multi-Step Workflow Testing

Two strategies depending on the level of isolation desired:

### Strategy A: Unit (mock at the same layer)

Mock the helper functions the workflow calls. Verify they were called in order (ONLY DO IF ORDER REALLY MATTER):

```perl
subtest '[ibsm_network_peering_aws_create] workflow' => sub {
    my @calls;
    $ibsm->redefine(aws_tgw_get_id => sub { push @calls, 'aws_tgw_get_id'; return 'tgw-123'; });
    $ibsm->redefine(aws_vpc_get_subnets => sub { push @calls, 'aws_vpc_get_subnets'; return ('s-1'); });
    $ibsm->redefine(aws_tgw_attach_vpc => sub { push @calls, 'aws_tgw_attach_vpc'; });

    ibsm_network_peering_aws_create(region => 'us-east-1', job_id => 'j1', ...);

    is(scalar @calls, 3, 'All workflow steps called');
    is($calls[0], 'aws_tgw_get_id', 'First step: get TGW ID');
};
```

### Strategy B: Integration (mock at the deepest layer -> usually testapi)

Mock only `script_run`/`script_output` and let intermediate layers execute:

```perl
subtest '[ibsm_network_peering_azure_create] integration' => sub {
    my @calls;
    $az_cli->redefine(script_output => sub {
        push @calls, $_[0];
        if ($_[0] =~ /vnet list.*-g (.*)/) { return '["VNET-' . $1 . '"]'; }
        if ($_[0] =~ /vnet show.*--name (.*)/) { return $1 . '-ID'; }
        return '[]';
    });
    $az_cli->redefine(assert_script_run => sub { push @calls, $_[0]; });

    ibsm_network_peering_azure_create(ibsm_rg => 'RG1', sut_rg => 'RG2');

    ok((any { /az network vnet peering create/ } @calls), 'Peering command fired');
};
```

### Strategy C: Symmetry (create + delete)

```perl
ibsm_network_peering_azure_create(ibsm_rg => 'A', sut_rg => 'B');
is(scalar @peerings_created, 2, 'Two peerings created');

ibsm_network_peering_azure_delete(ibsm_rg => 'A', sut_rg => 'B');
is(scalar @peerings_deleted, 2, 'Both peerings deleted');
```

---

## 11. Debugging

Always include this line **before** assertions to produce readable TAP output:

```perl
note("\n  -->  " . join("\n  -->  ", @calls));
```

For `record_info` calls, redirect to note:

```perl
$mock->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });
```

This makes test output self-documenting when run with `prove -v`.

---

## 12. Test::Mock::Time

Always import it:

```perl
use Test::Mock::Time;
```

This module makes `sleep()` and `time()` instant. Libraries often have polling loops or timeouts (e.g., waiting for a VM to start). Without this, tests would block for real duration.

No explicit API calls needed -- importing it is sufficient.

---

## 13. Test Data Conventions

### Inline, not external

Test data is defined inline inside subtests (JSON strings, simple values).
There is also a `t/data/` directory. For the moment it is only used for YAML schedule and autoyast tests

### Distinctive fake values

Use **unique, memorable, traceable** values -- never generic strings like "test" or "foo":

| Category | Examples |
|----------|----------|
| Mushroom names | `RussulaEmetica`, `AmanitaMuscaria`, `LactariusTorminosus` |
| Italian names of bird | `FRUTTOLO`, `PASSEROTTO`, `COLIBRI`, `BARBAGIANNI` |
| Greek mythology | `Agamemnon`, `Mycenaeans`, `TrojanHorse` |
| Commedia dell'arte | `Arlecchino`, `Pantalone` |

Decide a new different theme for each test file.

Why: If a value leaks into the wrong assertion, you immediately see it does not belong.

---

## 14. Naming Convention: Test to Library Mapping

All unit and integration tests are located in the `t/` directory at the repository root.

```
t/NN_<module_name>.t  -->  lib/<package>/<module_name>.pm
```

Examples:
- `t/21_azure_cli.t` tests `lib/mypackage/azure_cli.pm`
- `t/35_ibsm.t` tests `lib/mypackage/ibsm.pm`
- `t/22_ipaddr2.t` tests `lib/mypackage/ipaddr2.pm`

For nested modules:
- `t/15_qesap_azure.t` tests `lib/mypackage/qesap/azure.pm`
- `t/16_qesap_aws.t` tests `lib/mypackage/qesap/aws.pm`

The `NN` prefix is a sequential number for ordering. Pick the next available number.

---

## 15. Complete Example: Writing a New Test

Suppose you add a new function `az_disk_create` to `lib/mypackage/azure_cli.pm`:

```perl
# In lib/mypackage/azure_cli.pm
sub az_disk_create(%args) {
    foreach (qw(resource_group name size_gb)) {
        croak("Argument < $_ > missing") unless $args{$_};
    }
    $args{sku} //= 'Standard_LRS';
    my $cmd = join(' ',
        'az', 'disk', 'create',
        '--resource-group', $args{resource_group},
        '--name', $args{name},
        '--size-gb', $args{size_gb},
        '--sku', $args{sku});
    assert_script_run($cmd);
}
```

The corresponding test additions in `t/21_azure_cli.t`:

```perl
subtest '[az_disk_create] missing arguments' => sub {
    dies_ok { az_disk_create(name => 'X', size_gb => 10) }
        'Die for missing argument resource_group';
    dies_ok { az_disk_create(resource_group => 'X', size_gb => 10) }
        'Die for missing argument name';
    dies_ok { az_disk_create(resource_group => 'X', name => 'Y') }
        'Die for missing argument size_gb';
};

subtest '[az_disk_create]' => sub {
    my @calls;
    my $mock = Test::MockModule->new('mypackage::azure_cli', no_auto => 1);
    $mock->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
    $mock->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    az_disk_create(resource_group => 'Ithaca', name => 'Odysseus', size_gb => 128);

    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /az disk create/ } @calls), 'Main command executed');
    ok((any { /--resource-group Ithaca/ } @calls), 'Resource group correct');
    ok((any { /--name Odysseus/ } @calls), 'Disk name correct');
    ok((any { /--size-gb 128/ } @calls), 'Size correct');
    ok((any { /--sku Standard_LRS/ } @calls), 'Default SKU applied');
};

subtest '[az_disk_create] with custom sku' => sub {
    my @calls;
    my $mock = Test::MockModule->new('mypackage::azure_cli', no_auto => 1);
    $mock->redefine(assert_script_run => sub { push @calls, $_[0]; return; });
    $mock->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    az_disk_create(resource_group => 'Ithaca', name => 'Penelope', size_gb => 64, sku => 'Premium_LRS');

    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /--sku Premium_LRS/ } @calls), 'Custom SKU overrides default');
};
```

---

## 16. Checklist for New Tests

- [ ] File starts with `use strict; use warnings;`
- [ ] Imports: `Test::More`, `Test::Exception`, `Test::Warnings`, `Test::MockModule`, `Test::Mock::Time`
- [ ] Import `List::Util qw(any none)` for assertion idioms
- [ ] Import the module under test
- [ ] Each subtest is self-contained (no shared state across subtests)
- [ ] Mock created with `no_auto => 1` inside each subtest
- [ ] `record_info` is always mocked (redirected to `note`)
- [ ] `@calls` array captures all `script_run`/`assert_script_run`/`script_output` invocations
- [ ] `note("\n  -->  " . join(...))` before assertions
- [ ] Mandatory args tested with `dies_ok` (one per arg)
- [ ] Optional args tested in separate subtests
- [ ] `set_var` cleaned up with `undef`
- [ ] Fake values are distinctive and traceable
- [ ] File ends with `done_testing;`

---

## 17. Running Tests

```bash
# Single file
prove -v t/21_azure_cli.t

# All tests
prove -v t/

# With library path (if needed)
prove -Ilib -v t/35_ibsm.t
```

---

## 18. Anti-Patterns (Do NOT Do)

| Anti-pattern | Why |
|--------------|-----|
| Shared `@calls` across subtests | Pollutes results, makes failures non-deterministic |
| Using `$mock->mock()` instead of `redefine` | `mock` has different semantics for existing subs |
| Forgetting `no_auto => 1` | Can cause mysterious test failures from auto-mocked imports |
| Using generic values (`"test"`, `"foo"`, `"bar"`) | Impossible to trace which arg leaked where |
| Testing multiple functions in one subtest | Makes failures harder to isolate |
| Leaving `set_var` dirty | Affects subsequent subtests unpredictably |
| Using `plan tests => N` | Brittle; breaks when adding/removing assertions |
| External fixture files for command tests | Overkill; inline data is simpler and self-documenting |

---

## 19. Test Behavior, Not Implementation (BDD Principle)

**The golden rule:** Tests must verify *observable behavior* (return values,
side effects, output), never *internal implementation details* (call order,
internal variable state, how many times a helper was invoked).

### Why this matters

When tests are coupled to implementation, **any refactoring breaks the tests**
even though the module's behavior is unchanged. This creates a test suite that
*punishes* improvement rather than *protecting* correctness.

### What to test vs. what NOT to test

| Test (behavior) | Don't test (implementation) |
|-----------------|---------------------------|
| The return value of `run()` | How many internal methods were called |
| Which `assert_script_run` commands were generated | The order of `set_var` calls inside a helper |
| That `die` is raised on invalid input | That a specific code path was taken |
| That record_info was called with expected args | How the string was assembled internally |
| The final state after a function completes | Intermediate state during execution |

### Practical example

```perl
# BAD: testing implementation (fragile, breaks on refactoring)
subtest '[create_vm] internal call sequence' => sub {
    # ... run create_vm ...
    is($internal_calls[0], 'validate_args', 'First calls validate_args');
    is($internal_calls[1], 'build_command', 'Then calls build_command');
    is($internal_calls[2], 'execute', 'Finally calls execute');
};

# GOOD: testing behavior (stable, survives refactoring)
subtest '[create_vm] generates correct az command' => sub {
    # ... run create_vm ...
    ok((any { /az vm create/ } @calls), 'az vm create command is executed');
    ok((any { /--name Agamemnon/ } @calls), 'VM name is passed correctly');
};
```

### The refactoring test

Ask yourself: *"If someone refactored the internals without changing the
public API, would this test still pass?"* If the answer is no, the test is
too tightly coupled to implementation.

---

## 20. Assertion Messages Must Be Unambiguous

Every `ok()`, `is()`, `like()`, and `dies_ok` call **must** have a descriptive
message that uniquely identifies the assertion within the test file.

### Rules

1. **Be specific** -- a message must say *what* is being tested, not just "it works"
2. **Be unique** -- no two assertions in the same file should have identical messages
3. **Include context** -- mention the function, parameter, or scenario being tested
4. **Use the subtest name as context** -- the message complements `[function_name]`

### Examples

```perl
# BAD: vague, duplicated, unhelpful on failure
ok($result, 'test passed');
ok($other, 'test passed');
is($val, 1, 'correct');

# GOOD: specific, unique, informative on failure
ok($result, 'create_vm returns true on success');
ok($other, 'create_vm sets resource_group variable');
is($val, 1, 'retry count is 1 after single failure');
```

### Why this matters

When a test fails in CI, the developer sees only the message. If it says
`"test passed"`, they must read the source to understand what failed. If it says
`"create_vm returns true when --zone is specified"`, they know immediately.

---

## 21. Don't Test Too Strictly (Regex Flexibility)

Assertions should be **strict enough to catch bugs** but **flexible enough to
survive harmless changes** (whitespace, option reordering, extra flags).

### The spectrum

```
Too loose                          Right balance                     Too strict
────────────────────────────────────────────────────────────────────────────────
ok(1)                             like($cmd, qr/az vm create/)     is($cmd, "az vm create --name X --rg Y")
                                  ok(any { /--name X/ } @calls)
```

### Guidelines

| Scenario | Use | Avoid |
|----------|-----|-------|
| Checking a command includes a flag | `any { /--name Agamemnon/ }` | `is($calls[0], "exact full command string")` |
| Checking a string contains a pattern | `like($msg, qr/error.*timeout/)` | `is($msg, "Error: connection timeout after 30s")` |
| Checking argument presence | `ok(any { /--zone/ } @calls)` | `is($calls[2], "--zone us-east-1")` |
| Checking exact return value | `is($ret, 42, ...)` | N/A (exact match is correct here) |

### Why this matters

If you test `is($cmd, "az vm create --name X --rg Y --zone Z")`, then:
- Adding a new default flag breaks the test
- Reordering arguments (which is valid) breaks the test
- The test is testing *string construction* not *behavior*

Instead, test that each important argument is present independently:

```perl
# Resilient: survives argument reordering and new defaults
ok((any { /az vm create/ } @calls), 'az vm create was called');
ok((any { /--name Agamemnon/ } @calls), 'VM name is correct');
ok((any { /--resource-group Mycenaeans/ } @calls), 'Resource group is correct');
```

---

## 22. Review Principles Quick Reference

| # | Principle | Where documented |
|---|-----------|-----------------|
| 1 | Clean up `set_var` with `undef` after each subtest | §9 Variable Management |
| 2 | Mock `record_info` -> `note()` (never let it call real openQA API) | §4, §8, §11 |
| 3 | `any{}`/`none{}`/`grep` are all valid assertion idioms | §5 Assertions |
| 4 | Split tests into focused subtests (one function per subtest) | §2 Structure |
| 5 | Name subtests `[function_name]` with square brackets | §2 Structure |
| 6 | Use `dies_ok{}` for death tests (don't mock `croak`) | §6 Exception Testing |
| 7 | Use distinctive/creative fake values (not "foo"/"bar") | §13 Naming |
| 8 | Test behavior, not implementation (BDD) | §19 |
| 9 | Import `Test::Mock::Time` before the module under test | §12 Time Mocking |
| 10 | Put tests in the file matching the module (`t/XX_module.t`) | §14 File Placement |
| 11 | Assertion messages must be unambiguous and unique | §20 |
| 12 | Don't test too strictly -- use regex for flexibility | §21 |
