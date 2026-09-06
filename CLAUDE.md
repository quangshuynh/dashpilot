# CLAUDE.md

Read `AGENTS.md` and `context.md` before substantial work.

`AGENTS.md` contains the repository-wide engineering rules and is authoritative for architecture, privacy, domain semantics, testing, persistence, documentation, and Git safety.

`context.md` contains the current implementation state, schema/export versions, active limitations, verification baseline, and recommended next interval. It is ignored by Git and must never be committed.

Before modifying code:
1. Read these three files.
2. Inspect `git status` and recent history.
3. Inspect only the implementation, tests, and docs relevant to the requested interval.
4. Source code overrides stale context.

For bounded development intervals:
- create/use the requested local branch
- stay inside the requested scope
- make coherent local commits
- run relevant tests during implementation
- run the full required validation before completion
- update docs when behavior changes
- replace stale information in `context.md`
- leave the working tree clean

Claude may create/switch local branches and commit.

Never automatically push, merge, force push, open a PR, tag, release, or modify remotes.

At completion report:
- objective
- branch and commits
- schema/export contract decisions
- important semantics
- UI/accessibility
- privacy
- verification
- issues discovered
- known limitations
- recommended next interval

Do not begin the recommended next interval.

Do not use em dashes in repository-facing prose.