#!/bin/bash
# Detect the maintainer for an OSADO test module.
# Fallback chain: existing file content -> lookup table -> --fallback arg -> error
#
# Usage: maintainer-detect.sh <file_path> [--fallback 'Team <email>']
# Output: prints "Team Name <email>" to stdout
# Exit codes: 0=found, 1=not found, 2=usage error

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAP_FILE="$SCRIPT_DIR/maintainers.map"

usage() {
    echo "Usage: maintainer-detect.sh <file_path> [--fallback 'Team <email>']"
    echo ""
    echo "Detect the maintainer for an OSADO test module."
    echo "Fallback chain: existing file -> lookup table -> --fallback arg -> error"
    exit 2
}

[[ -z "$1" ]] && usage

FILE_PATH="$1"
shift

FALLBACK=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fallback)
            [[ -z "$2" ]] && usage
            FALLBACK="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

# 1. Check existing file content for # Maintainer: line
if [[ -f "$FILE_PATH" ]]; then
    existing=$(grep -m1 '^# Maintainer:' "$FILE_PATH" 2>/dev/null | sed 's/^# Maintainer: *//' || true)
    if [[ -n "$existing" ]]; then
        # Validate format: "Name <email@domain>" before returning untrusted content
        local_re='^.+ <[^@]+@[^>]+>$'
        if [[ "$existing" =~ $local_re ]]; then
            echo "$existing"
            exit 0
        fi
        echo "WARNING: Found maintainer '$existing' but format is invalid, skipping" >&2
    fi
fi

# 2. Lookup table (longest prefix match)
if [[ -f "$MAP_FILE" ]]; then
    best_match=""
    best_len=0
    while IFS=: read -r prefix maintainer; do
        # Skip comments and empty lines
        [[ -z "$prefix" || "$prefix" == \#* ]] && continue
        if [[ "$FILE_PATH" == "$prefix"* ]]; then
            local_len=${#prefix}
            if (( local_len > best_len )); then
                best_len=$local_len
                best_match="$maintainer"
            fi
        fi
    done < "$MAP_FILE"
    if [[ -n "$best_match" ]]; then
        echo "$best_match"
        exit 0
    fi
fi

# 3. Fallback argument
if [[ -n "$FALLBACK" ]]; then
    echo "$FALLBACK"
    exit 0
fi

# 4. Error
echo "ERROR: Could not determine maintainer for '$FILE_PATH'" >&2
echo "Options:" >&2
echo "  - Add '# Maintainer: Team <email>' to the file" >&2
echo "  - Add a mapping to $MAP_FILE" >&2
echo "  - Pass --fallback 'Team <email>'" >&2
exit 1
