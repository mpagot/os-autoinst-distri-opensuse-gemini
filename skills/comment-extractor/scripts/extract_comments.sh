#!/bin/bash

#
# Script: extract_comments.sh
# Description:
#   Extracts all GitHub PR comments (issue comments and review comments) 
#   authored by specified users in the os-autoinst/os-autoinst-distri-opensuse repository.
#   It excludes approvals and focus on substantive feedback.
#
# Usage:
#   ./extract_comments.sh --user USER1,USER2 [--limit NUM] [--output FILE]
#

REPO="os-autoinst/os-autoinst-distri-opensuse"
USERS=""
OUTPUT_FILE=""
LIMIT=1000

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --user|-u) USERS="$2"; shift ;;
        --limit|-l) LIMIT="$2"; shift ;;
        --output|-o) OUTPUT_FILE="$2"; shift ;;
        -h|--help) 
            echo "Usage: $0 --user USER1,USER2 [--limit NUM] [--output FILE]"
            echo "  --user: Comma-separated list of GitHub usernames."
            exit 0
            ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
    shift
done

if [[ -z "$USERS" ]]; then
    echo "Error: --user is required."
    exit 1
fi

# Prepare search query part for multiple users: commenter:user1 commenter:user2 ...
# Note: GitHub "commenter" search is OR-based when multiple are provided.
IFS=',' read -r -a USER_ARRAY <<< "$USERS"
SEARCH_QUERY=""
for u in "${USER_ARRAY[@]}"; do
    SEARCH_QUERY+="commenter:$u "
done

# Prepare JQ filter array for matching authors
JQ_USERS=$(echo "$USERS" | jq -R 'split(",")')

# Compose output filename if not provided
if [[ -z "$OUTPUT_FILE" ]]; then
    SAFE_USERS=$(echo "$USERS" | tr ',' '_')
    OUTPUT_FILE="${SAFE_USERS}_comments.json"
fi

# Dependencies check
if ! command -v gh &> /dev/null || ! command -v jq &> /dev/null; then
    echo "Error: 'gh' and 'jq' are required."
    exit 1
fi

echo "Searching for PRs in $REPO where [$USERS] have commented..."
PR_NUMBERS=$(gh pr list -R "$REPO" --search "$SEARCH_QUERY" --state all --limit "$LIMIT" --json number -q '.[].number')

if [[ -z "$PR_NUMBERS" ]]; then
    echo "No PRs found for users: $USERS"
    exit 0
fi

NUM_PRS=$(echo "$PR_NUMBERS" | wc -l)
echo "Found $NUM_PRS PRs. Fetching comments..."

# Temporary directory for results
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

COUNT=0
for PR_NUM in $PR_NUMBERS; do
    ((COUNT++))
    echo -ne "Processing PR #$PR_NUM ($COUNT/$NUM_PRS)...\r"

    # Fetch Issue Comments (General PR comments)
    gh api "/repos/$REPO/issues/$PR_NUM/comments" --paginate \
        | jq --argjson users "$JQ_USERS" --arg pr_num "$PR_NUM" '
            map(select(.user.login as $u | $users | contains([$u])) | {
                pr: $pr_num,
                type: "issue_comment",
                author: .user.login,
                body: .body,
                url: .html_url,
                created_at: .created_at
            })' > "$TEMP_DIR/issue_${PR_NUM}.json"

    # Fetch Review Comments (Inline code comments)
    gh api "/repos/$REPO/pulls/$PR_NUM/comments" --paginate \
        | jq --argjson users "$JQ_USERS" --arg pr_num "$PR_NUM" '
            map(select(.user.login as $u | $users | contains([$u])) | {
                pr: $pr_num,
                type: "review_comment",
                author: .user.login,
                body: .body,
                url: .html_url,
                created_at: .created_at,
                path: .path,
                line: (.line // .original_line),
                diff_hunk: .diff_hunk
            })' > "$TEMP_DIR/review_${PR_NUM}.json"
done

echo -e "\nProcessing complete. Aggregating results..."

# Combine all results into a single JSON array, sorted by date
# Using -s to handle potential empty files if a PR had comments from users not in our filter
jq -s 'flatten | sort_by(.created_at)' "$TEMP_DIR"/*.json > "$OUTPUT_FILE"

FINAL_COUNT=$(jq 'length' "$OUTPUT_FILE")
echo "Extracted $FINAL_COUNT comments to $OUTPUT_FILE"
