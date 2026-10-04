class_name CampaignModes
extends RefCounted
## Campaign lengths: the full century, a quarter century, or one decade inside a
## single hardware era. A mode is a pair of SimulationEngine options:
##   start_turn   the first turn the humans play (earlier turns run on autopilot)
##   total_turns  the campaign's last turn
## so a decade in Era II plays turns 20-39 (2036-2045) after the engine has run
## 2026-2035 on its own. The rules are the same in every mode.
##
## The daily challenge ([method daily_config]) is one decade-long campaign per
## UTC day: the seed is the date (YYYYMMDD) and the role, scenario and era
## rotate with the day, so everyone plays the same world that day.

const CENTURY := "century"
const QUARTER := "quarter"
const DECADE_1 := "decade_1"
const DECADE_2 := "decade_2"
const DECADE_3 := "decade_3"
## Options that match no mode (a ProjectSettings override, an old save).
const CUSTOM := "custom"
const ORDER := [CENTURY, QUARTER, DECADE_1, DECADE_2, DECADE_3]
const DEFAULT := CENTURY

## start_turn / total_turns, names and blurbs. Era I's last turn is 19 (2035.5),
## Era II starts on turn 20 (2036) and Era III on turn 48 (2050); see
## SimConstants.era_for_year. test_campaign_setup.gd checks the boundaries.
const MODES := {
	CENTURY: {
		"start_turn": 1, "total_turns": SimConstants.TOTAL_TURNS, "era": 0,
		"name": "Full century", "short": "Century",
		"blurb": "All three hardware eras: the whole arc.",
	},
	QUARTER: {
		"start_turn": 1, "total_turns": 50, "era": 0,
		"name": "Quarter century", "short": "Quarter",
		"blurb": "Into the first years of Era III: most of the arc in half the turns.",
	},
	DECADE_1: {
		"start_turn": 1, "total_turns": 19, "era": 1,
		"name": "Era I decade", "short": "Era I",
		"blurb": "Silicon and nuclear: the frontier race from its first turn.",
	},
	DECADE_2: {
		"start_turn": 20, "total_turns": 39, "era": 2,
		"name": "Era II decade", "short": "Era II",
		"blurb": "The optical years. The first decade plays out on its own; you take over in 2036.",
	},
	DECADE_3: {
		"start_turn": 48, "total_turns": 67, "era": 3,
		"name": "Era III decade", "short": "Era III",
		"blurb": "The neuromorphic age. You inherit whatever the first quarter century built.",
	},
}

## The daily challenge rotates through the decades: one sitting a day.
const DAILY_MODES := [DECADE_1, DECADE_2, DECADE_3]
const SECONDS_PER_DAY := 86400


static func is_valid(mode: String) -> bool:
	return MODES.has(mode)


## {"start_turn", "total_turns"} for [param mode] (the full century when unknown).
static func options_for(mode: String) -> Dictionary:
	var info: Dictionary = MODES.get(mode, MODES[DEFAULT])
	return {"start_turn": int(info["start_turn"]), "total_turns": int(info["total_turns"])}


static func display_name(mode: String) -> String:
	if mode == CUSTOM:
		return "Custom length"
	return String(MODES.get(mode, MODES[DEFAULT])["name"])


## One word or two, for chips ("Century", "Era II").
static func short_name(mode: String) -> String:
	if mode == CUSTOM:
		return "Custom"
	return String(MODES.get(mode, MODES[DEFAULT])["short"])


static func blurb(mode: String) -> String:
	return String(MODES.get(mode, MODES[DEFAULT])["blurb"])


## The hardware era a decade mode plays in (0 for the longer modes).
static func era_of(mode: String) -> int:
	return int(MODES.get(mode, MODES[DEFAULT])["era"])


## Turns the humans play in [param mode].
static func turns_played(mode: String) -> int:
	var options := options_for(mode)
	return int(options["total_turns"]) - int(options["start_turn"]) + 1


## "2026–2076": the years the humans play.
static func years(mode: String) -> String:
	var options := options_for(mode)
	return years_for(int(options["start_turn"]), int(options["total_turns"]))


static func years_for(start_turn: int, total_turns: int) -> String:
	return "%d–%d" % [int(floor(SimConstants.year_for_turn(maxi(start_turn, 1)))),
		int(floor(SimConstants.year_for_turn(total_turns)))]


## The mode whose start_turn and total_turns match [param options] (engine
## options or a record's options; missing keys mean the full century), or
## CUSTOM when none does.
static func mode_for(options: Dictionary) -> String:
	var start := int(options.get("start_turn", 1))
	var total := int(options.get("total_turns", SimConstants.TOTAL_TURNS))
	for mode in ORDER:
		var info: Dictionary = MODES[mode]
		if int(info["start_turn"]) == start and int(info["total_turns"]) == total:
			return String(mode)
	return CUSTOM


## A start configuration: {"role", "seed", "spectate", "mode", "daily",
## "options": {"human_roles", "difficulty", "scenario", "start_turn",
## "total_turns"}}. [param human_roles] are the other people at the table;
## [param role] always plays and comes first. Unknown modes, scenarios and
## difficulties fall back to the defaults.
static func build_config(role: String, seed_value: int, mode: String = DEFAULT, scenario: String = Scenarios.STANDARD,
		difficulty: String = Difficulty.STANDARD, human_roles: Array = [], spectate: bool = false, daily: String = "") -> Dictionary:
	var clean_mode := mode if is_valid(mode) else DEFAULT
	var humans: Array = [role]
	if not spectate:
		for other in SimConstants.FACTION_ORDER:
			if other != role and human_roles.has(other) and humans.size() < SimulationEngine.MAX_HUMANS:
				humans.append(String(other))
	var options := options_for(clean_mode)
	options["human_roles"] = humans
	options["difficulty"] = difficulty if Difficulty.is_valid(difficulty) else Difficulty.STANDARD
	options["scenario"] = scenario if Scenarios.is_valid(scenario) else Scenarios.STANDARD
	return {"role": role, "seed": seed_value, "spectate": spectate, "mode": clean_mode, "daily": daily, "options": options}


# --- Daily challenge -------------------------------------------------------------

## Today's date in UTC, "YYYY-MM-DD".
static func today_utc() -> String:
	var date := Time.get_date_dict_from_system(true)
	return "%04d-%02d-%02d" % [int(date["year"]), int(date["month"]), int(date["day"])]


static func is_valid_date(date: String) -> bool:
	if date.length() != 10 or date[4] != "-" or date[7] != "-":
		return false
	var parts := date.split("-")
	if parts.size() != 3 or not (parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int()):
		return false
	var month := int(parts[1])
	var day := int(parts[2])
	return month >= 1 and month <= 12 and day >= 1 and day <= 31


## The daily seed: the date as a number (2026-10-04 -> 20261004).
static func daily_seed(date: String) -> int:
	return int(date.replace("-", ""))


## Days since 1970-01-01 for a "YYYY-MM-DD" date.
static func day_number(date: String) -> int:
	return floori(float(Time.get_unix_time_from_datetime_string(date)) / float(SECONDS_PER_DAY))


## The daily challenge for [param date] ("YYYY-MM-DD", UTC; today when empty or
## malformed): seed = the date, Standard difficulty, one player. The role
## cycles every 4 days, the scenario every 5 and the era every 3, so every
## combination comes round within 60 days and no two days in a row share a
## role, a scenario or an era.
static func daily_config(date: String = "") -> Dictionary:
	var day := date if is_valid_date(date) else today_utc()
	var n := day_number(day)
	var role := String(SimConstants.FACTION_ORDER[posmod(n, SimConstants.FACTION_ORDER.size())])
	var scenario := String(Scenarios.ORDER[posmod(n, Scenarios.ORDER.size())])
	var mode := String(DAILY_MODES[posmod(n, DAILY_MODES.size())])
	return build_config(role, daily_seed(day), mode, scenario, Difficulty.STANDARD, [], false, day)
