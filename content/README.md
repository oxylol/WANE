# content/: every number a designer might tune

Text resources (`.tres`) with a schema script that has a `validate()` method; `tools/ci/run_tests.gd` loads every file here and fails CI on any schema problem (CLAUDE.md, "Content"). Numbers are authored in BUILD.md's design units (units, units per second, frames, percent) and converted to core units once, at load, with integer rounding (ADR-0003).

When a number here changes, the same commit adds a feel log entry (`docs/feel_log/`) and updates BUILD.md, so the doc stays the spec.
