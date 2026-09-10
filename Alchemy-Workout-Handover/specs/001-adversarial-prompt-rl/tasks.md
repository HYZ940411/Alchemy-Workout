# Tasks: Adversarial Prompt Self-Optimization System

**Input**: Design documents from `/specs/001-adversarial-prompt-rl/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not included — spec does not request TDD. Testing is manual E2E with real Agent SDK calls + Vitest for unit/integration (added as needed during implementation).

**Organization**: Tasks grouped by user story. Each story is independently implementable and testable after Phase 2 (Foundational) completes.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- All file paths relative to `chapter04/prompts-lab/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and directory structure

- [x] T001 Create project directory structure under `chapter04/prompts-lab/` per plan.md — `src/agents/`, `src/schemas/`, `src/services/`, `src/tools/`, `src/types/`, `tests/unit/`, `tests/integration/`, `tests/fixtures/`
- [x] T002 Initialize TypeScript project — create `package.json` with `@anthropic-ai/claude-agent-sdk`, `zod`, `yaml`, `commander` dependencies; create `tsconfig.json` with strict mode; install dependencies

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core types, parsers, and services that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T003 [P] Define all shared TypeScript types in `src/types/` — `pipeline.ts` (Pipeline, Step), `experiment.ts` (Experiment, StepOutput), `review.ts` (ReviewReport, StepScore, DimensionScore, OptimizationPriority), `cycle.ts` (OptimizationCycle, CycleConfig with 5 configurable params)
- [x] T004 [P] Implement Pipeline YAML parser and validator in `src/schemas/pipeline.ts` — parse `pipeline.yml`, validate: version field, non-empty steps, unique step IDs, all prompt file paths exist on disk; reject invalid pipelines with descriptive errors (FR-016)
- [x] T005 [P] Implement Git service in `src/services/git.ts` — commit with prefixed message `[run-NNN][step-MMM] <step-id>`, parse git log to extract per-run commits, get diff between commits, check working directory status
- [x] T006 Create CLI entry point in `src/orchestrator.ts` — use `commander` to define `run` subcommand (--pipeline, --workspace, --rubric, --review flags) and `optimize` subcommand (--pipeline, --workspace, --rubric, --max-iterations, --convergence-threshold, --step-timeout, --retry-count, --researcher-mode flags); parse and validate args

**Checkpoint**: Foundation ready — user story implementation can begin

---

## Phase 3: User Story 1 — Single Experiment Run (Priority: P1) MVP

**Goal**: Run a prompt pipeline end-to-end — Controller dispatches Workers sequentially, each step output committed. One experiment = N commits in a run folder.

**Independent Test**: Configure a 3-step prompt pipeline, run one experiment, verify 3 commits exist with correct artifacts in `run-001/`.

### Implementation for User Story 1

- [x] T007 [US1] Implement experiment lifecycle service in `src/services/experiment.ts` — create `run-NNN/` folder (auto-increment run number), copy prompt files into `run-NNN/prompts/`, create step output directories `run-NNN/step-MMM-<id>/`, track experiment status (running/completed/failed) (FR-002, FR-010)
- [x] T008 [P] [US1] Implement `ask_controller` custom MCP tool in `src/tools/ask-controller.ts` — use `createSdkMcpServer()` + `tool()` with zod schema `{ question: z.string() }`; tool handler invokes a separate Controller `query()` and returns the answer as tool result (FR-005, R-002)
- [x] T009 [P] [US1] Implement Worker agent in `src/agents/worker.ts` — invoke `query()` with prompt file content + args as user prompt, attach `ask_controller` MCP tool via `mcpServers`, set `permissionMode: "bypassPermissions"`, collect result artifacts from the run folder diff (FR-003, FR-004)
- [x] T010 [US1] Implement Controller agent in `src/agents/controller.ts` — load pipeline context and system prompt describing PM role, implement `invokeController(question, context)` function that runs `query()` to answer Worker clarifications, implement `dispatchWorker(step, runFolder)` that creates a Worker for each step and commits output via Git service (FR-003, FR-005, FR-006)
- [x] T011 [US1] Wire `run` command end-to-end in `src/orchestrator.ts` — load and validate pipeline, create experiment via experiment service, invoke Controller to dispatch Workers for each step sequentially, commit after each step, log progress to stdout: `[run-NNN][step-M/N] <id> — running/done/failed` (FR-017)

**Checkpoint**: `npx ts-node src/orchestrator.ts run --pipeline pipeline.yml --workspace .` completes a full experiment with N commits

---

## Phase 4: User Story 2 — Review and Scoring (Priority: P2)

**Goal**: After an experiment completes, Reviewer evaluates all step outputs against a scoring rubric and produces a structured review report committed to the run folder.

**Independent Test**: Provide a completed experiment (with commits) and a scoring rubric, verify Reviewer produces `run-NNN/review-report.md` with per-step scores, evidence, and optimization suggestions.

### Implementation for User Story 2

- [x] T012 [P] [US2] Implement rubric markdown parser in `src/schemas/rubric.ts` — parse structured markdown per contracts/rubric-schema.md: extract `## Step: <id>` sections, parse dimensions table (name, description, weight, pass_threshold), validate weights sum to 100 per step, return typed `ScoringRubric` object
- [x] T013 [US2] Implement Reviewer agent in `src/agents/reviewer.ts` — invoke `query()` with system prompt containing rubric + instructions; provide experiment commit history and per-step artifacts as context; parse structured review report output into `ReviewReport` type; compute step scores (weighted sum) and overall score (average) (FR-007, FR-008, FR-009)
- [x] T014 [US2] Integrate Reviewer into experiment flow in `src/services/experiment.ts` — after all steps complete successfully, invoke Reviewer, write `review-report.md` to run folder, commit with message `[run-NNN] Add review report (score: NN/100)` (FR-009)
- [x] T015 [US2] Wire `--review` and `--rubric` flags in `src/orchestrator.ts` — when `--review` is passed with `run` command, load rubric, invoke Reviewer after experiment, log overall score to stdout

**Checkpoint**: `npx ts-node src/orchestrator.ts run --pipeline pipeline.yml --workspace . --rubric rubric.md --review` produces review report with per-step scores

---

## Phase 5: User Story 3 — Adversarial Optimization Loop (Priority: P3)

**Goal**: Full adversarial loop — run experiment → review → research (modify prompts) → repeat until convergence or max iterations. Handles failures, timeouts, retries, and resume.

**Independent Test**: Run 2-3 optimization iterations on a simple pipeline, verify scores improve or stabilize and optimization-summary.md is generated.

### Implementation for User Story 3

- [x] T016 [P] [US3] Implement Researcher agent in `src/agents/researcher.ts` — invoke `query()` with review report (or failure context) + current prompt files; system prompt instructs to modify prompts to address identified weaknesses; support configurable mode: modify-only (edit existing files only) vs create-allowed (can add/split/merge prompts and update pipeline YAML) (FR-010a)
- [x] T017 [P] [US3] Implement convergence detection service in `src/services/convergence.ts` — track score history array, compute delta between consecutive scored iterations, detect convergence (delta < threshold for 2 consecutive iterations), report convergence status (running/converged/hit-max), track best iteration and best score (FR-012)
- [x] T018 [P] [US3] Implement retry service in `src/services/retry.ts` — wrap async operations with configurable retry count (default: 2) for transient failures (network errors, API timeouts); implement `scanExistingRuns(workspace)` to find last completed iteration for resume-on-restart (FR-018)
- [x] T019 [US3] Implement optimization loop in `src/orchestrator.ts` — orchestrate: run experiment (US1) → review (US2) → dispatch Researcher → copy updated prompts for next run → repeat; check convergence after each scored iteration; enforce max iteration count (both successful and failed count); generate `optimization-summary.md` on termination with best iteration, score progression table, convergence status, path to best prompts (FR-011, FR-013)
- [x] T020 [US3] Implement failure handling path in `src/orchestrator.ts` — when Worker fails mid-step: abort experiment immediately, mark as failed, skip Reviewer, dispatch Researcher with failure context instead of review report, start new experiment with Researcher's updated prompts (FR-014, FR-015)
- [x] T021 [US3] Implement per-step timeout enforcement in `src/services/experiment.ts` — wrap Worker invocation with configurable timeout (default: 30 min); on timeout, treat as step failure triggering same abort-and-fix path as FR-014 (FR-019)
- [x] T022 [US3] Wire `optimize` command end-to-end in `src/orchestrator.ts` — accept all 5 configurable CLI params (--max-iterations, --convergence-threshold, --step-timeout, --retry-count, --researcher-mode); log per-iteration scores to stdout; handle resume from interrupted run via retry service scan (FR-017, FR-018)

**Checkpoint**: `npx ts-node src/orchestrator.ts optimize --pipeline pipeline.yml --rubric rubric.md --workspace .` runs multiple iterations and terminates on convergence or max iterations

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Validation and hardening across all stories

- [x] T023 Validate end-to-end flow against quickstart.md scenarios — single run (3-step pipeline), run+review, optimization loop (2-3 iterations)
- [x] T024 Verify reproducibility (SC-006) — confirm each experiment's full history (prompts used, outputs, scores) is recoverable from git commits alone

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Foundational — no other story dependencies
- **US2 (Phase 4)**: Depends on Foundational + US1 (needs a completed experiment to review)
- **US3 (Phase 5)**: Depends on Foundational + US1 + US2 (needs experiment + review before optimization)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

```
US1 (Single Experiment) ──► US2 (Review & Scoring) ──► US3 (Optimization Loop)
```

- **US1**: Foundational only — can start immediately after Phase 2
- **US2**: Requires US1 — needs completed experiment with commits to review
- **US3**: Requires US1 + US2 — needs full run→review cycle before adding the optimization loop

> **Note**: Unlike typical CRUD features, these user stories are NOT independent — each builds on the previous one. The adversarial loop (US3) structurally requires experiment execution (US1) and review (US2). This is by design per the spec's priority ordering.

### Within Each User Story

- Types before services
- Services before agents
- Agents before orchestrator wiring
- Tasks marked [P] within a phase can run in parallel

### Parallel Opportunities

Within Phase 2 (Foundational):
```
T003 (types) ──┐
T004 (pipeline) ├── all [P], run in parallel
T005 (git)     ├──
T006 (CLI)     ┘  (T006 may reference types but can scaffold independently)
```

Within Phase 3 (US1):
```
T007 (experiment service) ──┐
T008 (ask_controller tool) ──┼── T008 + T009 are [P]
T009 (Worker agent)        ──┘
Then T010 (Controller) → T011 (wire run command)
```

Within Phase 4 (US2):
```
T012 (rubric parser) ── [P], can run alongside T013 prep work
Then T013 (Reviewer) → T014 (integration) → T015 (CLI flags)
```

Within Phase 5 (US3):
```
T016 (Researcher) ──┐
T017 (convergence) ──┼── all [P], run in parallel
T018 (retry)       ──┘
Then T019 (loop) → T020 (failure handling) → T021 (timeout) → T022 (wire optimize)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Run a 3-step pipeline, verify 3 commits in `run-001/`
5. This is already useful — reproducible experiment execution

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. US1 → Test: single experiment run works → **MVP!**
3. US2 → Test: review report with scores produced → Experiment + Feedback
4. US3 → Test: optimization loop converges → Full Adversarial System
5. Polish → Validate all scenarios from quickstart.md

---

## Notes

- [P] tasks = different files, no dependencies within the same phase
- [Story] label maps task to specific user story for traceability
- All file paths relative to `chapter04/prompts-lab/`
- US1→US2→US3 is a sequential dependency chain (not parallelizable across stories)
- Commit after each task or logical group
- Stop at any checkpoint to validate the current increment
