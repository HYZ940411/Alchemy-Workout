# Optimization Summary Schema

Defines the structure of the final summary produced when the optimization loop terminates (convergence or max iterations).

## Format

```markdown
# Optimization Summary

## Result
- **Status**: Converged / Hit Max Iterations
- **Best Iteration**: run-NNN
- **Best Score**: NN/100
- **Total Iterations**: N
- **Best Prompts**: run-NNN/prompts/

## Score Progression

| Iteration | Run | Score | Delta | Status |
|-----------|-----|-------|-------|--------|
| 1 | run-001 | 52 | — | completed |
| 2 | run-002 | — | — | failed |
| 3 | run-003 | 68 | +16 | completed |
| 4 | run-004 | 71 | +3 | completed |
| 5 | run-005 | 72 | +1 | converged |

## Configuration
- Max Iterations: 10
- Convergence Threshold: 3
- Step Timeout: 30 min
- Retry Count: 2
- Researcher Mode: modify-only
```

## Field Definitions

### Result Section

| Field | Type | Description |
|-------|------|-------------|
| Status | enum | `Converged` (delta < threshold for 2 consecutive) or `Hit Max Iterations` |
| Best Iteration | string | Run folder with highest overall score |
| Best Score | integer | Highest overall score achieved (0-100) |
| Total Iterations | integer | Number of experiments run (including failed) |
| Best Prompts | string | Path to the best run's prompts directory |

### Score Progression Table

| Field | Type | Description |
|-------|------|-------------|
| Iteration | integer | 1-based iteration number |
| Run | string | Run folder name |
| Score | integer or "—" | Overall score. "—" for failed experiments |
| Delta | string | Score change from previous scored iteration. "—" for first or failed |
| Status | enum | `completed`, `failed`, `converged` (only on terminal iteration) |

### Configuration Section

Lists the 5 configurable parameters and their values for this cycle.

## Storage

- File path: `optimization-summary.md` (workspace root, alongside pipeline.yml)
- Committed to git after loop termination
- Commit message format: `[optimization] Final summary — <status> at iteration N (score: NN/100)`
