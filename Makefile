# ==============================================================================
# OSADO AI Assistant - Development Makefile
# ==============================================================================

.PHONY: test test-install test-integration lint shellcheck clean help

# Default target
help:
	@echo "Available targets:"
	@echo "  make test             - Run all local tests (install + lint)"
	@echo "  make test-install     - Run overlay installer unit tests"
	@echo "  make test-integration - Pull base image and run integration tests"
	@echo "  make lint             - Run shellcheck on all scripts"
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
lint: shellcheck

shellcheck:
	@echo "=== Running shellcheck ==="
	shellcheck tools/*.sh t/*.sh skills/*/scripts/*.sh

# Remove test artifacts
clean:
	rm -rf fake_osado/
