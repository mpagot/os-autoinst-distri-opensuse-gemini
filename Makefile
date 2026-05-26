# ==============================================================================
# OSADO AI Assistant - Development Makefile
# ==============================================================================

.PHONY: test test-install test-integration lint shellcheck perlcheck semgrep gemini-check claude-plugincheck skillcheck clean help

# Default target
help:
	@echo "Available targets:"
	@echo "  make test             - Run all local tests (install + lint + manifests)"
	@echo "  make test-install     - Run overlay installer unit tests"
	@echo "  make test-integration - Run integration tests in container"
	@echo "  make lint             - Run shellcheck + perl syntax on all scripts"
	@echo "  make shellcheck       - Lint shell scripts with shellcheck"
	@echo "  make perlcheck        - Syntax-check Perl scripts with perl -c"
	@echo "  make semgrep          - Run semgrep bash security rules (requires uvx)"
	@echo "  make clean            - Remove test artifacts"
	@echo ""
	@echo "Harness-specific validation:"
	@echo "  make gemini-check        - Validate Gemini CLI extension manifest"
	@echo "  make claude-plugincheck  - Validate Claude Code plugin manifests"
	@echo "  make skillcheck          - Validate SKILL.md frontmatter (name + description)"
	@echo ""
	@echo "Container runtime (default: podman):"
	@echo "  make test-integration CONTAINER_RT=docker"

# Container runtime (podman or docker)
CONTAINER_RT ?= podman
TEST_IMAGE ?= ghcr.io/mpagot/osado-gemini-tester:latest

# Run all local tests (no container needed)
test: test-install lint gemini-check claude-plugincheck skillcheck

# Overlay installer unit tests
test-install:
	@echo "=== Running installer tests ==="
	./t/test_install.sh

# Integration tests (requires container runtime)
test-integration:
	@echo "=== Running integration tests ==="
	$(CONTAINER_RT) run --rm \
		-v "$$(pwd):/src:ro" \
		$(TEST_IMAGE) \
		/src/t/test_integration.sh

# Lint all bash scripts with shellcheck
lint: shellcheck perlcheck

shellcheck:
	@echo "=== Running shellcheck ==="
	@sh_files=$$(find tools/ t/ skills/*/scripts/ -name '*.sh' 2>/dev/null); \
	if [ -n "$$sh_files" ]; then shellcheck --enable=all --severity=warning $$sh_files; else echo "No .sh files found"; fi

# Syntax-check all Perl scripts
perlcheck:
	@echo "=== Running perl -c on Perl scripts ==="
	@for f in skills/*/scripts/*.pl; do perl -c "$$f" || exit 1; done

# Semgrep bash security scan (optional, requires uvx/semgrep)
semgrep:
	@echo "=== Running semgrep bash security rules ==="
	@if command -v uvx >/dev/null 2>&1; then \
		uvx semgrep scan --config tools/semgrep-bash-security.yaml --include "*.sh" --error .; \
	elif command -v semgrep >/dev/null 2>&1; then \
		semgrep scan --config tools/semgrep-bash-security.yaml --include "*.sh" --error .; \
	else \
		echo "SKIP: semgrep not available (install via 'pipx install semgrep' or 'pip install uv')"; \
	fi

# ==============================================================================
# Harness-specific validation
# ==============================================================================

# Validate Gemini CLI extension manifest
gemini-check:
	@echo "=== Validating Gemini CLI extension manifest ==="
	@jq -e '.name and .version and .description' gemini-extension.json >/dev/null || \
		{ echo "ERROR: gemini-extension.json missing required fields (name, version, description)"; exit 1; }
	@echo "gemini-extension.json valid."

# Validate Claude Code plugin manifests and version sync
claude-plugincheck:
	@echo "=== Validating Claude Code plugin manifest ==="
	@[ -f .claude-plugin/plugin.json ] || { echo "ERROR: Missing .claude-plugin/plugin.json"; exit 1; }
	@jq -e '.name // empty' .claude-plugin/plugin.json >/dev/null || \
		{ echo "ERROR: plugin.json missing 'name'"; exit 1; }
	@jq -e '.description // empty' .claude-plugin/plugin.json >/dev/null || \
		{ echo "ERROR: plugin.json missing 'description'"; exit 1; }
	@name=$$(jq -r '.name' .claude-plugin/plugin.json); \
	 echo "$$name" | grep -qE '^[a-z0-9][a-z0-9-]{1,63}$$' || \
		{ echo "ERROR: plugin.json name '$$name' invalid (must be kebab-case, 2-64 chars)"; exit 1; }
	@[ -f .claude-plugin/marketplace.json ] || { echo "ERROR: Missing .claude-plugin/marketplace.json"; exit 1; }
	@jq -e '.name // empty' .claude-plugin/marketplace.json >/dev/null || \
		{ echo "ERROR: marketplace.json missing 'name'"; exit 1; }
	@jq -e '.owner.name // empty' .claude-plugin/marketplace.json >/dev/null || \
		{ echo "ERROR: marketplace.json missing 'owner.name'"; exit 1; }
	@jq -e '(.plugins | length) > 0' .claude-plugin/marketplace.json >/dev/null || \
		{ echo "ERROR: marketplace.json has no plugins"; exit 1; }
	@for field in name version description; do \
	   gemini_val=$$(jq -r --arg f "$$field" '.[$$f] // ""' gemini-extension.json); \
	   claude_val=$$(jq -r --arg f "$$field" '.[$$f] // ""' .claude-plugin/plugin.json); \
	   if [ -z "$$gemini_val" ] || [ -z "$$claude_val" ]; then \
	     echo "ERROR: '$$field' missing in one manifest (gemini='$$gemini_val' claude='$$claude_val')"; exit 1; \
	   fi; \
	   if [ "$$gemini_val" != "$$claude_val" ]; then \
	     echo "ERROR: '$$field' mismatch: gemini-extension.json='$$gemini_val' vs plugin.json='$$claude_val'"; exit 1; \
	   fi; \
	 done
	@echo "Claude Code plugin manifests valid and name/version/description in sync."

# Validate SKILL.md frontmatter (name + description required)
skillcheck:
	@echo "=== Validating SKILL.md frontmatter ==="
	@for f in skills/*/SKILL.md; do \
	   [ -f "$$f" ] || continue; \
	   head -1 "$$f" | grep -q '^---' || { echo "ERROR: $$f missing YAML frontmatter"; exit 1; }; \
	   frontmatter=$$(awk '/^---$$/{n++; next} n==1{print} n>=2{exit}' "$$f"); \
	   echo "$$frontmatter" | grep -q 'name:' || { echo "ERROR: $$f frontmatter missing 'name'"; exit 1; }; \
	   echo "$$frontmatter" | grep -q 'description:' || { echo "ERROR: $$f frontmatter missing 'description'"; exit 1; }; \
	 done
	@echo "All SKILL.md frontmatter valid."

# Remove test artifacts
clean:
	rm -rf fake_osado/
