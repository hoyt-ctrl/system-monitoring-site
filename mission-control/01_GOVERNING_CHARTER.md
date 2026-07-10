# HYANS / NORKO / Meridian Mission Control
## Governing Project Charter

**Status:** Controlling specification  
**Owner:** Clayton-Hoyt Uyehara / HYANS

## Vision

Build a private maritime operations knowledge and execution platform that allows HYANS and NORKO to coordinate high-consequence vessel programs, develop Meridian, produce decision-grade intelligence, manage client deliverables, retain institutional knowledge, and use multiple AI systems without depending on any single chat history or vendor memory.

> The project is the memory. Models are replaceable workers.

## Strategic objectives

1. Consolidate active work into a governed, searchable, versioned system.
2. Preserve all source material and provenance.
3. Make current status, decisions, risks, budgets, and next actions visible.
4. Enable Claude Code, ChatGPT, Gemini, Hermes, and future agents to work from the same canonical context.
5. Automate repetitive research, document production, QA, packaging, and reporting.
6. Maintain human approval gates for legal, financial, safety-critical, reputational, credential, and destructive actions.
7. Separate verified facts from assumptions, proposals, forecasts, and creative concepts.
8. Produce client-ready work from reusable structured knowledge.

## Operating domains

- HYANS vessel agency and statewide operations
- NORKO partnership and ship-agency support
- Meridian product and platform development
- WMG / LAUNCHPAD / WINGMAN Hawaiʻi program
- Offshore anchorage and seasonal operating intelligence
- GIS, NOAA, weather, bathymetry, KML/KMZ, and evidence packets
- Open Water Risk Management curriculum
- SEARCHER and community-stewardship initiatives
- Client budgets, proposals, invoices, and approvals
- Harbor, berth, shipyard, tender, aviation, provisioning, and logistics studies
- Government, authority, stakeholder, and relationship context
- Brand, presentation, image, and design systems

## Canonical architecture

```text
HYANS_MISSION_CONTROL/
├── README.md
├── GOVERNANCE.md
├── AGENTS.md
├── STATUS.md
├── task_queue/
├── knowledge/
├── projects/
├── clients/
├── operations/
├── research/
├── sources/
├── assets/
├── templates/
├── automations/
├── tools/
├── reports/
├── deliverables/
├── archive/
└── logs/
```

Each active project must contain `PROJECT_CONTEXT.md`, `STATUS.md`, `TASKS.md`, `DECISIONS.md`, `ASSUMPTIONS.md`, `RISKS.md`, `SOURCES.md`, and separate working, review, and deliverable directories.

## Agent roles

### ChatGPT — strategy and synthesis
Owns program architecture, cross-project prioritization, research synthesis, specifications, executive communications, decision frameworks, acceptance criteria, and final editorial review.

### Claude Code — engineering and repository lead
Owns repository audit, architecture implementation, refactoring, code, automation, tests, issue generation, documentation enforcement, and small reversible commits.

### Hermes — local execution runner
Owns local file inventory and indexing, batch conversion, document rendering, GIS/data processing, repetitive execution, validation, packaging, and evidence capture. Hermes is not the strategic source of truth.

### Gemini — Google and multimodal specialist
Owns Google Workspace workflows, map and image review, large visual-context comparison, and Google-native documents and datasets.

### Git/GitHub — institutional memory
Owns version history, branching, reviews, issues, releases, auditability, and recovery.

## Autonomous execution policy

Agents may continue without confirmation when work is reversible, non-destructive, inside the approved workspace, within an approved specification, and not legally, financially, or operationally binding.

Agents must stop before:

1. Sending external communications
2. Publishing or deploying to production
3. Spending or committing funds
4. Signing or modifying agreements
5. Deleting or irreversibly transforming source data
6. Changing credentials, security, permissions, or access
7. Making safety-critical navigational or operational determinations
8. Representing estimates as verified facts
9. Using private information outside its authorized purpose
10. Resolving a material factual conflict without evidence

## Quality standard

Every deliverable must have a defined audience and objective, traceable sources, clear fact/assumption separation, current date and version, internal consistency, appropriate disclaimer, visual/editorial QA, reproducible source files, and a defined owner and next action.

No fabricated citations, depths, coordinates, prices, approvals, authority positions, or operational claims are permitted.

For maritime planning products, planning-level information must be labeled non-navigational. Captain, master, authority, and current chart/weather review remain controlling.

## Definition of done

A task is complete only when the output exists in the correct canonical location, sources and assumptions are recorded, QA is complete, status files are updated, the output is reproducible and versioned, remaining risks are explicit, and client-ready material is separated from working files.

## Initial priorities

### Priority 0 — Establish control
Inventory all repositories and major local/cloud workspaces; identify duplicate project roots; create read-only snapshots; establish the canonical repository; import this charter; create status and backlog; confirm secrets are excluded.

### Priority 1 — Recover active work
WMG / LAUNCHPAD / WINGMAN; anchorage intelligence and evidence packets; Meridian; Open Water Risk Management; SEARCHER / stewardship; current client operations and financial work.

### Priority 2 — Build reusable systems
Research/source registry; visual briefing pipeline; budget and proposal templates; project dashboard; GIS/weather evidence workflow; document and slide QA; automated status reporting.

### Priority 3 — Controlled autonomy
Task router; agent handoff protocol; scheduled indexing; change detection; automated drafts; approval queue; release packaging.

## Governing rule

No model conversation, local cache, or proprietary memory may be the sole location of material project knowledge. Every material decision or output must be written back into the canonical system.
