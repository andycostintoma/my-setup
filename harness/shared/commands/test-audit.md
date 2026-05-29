---
description: Deep analysis of test completeness, determinism, and best practices
subtask: true
---
Run a comprehensive test audit.

Core questions to answer:
1. Are tests complete — do they cover meaningful edge cases?
2. Are there redundant or useless tests?
3. Are key cases missing? Are we testing too much at expensive layers?
4. Are all tests deterministic — will they always pass regardless of run order or time?
5. Are all tests idempotent — can they run multiple times without failing?
6. Is DB setup/cleanup safe even on failure? Are we polluting any shared database?
7. Are tests fast enough? Where are the bottlenecks?
8. Are some tests hiding bugs or working around code issues?

Files to review (use the project's actual test layout — check AGENTS.md/Makefile;
e.g. `*_test.go` for Go, `*.test.ts`/`*.spec.ts` for TS, `test_*.py`/`*_test.py`
for Python):
- All test files in the project
- Test helpers and fixtures
- Test infrastructure (Docker, emulator, etc.)
- The project's test guidelines (if they exist)
- Source files being tested

Run the project's test targets (check AGENTS.md or Makefile/Taskfile for commands).

Output:
- Findings categorized by priority (critical, medium, low)
- Exact file paths and line numbers
- Actionable recommendations
- Update test guidelines or PLAN.md with new discoveries if the project uses them
