# Quickstart: Adversarial Prompt Self-Optimization System

## Prerequisites

- Node.js 20+
- TypeScript 5.2+
- Git (initialized workspace)
- `@anthropic-ai/claude-agent-sdk` (npm package)
- `ANTHROPIC_API_KEY` environment variable set

## Workspace Setup

```bash
# 1. Navigate to workspace directory
cd chapter04/prompts-lab

# 2. Create prompt files
mkdir prompts
# Write your prompt files (one per step):
#   prompts/classify-intent.md
#   prompts/draft-reply.md
#   prompts/review-output.md

# 3. Create pipeline config
# See contracts/pipeline-schema.yml for schema
cat > pipeline.yml << 'EOF'
version: "1"
pipeline:
  name: "my-pipeline"
  description: "My prompt pipeline"
  steps:
    - id: classify
      prompt: prompts/classify-intent.md
      args:
        language: "zh-TW"
    - id: draft-reply
      prompt: prompts/draft-reply.md
      args:
        tone: "professional"
EOF

# 4. Create scoring rubric
# See contracts/rubric-schema.md for schema
cat > rubric.md << 'EOF'
# Scoring Rubric: my-pipeline

## Step: classify
### Dimensions
| Dimension | Description | Weight | Pass Threshold |
|-----------|-------------|--------|----------------|
| accuracy  | Correct classification | 60 | 70 |
| format    | Valid output schema    | 40 | 80 |
**Total weight: 100**

## Step: draft-reply
### Dimensions
| Dimension | Description | Weight | Pass Threshold |
|-----------|-------------|--------|----------------|
| relevance | Addresses the issue | 50 | 75 |
| tone      | Professional language | 50 | 70 |
**Total weight: 100**
EOF
```

## Run Single Experiment

```bash
# Run one experiment (Story 1)
npx ts-node src/orchestrator.ts run \
  --pipeline pipeline.yml \
  --workspace .

# Expected output:
# [run-001] Starting experiment...
# [run-001][step-1/2] classify — running...
# [run-001][step-1/2] classify — done (45s)
# [run-001][step-2/2] draft-reply — running...
# [run-001][step-2/2] draft-reply — done (32s)
# [run-001] Experiment completed. 2 commits created.
```

## Run with Review (Story 2)

```bash
# Run experiment + review
npx ts-node src/orchestrator.ts run \
  --pipeline pipeline.yml \
  --rubric rubric.md \
  --workspace . \
  --review

# Additional output:
# [run-001] Starting review...
# [run-001] Review complete. Score: 68/100
# [run-001] Report: run-001/review-report.md
```

## Run Optimization Loop (Story 3)

```bash
# Run full adversarial optimization
npx ts-node src/orchestrator.ts optimize \
  --pipeline pipeline.yml \
  --rubric rubric.md \
  --workspace . \
  --max-iterations 10 \
  --convergence-threshold 3 \
  --step-timeout 30 \
  --retry-count 2 \
  --researcher-mode modify-only

# Expected output:
# [iter-1] run-001: score 52/100
# [iter-2] run-002: score 68/100 (+16)
# [iter-3] run-003: score 71/100 (+3)
# [iter-4] run-004: score 72/100 (+1) — converged
# Optimization complete. Best: run-004 (72/100)
# Summary: optimization-summary.md
```

## Project Structure (after running)

```
chapter04/prompts-lab/
├── pipeline.yml              # Pipeline config (user-created)
├── rubric.md                 # Scoring rubric (user-created)
├── prompts/                  # Original prompts (user-created)
│   ├── classify-intent.md
│   └── draft-reply.md
├── run-001/                  # First experiment
│   ├── prompts/              # Copied prompts (exact versions used)
│   ├── step-001-classify/    # Step output artifacts
│   ├── step-002-draft-reply/
│   └── review-report.md     # Reviewer's evaluation
├── run-002/                  # Second experiment (modified prompts)
│   └── ...
├── run-003/
│   └── ...
└── optimization-summary.md   # Final summary (after loop terminates)
```

## Key Files

| File | Created By | Purpose |
|------|-----------|---------|
| `pipeline.yml` | User | Defines step order, prompt paths, default args |
| `rubric.md` | User | Defines scoring dimensions per step |
| `run-NNN/prompts/` | Controller (copy) + Researcher (modify) | Exact prompt versions for this experiment |
| `run-NNN/review-report.md` | Reviewer | Per-step scores, evidence, optimization suggestions |
| `optimization-summary.md` | Orchestrator | Score progression, convergence status, best run |
