#!/bin/bash

# ==============================================================================
# OSADO AI Assistant - Installation Test Suite
# ==============================================================================

set -e

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SCRIPT="$REPO_ROOT/tools/install.sh"
OVERLAY_DIR="$REPO_ROOT/osado_overlay"

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
    local actual_source=$(readlink "$target")
    # Resolve to absolute path for comparison
    local abs_expected=$(cd "$(dirname "$expected_source")" && pwd)/$(basename "$expected_source")
    [ "$actual_source" == "$abs_expected" ] || log_fail "Link '$target' points to '$actual_source', expected '$abs_expected'"
}

assert_not_exists() {
    [ ! -e "$1" ] || log_fail "Path '$1' should not exist"
}

assert_content() {
    local file="$1"
    local expected="$2"
    local actual=$(cat "$file")
    [ "$actual" == "$expected" ] || log_fail "File '$file' content mismatch. Got: '$actual', Expected: '$expected'"
}

# ------------------------------------------------------------------------------
# TEST 1: Basic Installation (Empty OSADO)
# Verifies basic installation on a clean repository where only .git exists.
# ------------------------------------------------------------------------------
log_test "Basic Installation on empty OSADO repo"
setup_fake_osado
"$INSTALL_SCRIPT" "$FAKE_OSADO" > /dev/null

assert_is_link "$FAKE_OSADO/.gemini/commands/github_pr_create.toml" "$OVERLAY_DIR/.gemini/commands/github_pr_create.toml"
assert_is_link "$FAKE_OSADO/.gemini/skills/test_compile.sh" "$OVERLAY_DIR/.gemini/skills/test_compile.sh"
assert_is_link "$FAKE_OSADO/GEMINI.md" "$OVERLAY_DIR/GEMINI.md"
log_pass

# ------------------------------------------------------------------------------
# TEST 2: Conflict Protection (Existing user files)
# Verifies that the script does not overwrite existing regular files and 
# issues a warning.
# ------------------------------------------------------------------------------
log_test "Conflict Protection - Do not overwrite user files"
setup_fake_osado
mkdir -p "$FAKE_OSADO/.gemini/commands"
echo "USER_CONTENT" > "$FAKE_OSADO/.gemini/commands/github_pr_create.toml"

# Run install
"$INSTALL_SCRIPT" "$FAKE_OSADO" > "$TEST_ROOT/install_output.log" 2>&1 || true

# Verify warning was issued
grep -q "Conflict" "$TEST_ROOT/install_output.log" || log_fail "No conflict warning found in output"

# Verify user file is untouched
[ ! -L "$FAKE_OSADO/.gemini/commands/github_pr_create.toml" ] || log_fail "User file was replaced by a link!"
assert_content "$FAKE_OSADO/.gemini/commands/github_pr_create.toml" "USER_CONTENT"

# Verify other files ARE linked
assert_is_link "$FAKE_OSADO/.gemini/skills/test_compile.sh" "$OVERLAY_DIR/.gemini/skills/test_compile.sh"
log_pass

# ------------------------------------------------------------------------------
# TEST 3: Uninstallation (Clean & Selective)
# Verifies that uninstallation only removes links pointing to the toolset,
# preserving other files in the .gemini directory.
# ------------------------------------------------------------------------------
log_test "Uninstallation - Remove only toolset links, keep user data"
setup_fake_osado
"$INSTALL_SCRIPT" "$FAKE_OSADO" > /dev/null

# Create a user-owned file
mkdir -p "$FAKE_OSADO/.gemini/skills"
echo "MY_SKILL" > "$FAKE_OSADO/.gemini/skills/my_skill.md"

# Uninstall
"$INSTALL_SCRIPT" --uninstall "$FAKE_OSADO" > /dev/null

# Verify toolset links are gone
assert_not_exists "$FAKE_OSADO/.gemini/commands/github_pr_create.toml"
assert_not_exists "$FAKE_OSADO/.gemini/skills/test_compile.sh"

# Verify user file is preserved
[ -f "$FAKE_OSADO/.gemini/skills/my_skill.md" ] || log_fail "User file was deleted during uninstall!"
log_pass

# ------------------------------------------------------------------------------
# TEST 4: Update Simulation (Mocked Git)
# Verifies that the --update flag triggers a 'git pull' in the toolset repo.
# ------------------------------------------------------------------------------
log_test "Update Simulation - verify mocked git pull"
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
export PATH="$MOCK_BIN:$PATH"
"$INSTALL_SCRIPT" --update "$FAKE_OSADO" > "$TEST_ROOT/update_output.log" 2>&1
grep -q "MOCK_GIT_PULL_CALLED" "$TEST_ROOT/update_output.log" || log_fail "Git pull was not called"
log_pass

# ------------------------------------------------------------------------------
# TEST 5: Nested Directory Structure
# Verifies that the script correctly handles and links files within nested 
# directory structures in the overlay.
# ------------------------------------------------------------------------------
log_test "Recursive Linking - verify nested directories"
setup_fake_osado
"$INSTALL_SCRIPT" "$FAKE_OSADO" > /dev/null

assert_is_link "$FAKE_OSADO/.gemini/skills/openqa-log-analyzer/SKILL.md" "$OVERLAY_DIR/.gemini/skills/openqa-log-analyzer/SKILL.md"
assert_is_link "$FAKE_OSADO/.gemini/skills/openqa-log-analyzer/scripts/extract_log_section.sh" "$OVERLAY_DIR/.gemini/skills/openqa-log-analyzer/scripts/extract_log_section.sh"
log_pass

# ------------------------------------------------------------------------------
# TEST 6: Existing .gemini (Non-conflicting)
# Verifies installation on a repo that already has a .gemini folder with
# existing user skills.
# ------------------------------------------------------------------------------
log_test "Installation with pre-existing .gemini (non-conflicting)"
setup_fake_osado
mkdir -p "$FAKE_OSADO/.gemini/skills"
echo "PRE_EXISTING" > "$FAKE_OSADO/.gemini/skills/user_skill.md"

"$INSTALL_SCRIPT" "$FAKE_OSADO" > /dev/null

assert_content "$FAKE_OSADO/.gemini/skills/user_skill.md" "PRE_EXISTING"
assert_is_link "$FAKE_OSADO/.gemini/skills/test_compile.sh" "$OVERLAY_DIR/.gemini/skills/test_compile.sh"
log_pass

# ------------------------------------------------------------------------------
# TEST 7: Edited before Uninstall (Symlink replacement)
# Verifies that if a user replaces a toolset symlink with their own file or
# a different link, it is NOT removed during uninstallation.
# ------------------------------------------------------------------------------
log_test "Uninstallation - Protect user-modified files that replaced symlinks"
setup_fake_osado
"$INSTALL_SCRIPT" "$FAKE_OSADO" > /dev/null

# Replace a symlink with a regular file
rm "$FAKE_OSADO/.gemini/skills/test_compile.sh"
echo "USER_MODIFIED" > "$FAKE_OSADO/.gemini/skills/test_compile.sh"

# Replace a symlink with a different link
rm "$FAKE_OSADO/.gemini/commands/github_pr_create.toml"
ln -s "/tmp" "$FAKE_OSADO/.gemini/commands/github_pr_create.toml"

# Run uninstall
"$INSTALL_SCRIPT" --uninstall "$FAKE_OSADO" > /dev/null

# Verify toolset links are gone (using one that wasn't touched)
assert_not_exists "$FAKE_OSADO/.gemini/skills/search_comments.sh"

# Verify modified files are preserved
assert_content "$FAKE_OSADO/.gemini/skills/test_compile.sh" "USER_MODIFIED"
[ -L "$FAKE_OSADO/.gemini/commands/github_pr_create.toml" ] || log_fail "User symlink was deleted!"
[ "$(readlink "$FAKE_OSADO/.gemini/commands/github_pr_create.toml")" == "/tmp" ] || log_fail "User symlink points to wrong place"
log_pass

# ------------------------------------------------------------------------------
# TEST 8: root GEMINI.md handling
# Verifies that the repository root GEMINI.md is correctly linked and
# protected from deletion during uninstallation if modified by the user.
# ------------------------------------------------------------------------------
log_test "Root GEMINI.md - verify linking and protection"
setup_fake_osado
"$INSTALL_SCRIPT" "$FAKE_OSADO" > /dev/null

assert_is_link "$FAKE_OSADO/GEMINI.md" "$OVERLAY_DIR/GEMINI.md"

# Replace with a real file
rm "$FAKE_OSADO/GEMINI.md"
echo "USER_GEMINI" > "$FAKE_OSADO/GEMINI.md"

# Run uninstall
"$INSTALL_SCRIPT" --uninstall "$FAKE_OSADO" > /dev/null

# Verify it is preserved
assert_content "$FAKE_OSADO/GEMINI.md" "USER_GEMINI"
log_pass

echo -e "\n${GREEN}All tests passed successfully!${NC}"
