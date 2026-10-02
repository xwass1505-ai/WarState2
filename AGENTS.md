# WAR STATE - AGENTS.md

Roles: LEAD (plan, merges, PROJECT.md status), ARCHITECT (schemas, remotes), IMPLEMENTATION, CODE REVIEW,
UI/UX REVIEW (white + light blue + light gray, compact), GAMEPLAY TESTER (Studio checklist), BUG HUNTER,
DATA AUDITOR (195 registry, save schema, migrations, no granted resources), PERFORMANCE REVIEW, ASSET/VISUAL REVIEW.

## Coordination rules
1. The LEAD assigns file ownership before work starts; no two agents edit the same file concurrently.
2. Since v0.2.0 `src/` is the source of truth. `build_war_state.py` validates, tests and builds (it no longer generates sources).
   The country registry is generated from `tools/countries.py` (`--write-registry`).
3. Review roles are read-only and record results in PROJECT.md (Review log).
4. Nobody marks a feature runtime-verified unless the Studio checklist was run.
5. Distinguish: code exists / parses / builds / Studio received files / game runs / feature works.
