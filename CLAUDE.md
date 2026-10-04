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
mkdir -p build/web && godot --headless --path . --export-release "Web" build/web/index.html  # needs the web_nothreads templates
(cd proxy && node --test)                                                   # Claude proxy (Cloudflare Worker) tests
```

- **Godot binary.** Set `GODOT=/path/to/godot` if `godot` isn't on PATH.
- **Fresh clones** need `godot --headless --path . --import` once to build the `class_name` cache. `run_tests.sh` does this for you.
- **CI** (`.github/workflows/ci.yml`) runs `tools/run_tests.sh` on Godot 4.3 and 4.7.
- **Pages** (`.github/workflows/pages.yml`) runs the same script on every push to `main`, applies the `SYNAPSE_LLM_*` repository variables with `tools/configure_web_build.gd`, then exports the Web preset with Godot 4.3 and deploys it to https://shotif.github.io/synapse-2076/.
- **LLM proxy** (`.github/workflows/llm-proxy.yml`, manual) tests and deploys `proxy/` to Cloudflare Workers. CI runs its tests on every push.

## Architecture rules

- **Headless-first.** Everything in `core/`, `entities/` and `systems/` extends `RefCounted` and must run without a scene tree. The only exception is `systems/llm/llm_service.gd`, a `Node` because `HTTPRequest` needs the tree. UI (`ui/`) and 3D (`viewports_3d/`) code binds through engine signals and never mutates simulation state directly. Player input goes through `SimulationEngine.submit_player_turn()`.
- **Deterministic.** All simulation randomness comes from `engine.rng`, which is seeded per campaign. Never call the global `randf()`/`randi()` in simulation code; the UI and 3D code may. Autonomous decisions are applied in `SimConstants.FACTION_ORDER` regardless of arrival order, and `HeuristicFallback` is a pure function of its input.
- **One mutation path.** Directives, crisis options, emergences, paradigm shifts and collapses are declarative effect dictionaries applied by `core/effect_resolver.gd`. World values change only through `WorldState.apply_delta()`/`set_value()`, which clamp to [0, 100], sanitize NaN/inf, and apply the interpretability drift multiplier. Faction currencies change through `ActorBase.add_resource()`.
- **LLM output is untrusted.** Route it through `PromptTemplates.validate_decision()`. Escape any text shown in BBCode labels with `CyberPalette.escape_bbcode()`. Never commit API keys: they come from `user://synapse_llm.cfg`, `SYNAPSE_LLM_API_KEY` or the web page URL (`#llm-key=`), never from `project.godot`, and never from a GitHub secret or variable for the public Pages build (`tools/configure_web_build.gd` refuses them).
- **Claude requests** use the Messages API (`/v1/messages`, auto-detected): `x-api-key`, `anthropic-version: 2023-06-01`, no `temperature`/`top_p`/`top_k` (current models reject non-default values), `output_config.effort` only where `LLMService.supports_effort()` allows it (not Haiku 4.5), `max_tokens` sized for thinking (`CLAUDE_MAX_TOKENS`), and replies read by text block, never `content[0]`. The optional `proxy/` Worker forwards only that shape.
- **Responsive UI.** `UiLayout.compute()` picks the desktop layout (1600x900 canvas) or the compact phone layout (about 1 logical px per CSS px) from the window size and device pixel ratio. `MainDashboard.set_compact()` switches the panels to WORLD / ACT / INTEL / LOG tabs and calls `set_compact()` on every component. On phones nothing may force a width: wrap or clip labels and check boxes, and keep the desktop look when `compact` is false. Dialogs use `UiLayout.build_overlay()` so they scroll. Call `UiLayout.pass_touch_through()` on scrollable content so drags reach the ScrollContainer. `test_ui_dashboard.gd` fails if any visible control overflows a 412 px phone on any tab or dialog.
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
9. **The Web build is single-threaded.** Keep `variant/thread_support=false`: GitHub Pages can't send COOP/COEP headers, so a threaded build won't start there. Export into `build/`, whose `.gdignore` stops Godot from importing the output and packing it into the next export. Web builds never auto-probe the default localhost LLM endpoint (`LLMService.should_auto_probe()`).
10. **`PanelContainer` and `Button` default to `MOUSE_FILTER_STOP`.** A touch drag that starts on one never reaches the enclosing `ScrollContainer`, so phones can't scroll. `UiLayout.pass_touch_through()` switches them to PASS; Godot then cancels the pressed button once the drag turns into a scroll.
11. **A `ScrollContainer` with horizontal scrolling off is as wide as its content plus the vertical scrollbar.** A full-width phone panel then overflows by the bar's width; compact overlays hide the bar (`SCROLL_MODE_SHOW_NEVER`, drag still scrolls).
12. **`HBoxContainer`/`VBoxContainer` can't change orientation at runtime** ("Can't change orientation"). Use a plain `BoxContainer` and set `vertical` when a row must stack on phones.
13. **`RichTextLabel` has no touch-drag scrolling in 4.3.** Put it in a `ScrollContainer` with `fit_content = true` (the event feed does).

## Layout

`core/` simulation engine and math · `entities/` factions · `systems/` compute physics, crisis deck, LLM layer · `ui/` dashboard and components · `viewports_3d/` globe, lattice and shaders · `tests/unit/` suites (one file per area) · `tools/` lint, Monte Carlo and capture scripts · `docs/` model spec, design directions and screenshots · `proxy/` optional Claude API proxy (Cloudflare Worker, plain JS, Node tests).
