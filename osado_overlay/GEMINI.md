# os-autoinst-distri-opensuse (osado)

This repository contains the test distribution executed by openQA for testing openSUSE and SUSE Linux Enterprise (SLE) distributions.
It is built on top of the `os-autoinst` test engine.

## Project Overview

- **Main Technology**: Perl (using the `os-autoinst` framework).
- **Other Technologies**: YAML (schedules), Jsonnet (configuration), Python (via `Inline::Python`), Bash.
- **Purpose**: Automating OS installation and functional tests across various architectures and backends.

## Project Structure

- `tests/`: Contains the actual test modules (e.g., `tests/installation/`, `tests/x11/`).
- `lib/`: Shared library modules and utility functions used by tests.
    - `lib/Utils/Architectures.pm`: Functions for architecture checks.
    - `lib/Utils/Backends.pm`: Functions for backend checks.
- `data/`: Static assets and data files used during test execution.
- `schedule/`: YAML definitions of test module execution sequences.
- `products/`: YAML definitions for product-specific configurations.
- `t/`: Unit tests for the repository's libraries and tools.
- `tools/`: Maintenance and CI helper scripts.

## Building and Running

### Testing
- **Run all tests**: `make test`
- **Unit tests only**: `make unit-test` or `prove -l -Ios-autoinst/ t/`
- **Syntax check**: `make test-compile`
- **Static analysis**: `make test-static` (includes YAML/Jsonnet validation, metadata checks, etc.)

### Formatting
- **Format code**: `make tidy` (uses `perltidy` and `perlcritic`)

## Development Conventions

- **Variable Mutation**: openQA settings (`get_var`, `set_var`) are frequently mutated throughout the test lifecycle. Always verify the source and scope of a variable before assuming its value.
- **Scheduling Logic**: Test execution order is defined by YAML schedules (in `schedule/`). Modules interact through shared state; changes in one module might affect downstream modules in the same schedule.
- **Method Parameters**: Always use `my ($self) = @_;` for method signatures. Avoid parsing parameters if they aren't used.
- **Synchronization**: **NEVER** use `sleep()`. Use proper synchronization or polling (e.g., `assert_screen`, `wait_still_screen`).
- **Product Checks**: Avoid `is_tumbleweed()`. Treat Tumbleweed as the default and use explicit exclusions for older products.
- **Utilities**: Use `lib/Utils/Architectures.pm` and `lib/Utils/Backends.pm` instead of raw `check_var()` calls for ARCH/BACKEND.
- **Commit Messages**:
    - Subject: Max 72 chars, no trailing dot, starts with a capital letter or tag.
    - Body: Separated from subject by an empty line. Describe *why* the change was made.
- **License**: Use SPDX-License-Identifier in all new files.
- **Formatting**: Adhere to `.perltidyrc` and `.perlcriticrc`.

## Key Files
- `Makefile`: Entry point for common development tasks.
- `variables.md`: Documentation for test variables used in openQA.
- `declarative-schedule-doc.md`: Documentation for the YAML-based scheduling mechanism.
