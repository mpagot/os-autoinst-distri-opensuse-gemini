#!/bin/bash

#
# Script: search_comments.sh
# Description:
#   Search through GitHub comments JSON file.
#   Supports interactive mode (fzf) and headless mode (regex query).
#
# Usage:
#   ./search_comments.sh [--file FILE] [--query REGEX]
#

FILE=""
QUERY=""

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --file|-f) FILE="$2"; shift ;;
        --query|-q) QUERY="$2"; shift ;;
        -h|--help) 
            echo "Usage: $0 [--file FILE] [--query REGEX]"
            echo "If --query is provided, the script runs in headless mode."
            exit 0
            ;;
        *) 
            if [[ -z "$FILE" ]]; then
                FILE="$1"
            fi
            ;;
    esac
    shift
done

# Default file if not provided
if [[ -z "$FILE" ]]; then
    if [[ -f "all_comments.json" ]]; then
        FILE="all_comments.json"
    else
        echo "Error: No input file provided and all_comments.json not found."
        exit 1
    fi
fi

if [[ ! -f "$FILE" ]]; then
    echo "Error: File '$FILE' not found."
    exit 1
fi

# Dependencies check
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is required."
    exit 1
fi

# Headless mode
if [[ -n "$QUERY" ]]; then
    echo "Searching for '$QUERY' in $FILE..."
    jq -r ".[] | select(.body | test(\"$QUERY\"; \"i\")) | .url" "$FILE" | sort -u
    exit 0
fi

# Interactive mode
if ! command -v fzf &> /dev/null; then
    echo "Error: 'fzf' is required for interactive mode. Use --query for headless mode."
    exit 1
fi

# Export variables and functions for use inside fzf preview subshell
export INPUT_FILE="$FILE"

preview_comment() {
    local index
    index=$(echo "$1" | cut -d' ' -f1)
    jq -r ".[$index]" "$INPUT_FILE" | jq -r '
        "PR:        #\(.pr)",
        "Date:      \(.created_at)",
        "Type:      \(.type)",
        "File:      \(.path // "N/A")",
        "Line:      \(.line // "N/A")",
        "URL:       \(.url)",
        "------------------------------------------------------------",
        .body
    '
}
export -f preview_comment

echo "Loading comments from $FILE..."

# Format: INDEX | DATE | PR | TYPE | FILE | BODY SNIPPET
entries=$(jq -r 'to_entries[] | "\(.key) | \(.value.created_at[:10]) | PR #\(.value.pr) | \(.value.type) | \(.value.path // "General") | \(.value.body | gsub("\n"; " "))"' "$INPUT_FILE")

selected=$(echo "$entries" | fzf \
    --multi \
    --header "Tab to multi-select, Enter to finish. Searching Body and Path." \
    --delimiter " \| " \
    --preview "preview_comment {}" \
    --preview-window "up:60%:wrap")

if [[ -n "$selected" ]]; then
    echo "------------------------------------------------------------"
    echo "Selected Comment URLs:"
    echo "------------------------------------------------------------"
    while read -r line; do
        idx=$(echo "$line" | cut -d' ' -f1)
        jq -r ".[$idx] | .url" "$INPUT_FILE"
    done <<< "$selected" | sort -u
fi