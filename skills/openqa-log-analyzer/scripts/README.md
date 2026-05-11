# openqa-log-analyzer Scripts

Six Perl scripts for analysing openQA log files. Each script targets a
specific analysis need and operates exclusively on **local files** -- none
of them fetch or download anything from an openQA instance.

All scripts share a common set of flags:

| Flag | Effect |
|------|--------|
| `--json` | Machine-readable JSON output |
| `--color` | ANSI-coloured terminal output |
| `--verbose` | Extra progress / debug messages |
| `--help` / `-h` | Built-in usage information |

## Scripts

### analyze_log_health.pl

Quick triage of an `autoinst-log.txt`. Scans for test failures, timeouts,
hook errors (`!!!`), explicit fail results (`>>>`), backend stress (high
loop counts), ring-buffer overflows, and `PIPE_SZ` changes. Perl
backtraces are extracted and attached to the issue that triggered them.

**Input:** one or more `autoinst-log.txt` files.

| Option | Default | Effect |
|--------|---------|--------|
| `--loop-threshold N` | 100 000 | Loop count above which a "heavy load" warning is raised |

```
analyze_log_health.pl autoinst-log.txt
analyze_log_health.pl --json --loop-threshold 50000 log1.txt log2.txt
```

---

### detect_lag.pl

Correlates backend loop counts with command timeouts to determine whether
a failure was caused by SUT slowness or worker-host stress. Tracks the
maximum loop count and duration seen before each `Test died: command ...
timed out` event and reports them together.

High loop counts (>100K) suggest the os-autoinst backend was under CPU or
I/O pressure -- the test logic itself may be fine.

**Input:** one or more `autoinst-log.txt` files.

```
detect_lag.pl autoinst-log.txt
detect_lag.pl --json log1.txt log2.txt
```

**Output columns:** Log File, Max Loops, Max Duration, Longest CMD,
Failed CMD.

---

### extract_log_section.pl

Lists all test modules in a log, or extracts a single module's log slice
to a separate file. Accepts a file path or a directory (appends
`autoinst-log.txt` automatically).

**Input:** `autoinst-log.txt` (or directory containing it).

```
extract_log_section.pl /path/to/logs/                # list modules
extract_log_section.pl autoinst-log.txt my_module     # extract → my_module.log
extract_log_section.pl --json /path/to/logs/          # list as JSON
```

When extracting, the script tries the `||| starting` marker first, then
falls back to the `scheduling` pattern. Extraction stops at `||| finished`
or `Test died: script timeout`.

---

### measure_cmd_time.pl

Per-command execution timing with flexible duration filters. Parses
testapi calls (`script_run`, `assert_script_run`, `ssh_script_output`,
etc.) and correlates them with their serial-output completion markers to
compute wall-clock duration, return code, calling source file and line,
and the 5-character tag that links start and finish.

**Input:** `autoinst-log.txt`, optional search term.

| Option | Effect |
|--------|--------|
| `--duration EXPR` | Boolean filter on duration. Operators: `> >= < <= == !=`. Connectives: `&&` (AND), `\|\|` (OR). Examples: `">5"`, `">=2 && <=10"` |

```
measure_cmd_time.pl autoinst-log.txt
measure_cmd_time.pl --duration ">5" autoinst-log.txt
measure_cmd_time.pl --duration ">1 && <=30" autoinst-log.txt zypper
measure_cmd_time.pl --json autoinst-log.txt
```

**Output columns:** Duration, Timestamp, Test API, Caller (File:Line),
Log Line, RC, Tag, Command.

---

### extract_cmd_output.pl

Extracts the stdout/stderr of commands matching a regex from
`serial_terminal.txt`. Matches lines of the form `# cmd; echo TAG-$?-`
and captures everything until the end tag `TAG-exitcode-`.

**Input:** `serial_terminal.txt` and a regex pattern.

> **Note:** This is the only script that operates on `serial_terminal.txt`
> rather than `autoinst-log.txt`.

```
extract_cmd_output.pl serial_terminal.txt "zypper"
extract_cmd_output.pl serial_terminal.txt "az vm create"
extract_cmd_output.pl --json serial_terminal.txt "crm configure"
```

---

### compare_modules_time.pl

Side-by-side comparison of per-module timing across two or more log files.
Computes three metrics for every module:

| Metric | Definition |
|--------|------------|
| **Wall** | Timestamp delta between consecutive `\|\|\| starting` markers |
| **Cmd** | Sum of `Matched output from SUT` durations within the module |
| **Overhead** | Wall - Cmd (framework time: needle matching, screen polling, etc.) |

**Input:** two or more `autoinst-log.txt` files.

```
compare_modules_time.pl pass_log.txt fail_log.txt
compare_modules_time.pl --json log1.txt log2.txt log3.txt
compare_modules_time.pl --color old_run.txt new_run.txt
```
