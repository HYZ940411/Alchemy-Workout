# Implementation Plan: Adversarial Prompt Self-Optimization System

**Branch**: `001-adversarial-prompt-rl` | **Date**: 2026-02-19 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-adversarial-prompt-rl/spec.md`

## Summary

Build a 4-agent adversarial system for automated prompt engineering reinforcement learning. A TypeScript orchestration script manages the agent lifecycle using the Claude Agent SDK: Controller orchestrates experiments, Worker executes prompts statelessly, Reviewer scores outputs against rubrics, and Researcher optimizes prompts based on feedback. The loop runs until scores converge or hit max iterations.

## Technical Context

**Language/Version**: TypeScript 5.2+ (Node.js 20+)
**Primary Dependencies**: `@anthropic-ai/claude-agent-sdk`, `zod` (tool schema validation), `yaml` (pipeline parsing), `commander` (CLI)
**Storage**: Local filesystem + Git (workspace is a git repo). No database.
**Testing**: Vitest (unit + integration). Manual E2E with real Agent SDK calls.
**Target Platform**: macOS / Linux CLI tool
**Project Type**: Single project (CLI orchestrator)
**Performance Goals**: Complete a 7-8 step experiment in < 30 min per step (configurable timeout). Optimization loop converges within 10 iterations.
**Constraints**: Per-step timeout 30 min (configurable). Single-threaded sequential execution. Local filesystem only.
**Scale/Scope**: Single user, single pipeline at a time. Pipelines of 3-10 steps. Up to 10 optimization iterations.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

No project constitution is defined (template is blank). Gate passes by default — no violations to check.

Post-design re-check: Still no constitution defined. No violations.

## Project Structure

### Documentation (this feature)

```text
specs/001-adversarial-prompt-rl/
├── plan.md              # This file
├── research.md          # Phase 0 — Agent SDK research, schema design
├── data-model.md        # Phase 1 — Entity definitions and relationships
├── quickstart.md        # Phase 1 — Setup and usage guide
├── contracts/           # Phase 1 — Schema definitions
│   ├── pipeline-schema.yml
│   ├── rubric-schema.md
│   ├── review-report-schema.md
│   └── optimization-summary-schema.md
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code

**Workspace**: `chapter04/prompts-lab/`

```text
chapter04/prompts-lab/
├── src/
│   ├── orchestrator.ts      # CLI entry point — parses args, runs experiment/optimize commands
│   ├── agents/
│   │   ├── controller.ts    # Controller agent — pipeline knowledge, dispatches Workers, answers clarifications
│   │   ├── worker.ts        # Worker agent — stateless prompt executor
│   │   ├── reviewer.ts      # Reviewer agent — scores outputs against rubric
│   │   └── researcher.ts    # Researcher agent — modifies prompts based on feedback
│   ├── schemas/
│   │   ├── pipeline.ts      # Pipeline YAML parser + validator (FR-016)
│   │   ├── rubric.ts        # Rubric markdown parser
│   │   └── config.ts        # OptimizationCycle config (5 configurable params)
│   ├── services/
│   │   ├── experiment.ts    # Experiment lifecycle — create run folder, copy prompts, commit steps
│   │   ├── convergence.ts   # Score tracking, delta comparison, convergence detection
│   │   ├── git.ts           # Git operations — init, commit, log parsing
│   │   └── retry.ts         # Transient failure retry logic (FR-018)
│   ├── tools/
│   │   └── ask-controller.ts  # Custom MCP tool for Worker→Controller clarification (R-002)
│   └── types/
│       ├── pipeline.ts      # Pipeline, Step types
│       ├── experiment.ts    # Experiment, StepOutput types
│       ├── review.ts        # ReviewReport, StepScore, DimensionScore types
│       └── cycle.ts         # OptimizationCycle, config types
├── tests/
│   ├── unit/
│   │   ├── schemas/
│   │   │   ├── pipeline.test.ts    # Pipeline YAML validation (FR-016)
│   │   │   └── rubric.test.ts      # Rubric parsing
│   │   ├── services/
│   │   │   ├── convergence.test.ts # Convergence detection logic
│   │   │   ├── experiment.test.ts  # Run folder creation, prompt copying
│   │   │   └── retry.test.ts       # Retry logic
│   │   └── tools/
│   │       └── ask-controller.test.ts
│   ├── integration/
│   │   ├── single-experiment.test.ts  # Story 1 — full experiment run
│   │   ├── review-scoring.test.ts     # Story 2 — review + scoring
│   │   └── optimization-loop.test.ts  # Story 3 — multi-iteration convergence
│   └── fixtures/
│       ├── pipelines/           # Test pipeline YAML files
│       ├── prompts/             # Test prompt files
│       └── rubrics/             # Test rubric files
├── package.json
└── tsconfig.json
```

**Structure Decision**: Single project (Option 1) under `chapter04/prompts-lab/`. CLI orchestrator — no frontend, no backend server. Agents are invoked as separate SDK processes but share the same source code structure.

## Complexity Tracking

> No constitution violations to justify — constitution is undefined.
