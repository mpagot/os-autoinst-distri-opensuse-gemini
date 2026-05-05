#!/bin/bash
# Script to extract module logs based on DEBUG_CRASH/issue_explanation.md
# It implements both Variant 1 (Standard Module Start) and Variant 2 (Scheduled Module Start)

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <log_file_or_dir> [module_name]"
    echo "Example (Extract): $0 DEBUG_CRASH/FAIL/20564435_autoinst-log.txt Crash_site_a-primary"
    echo "Example (List):    $0 DEBUG_CRASH/FAIL/"
    exit 1
fi

LOG_INPUT="$1"
MODULE_NAME="$2"

# Check if input is a directory and append default filename if so
if [ -d "$LOG_INPUT" ]; then
    LOG_FILE="${LOG_INPUT%/}/autoinst-log.txt"
else
    LOG_FILE="$LOG_INPUT"
fi

if [ ! -f "$LOG_FILE" ]; then
    echo "Error: Log file '$LOG_FILE' not found."
    exit 1
fi

if [ -z "$MODULE_NAME" ]; then
    echo "Module name not provided. Listing available modules in '$LOG_FILE':"
    echo "---------------------------------------------------------------------"
    # Extract module names from both "||| starting" and "scheduling" lines
    # Pattern 1: ||| starting <MODULE> <PATH>
    # Pattern 2: scheduling <MODULE> <PATH>
    awk '
    /\|\|\| starting / { print $6 }
    /scheduling / { print $5 }
    ' "$LOG_FILE" | sort | uniq
    exit 0
fi

OUTPUT_FILE="${MODULE_NAME}.log"

echo "Attempting to extract '$MODULE_NAME' using standard start pattern (||| starting)..."
# Variant 1: Standard Module Start
awk -v mod="$MODULE_NAME" '$0 ~ "\\|\\|\\| starting " mod " " {p=1} p {print} $0 ~ "\\|\\|\\| finished " mod " " {p=0; exit} /Test died: script timeout/ && p {p=0; exit}' "$LOG_FILE" > "$OUTPUT_FILE"

# Check if successful (file has content)
if [ ! -s "$OUTPUT_FILE" ]; then
    echo "Standard pattern not found. Attempting 'scheduling' pattern..."
    # Variant 2: Scheduled Module Start
    awk -v mod="$MODULE_NAME" '$0 ~ "scheduling " mod " " {p=1} p {print} $0 ~ "\\|\\|\\| finished " mod " " {p=0; exit} /Test died: script timeout/ && p {p=0; exit}' "$LOG_FILE" > "$OUTPUT_FILE"
fi

if [ -s "$OUTPUT_FILE" ]; then
    echo "Successfully extracted log to $OUTPUT_FILE"
    echo "Lines extracted: $(wc -l < "$OUTPUT_FILE")"
else
    echo "Failed to extract log for module '$MODULE_NAME'. Pattern not found."
    rm -f "$OUTPUT_FILE"
    exit 1
fi
