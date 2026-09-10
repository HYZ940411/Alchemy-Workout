# Data Model: Adversarial Prompt Self-Optimization System

**Date**: 2026-02-19
**Spec**: [spec.md](spec.md) | **Research**: [research.md](research.md)

## Entities

### Pipeline

The ordered sequence of prompt steps that define one experiment run.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| version | string | Schema version | Required. Currently `"1"` |
| name | string | Pipeline identifier | Required |
| description | string | Human-readable description | Optional |
| steps | Step[] | Ordered list of steps | Required. Min 1 step |

**Source**: Parsed from `pipeline.yml` (user-provided YAML file).
**Validation**: Controller validates before first experiment (FR-016). Checks: non-empty steps, all prompt paths exist, no duplicate step IDs.

---

### Step

One prompt execution unit within a pipeline.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| id | string | Stable step identifier | Required. Unique within pipeline. Used by rubric to reference step |
| prompt | string | Relative path to prompt file | Required. Must exist on filesystem |
| args | map<string, any> | Default arguments passed to Worker | Optional. Key-value pairs |
| sequence | integer | Implicit from list position | 1-based. Not stored in YAML — derived at parse time |

**Relationships**: Pipeline 1→N Step. Step.id → Rubric.Step section heading.

---

### Experiment (Run Folder)

A single end-to-end execution of the pipeline, stored as `run-NNN/`.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| run_number | integer | Sequential experiment number | Auto-incremented. 1-based |
| folder_path | string | Path to run folder (e.g., `run-001/`) | Unique within workspace |
| status | enum | `running`, `completed`, `failed` | Set by Controller |
| started_at | timestamp | When experiment began | ISO 8601 |
| completed_at | timestamp | When experiment finished | ISO 8601. Null if running/failed |
| step_count | integer | Total steps in pipeline | Matches Pipeline.steps.length |
| completed_steps | integer | Steps successfully committed | 0 to step_count |
| failure_context | string | Error details if failed | Null if completed. Used by Researcher |
| prompts_dir | string | Path to copied prompts within run folder | `run-NNN/prompts/` |

**Lifecycle**: `running` → `completed` | `failed`
- On creation: status = `running`, prompts copied from source
- On all steps done: status = `completed`
- On step failure: status = `failed`, failure_context populated

**Git representation**: One commit per completed step, prefixed `[run-NNN][step-MMM]`. Review report committed as separate final commit.

---

### StepOutput

The artifacts produced by a Worker for one step within an experiment.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| step_id | string | References Step.id | Required |
| step_sequence | integer | Position in pipeline | 1-based |
| output_dir | string | Path within run folder | `run-NNN/step-MMM-<id>/` |
| commit_hash | string | Git commit SHA | Populated after commit |
| status | enum | `running`, `completed`, `failed`, `timeout` | Set by orchestration script |
| duration_ms | integer | Execution time in milliseconds | Null if running |

**Relationships**: Experiment 1→N StepOutput. StepOutput.step_id → Step.id.

---

### ScoringRubric

User-provided evaluation criteria for the pipeline.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| pipeline_name | string | Which pipeline this rubric evaluates | Must match Pipeline.name |
| step_sections | StepRubric[] | Per-step evaluation criteria | One section per step (can be subset) |

**Source**: User-provided structured markdown file.

---

### StepRubric

Evaluation dimensions for one pipeline step.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| step_id | string | References Step.id | Must exist in pipeline |
| dimensions | Dimension[] | Evaluation criteria | Min 1. Weights must sum to 100 |

---

### Dimension

One evaluation criterion within a step rubric.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| name | string | Dimension identifier | Required. Unique within step |
| description | string | What this dimension measures | Required |
| weight | integer | Relative importance (0-100) | Required. All weights in step sum to 100 |
| pass_threshold | integer | Minimum score to pass (0-100) | Required |

---

### ReviewReport

The Reviewer's evaluation of one experiment.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| run_number | integer | Which experiment was reviewed | References Experiment.run_number |
| overall_score | integer | Average of all step scores (0-100) | Computed |
| step_scores | StepScore[] | Per-step evaluation results | One per step |
| optimization_priorities | Priority[] | Ranked list of improvement suggestions | Ordered by impact |
| warnings | string[] | Issues noted (e.g., rubric inconsistencies) | Optional |
| file_path | string | Location within run folder | `run-NNN/review-report.md` |

---

### StepScore

Per-step evaluation result within a review report.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| step_id | string | Which step was scored | References Step.id |
| score | integer | Weighted sum of dimension scores (0-100) | Computed |
| pass | boolean | All dimensions above threshold | Computed |
| dimension_scores | DimensionScore[] | Per-dimension results | One per dimension in rubric |

---

### DimensionScore

Per-dimension evaluation result.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| name | string | Dimension name | References Dimension.name |
| score | integer | Score for this dimension (0-100) | Assigned by Reviewer |
| pass | boolean | score >= pass_threshold | Computed |
| evidence | string | Specific evidence from step output | Required. Quotes or references |

---

### OptimizationPriority

A ranked improvement suggestion from the Reviewer.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| rank | integer | Priority order (1 = highest) | 1-based |
| step_id | string | Which step to improve | References Step.id |
| dimension | string | Which dimension is weak | References Dimension.name |
| suggestion | string | Concrete improvement action | Required |
| evidence | string | Why this was flagged | Required |

---

### OptimizationCycle

Tracks the full adversarial loop across multiple experiments.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| workspace_path | string | Root workspace directory | Required |
| pipeline_path | string | Path to pipeline.yml | Required |
| rubric_path | string | Path to rubric.md | Required |
| max_iterations | integer | Safety stop | Default: 10 |
| convergence_threshold | integer | Score delta for convergence | Default: 3 |
| step_timeout_min | integer | Per-step timeout in minutes | Default: 30 |
| retry_count | integer | Transient failure retries | Default: 2 |
| researcher_mode | enum | `modify-only`, `create-allowed` | Default: `modify-only` |
| current_iteration | integer | Current experiment number | 1-based |
| score_history | integer[] | Overall score per completed iteration | Indexed by iteration |
| convergence_status | enum | `running`, `converged`, `hit-max` | Computed |
| best_iteration | integer | Iteration with highest score | Computed |
| best_score | integer | Highest overall score achieved | Computed |

**State transitions**: `running` → `converged` | `hit-max`
- `converged`: score delta < threshold for 2 consecutive iterations
- `hit-max`: current_iteration >= max_iterations (includes failed experiments)

---

## Entity Relationship Diagram

```
Pipeline ─1:N─► Step
                  │
                  ├── id links to ──► StepRubric.step_id
                  │                      │
                  │                      └──1:N──► Dimension
                  │
                  └── id links to ──► StepOutput.step_id
                                        │
Experiment ─1:N─► StepOutput            │
    │                                    │
    └──1:1──► ReviewReport              │
                  │                      │
                  ├──1:N──► StepScore ──┘
                  │            │
                  │            └──1:N──► DimensionScore
                  │
                  └──1:N──► OptimizationPriority

OptimizationCycle ─1:N──► Experiment
```
