# OSADO AI Assistant

AI-powered developer productivity skills for the
[os-autoinst-distri-opensuse](https://github.com/os-autoinst/os-autoinst-distri-opensuse)
(OSADO) project. Provides modular **Skills** and **Commands** that act as an
on-demand pair programmer aware of OSADO architecture and workflows.

## Skills Included

| Skill | Description |
|-------|-------------|
| `perl-test-compile` | Compile-check Perl files with correct OSADO `PERL5LIB` |
| `comment-extractor` | Extract and search GitHub PR comments from OSADO |
| `vr-planner` | Plan verification runs for code changes |
| `sles4sap-catalog` | Add/audit Perldoc headers on SLES4SAP test modules |
| `openqa-log-analyzer` | Parse and extract sections from `autoinst-log.txt` |

## Dependencies

- `gh` (GitHub CLI) for PR operations.
- `jq` for JSON processing.
- `fzf` (optional, for interactive comment search).
- `perl` for compilation checks.

## Installation

### Option A: Gemini CLI Extension (Recommended)

Install as a native Gemini CLI extension. Skills, commands, and context are
discovered automatically.

```bash
# User-level (available across all projects)
gemini extensions install https://github.com/mpagot/os-autoinst-distri-opensuse-gemini
```

**Workspace-level is recommended** since the context and skills are
OSADO-specific.

#### Update

```bash
gemini extensions update osado-ai-assistant
```

#### Uninstall

```bash
gemini extensions uninstall osado-ai-assistant
```

### Option B: Manual Overlay (Legacy)

Symlinks skills and commands into your OSADO clone's `.gemini/` directory.
This method is deprecated in favor of the native extension install above.

```bash
# Clone this repository
git clone https://github.com/mpagot/os-autoinst-distri-opensuse-gemini
cd os-autoinst-distri-opensuse-gemini

# Install (symlinks into your OSADO clone)
./tools/install.sh /path/to/your/os-autoinst-distri-opensuse

# Update (git pull + refresh symlinks)
./tools/install.sh --update /path/to/your/os-autoinst-distri-opensuse

# Uninstall (removes only our symlinks, preserves your files)
./tools/install.sh --uninstall /path/to/your/os-autoinst-distri-opensuse
```

For cross-tool compatibility (also links into `.agents/skills/` and `AGENTS.md`):

```bash
./tools/install.sh --portable /path/to/your/os-autoinst-distri-opensuse
```

### Option C: Other AI Coding Tools

The skills in this repository follow the
[Agent Skills open standard](https://agentskills.io) (`SKILL.md` format) and
are compatible with 36+ AI coding tools.

#### OpenCode / Pi Agent

These tools discover skills in `.agents/skills/`. Copy or symlink the skills
directory into your OSADO clone:

```bash
# From your OSADO clone root:
mkdir -p .agents/skills
cp -r /path/to/os-autoinst-distri-opensuse-gemini/skills/* .agents/skills/

# Also place the AGENTS.md context file at your repo root:
cp /path/to/os-autoinst-distri-opensuse-gemini/OSADO_AGENTS.md ./AGENTS.md
```

Or use the manual installer with `--portable` (creates these symlinks for you).

#### Claude Code

Claude Code discovers skills in `.claude/skills/`:

```bash
# From your OSADO clone root:
mkdir -p .claude/skills
cp -r /path/to/os-autoinst-distri-opensuse-gemini/skills/* .claude/skills/
```

#### GitHub Copilot

Copilot reads `AGENTS.md` at the repository root for project context but does
not support the skills/scripts mechanism:

```bash
cp /path/to/os-autoinst-distri-opensuse-gemini/OSADO_AGENTS.md ./AGENTS.md
```

## Repository Structure

```
.
├── gemini-extension.json    # Extension manifest (for native Gemini install)
├── OSADO_AGENTS.md          # Agent guidelines deployed to OSADO (context + workflow)
├── skills/                  # Agent skills (SKILL.md + scripts)
│   ├── perl-test-compile/
│   ├── comment-extractor/
│   ├── vr-planner/
│   ├── sles4sap-catalog/
│   └── openqa-log-analyzer/
├── commands/                # Custom commands (Gemini CLI only, TOML)
│   └── github_pr_create.toml
├── tools/
│   └── install.sh           # Legacy manual installer
├── t/                       # Test suite
├── docs/                    # Project documentation
└── ideas/                   # Research and working artifacts
```

## Contributing

### Development Setup

```bash
# Clone and link for local development
git clone https://github.com/mpagot/os-autoinst-distri-opensuse-gemini
cd os-autoinst-distri-opensuse-gemini
gemini extensions link .
```

Changes to skills, commands, and context files are picked up on the next
Gemini CLI session.

### References

- [Agent Skills specification](https://agentskills.io/specification)
- [Gemini CLI Skills](https://geminicli.com/docs/cli/skills/)
- [Gemini CLI Custom Commands](https://geminicli.com/docs/cli/custom-commands/)
- [Gemini CLI Extensions](https://geminicli.com/docs/extensions/)

### Testing

```bash
# Run overlay installer tests
./t/test_install.sh

# Run integration tests (requires container runtime)
podman build -t osado-ai-test -f t/Containerfile .
podman run --rm osado-ai-test

# Lint bash scripts
shellcheck tools/*.sh t/*.sh skills/*/scripts/*.sh
```

## License

Licensed under the same terms as OSADO (GPL-2.0-or-later).
