# ADR-0002: Promote GDScript type and safety warnings to errors; allow integer division

- Status: Accepted
- Date: 2026-10-16
- BUILD.md sections: 13 (static analysis gate)
- Checklist lines: Process, "CI is green: ... lint"

## Summary

- Every GDScript warning guarding typing or correctness is level 2 (error) in `project.godot`; `tools/ci/run_tests.gd` compiles every script (see Decision 1).
- `integer_division`, `inferred_declaration` and `return_value_discarded` are off; negatives use `Fx.div_floor`/`Fx.div_round` (see Decisions 2 to 4).
- Calls that return an `Error` must be checked; reviewers enforce it (see Decision 4).
- `missing_await` is level 2; only `res://addons/gdUnit4` is exempt, first-party editor plugins get the full policy (see Decisions 5 and 6).
- `ci/lint.sh` rejects `@warning_ignore`, gdlint/gdformat suppression comments and untyped `Array`/`Dictionary` (see Decision 7).
- `tests/unit/test_toolchain.gd` asserts every level and fails on a Godot warning this ADR has not assigned (see Decision 8).

## Context

CLAUDE.md: "GDScript with static typing everywhere: typed variables, typed signatures, typed arrays. `@warning_ignore` is never used to silence a type warning." BUILD.md section 13: static analysis "zero warnings". Godot reports GDScript warnings to the editor, not to a headless run, so a warning set to level 1 can never fail CI.

The simulation core is integer arithmetic by design (CLAUDE.md rule 2, ADR-0003). Godot's `INTEGER_DIVISION` warning fires on every `int / int`, which in `core/` is the intended operation, not a mistake.

## Decision

1. In `project.godot`, every GDScript warning that guards typing or correctness is level 2 (error): untyped declarations, every `unsafe_*` warning, unused variables and parameters, shadowing, unreachable code, narrowing conversions, enum misuse, confusable identifiers and the rest listed there. A script that would warn does not compile, and `tools/ci/run_tests.gd` compiles every script in the project, so CI fails.
2. `integer_division` is off (level 0). Integer division truncates toward zero in GDScript; the core must not rely on that for negative numbers and instead uses explicit rounding helpers (`Fx.div_floor`, `Fx.div_round`, built in Phase 1 task 1 with unit tests for negative operands; ADR-0003).
3. `inferred_declaration` is off: `var x := expr` is statically typed by inference and is allowed.
4. `return_value_discarded` is off. Discarding explicitly is possible (`var _x := f()`), but every gdUnit4 assertion returns its assert object, so the warning would demand a throwaway variable on nearly every test line. Calls that return an `Error` (file and save code) must check it; reviewers enforce this.
5. `missing_await` is level 2: calling a coroutine without `await` is an error.
6. Only `res://addons/gdUnit4` (vendored) is excluded from warnings, as it is from lint. First-party editor plugins under `res://addons/` (the room editor, task 7) get the full policy.
7. `@warning_ignore` and gdlint/gdformat suppression comments do not appear in first-party code; `ci/lint.sh` greps for them. The same script rejects untyped `Array` and `Dictionary` declarations, parameters and return types (CLAUDE.md: "typed arrays"); engine APIs that return untyped containers are read through typed locals.
8. `tests/unit/test_toolchain.gd` asserts every warning level listed here and fails if Godot adds a warning this ADR has not assigned a level, so no gate can be lowered silently.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Keep warnings at level 1 and parse the editor's output | Headless runs never print them; the gate would be decorative |
| Leave `integer_division` on and wrap every division in a helper with `@warning_ignore` | Hundreds of annotations whose only purpose is to silence a warning about the intended arithmetic |

## Feel reason

None directly. Strict typing keeps the integer core from silently becoming a float core, which would break determinism and every replay fixture.

## Consequences

Tests and tools are held to the same rules as the game. Any new warning category in a Godot upgrade is reviewed in the upgrade task.
