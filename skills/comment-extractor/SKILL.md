---
name: comment-extractor
description: >
  Extracts and searches GitHub PR comments authored by specific users in
  os-autoinst/os-autoinst-distri-opensuse. Activate when the user asks to
  "fetch comments", "extract review feedback", "search PR comments", or
  "what did <user> say on PRs". Produces a JSON dump and supports headless
  regex search or interactive fzf browsing.
---

# Comment Extractor

This skill collects substantive PR feedback (issue comments + inline review
comments, excluding pure approvals) from the OSADO repo and lets you search
through it.

## Tools

Two scripts in `scripts/`:

* `extract_comments.sh` — pulls comments from GitHub via `gh` + `jq` and
  writes them to a JSON file.
* `search_comments.sh` — searches that JSON file. Headless mode with
  `--query REGEX`, or interactive fzf mode with preview pane.

## Workflow

### 1. Extract

```bash
.gemini/skills/comment-extractor/scripts/extract_comments.sh \
    --user user1,user2 [--limit 1000] [--output FILE.json]
```

Defaults:
* `--limit` = 1000 PRs scanned
* `--output` = `<users_underscored>_comments.json` in the current directory

Requires `gh` (authenticated against github.com) and `jq`.

### 2. Search

Headless (returns matching comment URLs, deduplicated):
```bash
.gemini/skills/comment-extractor/scripts/search_comments.sh \
    --file FILE.json --query 'regex'
```

Interactive (fzf with preview, multi-select with Tab):
```bash
.gemini/skills/comment-extractor/scripts/search_comments.sh --file FILE.json
```

If `--file` is omitted, the script falls back to `all_comments.json` in the
current directory.

## Rules

* Always confirm the target users before running `extract_comments.sh` — a
  large `--limit` against many users is slow and rate-limit sensitive.
* The repo is hard-coded to `os-autoinst/os-autoinst-distri-opensuse`.
* Do not commit the generated `*_comments.json` files; they are working
  artefacts.
