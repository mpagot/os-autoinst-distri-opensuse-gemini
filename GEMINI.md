# Gemini CLI Toolset Development (GEMINI.md)

This repository is dedicated to the development and maintenance of **Gemini CLI configurations, skills, and custom commands** specifically tailored for the `os-autoinst-distri-opensuse` (OSADO) project. 

## Repository Purpose
The goal of this project is to provide a "developer productivity overlay" for OSADO. As an agent working in *this* repository, your focus is on creating, refining, and validating Gemini-based tools that help OSADO developers.

## Development Workflow for Skills & Tools

### 1. Skill Architecture
Follow the standard layout for all new skills (refer to `docs/SKILL_DOC.md` for details):
- `.gemini/skills/<skill-name>/SKILL.md`: Main instructions and YAML metadata.
- `scripts/`: Implementation logic (Bash, Python, etc.) to keep the context window lean.
- `assets/`: Templates or static boilerplate.

### 2. Instruction Standards
When writing `SKILL.md` content:
- **Be Action-Oriented**: Use clear, imperative language in `<instructions>`.
- **Prefer Scripts**: Complex logic (regex parsing, multi-step CLI operations) should be offloaded to scripts in the `scripts/` directory.
- **Context Awareness**: Ensure skills are designed to work when the `.gemini` folder is overlaid into a local OSADO clone.

### 3. Validation and Testing
Use the helper scripts provided in `osado_overlay/.gemini/skills/` to validate your changes:
- `test_compile.sh`: Run this to verify Perl syntax in any templates or modules you generate.
- `search_comments.sh`: Use this to find historical reviewer feedback to inform the "The Committer" or "The Documenter" skills.

## The Overlay Pattern
The directory `osado_overlay/` mirrors the structure expected in the target OSADO repository. 
- Files inside `osado_overlay/` should be designed to be "dropped in" to an OSADO environment.
- The `osado_overlay/GEMINI.md` file contains instructions for the agent when it is *using* these tools inside OSADO, whereas *this* file (root `GEMINI.md`) is about *developing* the tools.

## Key Development Priorities
- **The Committer**: Refine the `/github-pr-create` command to strictly follow `CONTRIBUTE.md` rules.
- **The Documenter**: Improve POD generation templates based on the "Test Catalog" standards.
- **Log Analysis**: Enhance `extract_log_section.sh` to handle various log formats and edge cases in openQA output.

## Security & Safety
- **No Secrets**: Never hardcode API keys or credentials.
- **Instruction Injection**: Be mindful of how user input is passed to shell scripts to prevent command injection.
- Please do not mention any specific user (neither name or github name). Try to avoid as much as possible to name specific teams.
