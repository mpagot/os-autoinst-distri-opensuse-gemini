---
name: openqa-log-analyzer
description: A specialized skill for analyzing openQA logs, listing test modules, and extracting specific module logs for debugging failures.
---

# openQA Log Analyzer Skill

This skill provides specialized capabilities for analyzing openQA log files (typically `autoinst-log.txt`). It leverages the project's `DEBUG_CRASH/extract_log_section.sh` script to parse the massive log files into manageable chunks.

## Capabilities

1.  **List Modules**: Identify which test modules ran in a specific log file.
2.  **Extract Module Logs**: Extract the full log output for a specific test module to a separate file for focused analysis.

## Tools & Scripts

The primary tool is the shell script located at:
`scripts/extract_log_section.sh`

### Usage

**1. List available modules in a log file:**

```bash
.gemini/skills/openqa-log-analyzer/scripts/extract_log_section.sh <path_to_log_file_or_dir>
```
*Example:* `.gemini/skills/openqa-log-analyzer/scripts/extract_log_section.sh DEBUG_CRASH/FAIL/`

**2. Extract a specific module's log:**

```bash
.gemini/skills/openqa-log-analyzer/scripts/extract_log_section.sh <path_to_log_file_or_dir> <module_name>
```
*Example:* `.gemini/skills/openqa-log-analyzer/scripts/extract_log_section.sh DEBUG_CRASH/FAIL/ Crash_site_a-primary`
*Output:* Creates a file named `<module_name>.log` (e.g., `Crash_site_a-primary.log`) in the current directory.

## Workflow for Analysis

When asked to analyze a failure or a log file:

1.  **Locate the log file**: Confirm the path to the `autoinst-log.txt` or similar log file.
2.  **List Modules**: Run the script without a module name to see the sequence of tests and identify the failing module (or the one of interest).
3.  **Extract Log**: Run the script with the specific module name to generate a focused log file.
4.  **Analyze**: Read the content of the extracted `<module_name>.log` to find errors, failures, or timeout messages.
