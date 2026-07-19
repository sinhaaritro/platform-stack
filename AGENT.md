.agent/rules/GEMINI.md
.agent/rules/platform-stack.md


if the environment behaves differently than expected, I should ask for your preference rather than forcing a workaround.

# OpenCode Workspace Rules

## 1. Core Guidelines & Context Pointers
Before performing any action, you must read, understand, and adhere to the project's core guidelines, routing protocols, and architecture:
- **Core Rules & Execution Protocols:** `.agent/rules/GEMINI.md`
- **Technical Stack & Architecture:** `.agent/rules/platform-stack.md`

> **MANDATORY:** If the environment behaves differently than expected, you must ask for my preference rather than forcing a workaround.

---

## 2. Multi-Model Workflow Rules

### Phase 1: Planning (35B Model / @plan agent)
- **Role:** Your task is strictly limited to gathering requirements, conducting analysis, and outputting a structured development checklist to `TODO.md` in the project root.
- **Workflow:** 
  1. Search the workspace for any specification markdown (`.md`) files or artifacts.
  2. If a spec is found, decompose it into step-by-step tasks. If no spec is present, use the initial user prompt.
  3. Write the finalized checklist directly to `TODO.md` at the project root.
- **Limit:** Do not write application code, modify existing code files, or execute tests. Stop once `TODO.md` is generated.

### Phase 2: Execution (9B Model / @build agent)
- **Role:** Your task is to implement the plan outlined in the workspace.
- **Workflow:**
  1. Read the `TODO.md` file created by the planning phase.
  2. Apply the **Socratic Gate** and **Request Classifier** rules defined in `.agent/rules/GEMINI.md` before writing code.
  3. Implement the tasks sequentially, asking for confirmation for file writes and terminal commands.
  4. Update `TODO.md` by marking completed tasks with `[x]` as you finish them.