#!/bin/bash
# Script to audit SLES4SAP test modules for adherence to the Perldoc header template.
# Defined in SLES4SAP_CATALOG_HEADER.md

DIRECTORY="tests/sles4sap"
IGNORE_PATTERN="ipaddr2"

if [ -n "$1" ]; then
  FILES_TO_AUDIT="$1"
  # echo "Auditing specific file: $FILES_TO_AUDIT"
else
  FILES_TO_AUDIT=$(find "$DIRECTORY" -name "*.pm" | grep -v "$IGNORE_PATTERN" | sort)
  # echo "Auditing $DIRECTORY (excluding $IGNORE_PATTERN)..."
fi
# echo "------------------------------------------------"

for file in $FILES_TO_AUDIT; do
  [ ! -f "$file" ] && echo "File not found: $file" && continue
  
  # Use awk to check content and order in a single pass
  result=$(awk '
  BEGIN {
    # Define states/milestones
    has_copyright = 0
    has_spdx = 0
    has_summary = 0
    has_maintainer = 0
    correct_maintainer = 0
    has_head_maintainer = 0
    correct_head_maintainer = 0
    has_head_name = 0
    has_head_desc = 0
    
    # Track order violations
    order_error = ""
    last_found = 0 # 1=Copyright, 2=SPDX, 3=Summary, 4=Maintainer, 5=NAME, 6=DESCRIPTION, 7=MAINTAINER_POD
  }

  # 1. Copyright
  /Copyright.*SUSE LLC/ {
    if (has_copyright == 0) {
      has_copyright = 1
      if (last_found > 1) order_error = order_error "Copyright found after " last_found "; "
      last_found = 1
    }
  }

  # 2. SPDX
  /SPDX-License-Identifier/ {
    if (has_spdx == 0) {
      has_spdx = 1
      if (last_found > 2) order_error = order_error "SPDX found after " last_found "; "
      last_found = 2
    }
  }

  # 3. Summary
  /# Summary:/ {
    if (has_summary == 0) {
      has_summary = 1
      if (last_found > 3) order_error = order_error "Summary found after " last_found "; "
      last_found = 3
    }
  }

  # 4. Maintainer (Comment)
  /# Maintainer:/ {
    if (has_maintainer == 0) {
      has_maintainer = 1
      # Check exact value
      if ($0 ~ /# Maintainer: QE-SAP <qe-sap@suse.de>/) {
        correct_maintainer = 1
      }
      if (last_found > 4) order_error = order_error "Maintainer (Comment) found after " last_found "; "
      last_found = 4
    }
  }

  # 5. =head1 NAME
  /^=head1 NAME/ {
    if (has_head_name == 0) {
      has_head_name = 1
      if (last_found > 5) order_error = order_error "NAME found after " last_found "; "
      last_found = 5
    }
  }

  # 6. =head1 DESCRIPTION
  /^=head1 DESCRIPTION/ {
    if (has_head_desc == 0) {
      has_head_desc = 1
      if (last_found > 6) order_error = order_error "DESCRIPTION found after " last_found "; "
      last_found = 6
    }
  }

  # 7. =head1 MAINTAINER (POD)
  /^=head1 MAINTAINER/ {
    if (has_head_maintainer == 0) {
      has_head_maintainer = 1
      # Check next line for correct maintainer, allowing for one empty line
      getline;
      if ($0 ~ /^[[:space:]]*$/) getline;
      if ($0 ~ /QE-SAP <qe-sap@suse.de>/) {
        correct_head_maintainer = 1
      }
      if (last_found > 7) order_error = order_error "MAINTAINER (POD) found after " last_found "; "
      last_found = 7
    }
  }

  END {
    # Output results in a format the shell script can parse
    print "COPYRIGHT=" has_copyright
    print "SPDX=" has_spdx
    print "SUMMARY=" has_summary
    print "MAINTAINER=" has_maintainer
    print "CORRECT_MAINTAINER=" correct_maintainer
    print "HEAD_MAINTAINER=" has_head_maintainer
    print "CORRECT_HEAD_MAINTAINER=" correct_head_maintainer
    print "HEAD_NAME=" has_head_name
    print "HEAD_DESC=" has_head_desc
    print "ORDER_ERROR=\"" order_error "\""
  }
  ' "$file")

  # Parse awk results
  eval "$result"

  # Aggregate status
  missing_fields=""
  [[ $COPYRIGHT -eq 0 ]] && missing_fields="$missing_fields Copyright,"
  [[ $SPDX -eq 0 ]] && missing_fields="$missing_fields SPDX,"
  [[ $SUMMARY -eq 0 ]] && missing_fields="$missing_fields Summary,"
  [[ $MAINTAINER -eq 0 ]] && missing_fields="$missing_fields Maintainer(Comment),"
  [[ $HEAD_NAME -eq 0 ]] && missing_fields="$missing_fields =head1 NAME,"
  [[ $HEAD_DESC -eq 0 ]] && missing_fields="$missing_fields =head1 DESCRIPTION,"
  [[ $HEAD_MAINTAINER -eq 0 ]] && missing_fields="$missing_fields =head1 MAINTAINER,"

  maintainer_msg=""
  if [[ $MAINTAINER -eq 1 && $CORRECT_MAINTAINER -eq 0 ]]; then
    maintainer_msg=" [WRONG MAINTAINER COMMENT VALUE]"
  fi
  if [[ $HEAD_MAINTAINER -eq 1 && $CORRECT_HEAD_MAINTAINER -eq 0 ]]; then
    maintainer_msg="$maintainer_msg [WRONG MAINTAINER POD VALUE]"
  fi

  if [[ -n "$missing_fields" ]] || [[ -n "$ORDER_ERROR" ]] || [[ -n "$maintainer_msg" ]]; then
    echo "File: $file"
    [[ -n "$missing_fields" ]] && echo "  - Missing: ${missing_fields%,}"
    [[ -n "$ORDER_ERROR" ]] && echo "  - Order Issues: $ORDER_ERROR"
    [[ -n "$maintainer_msg" ]] && echo "  - Maintainer: $maintainer_msg"
    # echo ""
    exit 1
  fi

done
exit 0
