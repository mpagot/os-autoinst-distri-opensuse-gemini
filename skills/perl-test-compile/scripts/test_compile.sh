#!/bin/bash

# Set up PERL5LIB as used in the project
# Including project root, lib directory, and os-autoinst requirements
export PERL5LIB=".:lib:os-autoinst:os-autoinst/lib:$PERL5LIB"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check a single file
check_file() {
    local file=$1
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error: File '$file' not found.${NC}"
        return 1
    fi

    # Only check .pm and .pl files
    if [[ "$file" =~ \.(pm|pl)$ ]]; then
        echo -e "--------------------------------------------------------------------------------"
        echo -e "${YELLOW}Checking:${NC} $file"
        
        # Run perl -c and capture both stdout and stderr
        output=$(perl -c "$file" 2>&1)
        local status=$?
        
        if [ $status -eq 0 ]; then
            echo -e "$output"
            echo -e "${GREEN}Result: SUCCESS${NC}"
        else
            echo -e "${RED}$output${NC}"
            echo -e "${RED}Result: FAILED (Exit Code: $status)${NC}"
            return 1
        fi
    fi
    return 0
}

# Main logic
FILES_TO_CHECK=()

if [ $# -eq 0 ]; then
    echo "Usage: $0 [file1] [file2] [directory1] ..."
    echo "Example: $0 lib/publiccloud/basetest.pm"
    echo "Example: $0 lib/sles4sap/"
    exit 1
fi

for arg in "$@"; do
    if [ -f "$arg" ]; then
        FILES_TO_CHECK+=("$arg")
    elif [ -d "$arg" ]; then
        # Find all .pm and .pl files in the directory, excluding hidden folders
        while IFS= read -r -d '' file; do
            FILES_TO_CHECK+=("$file")
        done < <(find "$arg" -type f \( -name "*.pm" -o -name "*.pl" \) -not -path '*/.*' -print0 | sort -z)
    else
        echo -e "${YELLOW}Warning: '$arg' is not a valid file or directory. Skipping.${NC}"
    fi
done

if [ ${#FILES_TO_CHECK[@]} -eq 0 ]; then
    echo -e "${RED}No Perl files found to check.${NC}"
    exit 1
fi

# Run checks
FAILED_COUNT=0
TOTAL_COUNT=${#FILES_TO_CHECK[@]}

echo -e "Starting compilation check for $TOTAL_COUNT files..."

for file in "${FILES_TO_CHECK[@]}"; do
    check_file "$file" || ((FAILED_COUNT++))
done

echo -e "--------------------------------------------------------------------------------"
echo -e "Summary:"
echo -e "  Total files checked: $TOTAL_COUNT"
echo -e "  Passed: $((TOTAL_COUNT - FAILED_COUNT))"
echo -e "  Failed: ${RED}$FAILED_COUNT${NC}"

if [ $FAILED_COUNT -gt 0 ]; then
    exit 1
else
    exit 0
fi
