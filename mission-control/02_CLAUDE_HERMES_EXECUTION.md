# Claude Code and Hermes Execution Standard

## Claude Code bootstrap

Read `00_READ_ME_FIRST.md` and `01_GOVERNING_CHARTER.md` before acting.

### Phase 1 — Audit

Inspect the complete repository and approved local workspace. Produce:

- Repository and directory inventory
- Existing project roots
- Git status, branches, and recent commits
- Major document and asset collections
- Duplicate or conflicting files
- Untracked work
- Build and test commands
- Claude, Gemini, Hermes, MCP, and automation configurations
- Secret and credential exposure risks
- Broken workflows
- High-value unfinished work

Write the result to `reports/audits/INITIAL_SYSTEM_AUDIT.md`.

Do not delete, move, rename, or overwrite source material during the audit.

### Phase 2 — Establish control

Create or reconcile:

- `GOVERNANCE.md`
- `AGENTS.md`
- `STATUS.md`
- `task_queue/`
- `knowledge/`
- project-level status files
- `.gitignore`
- `.env.example`
- source registry
- agent-run logging

Create snapshots or branches before migration.

### Phase 3 — Generate backlog

Every task must include objective, owner agent, dependencies, inputs, acceptance criteria, risk, approval gate, and expected output path.

### Phase 4 — Execute

Begin Priority 0 automatically and continue through all safe, reversible, non-destructive work.

Stop only for credentials, destructive action, external sending or publishing, legal or financial commitment, production deployment, safety-critical factual conflict, or material ambiguity that cannot be resolved from existing evidence.

## Hermes runbook

Hermes is the bounded local execution runner.

### First run

1. Confirm the approved workspace root.
2. Confirm read/write boundaries.
3. Print Git status.
4. Inventory top-level directories.
5. Locate governing files.
6. Check for secrets and private keys before indexing.
7. Create a non-destructive inventory.
8. Record the run in `logs/agent_runs/`.

### Approved work

- File inventory and metadata extraction
- Duplicate detection
- Text extraction and indexing
- PDF, DOCX, PPTX, image, and spreadsheet processing
- Format conversion and rendering
- Visual QA
- GIS organization and KML/KMZ packaging
- Source snapshotting
- Link and citation checking
- Budget arithmetic validation
- Test execution
- Daily report generation

### Restricted work

Explicit approval is required for deletion, mass rename or move, credential changes, external uploads, external messages, production deployment, financial actions, legal submissions, and changes to safety-critical operational data.

## Required run record

Every autonomous run must record:

- Objective
- Inputs read
- Actions completed
- Files created or changed
- Tests or validation performed
- Sources used
- Assumptions made
- Risks identified
- Blockers
- Recommended next action

Store the record at `logs/agent_runs/YYYY-MM-DD_HHMM_AGENT_TASK.md`.
