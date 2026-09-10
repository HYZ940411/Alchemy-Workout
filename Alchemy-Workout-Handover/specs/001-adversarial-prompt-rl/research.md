# Research: Adversarial Prompt Self-Optimization System

**Date**: 2026-02-19
**Spec**: [spec.md](spec.md)

## R-001: Agent Execution Model — Claude Agent SDK

**Decision**: Each agent (Controller, Worker, Reviewer, Researcher) runs as a standalone Claude Agent SDK process. An external TypeScript orchestration script manages lifecycle, invocation order, and data passing.

**Rationale**: The user explicitly requires "full programmatic control" over agent lifecycle. The Claude Agent SDK's `query()` API returns an async generator, giving the orchestration script real-time visibility into agent progress, tool calls, and results. Custom tools via `createSdkMcpServer()` + `tool()` enable Worker→Controller clarification without shared memory.

**Alternatives considered**:
- Claude Code sub-agent spawning (Task tool) — rejected: insufficient programmatic control over inter-agent communication
- Direct Anthropic API calls — rejected: loses Claude Code's built-in tools (Read, Write, Bash, Glob, Grep, Edit) which agents need for file manipulation

**Key API details**:
- `query({ prompt, options })` → async generator yielding `SDKMessage` (system, assistant, result)
- `options.systemPrompt` — string or preset with append
- `options.mcpServers` — attach custom tool servers
- `options.permissionMode: "bypassPermissions"` + `allowDangerouslySkipPermissions: true` — fully autonomous
- `options.allowedTools` — whitelist specific tools per agent
- `options.canUseTool` — callback to intercept, approve/deny, or modify tool calls
- `options.model` — select model per agent

## R-002: Worker→Controller Clarification Pattern

**Decision**: Implement as a custom MCP tool `ask_controller` on the Worker agent. The tool handler in the orchestration script invokes a separate `query()` for the Controller agent and returns the answer as the tool result.

**Rationale**: This is the SDK's recommended pattern for inter-agent communication. The tool handler runs in the orchestration script's process, providing full control over what context the Controller receives. No shared memory or state leakage between agents.

**Implementation pattern**:
```typescript
const workerTools = createSdkMcpServer({
  name: "orchestration-tools",
  tools: [
    tool("ask_controller", "Ask Controller for clarification", {
      question: z.string()
    }, async (args) => {
      // Invoke Controller as separate query()
      const answer = await invokeController(args.question, pipelineContext);
      return { content: [{ type: "text", text: answer }] };
    })
  ]
});
```

**Alternatives considered**:
- Shared state/memory between agents — rejected: violates statelessness requirement (FR-004)
- Pre-computed FAQ — rejected: clarification questions are unpredictable

## R-003: Pipeline Configuration Schema

**Decision**: YAML configuration with ordered steps, each having an `id`, `prompt` path, and `args` map. The `id` field links pipeline steps to scoring rubric sections.

**Rationale**: YAML is human-readable and widely supported. The `id` field provides a stable coupling point between pipeline and rubric, decoupled from position. Sequential order is implied by list position (no `depends_on` needed per out-of-scope constraint).

**Schema**:
```yaml
version: "1"
pipeline:
  name: "pipeline-name"
  description: "Pipeline description"
  steps:
    - id: step-identifier
      prompt: prompts/step-prompt.md
      args:
        key: value
```

**Key design decisions**:
- `id` is stable identifier (not position-based) — rubric references it
- `args` are defaults, overridable at runtime
- `prompt` paths are relative to project root
- No branching/conditional fields (out of scope)

## R-004: Scoring Rubric Format

**Decision**: Structured markdown file with per-step sections. Each step contains a dimensions table with name, description, weight, and pass/fail threshold. Weights sum to 100 per step. All scores use 0-100 integer scale.

**Rationale**: Markdown is readable by both humans and LLMs. The Reviewer agent can parse the table format directly. Weights summing to 100 makes score calculation intuitive.

**Format**:
```markdown
# Scoring Rubric: <pipeline-name>

## Step: <step-id>
### Dimensions
| Dimension | Description | Weight | Pass Threshold |
|-----------|-------------|--------|----------------|
| accuracy  | ...         | 50     | 70             |
| format    | ...         | 20     | 80             |
**Total weight: 100**
```

**Scoring conventions**:
- Step score = `sum(score_i * weight_i) / 100` (0-100)
- Experiment score = average of all step scores (0-100)
- A step fails if any dimension score < its pass threshold
- Threshold guide: 90+ for hard constraints, 70-80 for quality, 60 for stylistic

## R-005: Review Report Structure

**Decision**: Committed as `run-NNN/review-report.md` inside the experiment's run folder. Contains per-step scores, overall score, evidence citations, and ranked optimization suggestions.

**Rationale**: Self-contained in run folder per FR-009. Markdown is parseable by both Researcher agent and humans. Committed to git for reproducibility (SC-006).

**Format**:
```markdown
# Review Report: run-NNN

## Summary
- Overall Score: NN/100
- Steps Evaluated: N/N

## Step Scores
| Step | Score | Pass/Fail | Key Issues |
|------|-------|-----------|------------|
| classify | 78 | PASS | ... |
| draft-reply | 52 | FAIL | accuracy below threshold |

## Detailed Evaluation
### Step: classify
- accuracy: 85/100 (weight: 50, threshold: 70) PASS
  Evidence: ...
- format: 65/100 (weight: 20, threshold: 80) FAIL
  Evidence: ...

## Optimization Priorities (ranked)
1. [draft-reply] accuracy — ...
2. [classify] format — ...
```

## R-006: Experiment Folder Structure

**Decision**: Each experiment is a subfolder `run-NNN/` in the workspace. Contains copied prompt files, step output artifacts, and review report. One commit per step, prefixed with run number.

**Rationale**: Self-contained per FR-010. Copy-on-write ensures originals stay intact. Commit prefixing enables cross-iteration comparison via git log filtering.

**Structure**:
```
workspace/
├── pipeline.yml          # Original pipeline config
├── rubric.md             # Scoring rubric
├── prompts/              # Original prompt files
│   ├── classify-intent.md
│   └── draft-reply.md
├── run-001/
│   ├── prompts/          # Copied (possibly modified) prompts
│   ├── step-001-classify/  # Step output artifacts
│   ├── step-002-draft/
│   ├── review-report.md
│   └── summary.json      # Metadata: status, scores, timestamp
├── run-002/
│   └── ...
└── optimization-summary.md  # Final summary after convergence
```

## R-007: Convergence Detection

**Decision**: Score delta below configurable threshold (default: 3 points on 0-100 scale) for 2 consecutive iterations. Both successful and failed experiments count toward max iteration limit (default: 10).

**Rationale**: Simple delta-based convergence is sufficient for prompt optimization. Failed experiments counting guarantees termination — prevents infinite retry loops.

**5 configurable parameters**:
| Parameter | Default | Description |
|-----------|---------|-------------|
| max_iterations | 10 | Safety stop — total experiments (any status) |
| convergence_threshold | 3 | Score delta below this for 2 consecutive = converged |
| step_timeout | 30 min | Per-step Worker timeout |
| retry_count | 2 | Transient failure retries before giving up |
| researcher_mode | modify-only | `modify-only` or `create-allowed` |
