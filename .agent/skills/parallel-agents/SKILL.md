---
name: parallel-agents
description: Multi-agent orchestration patterns. Use when multiple independent tasks can run with different domain expertise or when comprehensive analysis requires multiple perspectives.
allowed-tools: Read, Glob, Grep
---

# Native Parallel Agents

> Orchestration through Antigravity's built-in Agent Tool

## Overview

This skill enables coordinating multiple specialized agents through Antigravity's native agent system. Unlike external scripts, this approach keeps all orchestration within Antigravity's control.

## When to Use Orchestration

✅ **Good for:**
- Complex tasks requiring multiple expertise domains
- Code analysis from security, performance, and quality perspectives
- Comprehensive reviews (architecture + security + testing)
- Feature implementation needing backend + frontend + database work

❌ **Not for:**
- Simple, single-domain tasks
- Quick fixes or small changes
- Tasks where one agent suffices

---

## Native Agent Invocation

### Single Agent
```
Use the security-auditor agent to review authentication
```

### Sequential Chain
```
First, use the explorer-agent to discover project structure.
Then, use the devops-engineer to review IaC configuration.
Finally, use the security-auditor to identify security gaps.
```

### With Context Passing
```
Use the devops-engineer to analyze Ansible playbooks.
Based on those findings, have the security-auditor review vault encryption.
```

### Resume Previous Work
```
Resume agent [agentId] and continue with additional requirements.
```

---

## Orchestration Patterns

### Pattern 1: Infrastructure Review
```
Agents: explorer-agent → devops-engineer → security-auditor → synthesis

1. explorer-agent: Map IaC/Config structure
2. devops-engineer: Tofu/Ansible quality
3. security-auditor: Security posture & Vault
4. Synthesize all findings
```

### Pattern 2: Implementation Sweep
```
Agents: devops-engineer → security-auditor

1. Identify affected layers (IaC? Config? K8s?)
2. devops-engineer implements/validates
3. security-auditor verifies security hardening
4. Synthesize recommendations
```

### Pattern 3: Debugging Deep Dive
```
Agents: explorer-agent → debugger → devops-engineer → synthesis

1. explorer-agent: Trace error in codebase
2. debugger: Perform root cause analysis
3. devops-engineer: Apply fix to infrastructure/config
4. Synthesize with validation results
```

---

## Available Agents

| Agent | Expertise | Trigger Phrases |
|-------|-----------|-----------------|
| `orchestrator` | Coordination | "comprehensive", "multi-perspective" |
| `project-planner` | Planning | "plan", "roadmap", "milestones" |
| `devops-engineer` | DevOps & Infra | "deploy", "CI/CD", "infrastructure", "ansible", "tofu" |
| `security-auditor` | Security | "security", "auth", "vulnerabilities", "vault", "hardening" |
| `debugger` | Debugging | "bug", "error", "not working", "crash" |
| `explorer-agent` | Discovery | "explore", "map", "structure", "list" |
| `documentation-writer` | Documentation | "write docs", "create README", "generate guide" |

---

## Antigravity Built-in Agents

These work alongside custom agents:

| Agent | Model | Purpose |
|-------|-------|---------|
| **Explore** | Haiku | Fast read-only codebase search |
| **Plan** | Sonnet | Research during plan mode |
| **General-purpose** | Sonnet | Complex multi-step modifications |

Use **Explore** for quick searches, **custom agents** for domain expertise.

---

## Synthesis Protocol

After all agents complete, synthesize:

```markdown
## Orchestration Synthesis

### Task Summary
[What was accomplished]

### Agent Contributions
| Agent | Finding |
|-------|---------|
| security-auditor | Found X |
| devops-engineer | Identified Y |

### Consolidated Recommendations
1. **Critical**: [Issue from Agent A]
2. **Important**: [Issue from Agent B]
3. **Nice-to-have**: [Enhancement from Agent C]

### Action Items
- [ ] Fix hardening issue
- [ ] Refactor Ansible playbooks
- [ ] Verify security group rules
```

---

## Best Practices

1. **Available agents** - 7 specialized technical agents can be orchestrated
2. **Logical order** - Discovery → Planning → Implementation → Verification
3. **Share context** - Pass relevant findings to subsequent agents
4. **Single synthesis** - One unified report, not separate outputs
5. **Verify changes** - Always include security-auditor for sensitive changes

---

## Key Benefits

- ✅ **Single session** - All agents share context
- ✅ **AI-controlled** - Claude orchestrates autonomously
- ✅ **Native integration** - Works with built-in Explore, Plan agents
- ✅ **Resume support** - Can continue previous agent work
- ✅ **Context passing** - Findings flow between agents
