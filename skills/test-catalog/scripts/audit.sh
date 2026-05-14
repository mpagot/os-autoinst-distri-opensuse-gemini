#!/bin/bash
# Script to audit OSADO test modules for adherence to the Perldoc header template.
# Part of the test-catalog skill.

set -e

if [[ -z "$1" ]]; then
    echo "Usage: audit.sh <path_to_file_or_directory>"
    echo "  Audits Perl test modules for correct Perldoc header structure."
    echo "  A file path or a directory path is required."
    exit 2
fi

# Audit a single file. Prints diagnostics and returns 1 on failure, 0 on pass.
audit_file() {
    local file="$1"
    [[ ! -f "$file" ]] && echo "File not found: $file" && return 1

    # Use awk to check content and order in a single pass.
    # Output is one value per line in a fixed positional order (safe: no eval).
    readarray -t values < <(awk '
    BEGIN {
        has_copyright = 0
        has_spdx = 0
        has_summary = 0
        has_maintainer = 0
        valid_maintainer_format = 0
        maintainer_value = ""
        has_head_maintainer = 0
        valid_head_maintainer_format = 0
        head_maintainer_value = ""
        has_head_name = 0
        has_head_desc = 0
        order_error = ""
        last_found = 0
    }

    /Copyright.*SUSE LLC/ {
        if (has_copyright == 0) {
            has_copyright = 1
            if (last_found > 1) order_error = order_error "Copyright found after " last_found "; "
            last_found = 1
        }
    }

    /SPDX-License-Identifier/ {
        if (has_spdx == 0) {
            has_spdx = 1
            if (last_found > 2) order_error = order_error "SPDX found after " last_found "; "
            last_found = 2
        }
    }

    /# Summary:/ {
        if (has_summary == 0) {
            has_summary = 1
            if (last_found > 3) order_error = order_error "Summary found after " last_found "; "
            last_found = 3
        }
    }

    /^# Maintainer:/ {
        if (has_maintainer == 0) {
            has_maintainer = 1
            val = $0
            sub(/^# Maintainer: */, "", val)
            maintainer_value = val
            if (val ~ /.+ <.+@.+>/) {
                valid_maintainer_format = 1
            }
            if (last_found > 4) order_error = order_error "Maintainer (Comment) found after " last_found "; "
            last_found = 4
        }
    }

    /^=head1 NAME/ {
        if (has_head_name == 0) {
            has_head_name = 1
            if (last_found > 5) order_error = order_error "NAME found after " last_found "; "
            last_found = 5
        }
    }

    /^=head1 DESCRIPTION/ {
        if (has_head_desc == 0) {
            has_head_desc = 1
            if (last_found > 6) order_error = order_error "DESCRIPTION found after " last_found "; "
            last_found = 6
        }
    }

    /^=head1 MAINTAINER/ {
        if (has_head_maintainer == 0) {
            has_head_maintainer = 1
            getline;
            if ($0 ~ /^[[:space:]]*$/) getline;
            head_maintainer_value = $0
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", head_maintainer_value)
            if (head_maintainer_value ~ /.+ <.+@.+>/) {
                valid_head_maintainer_format = 1
            }
            if (last_found > 7) order_error = order_error "MAINTAINER (POD) found after " last_found "; "
            last_found = 7
        }
    }

    END {
        # Positional output: one value per line, fixed order.
        # Lines 1-11: numeric flags and strings (no quoting, no eval).
        print has_copyright
        print has_spdx
        print has_summary
        print has_maintainer
        print valid_maintainer_format
        print maintainer_value
        print has_head_maintainer
        print valid_head_maintainer_format
        print head_maintainer_value
        print has_head_name
        print has_head_desc
        print order_error
    }
    ' "$file")

    # Assign positional values to named variables
    local COPYRIGHT="${values[0]}"
    local SPDX="${values[1]}"
    local SUMMARY="${values[2]}"
    local MAINTAINER="${values[3]}"
    local VALID_MAINTAINER_FORMAT="${values[4]}"
    local MAINTAINER_VALUE="${values[5]}"
    local HEAD_MAINTAINER="${values[6]}"
    local VALID_HEAD_MAINTAINER_FORMAT="${values[7]}"
    local HEAD_MAINTAINER_VALUE="${values[8]}"
    local HEAD_NAME="${values[9]}"
    local HEAD_DESC="${values[10]}"
    local ORDER_ERROR="${values[11]}"

    # Aggregate status
    local missing_fields=""
    [[ "$COPYRIGHT" -eq 0 ]] && missing_fields="$missing_fields Copyright,"
    [[ "$SPDX" -eq 0 ]] && missing_fields="$missing_fields SPDX,"
    [[ "$SUMMARY" -eq 0 ]] && missing_fields="$missing_fields Summary,"
    [[ "$MAINTAINER" -eq 0 ]] && missing_fields="$missing_fields Maintainer(Comment),"
    [[ "$HEAD_NAME" -eq 0 ]] && missing_fields="$missing_fields =head1 NAME,"
    [[ "$HEAD_DESC" -eq 0 ]] && missing_fields="$missing_fields =head1 DESCRIPTION,"
    [[ "$HEAD_MAINTAINER" -eq 0 ]] && missing_fields="$missing_fields =head1 MAINTAINER,"

    local format_msg=""
    if [[ "$MAINTAINER" -eq 1 && "$VALID_MAINTAINER_FORMAT" -eq 0 ]]; then
        format_msg=" [INVALID MAINTAINER COMMENT FORMAT - expected: Team <email@domain>]"
    fi
    if [[ "$HEAD_MAINTAINER" -eq 1 && "$VALID_HEAD_MAINTAINER_FORMAT" -eq 0 ]]; then
        format_msg="$format_msg [INVALID MAINTAINER POD FORMAT - expected: Team <email@domain>]"
    fi

    # Consistency check: comment maintainer must match POD maintainer
    local consistency_msg=""
    if [[ "$MAINTAINER" -eq 1 && "$HEAD_MAINTAINER" -eq 1 ]]; then
        if [[ "$MAINTAINER_VALUE" != "$HEAD_MAINTAINER_VALUE" ]]; then
            consistency_msg=" [INCONSISTENT: comment='$MAINTAINER_VALUE' vs POD='$HEAD_MAINTAINER_VALUE']"
        fi
    fi

    if [[ -n "$missing_fields" ]] || [[ -n "$ORDER_ERROR" ]] || [[ -n "$format_msg" ]] || [[ -n "$consistency_msg" ]]; then
        echo "File: $file"
        [[ -n "$missing_fields" ]] && echo "  - Missing: ${missing_fields%,}"
        [[ -n "$ORDER_ERROR" ]] && echo "  - Order Issues: $ORDER_ERROR"
        [[ -n "$format_msg" ]] && echo "  - Format: $format_msg"
        [[ -n "$consistency_msg" ]] && echo "  - Consistency: $consistency_msg"
        return 1
    fi
    return 0
}

# Main: iterate files safely (no word splitting on paths)
if [[ -d "$1" ]]; then
    while IFS= read -r -d '' file; do
        audit_file "$file" || exit 1
    done < <(find "$1" -name "*.pm" -print0 | sort -z)
elif [[ -f "$1" ]]; then
    audit_file "$1" || exit 1
else
    echo "Error: '$1' is not a valid file or directory."
    exit 2
fi

exit 0
