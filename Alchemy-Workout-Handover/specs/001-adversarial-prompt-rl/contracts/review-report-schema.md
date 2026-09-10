# Review Report Schema

Defines the structure of review reports produced by the Reviewer agent and committed to `run-NNN/review-report.md`.

## Format

Structured markdown file with summary, step scores table, detailed per-step evaluation, and ranked optimization priorities.

```markdown
# Review Report: run-NNN

## Summary
- **Overall Score**: NN/100
- **Steps Evaluated**: N/N
- **Pipeline**: <pipeline-name>
- **Date**: YYYY-MM-DD HH:MM

## Step Scores

| Step | Score | Pass/Fail | Key Issues |
|------|-------|-----------|------------|
| <step-id> | NN | PASS/FAIL | <brief summary> |

## Detailed Evaluation

### Step: <step-id>
**Score: NN/100 — PASS/FAIL**

| Dimension | Score | Weight | Threshold | Status |
|-----------|-------|--------|-----------|--------|
| <name> | NN | NN | NN | PASS/FAIL |

**Evidence**:
- <dimension-name>: <specific evidence from output, with quotes or references>

### Step: <next-step-id>
...

## Optimization Priorities

| Rank | Step | Dimension | Suggestion | Evidence |
|------|------|-----------|------------|----------|
| 1 | <step-id> | <dimension> | <concrete improvement action> | <why flagged> |
| 2 | ... | ... | ... | ... |

## Warnings
- <any rubric inconsistencies or issues noted>
```

## Field Definitions

### Summary Section

| Field | Type | Description |
|-------|------|-------------|
| Overall Score | integer | Average of all step scores (0-100) |
| Steps Evaluated | string | "N/N" format — evaluated vs total |
| Pipeline | string | Pipeline name from pipeline.yml |
| Date | string | ISO 8601 timestamp |

### Step Scores Table

| Field | Type | Description |
|-------|------|-------------|
| Step | string | Step.id from pipeline |
| Score | integer | Weighted sum of dimension scores (0-100) |
| Pass/Fail | enum | PASS if all dimensions above threshold, FAIL otherwise |
| Key Issues | string | Brief summary of main problems (empty if PASS) |

### Detailed Evaluation

Per step, per dimension:

| Field | Type | Description |
|-------|------|-------------|
| Dimension | string | Dimension name from rubric |
| Score | integer | Reviewer-assigned score (0-100) |
| Weight | integer | From rubric |
| Threshold | integer | Pass threshold from rubric |
| Status | enum | PASS if score >= threshold, FAIL otherwise |
| Evidence | string | Specific quotes or references from step output |

### Optimization Priorities

Ranked list (highest impact first):

| Field | Type | Description |
|-------|------|-------------|
| Rank | integer | Priority order, 1 = most impactful |
| Step | string | Which step to improve |
| Dimension | string | Which dimension is weakest |
| Suggestion | string | Concrete, actionable improvement for the Researcher |
| Evidence | string | Why this was flagged — quotes from output |

### Warnings

Optional. List of issues the Reviewer noted:
- Rubric inconsistencies or contradictions
- Steps with no rubric section (evaluated best-effort)
- Ambiguous evaluation criteria

## Storage

- File path: `run-NNN/review-report.md` (inside experiment's run folder)
- Committed to git as a separate commit after all step commits
- Commit message format: `[run-NNN] Add review report (score: NN/100)`
