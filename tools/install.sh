#!/bin/bash

# ==============================================================================
# OSADO AI Assistant Installation & Management Script
# ==============================================================================
# 
#   This script create a non-destructive "overlay" mechanism. It allows the
#   Gemini CLI toolset to exist in a separate directory than OSADO 
#   while allowing to have all the tools properly configured when starting
#   the code assistent cli from the root of OSADO.
#
#   - Installation: Run the script pointing to your OSADO repo. It "installs" 
#      shared skills/commands using symlinks.
#   - Editing: Since files are symlinked, you can edit them directly in your
#      OSADO repo, and the changes are saved back to this toolset repo.
#   - Uninstallation: Removes the shared tools while leaving your repo clean.
#
#    Your personal files in .gemini/ are never touched or deleted.
#    Skips any target path that already exists as a 
#    regular file or a symlink to a different location.
#
# INTERNAL MECHANISM:
#   - Recursive Symlinking: The script iterates through this repo's
#     'commands/' and 'skills/' directories at the repo root. For every file
#     found, it creates a corresponding symlink in <osado>/.gemini/.
#   - Directory Mirroring: It uses 'mkdir -p' to recreate the directory tree.
#     It does NOT symlink directories themselves to avoid overwriting your
#     existing folders (like .gemini/skills).
#   - Files are processed individually. A conflict in one file does not stop
#     the rest of the installation.
#   - 'gemini-extension.json' at the repo root is NOT linked: it is only
#     meaningful when this repo is installed via 'gemini extensions install'.
#
# SUB-COMMANDS:
#   - [install]: Default behavior. Recursively symlinks files from the overlay
#     to the target OSADO repository.
#   - [--update]: Pulls the latest changes from this toolset repository before
#     refreshing symlinks.
#   - [--uninstall]: Traverses the overlay and uses 'unlink' to remove only
#     the symlinks that point specifically to this toolset.
#
# CORNER CASES:
#   - Missing Target: Validates that the provided path contains a .git folder.
#   - Broken Symlinks: The script detects and handles existing symlinks even 
#     if their target has been moved.
#   - Directory Preservation: During uninstallation, no directories are 
#     removed (even empty ones) to guarantee absolute safety for user data.
#   - Absolute Paths: Resolves all paths to absolute to ensure symlinks 
#     function regardless of where 'gemini-cli' is invoked.
#
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [OPTIONS] <path_to_osado_repo>"
    echo ""
    echo "Options:"
    echo "  --update       Update this toolset repository (git pull) before installation"
    echo "  --uninstall    Remove symlinks created by this toolset"
    echo "  --portable     Also link into .agents/skills/ and AGENTS.md (for OpenCode/Pi Agent)"
    echo "  --help         Show this help message"
    exit 1
}

log_info() { echo -e "${BLUE}INFO:${NC} $1"; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $1"; }
log_warn() { echo -e "${YELLOW}WARNING:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }

UPDATE=false
UNINSTALL=false
PORTABLE=false
OSADO_PATH=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --update) UPDATE=true ;;
        --uninstall) UNINSTALL=true ;;
        --portable) PORTABLE=true ;;
        --help) usage ;;
        -*) log_error "Unknown option: $1"; usage ;;
        *) OSADO_PATH="$1" ;;
    esac
    shift
done

if [[ -z "$OSADO_PATH" ]]; then
    log_error "Missing OSADO repository path."
    usage
fi

# Update sub-command
if [ "$UPDATE" = true ]; then
    log_info "Updating toolset repository..."
    git -C "$REPO_ROOT" pull
fi

# Validate OSADO path
if [[ ! -d "$OSADO_PATH/.git" ]]; then
    log_error "The path '$OSADO_PATH' does not appear to be a git repository root."
    exit 1
fi

OSADO_ABS_PATH="$(cd "$OSADO_PATH" && pwd)"
log_info "Target OSADO repository: $OSADO_ABS_PATH"

# Deprecation notice
log_warn "This manual installation method is deprecated."
log_warn "Preferred method: gemini extensions install https://github.com/os-autoinst/os-autoinst-distri-opensuse-gemini"
log_warn "See README.md for all installation options (Gemini CLI, OpenCode, Claude Code)."
echo ""

# Create target directories
TARGET_GEMINI_DIR="$OSADO_ABS_PATH/.gemini"
mkdir -p "$TARGET_GEMINI_DIR/commands"
mkdir -p "$TARGET_GEMINI_DIR/skills"

# Function to symlink files recursively
link_files() {
    local src_dir="$1"
    local rel_path="$2" # e.g. "commands" or "skills/openqa-log-analyzer"
    
    local source_full="$src_dir/$rel_path"
    local target_full="$TARGET_GEMINI_DIR/$rel_path"

    # Create target directory if it doesn't exist
    mkdir -p "$target_full"

    # Iterate over files and directories in source
    for item in "$source_full"/*; do
        [ -e "$item" ] || continue
        local name
        name=$(basename "$item")
        local target_item="$target_full/$name"

        if [ -d "$item" ]; then
            # Recursive call for directories
            link_files "$src_dir" "$rel_path/$name"
        else
            # Handle files
            if [ -e "$target_item" ] || [ -L "$target_item" ]; then
                if [ -L "$target_item" ]; then
                    local existing_link
                    existing_link=$(readlink "$target_item")
                    if [ "$existing_link" == "$item" ]; then
                        # Already linked correctly, skip
                        continue
                    else
                        log_warn "Conflict: '$target_item' is a symlink to another location. Skipping."
                    fi
                else
                    log_warn "Conflict: '$target_item' already exists as a regular file. Skipping to protect your changes."
                fi
            else
                ln -s "$item" "$target_item"
                echo "Linked: .gemini/$rel_path/$name"
            fi
        fi
    done
}

# Function to remove symlinks recursively
unlink_files() {
    local src_dir="$1"
    local rel_path="$2"
    
    local source_full="$src_dir/$rel_path"
    local target_full="$TARGET_GEMINI_DIR/$rel_path"

    [ -d "$source_full" ] || return 0

    for item in "$source_full"/*; do
        [ -e "$item" ] || continue
        local name
        name=$(basename "$item")
        local target_item="$target_full/$name"

        if [ -d "$item" ]; then
            unlink_files "$src_dir" "$rel_path/$name"
        else
            if [ -L "$target_item" ]; then
                local existing_link
                existing_link=$(readlink "$target_item")
                if [ "$existing_link" == "$item" ]; then
                    unlink "$target_item"
                    echo "Unlinked: .gemini/$rel_path/$name"
                fi
            fi
        fi
    done
}

if [ "$UNINSTALL" = true ]; then
    log_info "Uninstalling overlay files..."
    unlink_files "$REPO_ROOT" "commands"
    unlink_files "$REPO_ROOT" "skills"

    # Remove root GEMINI.md if it points to our OSADO_AGENTS.md
    if [ -L "$OSADO_ABS_PATH/GEMINI.md" ]; then
        if [ "$(readlink "$OSADO_ABS_PATH/GEMINI.md")" == "$REPO_ROOT/OSADO_AGENTS.md" ]; then
            unlink "$OSADO_ABS_PATH/GEMINI.md"
            log_success "Unlinked GEMINI.md from OSADO root."
        fi
    fi

    # Portable: remove .agents/skills/ symlinks and AGENTS.md
    if [ "$PORTABLE" = true ]; then
        log_info "Removing portable cross-tool files..."
        TARGET_AGENTS_DIR="$OSADO_ABS_PATH/.agents"
        if [ -d "$TARGET_AGENTS_DIR/skills" ]; then
            # Reuse unlink_files with .agents as target
            local_target_backup="$TARGET_GEMINI_DIR"
            TARGET_GEMINI_DIR="$TARGET_AGENTS_DIR"
            unlink_files "$REPO_ROOT" "skills"
            TARGET_GEMINI_DIR="$local_target_backup"
        fi
        if [ -L "$OSADO_ABS_PATH/AGENTS.md" ]; then
            if [ "$(readlink "$OSADO_ABS_PATH/AGENTS.md")" == "$REPO_ROOT/OSADO_AGENTS.md" ]; then
                unlink "$OSADO_ABS_PATH/AGENTS.md"
                log_success "Unlinked AGENTS.md from OSADO root."
            fi
        fi
    fi

    log_success "Uninstallation complete!"
    exit 0
fi

log_info "Deploying overlay files..."
link_files "$REPO_ROOT" "commands"
link_files "$REPO_ROOT" "skills"

if [ -f "$REPO_ROOT/OSADO_AGENTS.md" ]; then
    if [ ! -e "$OSADO_ABS_PATH/GEMINI.md" ]; then
        ln -s "$REPO_ROOT/OSADO_AGENTS.md" "$OSADO_ABS_PATH/GEMINI.md"
        log_success "Linked OSADO_AGENTS.md to OSADO root as GEMINI.md."
    else
         log_info "GEMINI.md already exists in OSADO root. Skipping."
    fi
fi

# Portable: also link into .agents/skills/ and AGENTS.md for cross-tool compatibility
if [ "$PORTABLE" = true ]; then
    log_info "Deploying portable cross-tool files..."

    # Link skills into .agents/skills/ (for OpenCode, Pi Agent)
    TARGET_AGENTS_DIR="$OSADO_ABS_PATH/.agents"
    mkdir -p "$TARGET_AGENTS_DIR/skills"
    local_target_backup="$TARGET_GEMINI_DIR"
    TARGET_GEMINI_DIR="$TARGET_AGENTS_DIR"
    link_files "$REPO_ROOT" "skills"
    TARGET_GEMINI_DIR="$local_target_backup"

    # Link AGENTS.md to OSADO root (for OpenCode, Pi Agent, Copilot)
    if [ -f "$REPO_ROOT/OSADO_AGENTS.md" ]; then
        if [ ! -e "$OSADO_ABS_PATH/AGENTS.md" ]; then
            ln -s "$REPO_ROOT/OSADO_AGENTS.md" "$OSADO_ABS_PATH/AGENTS.md"
            log_success "Linked AGENTS.md to OSADO root (cross-tool compatibility)."
        else
            log_info "AGENTS.md already exists in OSADO root. Skipping."
        fi
    fi
fi

log_success "Installation/Update complete!"
log_info "You can now run 'gemini' from '$OSADO_ABS_PATH'."
