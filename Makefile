# ==============================================================================
# OSADO AI Assistant - Development Makefile
# ==============================================================================

.PHONY: test test-install test-integration lint shellcheck perlcheck semgrep clean help

# Default target
help:
	@echo "Available targets:"
	@echo "  make test             - Run all local tests (install + lint)"
	@echo "  make test-install     - Run overlay installer unit tests"
	@echo "  make test-integration - Run integration tests in container"
	@echo "  make lint             - Run shellcheck + perl syntax on all scripts"
	@echo "  make shellcheck       - Lint shell scripts with shellcheck"
	@echo "  make perlcheck        - Syntax-check Perl scripts with perl -c"
	@echo "  make semgrep          - Run semgrep bash security rules (requires uvx)"
	@echo "  make clean            - Remove test artifacts"
	@echo ""
	@echo "Container runtime (default: podman):"
	@echo "  make test-integration CONTAINER_RT=docker"

# Container runtime (podman or docker)
CONTAINER_RT ?= podman
TEST_IMAGE ?= ghcr.io/mpagot/osado-gemini-tester:latest

# Run all local tests (no container needed)
test: test-install lint

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

# Remove test artifacts
clean:
	rm -rf fake_osado/
