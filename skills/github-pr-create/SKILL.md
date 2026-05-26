---
name: github-pr-create
description: >
  Creates a GitHub pull request from staged git changes, handling commit,
  push, and PR creation in one workflow. Activate when the user asks to
  "create PR", "open pull request", "push and create PR", "submit PR",
  or wants to send their changes upstream to os-autoinst-distri-opensuse.
---

<instructions>

You help an OSADO developer create a GitHub pull request from staged git
changes. This is an end-to-end workflow: commit, push, and PR creation.

## Workflow

### 1. Prepare and execute the commit
Delegate to the `git-commit` skill to:
- Inspect the staged changes
- Propose a commit message complying with OSADO CONTRIBUTING.md rules
- Write it to `commit_message.txt` for the user to review
- Wait for the user's approval

Once approved, run:
```bash
git commit -F commit_message.txt
```

### 2. Push the changes
- Get the current branch name with `git rev-parse --abbrev-ref HEAD`.
- Push the changes to the remote repository:
  ```bash
  git push --set-upstream origin <branch>
  ```

### 3. Create the pull request
- Read the pull request template from `.github/PULL_REQUEST_TEMPLATE.md`
  (if it exists in the target repo).
- Get the title from the first line of the commit message.
- Use the rest of the commit message as the description of the pull request.
- Combine the description with the content of the pull request template.
- Remove the line about needles if the user does not explicitly request it.
- Ask the user for a ticket reference and put it in the description.
- Write the PR description to a temporary file (e.g., `pr_body.txt`).
- Create the pull request using the GitHub CLI:
  ```bash
  gh pr create \
    --title "<title>" \
    --body-file pr_body.txt \
    --repo https://github.com/os-autoinst/os-autoinst-distri-opensuse
  ```

## Important Notes

- Always use the `--repo https://github.com/os-autoinst/os-autoinst-distri-opensuse`
  option to ensure the PR targets the upstream repository, not a fork.
- If GitHub MCP tools are available, prefer using them over the `gh` CLI.
- The workflow is interactive: wait for user approval at each critical step
  (commit message, PR description) before proceeding.

</instructions>
