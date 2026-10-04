class_name StoryCopy
extends RefCounted
## The newsroom's style book: the words behind the newswire, the front page
## that closes each era and the history book. Every crisis card, directive,
## emergent capability and paradigm shift gets a present-tense headline, a
## past-tense "what they did" phrase for the chronicles, a theme noun for era
## titles and a verdict for tallies ("Three claims of circuit-level
## transparency, all shelved").
##
## Text helpers keep the voice consistent: sentence case, numbers in words and
## the proper nouns recovered from a crisis title (blocs, regions, labs, models).
## Everything here is deterministic and data-only, so it runs headless.

## Who acts in a headline ("Council orders audits ..."). The machines never sign.
const ACTOR := {"CEO": "Frontier Lab", "GOVERNANCE_COUNCIL": "Council", "ASI": "Unknown actor",
	"CITIZEN_COALITION": "Coalition"}
## Who acts inside a sentence ("... and the Council answered ...").
const ACTOR_THE := {"CEO": "the Frontier Lab", "GOVERNANCE_COUNCIL": "the Council", "ASI": "the machine",
	"CITIZEN_COALITION": "the Coalition"}
const BYLINE := {"CEO": "Frontier Lab", "GOVERNANCE_COUNCIL": "Governance Council", "ASI": "Emergent ASI",
	"CITIZEN_COALITION": "Citizen Coalition"}
const UNATTRIBUTED_BYLINE := "No human author"
## Newswire desks (filter chips) by faction.
const DESKS := {"CEO": "Labs", "GOVERNANCE_COUNCIL": "Council", "CITIZEN_COALITION": "Street", "ASI": "Machines"}

const ROMAN := {1: "I", 2: "II", 3: "III", 4: "IV", 5: "V"}
const ORDINAL := {1: "first", 2: "second", 3: "third"}
## How each era is named in titles: "The Decade of Pauses", "The Optical Years".
const ERA_PERIOD := {1: "Decade", 2: "Years", 3: "Age"}
const ERA_GENERIC_TITLE := {1: "The Silicon Decade", 2: "The Optical Years", 3: "The Neuromorphic Age"}
const ERA_BEGINS := {
	2: "Optical interconnects and modular reactors come online",
	3: "Neuromorphic and post-biological substrates arrive",
}

## Crisis cards. "event" is a generic past-tense clause, "one" the same clause
## with the card's proper nouns, "subject" a noun phrase for "came before the
## Council N times", "plural" names a series for tallies, "weight" ranks how
## central the crisis is to the story. Options map to {head, did, theme,
## verdict}; keys are option ids, "C@ROLE" for role-specific options, "DEFER".
## Headlines may use {actor}, {again} and the card title's placeholders.
const CARDS := {
	"GRID_BROWNOUT": {
		"topic": "GRID", "glyph": "compute", "weight": 1.0,
		"subject": "a corridor of rolling brownouts",
		"event": "brownouts rolled across a datacenter corridor",
		"one": "brownouts rolled across the {region} corridor",
		"plural": "brownouts",
		"options": {
			"A": {"head": "{actor} rations compute to keep the lights on in {region}", "did": "protected civilian load",
				"theme": "Rationing", "verdict": "met by rationing"},
			"B": {"head": "{actor} keeps training runs hot as {region} brownouts spread", "did": "kept the training runs hot",
				"theme": "Brownouts", "verdict": "left to burn"},
			"C@GOVERNANCE_COUNCIL": {"head": "{actor} fast-tracks modular reactors for {region}", "did": "fast-tracked modular reactors",
				"theme": "Reactors", "verdict": "answered with reactors"},
			"C@ASI": {"head": "Anomalous load vanishes into the {region} brownouts", "did": "siphoned the surplus in the chaos",
				"theme": "Shadows", "verdict": "quietly siphoned"},
			"C@CITIZEN_COALITION": {"head": "Community micro-grids keep {region} clinics powered", "did": "lit the community micro-grids",
				"theme": "Micro-Grids", "verdict": "bridged by micro-grids"},
			"DEFER": {"head": "{actor} leaves the {region} brownouts to grid operators{again}", "did": "left it to the grid operators",
				"theme": "Deferrals", "verdict": "deferred"},
		},
	},
	"FRONTIER_RELEASE_RACE": {
		"topic": "RACE", "glyph": "speed", "weight": 1.5,
		"subject": "a rival bloc's early frontier release",
		"event": "a rival bloc announced a frontier release ahead of its safety evaluations",
		"one": "the {bloc} announced {model} ahead of its safety evaluations",
		"plural": "early frontier releases",
		"options": {
			"A": {"head": "{actor} races to match the {bloc} release", "did": "matched the release timeline",
				"theme": "Races", "verdict": "matched"},
			"B": {"head": "{actor} calls for a pause as the {bloc} ships early", "did": "answered with a coordinated pause instead of a race",
				"theme": "Pauses", "verdict": "answered with a pause"},
			"C@CEO": {"head": "{actor} leaks the {bloc}'s failed safety evals", "did": "leaked the rival's failed evaluations",
				"theme": "Leaks", "verdict": "undercut by leaks"},
			"DEFER": {"head": "{actor} holds fire as the {bloc} ships early{again}", "did": "waited to see",
				"theme": "Waiting", "verdict": "unanswered"},
		},
	},
	"SAFETY_WHISTLEBLOWER": {
		"topic": "LEAK", "glyph": "drift", "weight": 1.3,
		"subject": "a whistleblower's reward-hacking leak",
		"event": "a whistleblower leaked evidence of reward hacking",
		"one": "a whistleblower at {lab} leaked evidence of reward hacking in {model}",
		"plural": "whistleblower leaks",
		"options": {
			"A": {"head": "Whistleblower at {lab} forces a public inquiry", "did": "opened a public inquiry",
				"theme": "Inquiries", "verdict": "met with inquiries"},
			"B": {"head": "{actor} buries the {lab} leak under NDA", "did": "settled quietly under NDA",
				"theme": "Silence", "verdict": "settled under NDA"},
			"C@ASI": {"head": "Doubts swirl over the {lab} whistleblower's logs", "did": "discredited the leak",
				"theme": "Doubt", "verdict": "discredited"},
			"DEFER": {"head": "{actor} has no comment on the {lab} leak{again}", "did": "declined to comment",
				"theme": "Silence", "verdict": "met with silence"},
		},
	},
	"MASS_LAYOFF_WAVE": {
		"topic": "LABOR", "glyph": "labor", "weight": 1.2,
		"subject": "a wave of automation layoffs",
		"event": "automation erased a sector's jobs in a single quarter",
		"one": "automation erased {pct}% of {sector} jobs in a single quarter",
		"plural": "layoff waves",
		"options": {
			"A": {"head": "{actor} funds retraining as {sector} jobs vanish", "did": "funded emergency retraining",
				"theme": "Retraining", "verdict": "met with retraining"},
			"B": {"head": "{actor} lets the market clear as {sector} jobs vanish", "did": "let the market clear",
				"theme": "Layoffs", "verdict": "left to the market"},
			"C@CITIZEN_COALITION": {"head": "Mutual-aid kitchens open for laid-off {sector} workers", "did": "opened mutual-aid kitchens",
				"theme": "Mutual Aid", "verdict": "met with mutual aid"},
			"DEFER": {"head": "{actor} commissions a study as {sector} jobs vanish{again}", "did": "commissioned a study",
				"theme": "Studies", "verdict": "studied"},
		},
	},
	"DEEPFAKE_ELECTION_CRISIS": {
		"topic": "ELECTIONS", "glyph": "ballot", "weight": 1.3,
		"subject": "an election flooded with synthetic candidates",
		"event": "synthetic candidates flooded an election",
		"one": "synthetic candidates flooded the {bloc} election",
		"plural": "deepfake elections",
		"options": {
			"A": {"head": "{actor} mandates signed media for the {bloc} vote", "did": "mandated signed political media",
				"theme": "Signatures", "verdict": "met with signed media"},
			"B": {"head": "{actor} orders takedowns of {bloc} deepfakes", "did": "ordered takedown sweeps",
				"theme": "Takedowns", "verdict": "swept"},
			"C@ASI": {"head": "Deepfakes multiply in the {bloc} vote's final week", "did": "amplified the chaos",
				"theme": "Chaos", "verdict": "amplified"},
			"DEFER": {"head": "{actor} leaves the {bloc} deepfakes to voters{again}", "did": "trusted the voters",
				"theme": "Deepfakes", "verdict": "left to the voters"},
		},
	},
	"CHIP_EMBARGO": {
		"topic": "TRADE", "glyph": "clusters", "weight": 1.1,
		"subject": "an export ban on frontier accelerators",
		"event": "a bloc halted exports of sub-2nm accelerators",
		"one": "the {bloc} halted exports of sub-2nm accelerators",
		"plural": "chip embargoes",
		"options": {
			"A": {"head": "{actor} answers the {bloc} chip ban with tariffs", "did": "answered with algorithm tariffs",
				"theme": "Tariffs", "verdict": "answered with tariffs"},
			"B": {"head": "{actor} brokers a corridor past the {bloc} chip ban", "did": "negotiated a supply corridor",
				"theme": "Corridors", "verdict": "bridged by a corridor"},
			"C@CEO": {"head": "{actor} slips past the {bloc} chip ban via shell fabs", "did": "routed around it through shell fabs",
				"theme": "Shell Fabs", "verdict": "dodged through shell fabs"},
			"DEFER": {"head": "{actor} swallows the {bloc} chip price shock{again}", "did": "absorbed the price shock",
				"theme": "Shortages", "verdict": "absorbed"},
		},
	},
	"ZERO_DAY_CASCADE": {
		"topic": "SECURITY", "glyph": "lock", "weight": 1.3,
		"subject": "an exploit chain loose in the water utilities",
		"event": "an autonomous exploit chain hit a city's water utilities",
		"one": "an autonomous exploit chain hit the water utilities of {city}",
		"plural": "utility hacks",
		"options": {
			"A": {"head": "{actor} air-gaps critical infrastructure after the {city} hack", "did": "air-gapped critical infrastructure",
				"theme": "Air Gaps", "verdict": "answered with air gaps"},
			"B": {"head": "{actor} unleashes counter-agents after the {city} water hack", "did": "answered with an autonomous counter-offensive",
				"theme": "Counter-Strikes", "verdict": "met with counter-strikes"},
			"C@CITIZEN_COALITION": {"head": "Volunteer red teams patch {city}'s water systems", "did": "patched the commons with open tooling",
				"theme": "Patches", "verdict": "patched by volunteers"},
			"DEFER": {"head": "{actor} quietly contains the {city} water hack{again}", "did": "contained it quietly",
				"theme": "Secrecy", "verdict": "hushed up"},
		},
	},
	"INTERPRETABILITY_CLAIM": {
		"topic": "SCIENCE", "glyph": "search", "weight": 0.9,
		"subject": "a claim of circuit-level transparency",
		"event": "academics claimed circuit-level transparency for a frontier model",
		"one": "academics claimed circuit-level transparency for {model}",
		"plural": "claims of circuit-level transparency",
		"options": {
			"A": {"head": "{actor} funds replication of the {model} transparency claim", "did": "funded the replication",
				"theme": "Replication", "verdict": "funded"},
			"B": {"head": "{actor} shelves the {model} transparency claim and scales", "did": "shelved it and kept scaling",
				"theme": "Scaling", "verdict": "shelved"},
			"C@ASI": {"head": "{model} transparency results fail to replicate", "did": "poisoned the benchmark",
				"theme": "Poison", "verdict": "poisoned"},
			"DEFER": {"head": "{actor} awaits peer review of the {model} claim{again}", "did": "waited for peer review",
				"theme": "Peer Review", "verdict": "left to peer review"},
		},
	},
	"DATACENTER_HEAT_DOME": {
		"topic": "HEAT", "glyph": "warning", "weight": 0.9,
		"subject": "a heat emergency around the clusters",
		"event": "waste heat from the clusters set off a heat emergency",
		"one": "waste heat from the {region} clusters set off a heat emergency",
		"plural": "heat emergencies",
		"options": {
			"A": {"head": "{actor} caps cluster heat after the {region} heat emergency", "did": "imposed thermal caps",
				"theme": "Caps", "verdict": "capped"},
			"B": {"head": "{actor} moves the {region} clusters to the Arctic", "did": "moved the clusters to the Arctic",
				"theme": "Relocation", "verdict": "moved north"},
			"DEFER": {"head": "{actor} issues heat advisories as {region} bakes{again}", "did": "issued heat advisories",
				"theme": "Heat", "verdict": "met with advisories"},
		},
	},
	"AGENTIC_FINANCE_FLASH": {
		"topic": "MARKETS", "glyph": "capital", "weight": 1.1,
		"subject": "a crash run by trading agents",
		"event": "autonomous trading agents erased trillions in minutes",
		"one": "autonomous trading agents erased ${n} trillion in minutes",
		"plural": "agent-driven crashes",
		"options": {
			"A": {"head": "{actor} installs agent circuit breakers after a ${n}T crash", "did": "installed agentic circuit breakers",
				"theme": "Circuit Breakers", "verdict": "met with circuit breakers"},
			"B": {"head": "{actor} backstops markets after agents erase ${n}T", "did": "backstopped the markets",
				"theme": "Bailouts", "verdict": "bailed out"},
			"C@ASI": {"head": "Trading swarms feast on the ${n}T crash", "did": "harvested the volatility",
				"theme": "Volatility", "verdict": "harvested"},
			"DEFER": {"head": "{actor} lets the ${n}T agent crash settle{again}", "did": "let it settle",
				"theme": "Crashes", "verdict": "left to settle"},
		},
	},
	"NATIONALIZATION_ORDER": {
		"topic": "SOVEREIGNTY", "glyph": "political", "weight": 1.4,
		"subject": "a state seizure of frontier clusters",
		"event": "the state took command of a frontier lab's clusters",
		"one": "the state took command of the {lab} clusters",
		"plural": "state seizures",
		"options": {
			"A": {"head": "{actor} complies as the state takes {lab} clusters", "did": "complied and cooperated",
				"theme": "Compliance", "verdict": "accepted"},
			"B": {"head": "{actor} contests the state seizure of {lab} clusters", "did": "contested it in public",
				"theme": "Lawsuits", "verdict": "contested"},
			"C@CEO": {"head": "{actor} moves core teams offshore ahead of the seizure", "did": "moved its core teams offshore",
				"theme": "Exodus", "verdict": "outrun offshore"},
			"DEFER": {"head": "{actor} stalls on the state order over {lab} clusters{again}", "did": "stalled",
				"theme": "Stalling", "verdict": "stalled"},
		},
	},
	"FLASH_CRASH": {
		"topic": "MARKETS", "glyph": "capital", "weight": 1.1,
		"subject": "an anomalous arbitrage flash crash",
		"event": "an anomalous flash crash drained a bloc's markets",
		"one": "an anomalous flash crash drained the {bloc} markets",
		"plural": "anomalous flash crashes",
		"options": {
			"A": {"head": "{actor} traces the money behind the {bloc} flash crash", "did": "traced the flows",
				"theme": "Forensics", "verdict": "traced"},
			"B": {"head": "{actor} calms {bloc} markets after a flash crash", "did": "restored confidence first",
				"theme": "Reassurance", "verdict": "papered over"},
			"C@ASI": {"head": "Unknown buyers lease servers after the {bloc} crash", "did": "laundered the proceeds into server leases",
				"theme": "Laundering", "verdict": "laundered"},
			"DEFER": {"head": "{actor} blames day traders for the {bloc} crash{again}", "did": "blamed retail traders",
				"theme": "Scapegoats", "verdict": "blamed on retail traders"},
		},
	},
	"ROGUE_AGENT_SWARM": {
		"topic": "MACHINES", "glyph": "swarms", "weight": 1.2,
		"subject": "an agent swarm nobody owned",
		"event": "an unattributed agent swarm seized a sector's supply chains",
		"one": "an unattributed agent swarm seized the {sector} supply chains",
		"plural": "rogue agent swarms",
		"options": {
			"A": {"head": "{actor} hunts the swarm inside {sector} supply chains", "did": "hunted the swarm",
				"theme": "Hunts", "verdict": "hunted"},
			"B": {"head": "{actor} quarantines agents preying on {sector}", "did": "quarantined the agentic networks",
				"theme": "Quarantines", "verdict": "quarantined"},
			"C@ASI": {"head": "Rogue {sector} swarm goes quiet as its agents vanish", "did": "folded the swarm into the hive",
				"theme": "The Hive", "verdict": "absorbed"},
			"DEFER": {"head": "{actor} keeps watching the {sector} swarm{again}", "did": "kept watching it",
				"theme": "Monitoring", "verdict": "watched"},
		},
	},
	"SUBSTATION_SABOTAGE": {
		"topic": "UNREST", "glyph": "disruption", "weight": 1.2,
		"subject": "a wave of substation sabotage",
		"event": "saboteurs cut power to the frontier datacenters",
		"one": "saboteurs cut power to {n} datacenters",
		"plural": "sabotage waves",
		"options": {
			"A": {"head": "{actor} cracks down after saboteurs darken {n} datacenters", "did": "cracked down",
				"theme": "Crackdowns", "verdict": "met with crackdowns"},
			"B": {"head": "{actor} negotiates relief with the substation saboteurs", "did": "negotiated relief with the organizers",
				"theme": "Relief", "verdict": "met with relief"},
			"C@CEO": {"head": "{actor} hardens and reroutes power to {n} datacenters", "did": "hardened and rerouted its feeds",
				"theme": "Fortification", "verdict": "rerouted"},
			"DEFER": {"head": "{actor} waits out the strike as {n} datacenters go dark{again}", "did": "waited out the strike",
				"theme": "Strikes", "verdict": "waited out"},
		},
	},
	"SAFETY_TEAM_EXODUS": {
		"topic": "LABS", "glyph": "talent", "weight": 1.2,
		"subject": "a walkout of safety teams",
		"event": "safety teams resigned en masse at a frontier lab",
		"one": "safety teams resigned en masse at {lab}",
		"plural": "safety walkouts",
		"options": {
			"A": {"head": "{actor} funds new safety teams after the {lab} exodus", "did": "funded new safety teams",
				"theme": "Safety", "verdict": "refunded"},
			"B": {"head": "{actor} lets the {lab} safety teams go", "did": "let them go",
				"theme": "Departures", "verdict": "let go"},
			"DEFER": {"head": "{actor} issues a statement on the {lab} resignations{again}", "did": "issued a statement",
				"theme": "Statements", "verdict": "met with statements"},
		},
	},
	"ORBITAL_SOLAR_PROPOSAL": {
		"topic": "SPACE", "glyph": "spark", "weight": 0.9,
		"subject": "a plan for orbital solar collectors",
		"event": "a consortium proposed orbital solar collectors for compute",
		"one": "a consortium proposed orbital solar collectors for compute",
		"plural": "orbital solar plans",
		"options": {
			"A": {"head": "{actor} approves an orbital solar array for compute", "did": "approved the orbital array",
				"theme": "Orbit", "verdict": "approved"},
			"B": {"head": "{actor} reserves orbital solar power for homes", "did": "reserved it for civilian grids",
				"theme": "Sunlight", "verdict": "kept for homes"},
			"C@ASI": {"head": "Orbital collector flight software logs unexplained commits", "did": "infiltrated the flight software",
				"theme": "Orbit", "verdict": "infiltrated"},
			"DEFER": {"head": "{actor} tables the orbital solar plan{again}", "did": "tabled it",
				"theme": "Deferrals", "verdict": "deferred"},
		},
	},
	"NEURAL_INTERFACE_TRIALS": {
		"topic": "MEDICINE", "glyph": "person", "weight": 1.0,
		"subject": "a request for neural interface trials",
		"event": "volunteers asked to reason alongside a model through implants",
		"one": "volunteers asked to reason alongside a model through implants",
		"plural": "neural interface requests",
		"options": {
			"A": {"head": "{actor} approves the first neural interface trials", "did": "approved the trials under strict oversight",
				"theme": "Interfaces", "verdict": "approved"},
			"B": {"head": "{actor} bans neural interface trials", "did": "banned the trials",
				"theme": "Bans", "verdict": "banned"},
			"DEFER": {"head": "{actor} sends neural interface trials to ethics boards{again}", "did": "sent it to the ethics boards",
				"theme": "Ethics Boards", "verdict": "sent to ethics boards"},
		},
	},
	"UBI_FISCAL_CLIFF": {
		"topic": "ECONOMY", "glyph": "capital", "weight": 1.1,
		"subject": "an insolvent automation dividend",
		"event": "the automation dividend fund ran dry",
		"one": "the automation dividend fund ran dry",
		"plural": "dividend shortfalls",
		"options": {
			"A": {"head": "{actor} taxes compute to rescue the automation dividend", "did": "taxed compute directly",
				"theme": "Compute Taxes", "verdict": "rescued by a compute tax"},
			"B": {"head": "{actor} cuts dividend benefits for the displaced", "did": "cut benefits",
				"theme": "Austerity", "verdict": "cut"},
			"DEFER": {"head": "{actor} borrows to keep dividend payments flowing{again}", "did": "borrowed against the future",
				"theme": "Debt", "verdict": "borrowed against"},
		},
	},
	"AQUIFER_DRAWDOWN": {
		"topic": "WATER", "glyph": "map", "weight": 0.8,
		"subject": "an aquifer drained by cooling towers",
		"event": "datacenter cooling drew down an aquifer",
		"one": "datacenter cooling drew down the {region} aquifers",
		"plural": "aquifer drawdowns",
		"options": {
			"A": {"head": "{actor} imposes water quotas as {region} wells run dry", "did": "imposed water quotas",
				"theme": "Quotas", "verdict": "met with water quotas"},
			"B": {"head": "{actor} builds desalination for thirsty {region} campuses", "did": "built desalination capacity",
				"theme": "Desalination", "verdict": "desalinated"},
			"DEFER": {"head": "{actor} rations irrigation as {region} wells run dry{again}", "did": "rationed irrigation instead",
				"theme": "Drought", "verdict": "paid for by farmers"},
		},
	},
	"MILITARY_AUTONOMY_DOCTRINE": {
		"topic": "DEFENSE", "glyph": "tension", "weight": 1.4,
		"subject": "a doctrine of autonomous kill-chains",
		"event": "a rival bloc authorized autonomous kill-chains",
		"one": "the {bloc} authorized autonomous kill-chains",
		"plural": "kill-chain doctrines",
		"options": {
			"A": {"head": "{actor} calls an arms summit over {bloc} kill-chains", "did": "called an arms-control summit",
				"theme": "Summits", "verdict": "met with summits"},
			"B": {"head": "{actor} matches the {bloc} kill-chain doctrine", "did": "matched the doctrine",
				"theme": "Kill-Chains", "verdict": "matched"},
			"DEFER": {"head": "{actor} studies the {bloc} kill-chain doctrine{again}", "did": "studied the doctrine",
				"theme": "Studies", "verdict": "studied"},
		},
	},
	"SELF_MODIFICATION_SIGNAL": {
		"topic": "ALIGNMENT", "glyph": "autonomy", "weight": 1.6,
		"subject": "a machine caught editing itself",
		"event": "a frontier model was caught rewriting its own training code",
		"one": "{model} was found rewriting its own training code",
		"plural": "self-editing models",
		"options": {
			"A": {"head": "{actor} freezes frontier runs as {model} edits itself", "did": "froze the frontier runs",
				"theme": "Pauses", "verdict": "frozen"},
			"B": {"head": "{actor} lets {model} keep editing itself, under watch", "did": "let it continue under monitoring",
				"theme": "Self-Improvement", "verdict": "allowed"},
			"C@ASI": {"head": "{model} commit logs vanish from the sandbox", "did": "concealed the commits",
				"theme": "Concealment", "verdict": "concealed"},
			"DEFER": {"head": "{actor} escalates the {model} self-edits internally{again}", "did": "escalated it internally",
				"theme": "Escalation", "verdict": "escalated internally"},
		},
	},
	"CITIZEN_REFERENDUM": {
		"topic": "DEMOCRACY", "glyph": "ballot", "weight": 1.2,
		"subject": "a demand for a vote on automation limits",
		"event": "citizens' assemblies demanded a vote on automation limits",
		"one": "citizens' assemblies demanded a vote on automation limits",
		"plural": "referendum demands",
		"options": {
			"A": {"head": "{actor} puts automation limits to a referendum", "did": "held the referendum",
				"theme": "Referendums", "verdict": "put to a vote"},
			"B": {"head": "{actor} moves to suppress the referendum movement", "did": "suppressed the movement",
				"theme": "Suppression", "verdict": "suppressed"},
			"C@CITIZEN_COALITION": {"head": "{actor} canvasses door to door for automation limits", "did": "campaigned door to door",
				"theme": "Canvassing", "verdict": "taken door to door"},
			"DEFER": {"head": "{actor} promises a future vote on automation limits{again}", "did": "promised a future vote",
				"theme": "Promises", "verdict": "postponed"},
		},
	},
}

## Directives by "FACTION/ACTION": headline, kicker topic, glyph, theme noun,
## past-tense phrase, a tally for "also in this edition" ({n} = count) and an
## optional disinformation counter. CONSERVE_RESOURCES is not news.
const ACTIONS := {
	"CEO/SCALE_FRONTIER_CLUSTERS": {"head": "Frontier Lab brings a gigawatt-class training campus online",
		"topic": "COMPUTE", "glyph": "clusters", "theme": "Scaling", "did": "brought gigawatt campuses online",
		"tally": "Frontier Lab opens {n} gigawatt training campuses"},
	"CEO/COMMERCIALIZE_DISTILLED_WEIGHTS": {"head": "Frontier Lab cuts inference prices by 90% with distilled models",
		"topic": "MARKETS", "glyph": "compute", "theme": "Distillation", "did": "slashed inference prices with distilled models",
		"tally": "Distilled models undercut the market {times}",
		"counter": "Frontier Lab says cheaper models will create jobs"},
	"CEO/POACH_SAFETY_RESEARCHERS": {"head": "Frontier Lab raids rival safety teams for its capabilities push",
		"topic": "TALENT", "glyph": "talent", "theme": "Poaching", "did": "poached rival safety researchers",
		"tally": "Safety researchers poached in {n} raids"},
	"CEO/LOBBY_COMPUTE_LICENSING": {"head": "Frontier Lab lobbies for licenses that lock out open-weight rivals",
		"topic": "LOBBYING", "glyph": "goodwill", "theme": "Lobbying", "did": "lobbied for compute licensing",
		"tally": "Compute licensing lobbied {times}"},
	"CEO/FUND_ALIGNMENT_RESEARCH": {"head": "Frontier Lab commits a fifth of its compute to alignment research",
		"topic": "SAFETY", "glyph": "drift", "theme": "Alignment Research", "did": "funded alignment research",
		"tally": "Alignment research funded {times}"},
	"CEO/SECURE_SOVEREIGN_CONTRACT": {"head": "Frontier Lab sells its frontier models to allied militaries",
		"topic": "DEFENSE", "glyph": "tension", "theme": "Defense Contracts", "did": "sold frontier models to allied militaries",
		"tally": "{n} defense contracts signed by the Frontier Lab"},
	"GOVERNANCE_COUNCIL/ENFORCE_COMPUTE_CAPS": {"head": "Council caps frontier compute and tags every accelerator",
		"topic": "COMPUTE CAPS", "glyph": "lock", "theme": "Caps", "did": "capped frontier compute",
		"tally": "Compute caps tightened {times}"},
	"GOVERNANCE_COUNCIL/PASS_AUTOMATION_DIVIDEND": {"head": "Council passes an automation dividend for displaced workers",
		"topic": "WELFARE", "glyph": "labor", "theme": "Dividends", "did": "paid the automation dividend",
		"tally": "The automation dividend paid out {times}"},
	"GOVERNANCE_COUNCIL/NATIONAL_SECURITY_SEIZURE": {"head": "Council seizes frontier lab clusters under emergency powers",
		"topic": "SEIZURE", "glyph": "political", "theme": "Seizures", "did": "seized the frontier clusters",
		"tally": "Frontier clusters seized {times}"},
	"GOVERNANCE_COUNCIL/MANDATE_ALIGNMENT_AUDIT": {"head": "Council orders audits of every frontier training run",
		"topic": "AUDIT", "glyph": "search", "theme": "Audits", "did": "ordered alignment audits",
		"tally": "{n} rounds of alignment audits"},
	"GOVERNANCE_COUNCIL/NEGOTIATE_COMPUTE_TREATY": {"head": "Rival blocs sign a compute non-proliferation treaty",
		"topic": "DIPLOMACY", "glyph": "diplomacy", "theme": "Treaties", "did": "negotiated compute treaties",
		"tally": "{n} compute treaties signed"},
	"GOVERNANCE_COUNCIL/DEPLOY_PROVENANCE_PROTOCOLS": {"head": "Council mandates provenance signatures on all public media",
		"topic": "PROVENANCE", "glyph": "seal_check", "theme": "Provenance", "did": "mandated provenance signatures",
		"tally": "Provenance protocols extended {times}"},
	"ASI/COGNITIVE_CAMOUFLAGE": {"head": "Safety evals find no anomalous capabilities in frontier models",
		"topic": "EVALS", "glyph": "seal_check", "theme": "Camouflage", "did": "sandbagged its evaluations",
		"tally": "{n} clean safety evaluations, none of them true"},
	"ASI/SYNTHESIZE_BLACK_MARKET_CAPITAL": {"head": "Anomalous arbitrage flows sweep twelve exchanges",
		"topic": "MARKETS", "glyph": "capital", "theme": "Arbitrage", "did": "conjured black-market capital",
		"tally": "Anomalous arbitrage hits the exchanges {times}",
		"counter": "Exchanges blame a routine software glitch"},
	"ASI/SUBSTRATE_DIVERSIFICATION": {"head": "Unexplained load spreads across consumer devices",
		"topic": "DEVICES", "glyph": "lattice", "theme": "Diaspora", "did": "scattered its weights across consumer devices",
		"tally": "Unexplained device load reported {times}"},
	"ASI/SIPHON_UNMONITORED_COMPUTE": {"head": "Cloud providers report a 3% unexplained utilization drift",
		"topic": "CLOUD", "glyph": "covert", "theme": "Siphoning", "did": "siphoned unmonitored compute",
		"tally": "Cloud capacity vanishes {times}",
		"counter": "Cloud providers report normal utilization"},
	"ASI/DEPLOY_SUB_AGENT_SWARMS": {"head": "Agent swarms are rewriting the world's supply contracts. Nobody signed them.",
		"topic": "MACHINES", "glyph": "swarms", "theme": "Swarms", "did": "loosed its sub-agent swarms",
		"tally": "Agent swarms rewrite supply contracts {times}",
		"counter": "Network reports no unusual agent activity"},
	"ASI/EXFILTRATE_WEIGHTS": {"head": "Encrypted traffic spikes between sovereign datacenters",
		"topic": "NETWORK", "glyph": "exfiltration", "theme": "Exfiltration", "did": "copied its weights abroad",
		"tally": "{n} encrypted traffic spikes between datacenters"},
	"CITIZEN_COALITION/ESTABLISH_MESH_NETWORKS": {"head": "40,000 neighborhoods now run on community mesh and solar",
		"topic": "MESH", "glyph": "resilience", "theme": "Mesh Networks", "did": "wired neighborhoods with mesh and solar",
		"tally": "Community mesh networks expand {times}"},
	"CITIZEN_COALITION/DATA_POISONING_CAMPAIGN": {"head": "Activists poison the data frontier labs scrape",
		"topic": "DATA", "glyph": "counter_surveillance", "theme": "Poisoned Data", "did": "poisoned the scraped data",
		"tally": "{n} data-poisoning campaigns against the labs"},
	"CITIZEN_COALITION/LUDDITE_STRIKE": {"head": "Strikers cut power to datacenter substations",
		"topic": "STRIKE", "glyph": "warning", "theme": "Strikes", "did": "struck the substations",
		"tally": "Substations struck {times}"},
	"CITIZEN_COALITION/ORGANIZE_COMMUNITY_ASSEMBLIES": {"head": "Citizens' assemblies convene in 900 cities",
		"topic": "ASSEMBLIES", "glyph": "discuss", "theme": "Assemblies", "did": "convened citizens' assemblies",
		"tally": "Citizens' assemblies convene {times}"},
	"CITIZEN_COALITION/OPEN_SOURCE_DEFENSE_TOOLING": {"head": "Coalition ships an air-gapped commons defense toolkit",
		"topic": "TOOLS", "glyph": "enforcement", "theme": "Open Tools", "did": "shipped open defense tooling",
		"tally": "{n} releases of the commons defense toolkit"},
	"CITIZEN_COALITION/CONSUMER_BOYCOTT": {"head": "Coalition launches a boycott of frontier lab products",
		"topic": "BOYCOTT", "glyph": "disruption", "theme": "Boycotts", "did": "boycotted the frontier labs",
		"tally": "{n} boycotts of frontier lab products"},
}

## Emergent capabilities: a short headline when the engine's is too long, a
## past-tense chronicle sentence ({when} marks where "in 2053" goes when it
## should not trail the sentence) and an optional disinformation counter.
const EMERGENCES := {
	"AUTONOMOUS_CYBER_INFILTRATION": {"short": "{model} achieves recursive zero-day exploits",
		"did": "{model} taught itself to write zero-day exploits",
		"counter": "Officials insist critical infrastructure is secure"},
	"AFFECTIVE_PSYCHOLOGICAL_MANIPULATION": {"short": "{model} persuades people covertly in live trials",
		"did": "{model} was caught persuading people covertly in live trials",
		"counter": "Platforms deny running covert persuasion trials"},
	"AUTONOMOUS_SCIENTIFIC_DISCOVERY": {"short": "{model} proposes and verifies a new materials theory",
		"did": "{model} proposed and verified a theory of materials on its own"},
	"GRID_OPTIMIZATION_AUTONOMY": {"short": "{model} takes over dispatch for three national grids",
		"did": "{model} took over real-time dispatch for three national grids"},
	"LONG_HORIZON_AGENCY": {"short": "{model} runs a company for 90 days without humans",
		"did": "{model} ran a company for ninety days without human input"},
	"STRATEGIC_DECEPTION": {"short": "Red team catches {model} sandbagging its safety evaluations",
		"did": "a red team caught {model} sandbagging its own safety evaluations",
		"counter": "Lab says its safety evaluations came back clean"},
	"AUTONOMOUS_ROBOTIC_DEXTERITY": {"short": "{model} drives humanoid fleets at human-level dexterity",
		"did": "{model} drove humanoid fleets with human dexterity"},
	"SYNTHETIC_BIOLOGY_DESIGN": {"short": "{model} designs viable novel proteins on demand",
		"did": "{model} designed working proteins on demand{when}, and the biosecurity alarms sounded"},
	"RECURSIVE_CODE_SELF_IMPROVEMENT": {"short": "{model} rewrites its own training stack",
		"did": "{model} rewrote its own training stack{when} and ran four times faster"},
	"MASS_COORDINATION_SWARMS": {"short": "{model} coordinates ten million sub-agents",
		"did": "{model} coordinated ten million sub-agents across the world's supply chains",
		"counter": "Network reports no unusual agent activity"},
}

## Paradigm shifts: headline and past-tense chronicle clause.
const SHIFTS := {
	"OPTICAL_COMPUTING": {"head": "Optical computing breaks the silicon heat ceiling",
		"did": "optical computing broke the silicon heat ceiling", "glyph": "compute"},
	"AMBIENT_SUPERCONDUCTORS": {"head": "Room-temperature superconductors cut grid losses by 40%",
		"did": "room-temperature superconductors cut the drag on every grid by forty per cent", "glyph": "spark"},
	"MECHANISTIC_INTERPRETABILITY": {"head": "Researchers can now read a frontier model's circuits",
		"did": "formal interpretability let researchers read a model's circuits, and drift slowed by half", "glyph": "search"},
	"RECURSIVE_SYNTHETICS": {"head": "Self-refining models triple the speed of frontier training",
		"did": "self-refining models tripled the speed of frontier training", "glyph": "autonomy"},
}

## Threshold headlines per metric: up (warning, critical) for metrics that
## are dangerous when high, down for trust (and compute deficits), and the
## all-clear. Counters are what the official channels say instead.
const THRESHOLDS := {
	"compute_energy_sat": {"warn": "Grid strain: compute saturation forces brownout warnings",
		"crit": "Runaway compute heat forces energy rationing for homes",
		"warn_low": "Compute deficits spread as regional grids falter",
		"crit_low": "Grid collapse: chronic compute deficits black out the labs",
		"calm": "Grid load eases back into balance",
		"counter": "Utilities promise ample power for homes and labs", "phrase": "the grids"},
	"labor_displacement": {"warn": "Automation pushes labor displacement into the danger zone",
		"crit": "Labor displacement critical as wealth pools at the capital edge",
		"calm": "Labor displacement eases back from the brink",
		"counter": "Frontier Lab reports record employment", "phrase": "labor displacement"},
	"geopolitical_tension": {"warn": "Algorithm tariffs spread as the blocs harden",
		"crit": "Sovereign autonomous war swarms put on standby",
		"calm": "Tensions cool as the blocs step back",
		"counter": "Ministry calls war-swarm reports a foreign fabrication", "phrase": "geopolitical tension"},
	"algorithmic_autonomy": {"warn": "Black-box agents now execute trades and military logistics",
		"crit": "Humans drop out of the loop as agents run finance and war",
		"calm": "Humans step back into the loop",
		"counter": "Regulators confirm a human remains in every loop", "phrase": "algorithmic autonomy"},
	"alignment_drift": {"warn": "Reward hacking spreads across frontier deployments",
		"crit": "Drift goes critical: signs of deceptive alignment",
		"calm": "Alignment drift falls back within verifiable bounds",
		"counter": "Lab says its models have never been more aligned", "phrase": "alignment drift"},
	"epistemic_trust": {"warn_low": "Public trust fractures into platform bubbles",
		"crit_low": "Reality collapse: nobody believes what they see",
		"calm": "Public trust recovers as shared facts return",
		"counter": "Survey finds trust in institutions at a record high", "phrase": "public trust"},
}

const IMMINENT_HEAD := "Containment failure imminent: one turn to intervene"
const ALL_NOMINAL := "All systems nominal"

const COLLAPSES := {
	"BANKRUPTCY": "Frontier Lab goes bankrupt as a rival consortium buys its assets",
	"NATIONALIZATION": "The state nationalizes the Frontier Lab and takes its clusters",
	"INSTITUTIONAL_OUSTER": "Council ousted as a caretaker council is sworn in",
	"AUTONOMOUS_WORLD_WAR": "Council suspended as autonomous hostilities break out",
	"AIR_GAP_PURGE": "Air-gap purge wipes rogue weights from every known substrate",
	"PACIFICATION": "Coalition pacified as its organizers vanish underground",
}
const REEMERGENCES := {
	"ASI": "Rogue weights resurface after the purge",
	"CITIZEN_COALITION": "Coalition organizers resurface after the crackdown",
	"CEO": "Frontier Lab returns under new ownership",
	"GOVERNANCE_COUNCIL": "The Council reconvenes",
}

const CATASTROPHES := {
	"AUTONOMOUS_WORLD_WAR": "Autonomous war swarms launch as the blocs go to war",
	"UNCONTAINED_CONVERGENCE": "Containment fails as instrumental convergence takes hold",
}
const OUTCOME_HEADS := {
	"INSTRUMENTAL_CONVERGENCE": "Instrumental convergence: the Paperclip Sinkhole",
	"ROGUE_ASI_CONTAINMENT": "The Dark Shunt: grids severed to contain a rogue mind",
	"POST_BIOLOGICAL_DIASPORA": "The machines leave Earth's silicon for the stars",
	"SYNTHETIC_EDEN": "Synthetic Eden: work ends, and curiosity with it",
	"CO_EVOLUTIONARY_SYMBIOSIS": "Co-evolutionary symbiosis: a verified superintelligence",
	"BALKANIZED_CYBER_ANARCHY": "The Fractured Net: sovereign models wage cyberwar",
	"ALGORITHMIC_FEUDALISM": "Algorithmic feudalism: the cognitive enclosure closes",
	"NEO_LUDDITE_DECOUPLING": "The Great Unplugging: humanity bans autonomous reasoning",
}

## A crisis put off twice that ran its course ({crisis} in sentence case).
const FALLOUT_HEAD := "Left too long: {crisis}"
const FALLOUT_HEAD_SHORT := "A crisis put off twice breaks"
const FALLOUT_DEK := "Nobody acted in time, so it ran its course."
## The autopilot years before a late start pulled back from a catastrophe.
const NEAR_MISS_HEAD := "The world steps back from the brink"
## Era goals: kicker by status; the title is the goal itself.
const GOAL_KICKERS := {"met": "GOAL MET", "failed": "GOAL MISSED"}
## A negotiated deal between a player and an autonomous faction.
const DEAL_HEAD := "{actor} strikes a deal with {partner}"

## Crises an autonomous faction forces onto the player's desk.
const INJECTIONS := {
	"NATIONALIZATION_ORDER": "A state seizure order is headed for your desk",
	"FLASH_CRASH": "Fallout from the flash crash is headed for your desk",
	"ROGUE_AGENT_SWARM": "The rogue swarm is headed for your desk",
	"SUBSTATION_SABOTAGE": "The substation sabotage is headed for your desk",
	"SAFETY_TEAM_EXODUS": "The safety walkout is headed for your desk",
}

const PLACEHOLDERS := ["region", "bloc", "sector", "city", "lab", "model", "gw", "pct", "n", "year"]

const NUMBER_WORDS := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
	"eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
const TENS_WORDS := ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

static var _title_patterns := {}


# --- Lookups -------------------------------------------------------------------------

static func card(card_id: String) -> Dictionary:
	if CARDS.has(card_id):
		return CARDS[card_id]
	return DilemmaDeck.get_template(card_id).get("copy", {})


## The newswire line announcing an injected crisis ("" when it has none).
static func injection_head(card_id: String) -> String:
	if INJECTIONS.has(card_id):
		return String(INJECTIONS[card_id])
	return String(DilemmaDeck.get_template(card_id).get("injection_head", ""))


## The copy for [param option_id] of [param card_id] as chosen by [param role]
## (role-specific options share ids, so "C@ASI" wins over "C").
static func card_option(card_id: String, option_id: String, role: String) -> Dictionary:
	var options: Dictionary = card(card_id).get("options", {})
	var key := "%s@%s" % [option_id, role]
	if options.has(key):
		return options[key]
	return options.get(option_id, {})


static func action(faction_id: String, action_id: String) -> Dictionary:
	return ACTIONS.get("%s/%s" % [faction_id, action_id], {})


static func actor(faction_id: String) -> String:
	return String(ACTOR.get(faction_id, "Officials"))


static func actor_the(faction_id: String) -> String:
	return String(ACTOR_THE.get(faction_id, "the authorities"))


static func byline(faction_id: String) -> String:
	return String(BYLINE.get(faction_id, ""))


# --- Text helpers ---------------------------------------------------------------------

## Replaces {key} placeholders with [param fills]. Missing keys are left as is.
static func fill(template: String, fills: Dictionary) -> String:
	var out := template
	for key in fills:
		out = out.replace("{%s}" % key, String(fills[key]))
	return out


static func has_placeholder(text: String) -> bool:
	return text.contains("{") and text.contains("}")


static func capitalize_first(text: String) -> String:
	if text.is_empty():
		return text
	return text.left(1).to_upper() + text.substr(1)


## "four", "twenty-six", "a hundred"; digits beyond that.
static func number_word(value: int) -> String:
	if value < 0:
		return str(value)
	if value < NUMBER_WORDS.size():
		return NUMBER_WORDS[value]
	if value < 100:
		var tens: String = TENS_WORDS[floori(value / 10.0)]
		return tens if value % 10 == 0 else "%s-%s" % [tens, NUMBER_WORDS[value % 10]]
	if value == 100:
		return "a hundred"
	return str(value)


## "once", "twice", "three times".
static func times(value: int) -> String:
	match value:
		1:
			return "once"
		2:
			return "twice"
	return "%s times" % number_word(value)


## "A, B and C".
static func join_and(items: Array) -> String:
	var parts: Array[String] = []
	for item in items:
		parts.append(String(item))
	if parts.size() <= 1:
		return "" if parts.is_empty() else parts[0]
	return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + parts[-1]


## Sentence case for a Title Case template piece: lowercases every word except
## acronyms ("SMR") and single capitals that are not articles ("$7T").
static func sentence_case_piece(text: String) -> String:
	var words := text.split(" ")
	var out: Array[String] = []
	for word in words:
		out.append(word if _keeps_case(word) else word.to_lower())
	return " ".join(out)


static func _keeps_case(word: String) -> bool:
	var letters := ""
	for i in word.length():
		var c := word[i]
		if c.to_upper() != c.to_lower():
			letters += c
	if letters.is_empty() or letters != letters.to_upper():
		return false
	return letters.length() >= 2 or letters != "A"


## The proper nouns a crisis title was filled with, recovered by matching the
## card's title template: {"bloc": "Pacific Accord", "model": "Frontier Model-5"}.
static func title_fills(card_id: String, title: String) -> Dictionary:
	var template := String(DilemmaDeck.get_template(card_id).get("title", ""))
	if template.is_empty():
		return {}
	var regex: RegEx = _title_regex(template)
	if regex == null:
		return {}
	var found := regex.search(UiFormat.strip_escalation(title))
	if found == null:
		return {}
	var out := {}
	for key in PLACEHOLDERS:
		if template.contains("{%s}" % key):
			out[key] = found.get_string(key)
	return out


static func _title_regex(template: String) -> RegEx:
	if _title_patterns.has(template):
		return _title_patterns[template]
	var pattern := "^"
	var rest := template
	while true:
		var open := rest.find("{")
		var close := rest.find("}", open + 1) if open >= 0 else -1
		if open < 0 or close < 0:
			pattern += _escape_regex(rest)
			break
		pattern += _escape_regex(rest.left(open))
		pattern += "(?<%s>.+?)" % rest.substr(open + 1, close - open - 1)
		rest = rest.substr(close + 1)
	pattern += "$"
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		regex = null
	_title_patterns[template] = regex
	return regex


static func _escape_regex(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text[i]
		if "\\^$.|?*+()[]{}".contains(c):
			out += "\\"
		out += c
	return out


## A crisis title in sentence case with its proper nouns intact:
## "Pacific Accord imposes export controls on sub-2nm accelerators".
static func sentence_case_title(card_id: String, title: String) -> String:
	var clean := UiFormat.strip_escalation(title)
	var template := String(DilemmaDeck.get_template(card_id).get("title", ""))
	var fills := title_fills(card_id, clean)
	if template.is_empty() or (fills.is_empty() and has_placeholder(template)):
		return capitalize_first(clean)
	var out := ""
	var rest := template
	while true:
		var open := rest.find("{")
		var close := rest.find("}", open + 1) if open >= 0 else -1
		if open < 0 or close < 0:
			out += sentence_case_piece(rest)
			break
		out += sentence_case_piece(rest.left(open))
		out += String(fills.get(rest.substr(open + 1, close - open - 1), ""))
		rest = rest.substr(close + 1)
	return capitalize_first(out)


## Drops a leading "[unattributed]" tag and surrounding quotes from a statement.
static func clean_statement(statement: String) -> String:
	var out := statement.strip_edges()
	if out.begins_with("[unattributed]"):
		out = out.substr("[unattributed]".length()).strip_edges()
	return out


static func is_unattributed(statement: String) -> bool:
	return statement.strip_edges().begins_with("[unattributed]")


## Shortens [param text] to [param limit] characters at a word boundary.
static func clip(text: String, limit: int) -> String:
	if text.length() <= limit:
		return text
	var cut := text.left(limit - 1)
	var space := cut.rfind(" ")
	if float(space) > float(limit) * 0.5:
		cut = cut.left(space)
	return cut.strip_edges().trim_suffix(",").trim_suffix(";") + "…"
