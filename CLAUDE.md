# CLAUDE.md: working on SYNAPSE-2076

A Godot 4.3+ (GDScript) turn-based simulation. Read `README.md` for the product and `docs/SIMULATION_MODEL.md` for the math.

## Commands

```bash
tools/run_tests.sh                          # ALWAYS run before committing: import + lint + unit tests + 100-turn sim
tools/run_tests.sh --suite=dilemma          # one suite (substring of tests/unit/test_*.gd)
tools/run_tests.sh --suite=engine --filter=async
godot --headless --path . --script res://tools/check_scripts.gd             # compile every script/shader/scene
godot --headless --path . --script res://tools/monte_carlo.gd -- --runs=60  # balance report (run after touching the model)
godot --headless --path . --script res://tests/headless_sim_test.gd        # PRD smoke test
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 \
  --script res://tools/capture_dashboard.gd -- --out=/tmp/shots             # screenshot the real UI (no GPU needed)
```

- **Godot binary.** Set `GODOT=/path/to/godot` if `godot` isn't on PATH.
- **Fresh clones** need `godot --headless --path . --import` once to build the `class_name` cache. `run_tests.sh` does this for you.
- **CI** (`.github/workflows/ci.yml`) runs `tools/run_tests.sh` on Godot 4.3 and 4.7.

## Architecture rules

- **Headless-first.** Everything in `core/`, `entities/` and `systems/` extends `RefCounted` and must run without a scene tree. The only exception is `systems/llm/llm_service.gd`, a `Node` because `HTTPRequest` needs the tree. UI (`ui/`) and 3D (`viewports_3d/`) code binds through engine signals and never mutates simulation state directly. Player input goes through `SimulationEngine.submit_player_turn()`.
- **Deterministic.** All simulation randomness comes from `engine.rng`, which is seeded per campaign. Never call the global `randf()`/`randi()` in simulation code; the UI and 3D code may. Autonomous decisions are applied in `SimConstants.FACTION_ORDER` regardless of arrival order, and `HeuristicFallback` is a pure function of its input.
- **One mutation path.** Directives, crisis options, emergences, paradigm shifts and collapses are declarative effect dictionaries applied by `core/effect_resolver.gd`. World values change only through `WorldState.apply_delta()`/`set_value()`, which clamp to [0, 100], sanitize NaN/inf, and apply the interpretability drift multiplier. Faction currencies change through `ActorBase.add_resource()`.
- **LLM output is untrusted.** Route it through `PromptTemplates.validate_decision()`. Escape any text shown in BBCode labels with `CyberPalette.escape_bbcode()`. Never commit API keys: they come from `user://synapse_llm.cfg` or `SYNAPSE_LLM_API_KEY`, never from `project.godot`.
- **The engine pauses at two points.** `advance()` stops after presenting the player phase and after each turn's telemetry. Autoplay therefore needs two calls per turn, and `run_headless()` handles that.

## Extending

- **New directive:**
  1. Add an entry to the faction's `ACTIONS` with `name`, `description`, `cost`, `cooldown`, `effects` and `statement`, using the effect schema in `effect_resolver.gd`.
  2. Add a rule to the faction's tree in `systems/llm/heuristic_fallback.gd` so the AI uses it.
  3. `tests/unit/test_factions.gd::test_catalog_effects_reference_known_keys` validates every key automatically.
- **New crisis card:** add a template to `DilemmaDeck.CARDS`. Every role must see at least 2 options (use `"roles"` for role-specific ones) and every option needs a `cost` or `cost_tier`. `test_dilemma_deck.gd` enforces this. Set `"injection_only": true` for cards that only autonomous factions trigger (through `"inject_dilemma"` in an action's effects).
- **Model or balance change:**
  1. Edit the named constants (`WorldState.K_*`, `*_REINFORCEMENT`, `ComputeScaling`, `TechTreeManager`).
  2. Run `tools/monte_carlo.gd` before and after the change.
  3. Keep `tests/unit/test_balance.gd` green.
  4. Update `docs/SIMULATION_MODEL.md` and its balance snapshot.
- **New end-state rule:** `core/victory_matrix.gd` holds the `OUTCOMES` (in priority order), `ROLE_OUTCOME_VALUE` and `CATASTROPHE_OUTCOMES`.

## GDScript / Godot 4.3 gotchas hit in this codebase

1. **`:=` on a Variant expression is a parse error** (INFERENCE_ON_VARIANT is an error by default). This shows up with loop variables over untyped arrays (`for x in [1.0, 2.0]`), dictionary values, and ternaries mixing types. Annotate the type instead: `var y: float = ...`.
2. **Packed arrays inside a Dictionary are copies.** `(dict["buf"] as PackedByteArray).append_array(x)` silently does nothing. Read the array into a local, modify it, and assign it back.
3. **A `SceneTree` script's `_initialize()` runs before the root window joins the tree.** `HTTPRequest`, timers and scene nodes added there aren't inside the tree yet, so `await process_frame` first. The test runner already does this.
4. **`class_name` globals only resolve after an import.** Run `--import` on fresh clones and in CI. Test suites extend the framework by path (`extends "res://tests/framework/test_case.gd"`).
5. **GDScript runtime errors don't change the exit code.** `tools/run_tests.sh` fails if output contains `SCRIPT ERROR`. A test that reports "no assertions ran" usually aborted on an error.
6. **The headless dummy renderer prints `mesh_get_surface_count` errors** when a mesh instance and its mesh are freed together. Viewports call `GlobeViewport.release_meshes(self)` in `_exit_tree()`, and line meshes are rebuilt in place (`clear_surfaces()`) instead of being replaced.
7. **`const` Dictionaries and Arrays are read-only.** `duplicate(true)` before mutating templates (see `DilemmaDeck._resolve_option`).
8. **Don't load class_name scripts with `CACHE_MODE_IGNORE`:** it can segfault 4.3 (seen in `tools/check_scripts.gd`).

## Layout

`core/` simulation engine and math · `entities/` factions · `systems/` compute physics, crisis deck, LLM layer · `ui/` dashboard and components · `viewports_3d/` globe, lattice and shaders · `tests/unit/` suites (one file per area) · `tools/` lint, Monte Carlo and capture scripts · `docs/` model spec and screenshots.
