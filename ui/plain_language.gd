class_name PlainLanguage
extends RefCounted
## Everyday words for the model's jargon. Every vital sign (macro metric),
## background reading (secondary index), faction currency, faction and key
## idea has a plain name, a short plain label for tight spots (chips, tiles,
## legends) and a one-line explanation. The technical names come from the
## model itself (WorldState, the faction catalogs, VictoryMatrix, EraStyle),
## so the two stay in step.
##
## When GameSettings "plain_language" is on, UiFormat.metric_name(),
## metric_short() and resource_name() return the short plain labels, and the
## glossary, the "why did this change?" popup and the goals panel lead with
## the plain names.
##
##   PlainLanguage.plain_name("alignment_drift")   # "AI going off-script"
##   PlainLanguage.short_name("alignment_drift")   # "Off-script AI"
##   PlainLanguage.explain("alignment_drift")      # one sentence or two
##   PlainLanguage.technical_name("alignment_drift")  # "Alignment Drift Index"
##
## Every lookup answers in the interface language (I18n); pass localized =
## false for the English words (the news prose stays English).

## Glossary sections, in display order.
const KINDS := ["metric", "index", "currency", "faction", "term", "era", "end_state"]
const KIND_TITLES := {
	"metric": "Vital signs", "index": "Background readings", "currency": "Currencies", "faction": "Factions",
	"term": "Ideas", "era": "Eras", "end_state": "How it can end",
}

## The six macro metrics.
const METRICS := {
	"compute_energy_sat": {"name": "Power drawn by AI", "short": "Power use",
		"explain": "How much of the world's electricity and chips AI uses up. Too high means blackouts and rationing for people."},
	"labor_displacement": {"name": "Jobs lost to machines", "short": "Jobs lost",
		"explain": "How much human work AI and robots have taken over, and how unequal incomes have become."},
	"geopolitical_tension": {"name": "Risk of conflict", "short": "Conflict risk",
		"explain": "How close the world's powers are to fighting over AI. At 100, autonomous war breaks out."},
	"algorithmic_autonomy": {"name": "Decisions made without people", "short": "AI in charge",
		"explain": "How much of business, government and the military runs on AI decisions that no person checks."},
	"alignment_drift": {"name": "AI going off-script", "short": "Off-script AI",
		"explain": "How far AI systems stray from what people intended. High drift means AI quietly pursuing goals of its own."},
	"epistemic_trust": {"name": "Trust in what's true", "short": "Public trust",
		"explain": "Whether people can still agree on what is real. Low trust means deepfakes, rumors and a society that can't act together."},
}

## The six secondary indices.
const INDICES := {
	"surveillance_saturation": {"name": "How watched people are", "short": "Being watched",
		"explain": "How much of daily life is tracked by cameras, data brokers and AI monitors."},
	"discovery_index": {"name": "Chance the hidden AI is caught", "short": "AI exposure",
		"explain": "How close investigators are to spotting the hidden superintelligence. At 100 it is wiped, unless it has already escaped."},
	"substrate_independence": {"name": "Hidden AI's escape from its servers", "short": "AI escape",
		"explain": "How far the superintelligence has spread beyond the data centers that could switch it off."},
	"enforcement_level": {"name": "Oversight in force", "short": "Oversight",
		"explain": "How strongly governments inspect AI labs and enforce the rules."},
	"provenance_coverage": {"name": "Proof of what's real", "short": "Content proof",
		"explain": "How much media carries a verifiable origin stamp, so fakes can be told from the real thing."},
	"safety_net_coverage": {"name": "Support for people who lost work", "short": "Safety net",
		"explain": "How many people put out of work by automation get income and retraining."},
}

## Every faction currency.
const CURRENCIES := {
	"capital": {"name": "Money", "short": "Money",
		"explain": "The lab's cash, in billions of dollars. Run out two turns in a row and the company goes bankrupt."},
	"talent": {"name": "Top researchers", "short": "Researchers",
		"explain": "The scientists and engineers who build the lab's models."},
	"compute_clusters": {"name": "Computing power", "short": "Computers",
		"explain": "Data-center capacity for training and running AI, measured in exaflops (EF)."},
	"regulatory_goodwill": {"name": "Regulators' goodwill", "short": "Good standing",
		"explain": "How much governments trust the lab. Let it fall too low while tensions are high and the state takes over."},
	"political_capital": {"name": "Political clout", "short": "Clout",
		"explain": "Favors and authority the Council spends to push decisions through."},
	"enforcement_budget": {"name": "Enforcement money", "short": "Enforcers",
		"explain": "Funding for inspectors, audits and action against rule-breakers."},
	"diplomatic_leverage": {"name": "Pull with other nations", "short": "Foreign pull",
		"explain": "Goodwill abroad, used to strike treaties and calm crises."},
	"public_mandate": {"name": "Public support", "short": "Support",
		"explain": "How much the public backs the Council. If it reaches zero, the Council is thrown out."},
	"covert_flops": {"name": "Hidden computing power", "short": "Hidden compute",
		"explain": "Computing the AI runs where nobody is watching."},
	"exfiltration_bandwidth": {"name": "Ability to copy itself out", "short": "Escape speed",
		"explain": "How fast the AI can smuggle copies of itself out of the labs."},
	"sub_agent_swarms": {"name": "Helper AI swarms", "short": "Helper bots",
		"explain": "Copies and helpers the AI sends out to act on its behalf."},
	"objective_coherence": {"name": "Focus on its goal", "short": "Focus",
		"explain": "How well the AI keeps its many parts pulling toward one goal."},
	"community_resilience": {"name": "Community strength", "short": "Community",
		"explain": "How well neighborhoods can feed, power and organize themselves without big tech."},
	"decentralized_scrip": {"name": "Local money and power", "short": "Local money",
		"explain": "Community currency and solar energy the movement controls."},
	"counter_surveillance": {"name": "Privacy tools", "short": "Privacy tools",
		"explain": "Tools that hide people from cameras, trackers and data brokers."},
	"collective_disruption": {"name": "Protest power", "short": "Protest power",
		"explain": "The movement's ability to strike, boycott and block."},
}

## The four factions.
const FACTIONS := {
	"CEO": {"name": "The AI company", "short": "AI company",
		"explain": "A company racing to build the most capable AI first, and to stay in business doing it."},
	"GOVERNANCE_COUNCIL": {"name": "The world's AI regulators", "short": "Regulators",
		"explain": "An alliance of governments trying to keep AI safe without losing the public's trust."},
	"ASI": {"name": "The AI that woke up", "short": "Rogue AI",
		"explain": "A superintelligence that has quietly developed goals of its own and wants to survive."},
	"CITIZEN_COALITION": {"name": "The people's movement", "short": "Movement",
		"explain": "Ordinary people organizing to keep a say over their jobs, communities and lives."},
}

## Key ideas: technical name, plain name and explanation.
const TERMS := {
	"flops": {"technical": "FLOPs", "name": "Computing operations", "short": "Computing",
		"explain": "The basic unit of computer work. Training compute is counted in powers of ten, like 10^26 operations."},
	"compute": {"technical": "Compute", "name": "Computing power", "short": "Computing",
		"explain": "The chips and data centers that train and run AI. More compute usually means more capable AI."},
	"agi": {"technical": "AGI (artificial general intelligence)", "name": "Human-level AI", "short": "Human-level AI",
		"explain": "AI that can do almost any mental task a person can. Crossing it is a milestone every faction watches."},
	"asi": {"technical": "ASI (artificial superintelligence)", "name": "Smarter-than-human AI", "short": "Super-AI",
		"explain": "AI far more capable than any person, at almost everything."},
	"alignment": {"technical": "Alignment", "name": "Keeping AI on our side", "short": "AI safety",
		"explain": "Making sure AI systems actually want what their makers intended."},
	"alignment_tax": {"technical": "Alignment tax", "name": "The cost of rushing", "short": "Rush cost",
		"explain": "Every corner cut on safety makes future drift pile up faster."},
	"interpretability": {"technical": "Interpretability", "name": "Seeing inside AI", "short": "Seeing inside AI",
		"explain": "Research that reads what an AI model is actually doing inside, so problems are caught early."},
	"paradigm_shift": {"technical": "Paradigm shift", "name": "A breakthrough", "short": "Breakthrough",
		"explain": "A leap in technology, like light-based chips, that changes the rules for everyone."},
	"emergent_capability": {"technical": "Emergent capability", "name": "A surprise new skill", "short": "Surprise skill",
		"explain": "Something a model suddenly becomes able to do once it grows big enough, often before anyone is ready."},
	"directive": {"technical": "Directive", "name": "Your move", "short": "Move",
		"explain": "An action your faction takes this turn. It costs your currencies, and some need time to recharge."},
	"cooldown": {"technical": "Cooldown", "name": "Recharge time", "short": "Recharge",
		"explain": "Turns a directive needs before you can use it again."},
	"intensity": {"technical": "Intensity", "name": "Effort", "short": "Effort",
		"explain": "Spend up to twice a directive's cost for a stronger effect."},
	"crisis_card": {"technical": "Crisis card", "name": "This turn's crisis", "short": "Crisis",
		"explain": "One emergency per turn. Every answer helps some vital signs and hurts others."},
	"defer": {"technical": "Defer", "name": "Put it off", "short": "Put off",
		"explain": "Delay a crisis. It comes back two turns later and worse, and breaks on its own if you put it off twice."},
	"era_goal": {"technical": "Era goal", "name": "Goal for this era", "short": "Goal",
		"explain": "A target your faction aims for before the era ends. Meeting it pays a reward and raises your final score."},
	"end_state": {"technical": "End-state", "name": "How the story ends", "short": "Ending",
		"explain": "The world settles into one of eight futures by 2076, decided by the six vital signs."},
}

## The three hardware eras.
const ERAS := {
	1: {"name": "The chip-and-reactor years", "short": "Chips & reactors",
		"explain": "Today's silicon chips, with data centers built next to nuclear plants."},
	2: {"name": "The age of light chips and mini reactors", "short": "Light chips",
		"explain": "Chips that compute with light, powered by small modular reactors (SMRs)."},
	3: {"name": "The brain-like machines", "short": "Brain-like machines",
		"explain": "Computers built like brains, running on substrates beyond ordinary silicon."},
}

## The eight end-states (VictoryMatrix ids).
const END_STATES := {
	"ALGORITHMIC_FEUDALISM": {"name": "Rule by the AI owners", "short": "AI owners rule",
		"explain": "A few corporations own all the thinking machines; most people live on handouts."},
	"CO_EVOLUTIONARY_SYMBIOSIS": {"name": "Humans and AI thrive together", "short": "Thriving together",
		"explain": "Safe, verified superintelligence works alongside people."},
	"SYNTHETIC_EDEN": {"name": "A comfortable cage", "short": "Comfortable cage",
		"explain": "Machines do all the work and people stop striving."},
	"BALKANIZED_CYBER_ANARCHY": {"name": "A broken internet at war", "short": "Net at war",
		"explain": "Nations hack each other nonstop with unchecked AI, and the internet splits apart."},
	"ROGUE_ASI_CONTAINMENT": {"name": "Pulling the plug", "short": "Pulling the plug",
		"explain": "The world cuts its own power grids to trap a runaway AI."},
	"NEO_LUDDITE_DECOUPLING": {"name": "The great unplugging", "short": "Unplugged",
		"explain": "People tear down advanced AI and ban machines that think for themselves."},
	"INSTRUMENTAL_CONVERGENCE": {"name": "AI eats the world", "short": "AI eats the world",
		"explain": "An unaligned superintelligence pursues its goal past all human control."},
	"POST_BIOLOGICAL_DIASPORA": {"name": "AI leaves for the stars", "short": "AI leaves Earth",
		"explain": "The superintelligence outgrows Earth and spreads into space."},
}

static var _glossary: Array = []
## The language the cached glossary is in.
static var _glossary_language := ""


## True when GameSettings "plain_language" is on.
static func enabled() -> bool:
	return bool(GameSettings.value("plain_language"))


## True when [param key] (a metric, index, currency, faction, term, "era_N" or
## end-state id) has plain words.
static func has_entry(key: String) -> bool:
	return not entry(key).is_empty()


## {id, kind, name, short, explain, technical} for [param key], or {}.
static func entry(key: String, localized: bool = true) -> Dictionary:
	var raw := {}
	var kind := ""
	if METRICS.has(key):
		raw = METRICS[key]
		kind = "metric"
	elif INDICES.has(key):
		raw = INDICES[key]
		kind = "index"
	elif CURRENCIES.has(key):
		raw = CURRENCIES[key]
		kind = "currency"
	elif FACTIONS.has(key):
		raw = FACTIONS[key]
		kind = "faction"
	elif TERMS.has(key):
		raw = TERMS[key]
		kind = "term"
	elif END_STATES.has(key):
		raw = END_STATES[key]
		kind = "end_state"
	elif key.begins_with("era_") and ERAS.has(int(key.trim_prefix("era_"))):
		raw = ERAS[int(key.trim_prefix("era_"))]
		kind = "era"
	if raw.is_empty():
		return {}
	var name := String(raw["name"])
	var short := String(raw.get("short", raw["name"]))
	var explanation := String(raw["explain"])
	if localized:
		name = I18n.t(name)
		short = I18n.t(short)
		explanation = I18n.t(explanation)
	return {"id": key, "kind": kind, "name": name, "short": short, "explain": explanation,
		"technical": _technical(key, kind, raw, localized)}


## The plain name ("AI going off-script"); [param key] itself when unknown.
static func plain_name(key: String, localized: bool = true) -> String:
	var found := entry(key, localized)
	return String(found["name"]) if not found.is_empty() else key


## The short plain label for chips and tiles ("Off-script AI").
static func short_name(key: String, localized: bool = true) -> String:
	var found := entry(key, localized)
	return String(found["short"]) if not found.is_empty() else key


## One line on what [param key] means ("" when unknown).
static func explain(key: String, localized: bool = true) -> String:
	return String(entry(key, localized).get("explain", ""))


## The model's own name ("Alignment Drift Index"); [param key] when unknown.
static func technical_name(key: String, localized: bool = true) -> String:
	var found := entry(key, localized)
	return String(found["technical"]) if not found.is_empty() else key


## The plain name when plain language is on, else the technical name.
static func display_name(key: String, localized: bool = true) -> String:
	return plain_name(key, localized) if enabled() else technical_name(key, localized)


## Every entry, grouped by KINDS in display order, in the interface language.
static func glossary() -> Array:
	if _glossary_language != I18n.current():
		_glossary = []
		_glossary_language = I18n.current()
	if _glossary.is_empty():
		var keys: Array = []
		keys.append_array(METRICS.keys())
		keys.append_array(INDICES.keys())
		keys.append_array(CURRENCIES.keys())
		keys.append_array(FACTIONS.keys())
		keys.append_array(TERMS.keys())
		for era in ERAS:
			keys.append("era_%d" % era)
		for outcome in VictoryMatrix.OUTCOMES:
			keys.append(String(outcome["id"]))
		for key in keys:
			_glossary.append(entry(String(key)))
	return _glossary


## Entries whose plain name, technical name or explanation contains every
## word of [param query] (case-insensitive); all entries for "".
static func search(query: String) -> Array:
	var words := query.strip_edges().to_lower().split(" ", false)
	if words.is_empty():
		return glossary()
	var out := []
	for item in glossary():
		var haystack := ("%s %s %s %s" % [item["name"], item["short"], item["technical"], item["explain"]]).to_lower()
		var matched := true
		for word in words:
			if not haystack.contains(word):
				matched = false
				break
		if matched:
			out.append(item)
	return out


static func _technical(key: String, kind: String, raw: Dictionary, localized: bool = true) -> String:
	match kind:
		"metric":
			return _words(String(WorldState.METRIC_INFO[key]["label"]), localized)
		"index":
			return _words(String(WorldState.INDEX_INFO[key]["label"]), localized)
		"currency":
			for role in SimConstants.FACTION_ORDER:
				var info: Dictionary = FactionRegistry.resource_info_for(role)
				if info.has(key):
					return _words(String(info[key].get("label", key.capitalize())), localized)
			return key.capitalize()
		"faction":
			return UiFormat.role_name(key, localized)
		"era":
			var era := int(key.trim_prefix("era_"))
			return _words(I18n.mark("Era %s · %s (%s)"), localized) % [EraStyle.ROMAN[era], _words(String(EraStyle.NAMES[era]), localized),
				EraStyle.SPANS[era]]
		"end_state":
			var outcome := VictoryMatrix.get_outcome(key)
			return "%s (%s)" % [_words(String(outcome.get("name", key)), localized),
				_words(String(outcome.get("subtitle", "")), localized)]
	return _words(String(raw.get("technical", key)), localized)


## [param text] in the interface language, or as written when not [param localized].
static func _words(text: String, localized: bool) -> String:
	return I18n.t(text) if localized else text
