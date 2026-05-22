---
description: Scan for stubs, architecture violations, and structural code smells
subtask: true
---
Run a comprehensive code audit. Focus on things linters cannot catch.

Architecture layer violations (adapt to the project's layer definitions from AGENTS.md):
- Domain: business rules only, no infrastructure or transport leakage
- Application: orchestration only, no domain policy shortcuts or adapter knowledge
- Ports: mapping and validation only, no business logic
- Adapters: persistence/integration only, no business policy decisions

Linter-invisible issues:
- Stub or placeholder implementations (hardcoded returns, hidden TODO paths)
- Missing domain validations, invariant leaks, weak error semantics
- Useless/redundant comments (describe WHAT, not WHY) — delete them
- Open architectural questions embedded in code
- Unclear patterns or incomplete features

Manual-review smell checklist (treat as first-class audit targets):
- Responsibilities collapsed together that should be separated
- Weak or misleading naming that hides intent
- Helper signatures that are hard to understand or easy to misuse
- Forced shared request/command shapes where use cases have different semantics (share mechanics, not shape)
- Data modeling that doesn't match the business concept cleanly
- Test setup that contains hidden business behavior instead of only wiring/fixtures
- Policy drift between docs, scenarios, and implementation
- Validation/error design that makes debugging or API behavior less precise than it should be
- Ownership/auth flows that trust caller-supplied IDs when actor identity should be source of truth
- Abstractions that add indirection without improving clarity
- When you find one structural smell, scan sibling flows for the same pattern class

Scope: all source files under the project's main source directories (check AGENTS.md for structure).

Output format:
1. Categorize by priority (critical, medium, low)
2. Exact file paths and line numbers for each finding
3. Why it matters (correctness, isolation, architectural drift, performance, maintainability)
4. Actionable recommendation for each finding
5. Update PLAN.md with new open issues discovered if the project uses one
6. Ask targeted questions when any finding is ambiguous
