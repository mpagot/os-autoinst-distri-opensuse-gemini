# Agent Guidelines for os-autoinst-distri-opensuse-gemini

This repository develops and maintains **AI coding assistant skills and
commands** for the `os-autoinst-distri-opensuse` (OSADO) project. It is
packaged as a Gemini CLI extension and also supports OpenCode, Claude Code,
and Pi Agent via the [Agent Skills open standard](https://agentskills.io).

Your focus is on creating, refining, and validating skills that help OSADO
developers. See `README.md` for installation options and user-facing
documentation.

## 1. Build, Lint, and Test

Run `make help` to list all targets. Key targets:

```bash
make test              # installer tests + shellcheck (no container needed)
make test-integration  # integration tests in container
make clean             # remove test artifacts
```

Always run `make test` before committing. Run `make test-integration` when
modifying skills or the install script.

Linting: `shellcheck` is enforced on all `.sh` files. Ensure valid YAML
frontmatter in all `SKILL.md` files.

## 2. Code Style

### Bash (`*.sh`)
*   Shebang: `#!/bin/bash`. Start with `set -e`.
*   4-space indent. Lines ≤100 chars. Use `[[ ]]` not `[ ]`.
*   `snake_case` for variables/functions; `UPPER_CASE` for globals/constants.
*   `local` for all function variables.
*   Logging: use `log_info`, `log_success`, `log_warn`, `log_error` (see `tools/install.sh`).
*   Resolve paths to absolute (`$(cd ... && pwd)`). Self-locate with `dirname "${BASH_SOURCE[0]}"`.
*   Prefer `awk`/`sed` over Bash loops for text processing.

### Perl (`*.pl`)
*   `use strict; use warnings;` always.
*   `Getopt::Long` for CLI args. Support `--help`, `--repo`, `--json`, `--verbose`.
*   POD `=head2` for each function (except `print_usage`).
*   `snake_case` naming. Standard library only (no CPAN).
*   `JSON::PP` for structured output. `die` on unrecoverable errors.
*   Self-locate with `dirname(abs_path($0))`.

### Skill Definitions (`SKILL.md`)
*   YAML frontmatter with `name` and `description`.
*   Wrap prompt body in `<instructions>` XML tags.
*   Put logic in `scripts/`, not in Markdown. Use `assets/` for templates.

### Custom Commands (`commands/`)
*   TOML files with `description` and `prompt`. Gemini CLI only.
*   Use `"""` for multi-line prompts and `!{shell command}` for dynamic context.

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

| File | Purpose |
|------|---------|
| `gemini-extension.json` | Extension manifest (Gemini CLI) |
| `GEMINI.md` | Agent context loaded by Gemini CLI |
| `OSADO_AGENTS.md` | Agent guidelines deployed to OSADO repos |
| `skills/` | Agent skills (`SKILL.md` + `scripts/`) |
| `commands/` | Custom slash commands (TOML, Gemini CLI only) |
| `tools/install.sh` | Legacy symlink installer |
| `Makefile` | Development build/test/lint targets |
| `AGENTS.md` | Developer guidelines for THIS repo (this file) |

### Common Tasks

**Adding a new Skill:**
1.  Create `skills/<name>/SKILL.md` with YAML frontmatter.
2.  Add `scripts/` and `assets/` as needed.
3.  Run `make test` to verify linking and linting.
4.  Test with `gemini extensions link .` and start a new session.

**Modifying the Install Script:**
Edit `tools/install.sh`, then run `make test` to verify no regressions.

## 4. Safety Rules

1.  **Non-Destructive:** The install script never overwrites a file that is not a symlink to this repo.
2.  **Conflict Awareness:** New files must not conflict with common user filenames.
3.  **Symlink Logic:** The installer mirrors directory structure (`mkdir -p`) but symlinks individual files.
4.  **No Secrets:** Never hardcode API keys or credentials.
5.  **Injection Prevention:** Sanitize user input passed to shell scripts.
6.  **No PII:** Do not mention specific users, GitHub handles, or team names.
