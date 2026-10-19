# content/: every number a designer might tune

Text resources (`.tres`) with a schema script that has a `validate()` method; `tools/ci/run_tests.gd` loads every file here and fails CI on any schema problem (CLAUDE.md, "Content"). Numbers are authored in BUILD.md's design units (units, units per second, frames, percent) and converted to core units once, at load, with integer rounding (ADR-0003).

When a number here changes, the same commit adds a feel log entry (`docs/feel_log/`) and updates BUILD.md, so the doc stays the spec.

A Votive is `votives/<id>.tres` (the `Votive` schema: tier, stacking curve, triggers, numbers, the two item lines and the in-world line's author) with its listener script `votives/<id>.gd` beside it. The script extends `VotiveListener` and acts only through the API it is handed; CI holds it to the core's rules and the API boundary (no state of its own, no classes but the API's, no numbers of its own: they belong in the `.tres`). Adding a Votive never touches `core/` (docs/adr/0015). A Votive that can proc also gets its grey-box look in `votive_looks.tres`.
