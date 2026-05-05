# Gemini CLI Toolset Development (GEMINI.md)

This repository develops and maintains **AI coding assistant skills and
commands** for the `os-autoinst-distri-opensuse` (OSADO) project. It is
packaged as a Gemini CLI extension and supports cross-tool portability via
the Agent Skills open standard.

## Repository Purpose

Provide a "developer productivity extension" for OSADO. As an agent working
in *this* repository, your focus is on creating, refining, and validating
skills that help OSADO developers.

## Architecture

This repository IS the extension. The root-level structure maps directly to
the Gemini CLI extension format:

- `gemini-extension.json` — Extension manifest
- `OSADO_GEMINI.md` — Context file loaded every session (via `contextFileName`)
- `skills/` — Agent skills auto-discovered by the extension system
- `commands/` — Custom commands auto-discovered (Gemini CLI only, TOML)
- `osado_overlay/AGENTS.md` — Agent guidelines for users of other tools
  (placed at the OSADO repo root for OpenCode/Pi Agent/Copilot)

## Development Workflow for Skills & Tools

### 1. Skill Architecture
Follow the standard layout for all new skills (refer to `docs/SKILL_DOC.md`):
- `skills/<skill-name>/SKILL.md`: Main instructions and YAML metadata.
- `scripts/`: Implementation logic (Bash, Python, Perl) to keep context lean.
- `assets/`: Templates or static boilerplate.

### 2. Instruction Standards
When writing `SKILL.md` content:
- **Be Action-Oriented**: Use clear, imperative language in `<instructions>`.
- **Prefer Scripts**: Complex logic should be offloaded to `scripts/`.
- **Context Awareness**: Skills are designed for use when the extension is
  active in an OSADO working directory.

### 3. Validation and Testing
- `./t/test_install.sh` — Validates the overlay installer logic.
- `gemini extensions link .` — Test extension discovery in a live session.
- `podman build -t osado-ai-test -f t/Containerfile . && podman run --rm osado-ai-test`
  — Full integration test with actual CLI tools.

## Key Development Priorities
- **The Committer**: Refine the `/github-pr-create` command to strictly follow
  `CONTRIBUTE.md` rules.
- **The Documenter**: Improve POD generation templates based on the "Test
  Catalog" standards.
- **Log Analysis**: Enhance `extract_log_section.sh` to handle various log
  formats and edge cases in openQA output.

## Security & Safety
- **No Secrets**: Never hardcode API keys or credentials.
- **Instruction Injection**: Be mindful of how user input is passed to shell
  scripts to prevent command injection.
- Do not mention specific users (names or GitHub handles). Avoid naming
  specific teams.
