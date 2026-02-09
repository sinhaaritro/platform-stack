---
name: decision-making
description: Comprehensive workflow for managing Architecture Decision Records (ADRs). Use when you need to propose, accept, supersede, or query architectural decisions. Supports creating new ADRs from a standard template and maintaining the decision log in `planning/adr/`.
allowed-tools: Read, Write, List, Grep, Copy
---

# Decision Making (ADR) Skill

> This skill manages the lifecycle of Architecture Decision Records (ADRs) in `planning/adr/`.

## Overview

Architecture Decision Records (ADRs) capture important architectural decisions, along with their context and consequences. This skill provides a standardized way to create and manage these records.

## Workflow Rules

### 1. Creating a New Decision
To propose a new architectural decision:

1.  **Scan:** List files in `planning/adr/` to find the highest number (e.g., `0005-foo.md`).
2.  **Increment:** The new file must be `planning/adr/XXXX-kebab-case-title.md` (4 digits, zero-padded).
    *   Example: If `0005` exists, create `0006`.
3.  **Copy Template:** Read content from `assets/adr.md` and write it to the new file.
4.  **Fill Details:** Update the Title, Status (to **Proposed**), Date, Author, and Context.

### 2. Accepting a Decision
To mark a proposed decision as accepted:

1.  **Update Status:** Change `Status: Proposed` to `Status: Accepted`.
2.  **Date:** Update `Date: [YYYY-MM-DD]` to the current date.

### 3. Superseding a Decision
To replace an old decision with a new one:

1.  **Identify:** Find the *old* ADR that is being replaced (e.g., `0002-old-db.md`).
2.  **Update Old:**
    *   Change Status to `Superseded`.
    *   Add a note at the top: `> Superseded by [0006-new-db.md](./0006-new-db.md)`
3.  **Create New:** Create the new ADR with `Status: Accepted` and mention the old one in the "Context" section.

---

## 3. Bundled Resources

### assets/
*   `adr.md`: The canonical template for all new ADRs.

### scripts/
*   (None currently - logic is simple enough for text instructions)

### references/
*   (None currently - standard format is self-explanatory)
