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
#   - Recursive Symlinking: The script iterates through the 'osado_overlay' 
#     directory. For every file found, it creates a corresponding symlink in 
#     the target OSADO repo.
#   - Directory Mirroring: It uses 'mkdir -p' to recreate the directory tree. 
#     It does NOT symlink directories themselves to avoid overwriting your 
#     existing folders (like .gemini/skills).
#   - Files are processed individually. A conflict in one file does not stop
#     the rest of the installation.
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
OVERLAY_DIR="$REPO_ROOT/osado_overlay"

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
    echo "  --help         Show this help message"
    exit 1
}

log_info() { echo -e "${BLUE}INFO:${NC} $1"; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $1"; }
log_warn() { echo -e "${YELLOW}WARNING:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }

UPDATE=false
UNINSTALL=false
OSADO_PATH=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --update) UPDATE=true ;;
        --uninstall) UNINSTALL=true ;;
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

# Create target directories
TARGET_GEMINI_DIR="$OSADO_ABS_PATH/.gemini"
mkdir -p "$TARGET_GEMINI_DIR/commands"
mkdir -p "$TARGET_GEMINI_DIR/skills"

# Function to symlink files recursively
link_files() {
    local src_dir="$1"
    local rel_path="$2" # e.g. "commands" or "skills/openqa-log-analyzer"
    
    local source_full="$src_dir/.gemini/$rel_path"
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
    
    local source_full="$src_dir/.gemini/$rel_path"
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
    unlink_files "$OVERLAY_DIR" "commands"
    unlink_files "$OVERLAY_DIR" "skills"

    # Remove root GEMINI.md if it's our link
    if [ -L "$OSADO_ABS_PATH/GEMINI.md" ]; then
        if [ "$(readlink "$OSADO_ABS_PATH/GEMINI.md")" == "$OVERLAY_DIR/GEMINI.md" ]; then
            unlink "$OSADO_ABS_PATH/GEMINI.md"
            log_success "Unlinked GEMINI.md from OSADO root."
        fi
    fi

    log_success "Uninstallation complete!"
    exit 0
fi

log_info "Deploying overlay files..."
link_files "$OVERLAY_DIR" "commands"
link_files "$OVERLAY_DIR" "skills"

# Special case: osado_overlay/GEMINI.md should also be linked to OSADO root if desired,
# but the user requested files in .gemini folder. 
# Let's also link GEMINI.md to the root if it doesn't exist.
if [ -f "$OVERLAY_DIR/GEMINI.md" ]; then
    if [ ! -e "$OSADO_ABS_PATH/GEMINI.md" ]; then
        ln -s "$OVERLAY_DIR/GEMINI.md" "$OSADO_ABS_PATH/GEMINI.md"
        log_success "Linked GEMINI.md to OSADO root."
    else
         log_info "GEMINI.md already exists in OSADO root. Skipping."
    fi
fi

log_success "Installation/Update complete!"
log_info "You can now run 'gemini-cli' from '$OSADO_ABS_PATH'."
