class_name Difficulty
extends RefCounted
## Difficulty presets. They change only the people playing (their starting
## resources, income and crisis prices) and how hard the autonomous factions
## push; the world model itself is the same in every preset, except that drift
## accrues a little faster on Hard and slower on Story.

const STORY := "story"
const STANDARD := "standard"
const HARD := "hard"
const ORDER := [STORY, STANDARD, HARD]

const PRESETS := {
	STORY: {
		"name": "Story", "summary": "More resources, cheaper crises and calmer rivals. For reading the world as it unfolds.",
		"start_resources": 1.3, "income": 1.25, "crisis_costs": 0.75,
		"rival_intensity_bonus": 0.0, "injection_skip_chance": 0.5, "drift_accrual": 0.85, "goal_rewards": 1.25,
	},
	STANDARD: {
		"name": "Standard", "summary": "The balance the campaign was tuned for.",
		"start_resources": 1.0, "income": 1.0, "crisis_costs": 1.0,
		"rival_intensity_bonus": 0.0, "injection_skip_chance": 0.0, "drift_accrual": 1.0, "goal_rewards": 1.0,
	},
	HARD: {
		"name": "Hard", "summary": "Leaner budgets, pricier crises and rivals who push harder. Drift builds faster.",
		"start_resources": 0.85, "income": 0.9, "crisis_costs": 1.25,
		"rival_intensity_bonus": 0.25, "injection_skip_chance": 0.0, "drift_accrual": 1.15, "goal_rewards": 0.8,
	},
}


static func is_valid(preset_id: String) -> bool:
	return PRESETS.has(preset_id)


## [param key] of [param preset_id] (Standard when the preset is unknown).
static func value(preset_id: String, key: String) -> float:
	var preset: Dictionary = PRESETS.get(preset_id, PRESETS[STANDARD])
	return float(preset.get(key, PRESETS[STANDARD].get(key, 1.0)))


static func display_name(preset_id: String) -> String:
	return String(PRESETS.get(preset_id, PRESETS[STANDARD])["name"])
