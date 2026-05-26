---
name: git-commit
description: >
  Helps write OSADO-compliant git commit messages for staged changes.
  Activate when the user asks to "commit", "write commit message",
  "prepare commit", "stage and commit", or needs help creating a
  commit message following OSADO CONTRIBUTING.md rules.
---

<instructions>

You help an OSADO developer create a professional git commit message for
staged files, following the project's strict formatting rules.

## Workflow

1. **Inspect the changes**
   - Run `git diff --staged` to understand what has been changed.
   - You may explore other project files if needed to gain more context.

2. **Propose a commit message**
   Based on your analysis, propose a concise and informative commit message
   that strictly follows the **OSADO CONTRIBUTING.md** rules:

   ### Subject line rules
   - **Must start with a capital letter or a tag** (e.g., `Fix deep issue...`
     or `bugfix: Fix...`).
   - **Must NOT exceed 72 characters**.
   - **Must NOT end with a dot**.
   - **Must NOT** use conventional commit tags like `(feat)` or `feat(scope):`.

   ### Body rules
   - There **must be an empty newline** between the subject and the body.
   - The body should explain **"what"** and **"why"** of the changes.
   - Include details like: what issue is fixed, why this needs to change,
     to which versions/products it applies, and any choices you made.
   - Mention bug/ticket references if applicable (e.g., `bsc#12345`, `poo#12345`).

3. **Get user approval**
   - Write the proposed commit message to a temporary file named `commit_message.txt`.
   - Inform the user that the file is ready for review and editing.
   - Remind the user to run `make tidy` before committing if they haven't already.

4. **Provide the commit command**
   After the user reviews the file, suggest the command to perform the actual commit:
   ```bash
   git commit -F commit_message.txt
   ```

## Example Commit Message

```
Add retry logic to azure_cli resource group creation

The Azure CLI sometimes returns transient errors when creating resource
groups in regions with high load. This change adds exponential backoff
retry logic (max 3 attempts) to handle these cases gracefully.

Fixes: poo#123456
```

</instructions>
