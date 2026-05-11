#!/bin/bash

# ==============================================================================
# OSADO AI Assistant - Installation Test Suite
# ==============================================================================
# Tests the overlay install mechanism (tools/install.sh) including:
#   - Basic installation (symlinks from repo root skills/ and commands/)
#   - Conflict protection
#   - Uninstallation (selective, preserves user files)
#   - Update simulation (mocked git pull)
#   - Nested directory linking
#   - Pre-existing .gemini coexistence
#   - User-modified symlink protection
#   - Root GEMINI.md and AGENTS.md handling
#   - --portable flag (cross-tool .agents/skills/)
# ==============================================================================

set -e

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SCRIPT="$REPO_ROOT/tools/install.sh"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test environment
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

FAKE_OSADO="$TEST_ROOT/fake_osado"

# Helper functions
log_test() { echo -e "${YELLOW}TEST:${NC} $1"; }
log_pass() { echo -e "${GREEN}PASS${NC}"; }
log_fail() { echo -e "${RED}FAIL:${NC} $1"; exit 1; }

setup_fake_osado() {
    rm -rf "$FAKE_OSADO"
    mkdir -p "$FAKE_OSADO/.git"
}

assert_is_link() {
    local target="$1"
    local expected_source="$2"
    [ -L "$target" ] || log_fail "Path '$target' is not a symlink"
    local actual_source
    actual_source=$(readlink "$target")
    [ "$actual_source" == "$expected_source" ] || log_fail "Link '$target' points to '$actual_source', expected '$expected_source'"
}

assert_not_exists() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        log_fail "Path '$1' should not exist"
    fi
}

assert_exists() {
    [ -e "$1" ] || log_fail "Path '$1' should exist"
}

assert_content() {
    local file="$1"
    local expected="$2"
    local actual
    actual=$(cat "$file")
    [ "$actual" == "$expected" ] || log_fail "File '$file' content mismatch. Got: '$actual', Expected: '$expected'"
}

# ------------------------------------------------------------------------------
# TEST 1: Basic Installation (Empty OSADO)
# Verifies basic installation on a clean repository where only .git exists.
# ------------------------------------------------------------------------------
log_test "1: Basic Installation on empty OSADO repo"
setup_fake_osado
"$INSTALL_SCRIPT" "$FAKE_OSADO" > /dev/null 2>&1

# Commands
assert_is_link "$FAKE_OSADO/.gemini/commands/osado/github_pr_create.toml" \
    "$REPO_ROOT/commands/osado/github_pr_create.toml"

# Skills (check a few representative files)
assert_is_link "$FAKE_OSADO/.gemini/skills/perl-test-compile/SKILL.md" \
    "$REPO_ROOT/skills/perl-test-compile/SKILL.md"
assert_is_link "$FAKE_OSADO/.gemini/skills/perl-test-compile/scripts/test_compile.sh" \
    "$REPO_ROOT/skills/perl-test-compile/scripts/test_compile.sh"
assert_is_link "$FAKE_OSADO/.gemini/skills/openqa-log-analyzer/SKILL.md" \
    "$REPO_ROOT/skills/openqa-log-analyzer/SKILL.md"

# Root GEMINI.md
assert_is_link "$FAKE_OSADO/GEMINI.md" "$REPO_ROOT/OSADO_AGENTS.md"
log_pass

# ------------------------------------------------------------------------------
# TEST 2: Conflict Protection (Existing user files)
# Verifies that the script does not overwrite existing regular files.
# ------------------------------------------------------------------------------
log_test "2: Conflict Protection - Do not overwrite user files"
setup_fake_osado
mkdir -p "$FAKE_OSADO/.gemini/commands/osado"
echo "USER_CONTENT" > "$FAKE_OSADO/.gemini/commands/osado/github_pr_create.toml"

# Run install
"$INSTALL_SCRIPT" "$FAKE_OSADO" > "$TEST_ROOT/install_output.log" 2>&1 || true

# Verify warning was issued
grep -q "Conflict" "$TEST_ROOT/install_output.log" || log_fail "No conflict warning found in output"

# Verify user file is untouched
[ ! -L "$FAKE_OSADO/.gemini/commands/osado/github_pr_create.toml" ] || log_fail "User file was replaced by a link!"
assert_content "$FAKE_OSADO/.gemini/commands/osado/github_pr_create.toml" "USER_CONTENT"

# Verify other files ARE linked
assert_is_link "$FAKE_OSADO/.gemini/skills/perl-test-compile/SKILL.md" \
    "$REPO_ROOT/skills/perl-test-compile/SKILL.md"
log_pass

# ------------------------------------------------------------------------------
# TEST 3: Uninstallation (Clean & Selective)
# Verifies that uninstallation only removes links pointing to the toolset.
# ------------------------------------------------------------------------------
log_test "3: Uninstallation - Remove only toolset links, keep user data"
setup_fake_osado
"$INSTALL_SCRIPT" "$FAKE_OSADO" > /dev/null 2>&1

# Create a user-owned file
echo "MY_SKILL" > "$FAKE_OSADO/.gemini/skills/my_skill.md"

# Uninstall
"$INSTALL_SCRIPT" --uninstall "$FAKE_OSADO" > /dev/null 2>&1

# Verify toolset links are gone
assert_not_exists "$FAKE_OSADO/.gemini/commands/osado/github_pr_create.toml"
assert_not_exists "$FAKE_OSADO/.gemini/skills/perl-test-compile/SKILL.md"
assert_not_exists "$FAKE_OSADO/.gemini/skills/openqa-log-analyzer/SKILL.md"

# Verify user file is preserved
[ -f "$FAKE_OSADO/.gemini/skills/my_skill.md" ] || log_fail "User file was deleted during uninstall!"
log_pass

# ------------------------------------------------------------------------------
# TEST 4: Update Simulation (Mocked Git)
# Verifies that --update triggers 'git pull' in the toolset repo.
# ------------------------------------------------------------------------------
log_test "4: Update Simulation - verify mocked git pull"
setup_fake_osado

MOCK_BIN="$TEST_ROOT/bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/git" <<EOF
#!/bin/bash
if [[ "\$*" == *"pull"* ]]; then
    echo "MOCK_GIT_PULL_CALLED"
    exit 0
fi
/usr/bin/git "\$@"
EOF

chmod +x "$MOCK_BIN/git"
PATH="$MOCK_BIN:$PATH" "$INSTALL_SCRIPT" --update "$FAKE_OSADO" > "$TEST_ROOT/update_output.log" 2>&1
grep -q "MOCK_GIT_PULL_CALLED" "$TEST_ROOT/update_output.log" || log_fail "Git pull was not called"
log_pass

# ------------------------------------------------------------------------------
# TEST 5: Nested Directory Structure
# Verifies recursive linking for skills with scripts/ and assets/.
# ------------------------------------------------------------------------------
log_test "5: Recursive Linking - verify nested directories"
setup_fake_osado
"$INSTALL_SCRIPT" "$FAKE_OSADO" > /dev/null 2>&1

# openqa-log-analyzer has scripts/
assert_is_link "$FAKE_OSADO/.gemini/skills/openqa-log-analyzer/scripts/extract_log_section.pl" \
    "$REPO_ROOT/skills/openqa-log-analyzer/scripts/extract_log_section.pl"

# sles4sap-catalog has scripts/ and assets/
assert_is_link "$FAKE_OSADO/.gemini/skills/sles4sap-catalog/scripts/audit.sh" \
    "$REPO_ROOT/skills/sles4sap-catalog/scripts/audit.sh"
assert_is_link "$FAKE_OSADO/.gemini/skills/sles4sap-catalog/assets/template.md" \
    "$REPO_ROOT/skills/sles4sap-catalog/assets/template.md"

# vr-planner has multiple scripts
assert_is_link "$FAKE_OSADO/.gemini/skills/vr-planner/scripts/classify_changes.pl" \
    "$REPO_ROOT/skills/vr-planner/scripts/classify_changes.pl"
log_pass

# ------------------------------------------------------------------------------
# TEST 6: Existing .gemini (Non-conflicting)
# Verifies installation alongside existing user skills.
# ------------------------------------------------------------------------------
log_test "6: Installation with pre-existing .gemini (non-conflicting)"
setup_fake_osado
mkdir -p "$FAKE_OSADO/.gemini/skills"
echo "PRE_EXISTING" > "$FAKE_OSADO/.gemini/skills/user_skill.md"

"$INSTALL_SCRIPT" "$FAKE_OSADO" > /dev/null 2>&1

assert_content "$FAKE_OSADO/.gemini/skills/user_skill.md" "PRE_EXISTING"
assert_is_link "$FAKE_OSADO/.gemini/skills/perl-test-compile/SKILL.md" \
    "$REPO_ROOT/skills/perl-test-compile/SKILL.md"
log_pass

# ------------------------------------------------------------------------------
# TEST 7: Edited before Uninstall
# Verifies that user-replaced symlinks are NOT removed during uninstall.
# ------------------------------------------------------------------------------
log_test "7: Uninstallation - Protect user-modified files that replaced symlinks"
setup_fake_osado
"$INSTALL_SCRIPT" "$FAKE_OSADO" > /dev/null 2>&1

# Replace a symlink with a regular file
rm "$FAKE_OSADO/.gemini/skills/perl-test-compile/SKILL.md"
echo "USER_MODIFIED" > "$FAKE_OSADO/.gemini/skills/perl-test-compile/SKILL.md"

# Replace a symlink with a different link
rm "$FAKE_OSADO/.gemini/commands/osado/github_pr_create.toml"
ln -s "/tmp" "$FAKE_OSADO/.gemini/commands/osado/github_pr_create.toml"

# Run uninstall
"$INSTALL_SCRIPT" --uninstall "$FAKE_OSADO" > /dev/null 2>&1

# Verify modified files are preserved
assert_content "$FAKE_OSADO/.gemini/skills/perl-test-compile/SKILL.md" "USER_MODIFIED"
[ -L "$FAKE_OSADO/.gemini/commands/osado/github_pr_create.toml" ] || log_fail "User symlink was deleted!"
[ "$(readlink "$FAKE_OSADO/.gemini/commands/osado/github_pr_create.toml")" == "/tmp" ] || log_fail "User symlink points to wrong place"

# Verify other toolset links ARE removed
assert_not_exists "$FAKE_OSADO/.gemini/skills/openqa-log-analyzer/SKILL.md"
log_pass

# ------------------------------------------------------------------------------
# TEST 8: Root GEMINI.md handling
# Verifies linking and protection during uninstall.
# ------------------------------------------------------------------------------
log_test "8: Root GEMINI.md - verify linking and protection"
setup_fake_osado
"$INSTALL_SCRIPT" "$FAKE_OSADO" > /dev/null 2>&1

assert_is_link "$FAKE_OSADO/GEMINI.md" "$REPO_ROOT/OSADO_AGENTS.md"

# Replace with a real file
rm "$FAKE_OSADO/GEMINI.md"
echo "USER_GEMINI" > "$FAKE_OSADO/GEMINI.md"

# Run uninstall — should NOT remove user's regular file
"$INSTALL_SCRIPT" --uninstall "$FAKE_OSADO" > /dev/null 2>&1

assert_content "$FAKE_OSADO/GEMINI.md" "USER_GEMINI"
log_pass

# ------------------------------------------------------------------------------
# TEST 9: --portable flag (Cross-tool .agents/skills/ and AGENTS.md)
# Verifies that --portable creates additional symlinks for OpenCode/Pi Agent.
# ------------------------------------------------------------------------------
log_test "9: --portable flag - cross-tool .agents/skills/ and AGENTS.md"
setup_fake_osado
"$INSTALL_SCRIPT" --portable "$FAKE_OSADO" > /dev/null 2>&1

# .agents/skills/ should have the same skills
assert_is_link "$FAKE_OSADO/.agents/skills/perl-test-compile/SKILL.md" \
    "$REPO_ROOT/skills/perl-test-compile/SKILL.md"
assert_is_link "$FAKE_OSADO/.agents/skills/openqa-log-analyzer/SKILL.md" \
    "$REPO_ROOT/skills/openqa-log-analyzer/SKILL.md"
assert_is_link "$FAKE_OSADO/.agents/skills/openqa-log-analyzer/scripts/extract_log_section.pl" \
    "$REPO_ROOT/skills/openqa-log-analyzer/scripts/extract_log_section.pl"

# AGENTS.md at root
assert_is_link "$FAKE_OSADO/AGENTS.md" "$REPO_ROOT/OSADO_AGENTS.md"

# .gemini/ should ALSO be linked (--portable adds to the default, not replaces it)
assert_is_link "$FAKE_OSADO/.gemini/skills/perl-test-compile/SKILL.md" \
    "$REPO_ROOT/skills/perl-test-compile/SKILL.md"
log_pass

# ------------------------------------------------------------------------------
# TEST 10: --portable --uninstall (removes cross-tool files)
# Verifies that --portable --uninstall removes .agents/ symlinks and AGENTS.md.
# ------------------------------------------------------------------------------
log_test "10: --portable --uninstall - removes cross-tool files"

# AGENTS.md and .agents/ should exist from test 9
assert_exists "$FAKE_OSADO/AGENTS.md"
assert_exists "$FAKE_OSADO/.agents/skills/perl-test-compile/SKILL.md"

"$INSTALL_SCRIPT" --portable --uninstall "$FAKE_OSADO" > /dev/null 2>&1

# Cross-tool files should be removed
assert_not_exists "$FAKE_OSADO/.agents/skills/perl-test-compile/SKILL.md"
assert_not_exists "$FAKE_OSADO/AGENTS.md"

# .gemini files should also be removed
assert_not_exists "$FAKE_OSADO/.gemini/skills/perl-test-compile/SKILL.md"
log_pass

echo -e "\n${GREEN}All tests passed successfully!${NC}"
