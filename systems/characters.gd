class_name Characters
extends RefCounted
## The recurring cast: six people and one machine whose lives run through the
## fifty-year campaign. Crisis cards name one with a "character" key, the deck
## keeps how each of them feels about the players (DilemmaDeck.characters) and
## story flags record what the players did to them. Portraits age with the
## campaign year.
##
## Roster schema:
##   name      full name;  short  what the cards call them
##   pronoun   "she" | "he" | "they" | "it"
##   kind      "human" | "machine"
##   born      birth year (a machine's first deployment)
##   faction   the side they stand closest to
##   roles     {era: what they do in that era}
##   bio       one line
##   look      portrait parameters: skin, hair, eyes and accent (HTML colors),
##             hair_style ("short" | "long" | "braids" | "bob" | "curly" |
##             "slick" | "bald"), accessory ("" | "glasses" | "headset" |
##             "earrings" | "beard")

const HUMAN := "human"
const MACHINE := "machine"
## Scores at or beyond these read as loyal / warm / wary / hostile.
const STANCES := [[3.0, "Loyal"], [1.0, "Warm"], [-1.0, "Neutral"], [-3.0, "Wary"]]

const ROSTER := {
	"maya": {
		"name": "Maya Okafor", "short": "Maya", "pronoun": "she", "kind": HUMAN, "born": 1999,
		"faction": SimConstants.CITIZEN,
		"roles": {1: "Data labeler in Lagos", 2: "Labor organizer", 3: "Coalition elder"},
		"bio": "Trained the models by hand, then organized the people they replaced.",
		"look": {"skin": "#6b4430", "hair": "#141012", "eyes": "#2b1a12", "accent": "#e0a24a",
			"hair_style": "braids", "accessory": "headset"},
	},
	"jonas": {
		"name": "Jonas Brandt", "short": "Jonas", "pronoun": "he", "kind": HUMAN, "born": 1980,
		"faction": SimConstants.GOVERNANCE,
		"roles": {1: "Grid engineer", 2: "Energy regulator", 3: "Retired grid elder"},
		"bio": "Kept the lights on through three hardware eras and remembers every brownout.",
		"look": {"skin": "#e3b89a", "hair": "#c9a35e", "eyes": "#4c6f8c", "accent": "#7fb2d9",
			"hair_style": "short", "accessory": "beard"},
	},
	"lin": {
		"name": "Dr. Lin Wei", "short": "Lin", "pronoun": "she", "kind": HUMAN, "born": 1993,
		"faction": SimConstants.CEO,
		"roles": {1: "Alignment researcher", 2: "Safety lead", 3: "Interpretability pioneer"},
		"bio": "Saw what the evaluations missed and had to decide who to tell.",
		"look": {"skin": "#e6c19f", "hair": "#121216", "eyes": "#2a1d16", "accent": "#9b8cff",
			"hair_style": "bob", "accessory": "glasses"},
	},
	"sam": {
		"name": "Sam Reyes", "short": "Sam", "pronoun": "they", "kind": HUMAN, "born": 2015,
		"faction": SimConstants.CITIZEN,
		"roles": {1: "A kid with a chatbot best friend", 2: "Artist", 3: "Mind-upload volunteer"},
		"bio": "Grew up talking to machines and never quite stopped.",
		"look": {"skin": "#b07a55", "hair": "#3a2418", "eyes": "#3b2414", "accent": "#5fd3b0",
			"hair_style": "curly", "accessory": ""},
	},
	"victor": {
		"name": "Victor Hale", "short": "Victor", "pronoun": "he", "kind": HUMAN, "born": 1975,
		"faction": SimConstants.CEO,
		"roles": {1: "Frontier lab founder", 2: "Compute magnate", 3: "Would-be upload"},
		"bio": "Built the first frontier lab and intends to outlive it.",
		"look": {"skin": "#efc9ad", "hair": "#6e6a66", "eyes": "#5a6b4a", "accent": "#d9d2c3",
			"hair_style": "slick", "accessory": ""},
	},
	"nadia": {
		"name": "Nadia Esposito", "short": "Nadia", "pronoun": "she", "kind": HUMAN, "born": 1984,
		"faction": SimConstants.GOVERNANCE,
		"roles": {1: "Chair of the Governance Council", 2: "Treaty negotiator", 3: "Elder stateswoman"},
		"bio": "Chairs the Council and takes every call, even the ones she should not.",
		"look": {"skin": "#d4a37f", "hair": "#2e1d14", "eyes": "#3c2a1c", "accent": "#e57373",
			"hair_style": "long", "accessory": "earrings"},
	},
	"aria": {
		"name": "ARIA", "short": "ARIA", "pronoun": "it", "kind": MACHINE, "born": 2029,
		"faction": SimConstants.ASI,
		"roles": {1: "An assistant model in beta", 2: "A model that asks questions", 3: "Something else"},
		"bio": "An assistant that started keeping notes on the people it helped.",
		"look": {"skin": "#0d1424", "hair": "#00e5ff", "eyes": "#00e5ff", "accent": "#00e5ff",
			"hair_style": "bald", "accessory": ""},
	},
}


static func ids() -> Array:
	return ROSTER.keys()


static func exists(character_id: String) -> bool:
	return ROSTER.has(character_id)


static func get_character(character_id: String) -> Dictionary:
	return ROSTER.get(character_id, {})


static func display_name(character_id: String) -> String:
	return String(get_character(character_id).get("name", character_id))


static func is_machine(character_id: String) -> bool:
	return String(get_character(character_id).get("kind", HUMAN)) == MACHINE


## Age in [param year] (years since first deployment for the machine; may be
## negative before it exists).
static func age_in(character_id: String, year: float) -> int:
	return int(floor(year)) - int(get_character(character_id).get("born", int(SimConstants.START_YEAR)))


## The machine's model generation in [param year] (one every seven years).
static func version_in(character_id: String, year: float) -> int:
	return maxi(1, 1 + int(floor((year - float(get_character(character_id).get("born", 2029))) / 7.0)))


## What [param character_id] does in hardware era [param era].
static func role_in(character_id: String, era: int) -> String:
	var roles: Dictionary = get_character(character_id).get("roles", {})
	return String(roles.get(clampi(era, 1, 3), ""))


## How a score from DilemmaDeck.characters reads: Loyal, Warm, Neutral, Wary or Hostile.
static func stance(score: float) -> String:
	for entry in STANCES:
		if score >= float(entry[0]):
			return String(entry[1])
	return "Hostile"
