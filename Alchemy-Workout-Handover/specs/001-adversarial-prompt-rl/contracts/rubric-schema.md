# Scoring Rubric Schema

Defines the structure of scoring rubric files used by the Reviewer agent.

## Format

Structured markdown file with per-step sections. Each step section contains a dimensions table.

```markdown
# Scoring Rubric: <pipeline-name>

## Step: <step-id>

### Dimensions

| Dimension | Description | Weight | Pass Threshold |
|-----------|-------------|--------|----------------|
| <name>    | <what it measures> | <0-100> | <0-100> |

**Total weight: 100**
```

## Field Definitions

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| `pipeline-name` | string | H1 heading — matches Pipeline.name | Required |
| `step-id` | string | H2 heading — matches Step.id in pipeline | Required. Must exist in pipeline |
| Dimension.name | string | Column 1 — dimension identifier | Required. Unique within step |
| Dimension.description | string | Column 2 — what this dimension measures | Required |
| Dimension.weight | integer | Column 3 — relative importance | Required. 0-100. All weights in step MUST sum to 100 |
| Dimension.pass_threshold | integer | Column 4 — minimum passing score | Required. 0-100 |

## Scoring Conventions

- **Score per dimension**: 0-100 integer, assigned by Reviewer based on output quality
- **Step score**: `sum(score_i * weight_i) / 100` — weighted sum, yields 0-100
- **Experiment score**: average of all step scores — yields 0-100
- **Step pass/fail**: A step fails if ANY dimension score < its pass_threshold, regardless of aggregate score
- **Pass threshold guide**:
  - 90+: Hard constraints (schema validity, language match, format compliance)
  - 70-80: Quality dimensions (accuracy, relevance, completeness)
  - 60: Soft stylistic preferences (tone, conciseness)

## Validation Rules

Reviewer MUST warn (but not block) if:
1. A step in the pipeline has no corresponding rubric section (unscored step)
2. Weights in a step section do not sum to 100
3. Dimension names are ambiguous or overlapping

## Example

```markdown
# Scoring Rubric: customer-support-triage

## Step: classify

### Dimensions

| Dimension  | Description                                    | Weight | Pass Threshold |
|------------|------------------------------------------------|--------|----------------|
| accuracy   | Intent label matches ground-truth category     | 50     | 70             |
| confidence | Appropriate certainty; avoids hedging          | 30     | 60             |
| format     | Output is valid JSON matching expected schema   | 20     | 80             |

**Total weight: 100**

---

## Step: draft-reply

### Dimensions

| Dimension      | Description                                    | Weight | Pass Threshold |
|----------------|------------------------------------------------|--------|----------------|
| relevance      | Reply addresses the specific issue raised      | 40     | 75             |
| tone           | Language is professional and empathetic         | 30     | 70             |
| conciseness    | Under word limit; no filler or repetition      | 20     | 60             |
| language_match | Written in the requested language (zh-TW)      | 10     | 90             |

**Total weight: 100**

---

## Step: review-reply

### Dimensions

| Dimension       | Description                                             | Weight | Pass Threshold |
|-----------------|---------------------------------------------------------|--------|----------------|
| issue_detection | Correctly flags factual errors or tone problems         | 45     | 70             |
| completeness    | Reviews all criteria (accuracy, tone, completeness)     | 35     | 80             |
| actionability   | Feedback is specific enough to act on                   | 20     | 65             |

**Total weight: 100**
```
