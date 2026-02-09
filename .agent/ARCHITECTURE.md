# Antigravity Kit Architecture

> **Platform Infrastructure Edition** - Specialized AI Agent Capability Toolkit

---

## 📋 Overview

The Antigravity Kit in this repository is highly specialized for **Cloud-Native Infrastructure, GitOps, and Platform Engineering**. It has been trimmed of generic web/mobile bloat to ensure high performance and context accuracy.

- **7 Specialist Agents** - Role-based AI personas
- **12 Skills** - Domain-specific knowledge modules
- **10 Workflows** - Slash command procedures
- **4 Master Scripts** - Validation and session management

---

## 🏗️ Directory Structure

```plaintext
.agent/
├── ARCHITECTURE.md          # This file
├── agents/                  # 7 Specialist Agents
├── skills/                  # 10 Skills
├── workflows/               # 10 Slash Commands
├── rules/                   # Global Rules (GEMINI.md)
└── scripts/                 # Master Validation & Management Scripts
```

---

## 🤖 Agents (7)

Specialist AI personas for technical infrastructure and automation.

| Agent                  | Focus                      | Key Skills Used                                     |
| ---------------------- | -------------------------- | --------------------------------------------------- |
| `orchestrator`         | Multi-agent coordination   | parallel-agents, intelligent-routing                |
| `project-planner`      | Discovery, task planning   | brainstorming, plan-writing, decision-making        |
| `devops-engineer`      | CI/CD, IaC, Automation     | server-management, lint-and-validate                |
| `security-auditor`     | Security compliance        | vulnerability-scanner, code-review-checklist        |
| `debugger`             | Root cause analysis        | systematic-debugging, clean-code                    |
| `documentation-writer` | Technical manuals, docs    | documentation-templates                             |
| `explorer-agent`       | Codebase analysis          | (Native discovery tools)                            |

---

## 🧩 Skills (12)

Modular knowledge domains loaded on-demand.

| Category | Skill | Description |
| :--- | :--- | :--- |
| **Strategy** | `brainstorming` | Socratic discovery and problem mapping |
| | `plan-writing` | Structured task breakdown and dependencies |
| | `decision-making` | Manage Architecture Decision Records (ADRs) |
| **Logic** | `clean-code` | Universal coding standards |
| | `intelligent-routing` | Context-aware agent selection |
| **Technical** | `server-management` | Infrastructure and process management |
| | `systematic-debugging` | 4-phase root cause analysis |
| **Quality** | `lint-and-validate` | Code quality and schema enforcement |
| | `code-review-checklist` | Security and quality standards |
| **Automation** | `parallel-agents` | Multi-agent coordination patterns |
| | `documentation-templates`| Standardized technical documentation |
| | `skill-creator` | Create and standardize new agent skills |

---

## 🔄 Workflows (10)

Slash command procedures. Invoke with `/command`.

| Command | Description |
| :--- | :--- |
| `/brainstorm` | Socratic discovery and architecting |
| `/create` | Generate new features or infrastructure layers |
| `/debug` | Phase-based troubleshooting |
| `/deploy` | Execute deployment procedures |
| `/enhance` | Refactor or improve existing components |
| `/orchestrate` | Multi-agent collaboration for complex tasks |
| `/plan` | Generate `{task-slug}.md` for new work |
| `/preview` | Preview operational status/changes |
| `/status` | Check project health and agent progress |
| `/test` | Run validation suites and specific tests |

---

## 🎯 Scripts (4)

Master scripts used for validation and environment management.

| Script | Purpose |
| :--- | :--- |
| `checklist.py` | Priority-based validation (Security, Lint, Schema) |
| `verify_all.py` | Comprehensive verification suite |
| `session_manager.py` | Manages AI session state and context |
| `auto_preview.py` | Automates the preview of operational changes |

---

## 🎯 Usage Protocol

1.  **Read Rules:** Every session starts with `rules/GEMINI.md`.
2.  **Plan First:** Use `/plan` or the `project-planner` to create a technical breakdown.
3.  **Validate Constantly:** Use `checklist.py` after every non-trivial change.
4.  **Log technical debt:** Add any out-of-scope findings to `planning/BACKLOG.md`.
