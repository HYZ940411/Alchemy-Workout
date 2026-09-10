# Feature Specification: Adversarial Prompt Self-Optimization System

**Feature Branch**: `001-adversarial-prompt-rl`
**Created**: 2026-02-19
**Status**: Draft
**Input**: User description: "4-agent adversarial architecture for automated prompt engineering reinforcement learning — Controller orchestrates experiments, Worker executes prompts statelessly, Reviewer scores outputs and suggests optimizations, Researcher modifies prompts based on feedback."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Single Experiment Run (Priority: P1)

A prompt engineer wants to validate a prompt pipeline (e.g., 7-8 sequential steps) by running a full experiment end-to-end without manual intervention. The Controller agent reads the pipeline definition, creates an experiment folder in the configured workspace, and sequentially dispatches each step's prompt (file path + arguments) to a fresh Worker agent. The Worker executes the prompt, interacts with the Controller for any clarification loops, produces artifacts, and terminates. After each step completes, the Controller commits the output. At the end, the experiment folder contains one commit per step — a complete, reproducible record of the run.

**Why this priority**: This is the foundational capability. Without a reliable single-run mechanism, neither review nor optimization can happen.

**Independent Test**: Can be fully tested by configuring a 3-step prompt pipeline, running one experiment, and verifying 3 commits are created with the correct artifacts in the experiment folder.

**Acceptance Scenarios**:

1. **Given** a prompt pipeline with N steps and a configured workspace, **When** the Controller starts an experiment, **Then** an experiment folder is created and one Worker is dispatched per step sequentially.
2. **Given** a Worker is dispatched with a prompt path and arguments, **When** the Worker encounters a clarification question, **Then** the Controller answers on behalf of the user, and the Worker continues to completion.
3. **Given** a Worker completes a step, **When** the Controller receives the output, **Then** the output is committed with a message identifying the step number and prompt name.
4. **Given** all N steps are completed, **When** the experiment finishes, **Then** exactly N commits exist in the experiment folder, each traceable to its corresponding prompt step.

---

### User Story 2 - Review and Scoring (Priority: P2)

After an experiment run completes, the Reviewer agent examines the committed outputs. The Reviewer knows the scoring criteria for each step's expected output quality. It navigates the experiment's commit history, extracts each commit's artifacts, evaluates them against the criteria, and produces a structured review report. The report includes per-step scores, identified weaknesses, and specific optimization suggestions with evidence from the output.

**Why this priority**: Review is the feedback signal that drives optimization. Without scoring, there is no basis for improvement.

**Independent Test**: Can be tested by providing a completed experiment (with commits) and a scoring rubric, then verifying the Reviewer produces a report with per-step scores and actionable suggestions.

**Acceptance Scenarios**:

1. **Given** a completed experiment with N commits and a scoring rubric, **When** the Reviewer runs, **Then** a review report is produced with a score for each step.
2. **Given** a step's output has identifiable quality issues, **When** the Reviewer evaluates it, **Then** the report cites specific evidence from the output and suggests concrete improvements.
3. **Given** the Reviewer completes its evaluation, **When** the report is finalized, **Then** it includes: per-step scores, overall experiment score, a ranked list of optimization priorities, and the scoring criteria used.

---

### User Story 3 - Adversarial Optimization Loop (Priority: P3)

The prompt engineer initiates an optimization cycle. The Controller runs an experiment (Story 1), then the Reviewer evaluates it (Story 2). Based on the Reviewer's feedback, the Researcher agent modifies the prompt files to address identified weaknesses. The Researcher operates under a configurable mode: modify-only (can only edit existing prompt files) or create-allowed (can also add new prompt files, split large prompts into smaller ones, or add intermediate steps). The Controller then runs a new experiment with the updated prompts. This cycle repeats until prompts converge (scores stabilize or reach a target threshold). Each iteration is tracked as a separate experiment folder with its own commit history, allowing comparison across iterations.

**Why this priority**: This is the full adversarial loop — the core value proposition. It depends on Stories 1 and 2 being solid.

**Independent Test**: Can be tested by running 2-3 optimization iterations on a simple pipeline and verifying that scores improve or stabilize across iterations.

**Acceptance Scenarios**:

1. **Given** a Reviewer report with optimization suggestions, **When** the Controller starts a new iteration, **Then** it dispatches the Researcher to modify prompt files based on the suggestions before running the next experiment.
2. **Given** multiple iterations have been completed, **When** scores are compared across iterations, **Then** a clear trend is visible (improvement or convergence).
3. **Given** scores have stabilized (delta below a configured threshold across consecutive iterations), **When** the system evaluates convergence, **Then** the optimization loop terminates and a final summary is produced containing: best iteration number + overall score, score progression table across all iterations, convergence status, and path to the best run folder's prompts.
4. **Given** a maximum iteration count is configured, **When** the limit is reached without convergence, **Then** the loop terminates and produces the same final summary, with convergence status marked as "hit max iterations".

---

### Edge Cases

- What happens when a Worker fails mid-step? → Experiment aborts, Researcher optimizes the failing prompt based on failure context (without Reviewer).
- What happens when the Controller cannot answer a Worker's clarification question? → Not applicable. The Controller is the prompt's issuer (PM role); the Worker is the executor (RD role). The Controller always has authority to answer based on its own intent and context — just as a PM answers an RD's question.
- What happens when the Reviewer's scoring criteria are inconsistent or contradictory? → Reviewer proceeds with best-effort interpretation and notes inconsistencies as warnings in the review report alongside the scores. It does not block or refuse to evaluate.
- What happens when prompt modifications make a previously passing step regress? → No special mechanism. The Reviewer scores all steps every iteration, so regressions appear as score drops and get prioritized in the next optimization round. The loop is self-correcting.
- What happens when the prompt pipeline definition itself is invalid (missing steps, circular dependencies)? → Controller validates the pipeline YAML before starting any experiment. If invalid, it rejects immediately with a descriptive error. No experiment folder is created, no Workers are dispatched.
- What happens when the orchestration script or an agent crashes mid-experiment? → For transient failures (network errors, API timeouts), the orchestration script retries up to 2 times. If still failing, the interrupted experiment is left as-is (partial commits in run folder). The user manually restarts, and the script picks up from the last completed iteration by scanning existing run folders.

### Out of Scope

- Parallel step execution — all steps run sequentially within an experiment.
- Branching or conditional pipelines — steps are a flat, ordered list.
- Multi-user concurrent access to the same workspace.
- Remote workspaces — workspace is local filesystem only.
- Automatic rubric generation — rubrics are always user-provided.
- Cross-pipeline comparison — each optimization cycle operates on a single pipeline.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST support four distinct agent roles: Controller, Worker, Reviewer, and Researcher, each running as a standalone Claude Agent SDK process orchestrated by an external script. This ensures full programmatic control over agent lifecycle, context isolation, and inter-agent communication.
- **FR-002**: Controller MUST create a new, uniquely identified experiment folder for each experiment run within the configured workspace.
- **FR-003**: Controller MUST dispatch prompts to Worker by providing only the prompt file path and arguments — no additional context from the Controller's own state.
- **FR-004**: Worker MUST execute each prompt in a fresh, stateless context with no knowledge of prior steps or experiments.
- **FR-005**: Worker MUST be able to send clarification questions back to the Controller during execution. The Controller acts as the prompt's issuer (PM role) and MUST answer based on its own intent and pipeline context — there is no escalation path or "unanswerable" state.
- **FR-006**: Controller MUST commit the output of each completed step as a separate, identifiable commit.
- **FR-007**: Reviewer MUST be able to navigate the experiment's commit history and extract per-step outputs.
- **FR-008**: Reviewer MUST evaluate each step's output against a predefined scoring rubric and produce a structured review report.
- **FR-009**: Reviewer's review report MUST include: per-step scores, overall score, specific evidence for each score, and ranked optimization suggestions. The report MUST be committed as a file inside the experiment's run folder (e.g., `run-001/review-report.md`).
- **FR-010**: Controller MUST copy prompt files into the run folder before each experiment. Original prompt files remain intact; each run folder contains the exact prompt versions used for that experiment.
- **FR-010a**: The Researcher agent MUST modify the copied prompt files based on Reviewer feedback. The Researcher operates under a configurable mode:
  - **Modify-only** (default): Can only edit existing prompt files — no new files, no step additions or removals.
  - **Create-allowed**: Can also create new prompt files, split large prompts into smaller ones, merge prompts, or add/remove intermediate steps. If steps change, the Researcher MUST update the pipeline YAML accordingly.
- **FR-011**: System MUST track each optimization iteration as a separate experiment, preserving full history for cross-iteration comparison.
- **FR-012**: System MUST detect convergence (score stabilization below a configurable threshold) and terminate the loop automatically.
- **FR-013**: System MUST enforce a configurable maximum iteration count (default: 10) as a safety stop. Both successful and failed experiments count toward this limit to guarantee termination.
- **FR-014**: When a Worker fails mid-step, the experiment MUST be aborted immediately and marked as failed. The Controller MUST skip the Reviewer and dispatch the Researcher to optimize the failing prompt based on the failure context, then start a new experiment.
- **FR-015**: A failed experiment MUST NOT be sent to the Reviewer for scoring — the Researcher handles prompt optimization based on failure context, bypassing the Reviewer.
- **FR-016**: Controller MUST validate the pipeline YAML before starting any experiment. If the pipeline is invalid (missing prompt files, zero steps, structural errors), the Controller MUST reject immediately with a descriptive error. No experiment folder is created and no Workers are dispatched.
- **FR-017**: The orchestration script MUST log progress to stdout in real-time: iteration number, step number, step status (running/done/failed), and per-iteration overall scores as they become available from Reviewer reports.
- **FR-018**: The orchestration script MUST retry transient failures (network errors, API timeouts) up to 2 times before giving up. After exhausting retries, the interrupted experiment is left as-is with partial commits. On manual restart, the script MUST scan existing run folders to determine the last completed iteration and resume from there.
- **FR-019**: The orchestration script MUST enforce a configurable per-step timeout (default: 30 minutes). If a Worker exceeds the timeout, the step is treated as a failure and triggers the same abort-and-self-fix path as FR-014.

### Key Entities

- **Experiment**: A single end-to-end run of the prompt pipeline, stored as a subfolder (e.g., `run-001/`, `run-002/`) within the workspace. Contains an ordered set of step outputs, each stored as a commit prefixed with the run number. Belongs to an optimization cycle.
- **Step**: One prompt execution within an experiment. Has a sequence number, prompt file path, arguments, output artifacts, and a commit reference. Artifacts are whatever files the Worker generates — no fixed format. The Controller commits the entire run folder diff after each step completes.
- **Review Report**: The Reviewer's evaluation of one experiment, committed as a file inside the experiment's run folder (e.g., `run-001/review-report.md`). Contains per-step scores, overall score, evidence citations, and optimization suggestions.
- **Optimization Cycle**: A series of experiments linked by Reviewer feedback. Tracks iteration count, score progression, and convergence status. Upon termination, produces a final summary containing: best iteration number + overall score, score progression table (all iterations), convergence status (converged / hit max), and path to the best run folder's prompts.
- **Researcher**: The agent responsible for optimizing prompts based on Reviewer feedback (or failure context). Operates under a configurable mode: modify-only or create-allowed. Receives the current prompt files, the Reviewer's report (or failure details), and produces updated prompt files (and optionally an updated pipeline YAML in create-allowed mode).
- **Scoring Rubric**: A structured markdown file defining per-step evaluation dimensions. Each dimension has a name, description, weight (relative importance), and pass/fail threshold. All scores use a 0–100 integer scale. The overall step score is the weighted sum of dimension scores (0–100). The overall experiment score is the average of all step scores.

## Assumptions

- The prompt pipeline is defined as a YAML configuration file listing steps in order, each referencing a prompt path and default arguments. The prompts themselves remain general-purpose; the pipeline config is project-specific and passed to the Controller skill as an argument.
- Each prompt file is a self-contained, reusable instruction that a Worker can execute independently given only the file path and arguments from the pipeline config.
- The workspace is a local filesystem directory with version control initialized.
- Scoring rubrics are provided by the user before the first Reviewer run — the system does not generate rubrics automatically.
- The Controller answers Worker clarification questions using its knowledge of the overall pipeline context and the user's original requirements.
- Convergence is defined as score delta below threshold for 2 consecutive iterations (configurable). Default convergence threshold: 3 points (on 0–100 scale).
- Maximum iteration count defaults to 10 if not configured.
- Each agent (Controller, Worker, Reviewer, Researcher) runs as a standalone Claude Agent SDK process. An external orchestration script manages agent lifecycle, invocation order, and data passing between agents. This provides full programmatic control — no reliance on Claude Code's built-in sub-agent spawning.

## Clarifications

### Session 2026-02-19

- Q: What format should the scoring rubric take? → A: Structured markdown — per-step dimensions with name, weight, and pass/fail threshold. Overall step score = weighted sum.
- Q: What format should the pipeline definition take? → A: YAML config file listing ordered steps with prompt path + arguments. Prompts stay general-purpose; the config is project-specific and passed to the Controller as an argument.
- Q: How are experiments organized in the workspace? → A: Subfolders (`run-001/`, `run-002/`) in one branch. Commits prefixed with run number for easy filtering and cross-iteration comparison.
- Q: How does the Controller modify prompts between iterations? → A: Copy-on-write — prompts are copied into the run folder and modified there. Originals stay intact. Each run folder is self-contained with its exact prompt versions.
- Q: What happens when the Controller cannot answer a Worker's clarification? → A: Not applicable — Controller is the prompt's issuer (PM role), Worker is the executor (RD role). Controller always has authority to answer based on its own intent, like a PM answering an RD's question.
- Q: What happens when the pipeline definition is invalid? → A: Controller validates the YAML before starting. If invalid, rejects immediately with descriptive error — no experiment folder created, no Workers dispatched (fail-fast).
- Q: What happens when prompt modifications cause a previously passing step to regress? → A: No special mechanism — the Reviewer scores all steps every iteration, so regressions appear as score drops and get prioritized in the next optimization round. The loop is self-correcting.
- Q: What happens when the Reviewer's scoring criteria are inconsistent or contradictory? → A: Reviewer proceeds with best-effort interpretation and notes inconsistencies as warnings in the review report. It does not block or refuse to evaluate.
- Q: Where is the review report stored? → A: Committed as a file inside the experiment's run folder (e.g., `run-001/review-report.md`), maintaining the self-contained principle. Reproducible from commit history (SC-006).
- Q: What score scale do scores use? → A: 0–100 integer scale. Each dimension scored 0–100, weighted sum = step score (0–100), average of step scores = overall experiment score. SC-003's "10%" means 10 points on this scale.
- Q: What is explicitly out of scope? → A: Parallel step execution, branching/conditional pipelines, multi-user concurrent access, remote workspaces, automatic rubric generation, cross-pipeline comparison.
- Q: How do the agents execute? → A: Each agent (Controller, Worker, Reviewer, Researcher) runs as a standalone Claude Agent SDK process. An external orchestration script manages lifecycle and data passing — full programmatic control, no reliance on Claude Code sub-agent spawning.
- Q: What does the final summary contain? → A: Best iteration number + overall score, score progression table (all iterations), convergence status (converged / hit max), and path to the best run folder's prompts.
- Q: How does the user monitor progress? → A: Orchestration script logs to stdout in real-time — iteration number, step number, step status (running/done/failed), and per-iteration scores as available.
- Q: What format are step output artifacts? → A: No fixed format — each step produces whatever files the Worker generates (depends on the prompt). Controller commits the entire run folder diff after each step.
- Q: What happens on orchestration script crash? → A: Retry transient failures (network, API timeout) up to 2 times. After exhausting retries, leave interrupted experiment as-is. On manual restart, scan existing run folders to resume from last completed iteration.
- Q: Is there a per-step timeout? → A: Yes, configurable with default 30 minutes. If exceeded, step is treated as failure → triggers FR-014 abort-and-self-fix path.
- Q: What is the default convergence threshold? → A: 3 points (on 0–100 scale). Score delta below 3 for 2 consecutive iterations = converged.
- Q: Who optimizes prompts, and can they create new ones? → A: The Researcher agent (4th role) modifies prompts based on Reviewer feedback. Configurable mode: modify-only (default, edit existing only) or create-allowed (can add/split/merge prompts and update pipeline YAML).
- Q: Do failed experiments count toward the max iteration limit? → A: Yes. Both successful and failed experiments count. 10 total experiments (any status) = stop. Guarantees termination.
- Q: What parameters are configurable? → A: All configurable parameters with defaults: max iterations (10), convergence threshold (3 points), per-step timeout (30 min), retry count (2), Researcher mode (modify-only).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A full experiment run (7-8 steps) completes autonomously without human intervention, producing one commit per step.
- **SC-002**: The Reviewer produces a structured report within one pass over the experiment's commit history, with scores for 100% of steps.
- **SC-003**: After 3 optimization iterations, prompt quality scores (0–100 scale) improve by at least 10 points compared to the initial run, or converge within the configured threshold.
- **SC-004**: The system detects convergence and terminates autonomously within 10 iterations for a typical prompt pipeline.
- **SC-005**: Worker failures abort the experiment cleanly — the Researcher optimizes the failing prompt and the Controller starts a new experiment without Reviewer involvement.
- **SC-006**: Each experiment's full history (prompts used, outputs, scores) is reproducible from the commit history alone.
