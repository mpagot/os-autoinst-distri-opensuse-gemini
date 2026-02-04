# OSADO AI Assistant: Gemini-CLI Skills for Developer Productivity

This repository provides a specialized AI-assisted environment for developers working on the [os-autoinst-distri-opensuse](https://github.com/os-autoinst/os-autoinst-distri-opensuse) (OSADO) project. It leverages the [Gemini CLI](https://github.com/google/gemini-cli).
At the moment th efocus is to provide configurations, tools and skills for gemini-cli.

The OSADO AI Assistant acts as an on-demand pair programmer that "knows" the OSADO architecture.
It consists of modular **Skills** and **Tools** designed to:
- **The Committer:** Generate compliant git commit messages and PR descriptions.
- **The Documenter:** Write and update Perl POD documentation following internal templates.
- **The Linter/Navigator:** Recommend the correct tools for testing and linting based on context.
- **The Architect:** Explain complex scheduling and variable scope logic.
- **The Tester:** Generate unit test scaffolding using existing patterns.

## Dependency
To use these tools, you need:
- [Gemini CLI](https://github.com/google/gemini-cli) installed and configured.
- `gh` (GitHub CLI) for PR operations.
- `jq` for JSON processing.
- `fzf` (optional, for interactive comment search).
- `perl` (for compilation checks).

## Installation
This toolset is designed to be kept in a separate directory from your local OSADO clone. You then "overlay" the configurations using the provided installation script, which creates symlinks.
This allows you to:
- Stay updated with the latest toolset changes.
- Manually edit the provided skills/tools (changes will be reflected in this repo).
- Keep your personal `.gemini` configurations alongside the shared ones.

### 1. Clone this repository
```bash
git clone https://github.com/os-autoinst/os-autoinst-distri-opensuse-gemini
cd os-autoinst-distri-opensuse-gemini
```

### 2. Run the installation script
Provide the path to your local `os-autoinst-distri-opensuse` clone:
```bash
./tools/install.sh /path/to/your/os-autoinst-distri-opensuse
```

The script will:
- Create `.gemini/commands` and `.gemini/skills` directories in your OSADO repo if they don't exist.
- Symlink all tools and skills from this repo to your OSADO repo.
- **Protect your files**: It will never overwrite an existing file. If a conflict is detected, it will warn you and skip that file.
- Link the OSADO-specific `GEMINI.md` context to your project root.

### 3. Updating
To update the toolset to the latest version and refresh the links:
```bash
./tools/install.sh --update /path/to/your/os-autoinst-distri-opensuse
```

### 4. Uninstalling
To remove all symlinks created by this toolset from your OSADO repository:
```bash
./tools/install.sh --uninstall /path/to/your/os-autoinst-distri-opensuse
```

## Repository Structure
- `osado_overlay/`: The core Gemini configurations.
    - `.gemini/commands/`: Custom terminal commands (e.g., `/github-pr-create`).
    - `.gemini/skills/`: Specialized expertise packs (Log analysis, SAP catalogs).
- `docs/`: Documentation and project roadmap.

## Contributing
We welcome contributions! Please refer to Google `gemini-cli` official documentation:
- "skills" [https://geminicli.com/docs/cli/skills/](https://geminicli.com/docs/cli/skills/) 
- "tools" [https://geminicli.com/docs/cli/custom-commands/](https://geminicli.com/docs/cli/custom-commands/)

And refer to the OSADO documentation

## License
Licensed under the same terms as OSADO (GPL-2.0-or-later).
