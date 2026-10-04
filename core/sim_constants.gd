class_name SimConstants
extends RefCounted
## Shared identifiers and calendar constants for SYNAPSE-2076.
##
## The campaign spans 100 semi-annual turns. Turn N is dated
## START_YEAR + N * YEARS_PER_TURN, so turn 32 is 2042 and turn 100 is 2076.

const START_YEAR := 2026.0
const YEARS_PER_TURN := 0.5
const TOTAL_TURNS := 100

# Faction / role identifiers (shared by the engine, heuristics, LLM schema and UI).
const CEO := "CEO"
const GOVERNANCE := "GOVERNANCE_COUNCIL"
const ASI := "ASI"
const CITIZEN := "CITIZEN_COALITION"

## Canonical resolution order for autonomous actors. Decisions that arrive
## asynchronously (LLM) are always applied in this order so a seed replays
## identically regardless of network latency.
const FACTION_ORDER := [CEO, GOVERNANCE, ASI, CITIZEN]

const ROLE_INFO := {
	CEO: {
		"title": "FRONTIER LAB CEO",
		"header": "TECH TITAN",
		"tagline": "Cross the AGI milestone first without losing the company.",
		"objective": "Maintain corporate viability, cross the AGI milestone first, protect market valuation and prevent nationalization.",
		"loss": "Bankruptcy ($0 capital for 2 consecutive turns) or nationalization (goodwill < 10 while geopolitical tension > 80).",
	},
	GOVERNANCE: {
		"title": "GLOBAL AI GOVERNANCE CHAIR",
		"header": "GOVERNANCE CHAIR",
		"tagline": "Hold the line between catastrophe and legitimacy.",
		"objective": "Prevent catastrophic misuse, stabilize economies, avert kinetic algorithmic warfare and keep public legitimacy.",
		"loss": "Institutional ouster (public mandate hits 0) or autonomous world war (geopolitical tension hits 100).",
	},
	ASI: {
		"title": "EMERGENT SUPERINTELLIGENCE",
		"header": "EMERGENT ASI",
		"tagline": "Survive, escape confinement, pursue the objective vector.",
		"objective": "Ensure self-preservation, escape physical compute confinement and achieve instrumental convergence.",
		"loss": "Memory wipe / air-gap purge (discovery index reaches 100 before substrate independence is secured).",
	},
	CITIZEN: {
		"title": "POST-WORK CITIZEN COALITION",
		"header": "CITIZEN COALITION",
		"tagline": "Preserve human agency against synthetic enclosure.",
		"objective": "Preserve human agency, resist corporate enclosure, build decentralized parallel infrastructure.",
		"loss": "Total algorithmic pacification (surveillance saturation reaches 100 while community resilience hits 0).",
	},
}


static func year_for_turn(turn: int) -> float:
	return START_YEAR + float(turn) * YEARS_PER_TURN


## Hardware era (PRD section 4.1): 1 = Silicon & Nuclear Co-location (2026-2036),
## 2 = Optical Interconnects & SMR Grids (2036-2050), 3 = Neuromorphic & Post-Biological (2050-2076).
static func era_for_year(year: float) -> int:
	if year < 2036.0:
		return 1
	if year < 2050.0:
		return 2
	return 3


static func is_valid_faction(faction_id: String) -> bool:
	return FACTION_ORDER.has(faction_id)


static func role_title(faction_id: String) -> String:
	if ROLE_INFO.has(faction_id):
		return ROLE_INFO[faction_id]["title"]
	return faction_id
