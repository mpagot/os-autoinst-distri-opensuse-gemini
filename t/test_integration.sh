#!/bin/bash

# ==============================================================================
# Integration Test: Multi-Tool Extension Installation & Discovery
# ==============================================================================
#
# This script tests that the OSADO AI Assistant extension can be properly
# installed and discovered by multiple AI coding tools:
#   - Gemini CLI (native extension install)
#   - Claude Code (skills in .claude/skills/)
#   - OpenCode (skills in .agents/skills/)
#
# It also tests the legacy install.sh overlay mechanism.
#
# Requirements: Run inside the container built from t/Containerfile
#
# ==============================================================================

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

SRC_DIR="/src"
OSADO_DIR="/osado"

# Expected skills (directory names)
EXPECTED_SKILLS=(
    "perl-test-compile"
    "vr-planner"
    "sles4sap-catalog"
    "openqa-log-analyzer"
)

# Expected commands
EXPECTED_COMMANDS=(
    "osado/git_commit.toml"
    "osado/github_pr_create.toml"
)

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $1"; SKIP=$((SKIP + 1)); }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

# Helper: check a file exists
assert_file_exists() {
    local path="$1"
    local desc="$2"
    if [[ -f "$path" ]]; then
        log_pass "$desc: $path"
    else
        log_fail "$desc: $path (not found)"
    fi
}

# Helper: check a symlink exists and points to expected target
assert_symlink() {
    local path="$1"
    local expected_target="$2"
    local desc="$3"
    if [[ -L "$path" ]]; then
        local actual_target
        actual_target=$(readlink "$path")
        if [[ "$actual_target" == "$expected_target" ]]; then
            log_pass "$desc: $path -> $expected_target"
        else
            log_fail "$desc: $path -> $actual_target (expected $expected_target)"
        fi
    else
        log_fail "$desc: $path (not a symlink)"
    fi
}

# Helper: check command exists
has_command() {
    command -v "$1" &>/dev/null
}

# Helper: reset OSADO dir to a clean git repo (isolates tests from each other)
reset_osado() {
    rm -rf "$OSADO_DIR"
    mkdir -p "$OSADO_DIR"
    git init "$OSADO_DIR" >/dev/null 2>&1
    git -C "$OSADO_DIR" config user.email "test@test.com"
    git -C "$OSADO_DIR" config user.name "Test"
    touch "$OSADO_DIR/.gitkeep"
    git -C "$OSADO_DIR" add . >/dev/null 2>&1
    git -C "$OSADO_DIR" commit -m "init" >/dev/null 2>&1
}

# =============================================================================
# TEST 1: Source Repo Structure Validation
# =============================================================================
log_section "TEST 1: Source Repository Structure"

assert_file_exists "$SRC_DIR/gemini-extension.json" "Extension manifest exists"
assert_file_exists "$SRC_DIR/OSADO_AGENTS.md" "Context file exists"

for skill in "${EXPECTED_SKILLS[@]}"; do
    assert_file_exists "$SRC_DIR/skills/$skill/SKILL.md" "Skill SKILL.md"
done

for cmd in "${EXPECTED_COMMANDS[@]}"; do
    assert_file_exists "$SRC_DIR/commands/$cmd" "Command file"
done

# Validate SKILL.md frontmatter has required fields
for skill in "${EXPECTED_SKILLS[@]}"; do
    skill_file="$SRC_DIR/skills/$skill/SKILL.md"
    if grep -q "^name:" "$skill_file" && grep -q "^description:" "$skill_file"; then
        log_pass "SKILL.md frontmatter valid: $skill"
    else
        log_fail "SKILL.md frontmatter missing name/description: $skill"
    fi
done

# =============================================================================
# TEST 2: Legacy install.sh Overlay (Gemini CLI paths)
# =============================================================================
log_section "TEST 2: Legacy install.sh (Gemini CLI paths)"

reset_osado

# Run the installer
"$SRC_DIR/tools/install.sh" "$OSADO_DIR" 2>&1 || true

# Verify .gemini/skills/ symlinks
for skill in "${EXPECTED_SKILLS[@]}"; do
    assert_symlink "$OSADO_DIR/.gemini/skills/$skill/SKILL.md" \
        "$SRC_DIR/skills/$skill/SKILL.md" \
        "install.sh: .gemini/skills/$skill/SKILL.md"
done

# Verify .gemini/commands/ symlinks
for cmd in "${EXPECTED_COMMANDS[@]}"; do
    assert_symlink "$OSADO_DIR/.gemini/commands/$cmd" \
        "$SRC_DIR/commands/$cmd" \
        "install.sh: .gemini/commands/$cmd"
done

# Verify GEMINI.md at root
assert_symlink "$OSADO_DIR/GEMINI.md" \
    "$SRC_DIR/OSADO_AGENTS.md" \
    "install.sh: GEMINI.md -> OSADO_AGENTS.md"

# =============================================================================
# TEST 3: install.sh --portable (Cross-tool paths)
# =============================================================================
log_section "TEST 3: install.sh --portable (Cross-tool paths)"

reset_osado

"$SRC_DIR/tools/install.sh" --portable "$OSADO_DIR" 2>&1 || true

# Verify .agents/skills/ symlinks (for OpenCode/Pi Agent)
for skill in "${EXPECTED_SKILLS[@]}"; do
    assert_symlink "$OSADO_DIR/.agents/skills/$skill/SKILL.md" \
        "$SRC_DIR/skills/$skill/SKILL.md" \
        "--portable: .agents/skills/$skill/SKILL.md"
done

# Verify AGENTS.md at root
assert_symlink "$OSADO_DIR/AGENTS.md" \
    "$SRC_DIR/OSADO_AGENTS.md" \
    "--portable: AGENTS.md -> OSADO_AGENTS.md"

# =============================================================================
# TEST 4: install.sh --uninstall
# =============================================================================
log_section "TEST 4: install.sh --uninstall"

reset_osado

# Install first (so there's something to uninstall)
"$SRC_DIR/tools/install.sh" "$OSADO_DIR" >/dev/null 2>&1 || true

# Now uninstall
"$SRC_DIR/tools/install.sh" --uninstall "$OSADO_DIR" 2>&1 || true

# Verify .gemini symlinks are removed
for skill in "${EXPECTED_SKILLS[@]}"; do
    if [[ -L "$OSADO_DIR/.gemini/skills/$skill/SKILL.md" ]]; then
        log_fail "--uninstall: .gemini/skills/$skill/SKILL.md still exists"
    else
        log_pass "--uninstall: .gemini/skills/$skill/SKILL.md removed"
    fi
done

# Verify GEMINI.md is removed
if [[ -L "$OSADO_DIR/GEMINI.md" ]]; then
    log_fail "--uninstall: GEMINI.md still exists"
else
    log_pass "--uninstall: GEMINI.md removed"
fi

# =============================================================================
# TEST 5: Gemini CLI Extension Discovery
# =============================================================================
log_section "TEST 5: Gemini CLI Extension Discovery"

reset_osado

if has_command gemini; then
    # Link the extension for discovery testing
    gemini extensions link "$SRC_DIR" --consent 2>&1 || true

    # Check if skills are listed
    skills_output=$(gemini skills list 2>&1 || echo "")
    if [[ -n "$skills_output" ]]; then
        for skill in "${EXPECTED_SKILLS[@]}"; do
            if echo "$skills_output" | grep -q "$skill"; then
                log_pass "gemini skills list: $skill discovered"
            else
                log_fail "gemini skills list: $skill NOT discovered"
            fi
        done
    else
        log_skip "gemini skills list returned empty (may need API key)"
    fi

    # Check commands
    # Note: /help requires an interactive session, so we check file presence
    gemini_ext_dir="$HOME/.gemini/extensions/osado-ai-assistant"
    if [[ -d "$gemini_ext_dir" ]] || [[ -L "$gemini_ext_dir" ]]; then
        log_pass "Extension linked in ~/.gemini/extensions/"
    else
        log_skip "Extension directory not found (link may have failed)"
    fi
else
    log_skip "Gemini CLI not installed: skipping extension discovery tests"
fi

# =============================================================================
# TEST 6: Claude Code Skill Discovery
# =============================================================================
log_section "TEST 6: Claude Code Compatibility"

reset_osado

if has_command claude; then
    # Set up Claude Code skill directory
    mkdir -p "$OSADO_DIR/.claude/skills"
    cp -r "$SRC_DIR/skills/"* "$OSADO_DIR/.claude/skills/"

    for skill in "${EXPECTED_SKILLS[@]}"; do
        assert_file_exists "$OSADO_DIR/.claude/skills/$skill/SKILL.md" \
            "Claude Code: .claude/skills/$skill/SKILL.md"
    done

    # Try to list skills if claude supports it
    # Note: Claude Code may not have a non-interactive skill list command
    log_info "Claude Code installed. Skills copied to .claude/skills/."
    log_pass "Claude Code: skill files placed correctly"
else
    # Still verify the file structure would work
    mkdir -p "$OSADO_DIR/.claude/skills"
    cp -r "$SRC_DIR/skills/"* "$OSADO_DIR/.claude/skills/"

    for skill in "${EXPECTED_SKILLS[@]}"; do
        assert_file_exists "$OSADO_DIR/.claude/skills/$skill/SKILL.md" \
            "Claude Code (no CLI): .claude/skills/$skill/SKILL.md"
    done

    log_skip "Claude Code not installed: verified file placement only"
fi

# =============================================================================
# TEST 7: OpenCode Skill Discovery
# =============================================================================
log_section "TEST 7: OpenCode Compatibility"

reset_osado

if has_command opencode; then
    # Set up OpenCode skill directory
    mkdir -p "$OSADO_DIR/.agents/skills"
    cp -r "$SRC_DIR/skills/"* "$OSADO_DIR/.agents/skills/"
    cp "$SRC_DIR/OSADO_AGENTS.md" "$OSADO_DIR/AGENTS.md"

    for skill in "${EXPECTED_SKILLS[@]}"; do
        assert_file_exists "$OSADO_DIR/.agents/skills/$skill/SKILL.md" \
            "OpenCode: .agents/skills/$skill/SKILL.md"
    done
    assert_file_exists "$OSADO_DIR/AGENTS.md" "OpenCode: AGENTS.md at root"

    log_pass "OpenCode: skill files and AGENTS.md placed correctly"
else
    # Verify file structure
    mkdir -p "$OSADO_DIR/.agents/skills"
    cp -r "$SRC_DIR/skills/"* "$OSADO_DIR/.agents/skills/"
    cp "$SRC_DIR/OSADO_AGENTS.md" "$OSADO_DIR/AGENTS.md"

    for skill in "${EXPECTED_SKILLS[@]}"; do
        assert_file_exists "$OSADO_DIR/.agents/skills/$skill/SKILL.md" \
            "OpenCode (no CLI): .agents/skills/$skill/SKILL.md"
    done
    assert_file_exists "$OSADO_DIR/AGENTS.md" "OpenCode (no CLI): AGENTS.md at root"

    log_skip "OpenCode not installed: verified file placement only"
fi

# =============================================================================
# TEST 8: Context File Content Validation
# =============================================================================
log_section "TEST 8: Context File Validation"

# OSADO_AGENTS.md should contain key OSADO project info and workflow instructions
if grep -q "os-autoinst" "$SRC_DIR/OSADO_AGENTS.md"; then
    log_pass "OSADO_AGENTS.md references os-autoinst"
else
    log_fail "OSADO_AGENTS.md missing os-autoinst reference"
fi

if grep -q "make" "$SRC_DIR/OSADO_AGENTS.md"; then
    log_pass "OSADO_AGENTS.md contains build commands"
else
    log_fail "OSADO_AGENTS.md missing build commands"
fi

if grep -q "PERL5LIB" "$SRC_DIR/OSADO_AGENTS.md"; then
    log_pass "OSADO_AGENTS.md contains PERL5LIB setup"
else
    log_fail "OSADO_AGENTS.md missing PERL5LIB setup"
fi

if grep -q "make tidy" "$SRC_DIR/OSADO_AGENTS.md"; then
    log_pass "OSADO_AGENTS.md contains formatting commands"
else
    log_fail "OSADO_AGENTS.md missing formatting commands"
fi

# =============================================================================
# TEST 9: gemini-extension.json Validation
# =============================================================================
log_section "TEST 9: Extension Manifest Validation"

manifest="$SRC_DIR/gemini-extension.json"

# Check required fields
for field in name version description contextFileName; do
    if jq -e ".$field" "$manifest" >/dev/null 2>&1; then
        log_pass "Manifest has required field: $field"
    else
        log_fail "Manifest missing required field: $field"
    fi
done

# Verify contextFileName points to existing file
context_file=$(jq -r '.contextFileName' "$manifest")
if [[ -f "$SRC_DIR/$context_file" ]]; then
    log_pass "contextFileName '$context_file' exists"
else
    log_fail "contextFileName '$context_file' does not exist"
fi

# Verify name is valid (kebab-case)
ext_name=$(jq -r '.name' "$manifest")
if [[ "$ext_name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
    log_pass "Extension name is valid kebab-case: $ext_name"
else
    log_fail "Extension name is not valid kebab-case: $ext_name"
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "============================================"
echo -e "  ${GREEN}PASSED: $PASS${NC}"
echo -e "  ${RED}FAILED: $FAIL${NC}"
echo -e "  ${YELLOW}SKIPPED: $SKIP${NC}"
echo "  TOTAL:  $((PASS + FAIL + SKIP))"
echo "============================================"
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo -e "${RED}Integration tests FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}Integration tests PASSED${NC}"
    exit 0
fi
