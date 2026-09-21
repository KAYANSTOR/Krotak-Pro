# Krotak Pro — Branch Policy

## Allowed branches — ONLY

The repository has exactly three allowed working refs:

1. `main`
   - Stable production/integration branch.
   - Must remain buildable and testable.
   - Do not use it for exploratory or unfinished work.

2. `development/full-completion`
   - The ONLY branch for completing the remaining comprehensive product development.
   - All non-licensing feature work, fixes, UI completion, domain completion, integration work, and remaining roadmap work belong here.

3. `licensing`
   - The ONLY branch for creating, integrating, and validating the licensing system.
   - Licensing-related work must stay isolated here until explicitly approved for integration into `main`.

## Hard agent rules

- NEVER create another branch under any name.
- NEVER invent a temporary, phase, feature, fix, chore, hotfix, experiment, or worktree branch.
- If the task does not fit `development/full-completion` or `licensing`, STOP and report that the task needs explicit branch-policy authorization.
- NEVER change the branch structure or rename these branches without explicit owner instruction.
- NEVER move licensing implementation into `development/full-completion`.
- NEVER merge directly into `main` without verification and an explicit integration decision.
- Reuse the existing allowed branch instead of creating a new branch.
- Before making changes, verify the current branch is one of the allowed branches.
- Do not create scripts or automation whose purpose is to create additional Git branches.
- Treat this file as a repository-level instruction for every AI coding agent.

## Current policy

Allowed working branches:

- `main`
- `development/full-completion`
- `licensing`

No other branch is an approved development branch.
