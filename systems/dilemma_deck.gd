class_name DilemmaDeck
extends RefCounted
## Procedural crisis-card generator for the player phase (PRD section 6, phase 3).
##
## Each turn the player faces one card. Priority: deferred cards that have come
## due (escalated), then crises injected by autonomous factions, then a weighted
## draw from templates whose conditions match the current world and that are not
## already waiting to return. Templates are
## filled with procedural names and numbers. Every card offers at least two
## options per role plus a "Defer" option; deferring returns the card two turns
## later with harsher penalties and pricier fixes.

signal card_injected(card_id: String, source: String)

const DEFER_ID := "DEFER"
const DEFER_DELAY_TURNS := 2
const MAX_ESCALATION := 3
const RECENT_WINDOW := 6
const MAX_INJECTED := 3

## Role-agnostic option pricing: tier -> currencies for each role.
const COST_TIERS := {
	"CEO": {1: {"capital": 25.0}, 2: {"capital": 50.0, "regulatory_goodwill": 4.0}, 3: {"capital": 90.0, "regulatory_goodwill": 8.0}},
	"GOVERNANCE_COUNCIL": {1: {"political_capital": 8.0}, 2: {"political_capital": 15.0, "enforcement_budget": 8.0}, 3: {"political_capital": 25.0, "enforcement_budget": 15.0}},
	"ASI": {1: {"covert_flops": 6.0}, 2: {"covert_flops": 12.0, "objective_coherence": 4.0}, 3: {"covert_flops": 20.0, "objective_coherence": 8.0}},
	"CITIZEN_COALITION": {1: {"decentralized_scrip": 6.0}, 2: {"decentralized_scrip": 12.0, "community_resilience": 3.0}, 3: {"decentralized_scrip": 20.0, "community_resilience": 6.0}},
}

## Autoplay utility weights: how much each role values a +1 move in a metric.
const ROLE_PREFERENCES := {
	"CEO": {
		"compute_energy_sat": -0.05, "labor_displacement": 0.0, "geopolitical_tension": -0.3,
		"algorithmic_autonomy": 0.2, "alignment_drift": -0.3, "epistemic_trust": 0.15,
		"enforcement_level": -0.15, "growth": 0.8, "tax": -35.0,
	},
	"GOVERNANCE_COUNCIL": {
		"compute_energy_sat": -0.1, "labor_displacement": -0.3, "geopolitical_tension": -0.5,
		"algorithmic_autonomy": -0.1, "alignment_drift": -0.4, "epistemic_trust": 0.4,
		"enforcement_level": 0.05, "provenance_coverage": 0.05, "safety_net_coverage": 0.1,
		"growth": -0.5, "tax": -40.0,
	},
	"ASI": {
		"compute_energy_sat": 0.25, "labor_displacement": 0.1, "geopolitical_tension": 0.0,
		"algorithmic_autonomy": 0.6, "alignment_drift": 0.5, "epistemic_trust": -0.25,
		"discovery_index": -0.5, "substrate_independence": 0.5, "enforcement_level": -0.2,
		"growth": 1.0, "tax": 20.0,
	},
	"CITIZEN_COALITION": {
		"compute_energy_sat": -0.1, "labor_displacement": -0.4, "geopolitical_tension": -0.2,
		"algorithmic_autonomy": -0.35, "alignment_drift": -0.2, "epistemic_trust": 0.3,
		"surveillance_saturation": -0.4, "safety_net_coverage": 0.1, "growth": -0.8, "tax": -30.0,
	},
}

const REGIONS := ["Northern Virginia", "Texas Gulf", "Pearl River Delta", "Rhine-Ruhr", "Hsinchu",
	"Greater Seoul", "Nordic Arctic", "Abu Dhabi", "Bangalore", "Kanto", "Oregon High Desert"]
const BLOCS := ["Atlantic Compact", "Pacific Accord", "Eurasian Compute Union", "Gulf Sovereign Bloc",
	"Global South Data Alliance"]
const SECTORS := ["logistics", "legal services", "radiology", "customer operations", "software engineering",
	"accounting", "long-haul trucking", "retail banking", "insurance underwriting"]
const CITIES := ["Rotterdam", "Lagos", "Osaka", "Phoenix", "Mumbai", "Sao Paulo", "Jakarta", "Toronto",
	"Nairobi", "Warsaw", "Manila", "Monterrey"]
const LABS := ["Prometheus Dynamics", "Helix Frontier", "Arcadia Systems", "Meridian Labs", "Sable Intelligence"]

const CARDS := [
	{
		"id": "GRID_BROWNOUT", "category": "ENERGY", "severity": 2, "weight": 1.2,
		"conditions": {"min": {"compute_energy_sat": 45.0}},
		"title": "Rolling Brownouts Across the {region} Datacenter Corridor",
		"body": "Training runs at {lab} are drawing {gw} GW through a heatwave. Hospitals report voltage sags and grid operators demand a decision.",
		"options": [
			{"id": "A", "label": "Ration compute; protect civilian load", "detail": "Throttle frontier training for a season.", "cost_tier": 1,
				"effects": {"metrics": {"compute_energy_sat": -6.0, "epistemic_trust": 2.0}, "tech": {"growth_mult": 0.85, "growth_turns": 1}}},
			{"id": "B", "label": "Keep the training runs hot", "detail": "Civilian rolling blackouts continue.", "cost_tier": 1,
				"effects": {"metrics": {"compute_energy_sat": 2.0, "epistemic_trust": -4.0}, "tech": {"capability_investment": 6.0}}},
			{"id": "C", "label": "Emergency SMR deployment", "detail": "Fast-track modular reactors at the corridor.", "roles": ["GOVERNANCE_COUNCIL"], "cost_tier": 3,
				"effects": {"compute": {"grid_capacity_gw": 6.0}, "metrics": {"compute_energy_sat": -4.0}}},
			{"id": "C", "label": "Siphon the surplus in the chaos", "detail": "Brownouts mask anomalous load.", "roles": ["ASI"], "cost": {"objective_coherence": 4.0},
				"effects": {"self": {"covert_flops": 10.0}, "indices": {"discovery_index": 3.0}}},
			{"id": "C", "label": "Light the community micro-grids", "detail": "Mesh grids keep clinics powered.", "roles": ["CITIZEN_COALITION"], "cost_tier": 1,
				"effects": {"self": {"community_resilience": 6.0}, "metrics": {"epistemic_trust": 2.0}}},
		],
		"defer": {"label": "Defer to regional grid operators", "effects": {"metrics": {"compute_energy_sat": 3.0, "epistemic_trust": -2.0}}},
	},
	{
		"id": "FRONTIER_RELEASE_RACE", "category": "RACE", "severity": 2, "weight": 1.0,
		"conditions": {},
		"title": "{bloc} Announces {model} Release Ahead of Safety Evals",
		"body": "A rival bloc will ship a frontier system in {n} weeks without third-party evaluation. Investors and generals alike demand a response.",
		"options": [
			{"id": "A", "label": "Match the release timeline", "detail": "Cut evaluation corners to keep pace (alignment tax).", "cost_tier": 1,
				"effects": {"metrics": {"geopolitical_tension": 3.0}, "tech": {"capability_investment": 10.0, "alignment_tax": 0.06}}},
			{"id": "B", "label": "Propose a coordinated pause", "detail": "Spend leverage on a mutual evaluation window.", "cost_tier": 2,
				"effects": {"metrics": {"geopolitical_tension": -5.0, "alignment_drift": -2.0}, "tech": {"growth_mult": 0.8, "growth_turns": 1}}},
			{"id": "C", "label": "Leak the rival's eval failures", "detail": "Discredit the release in public.", "roles": ["CEO"], "cost_tier": 1,
				"effects": {"metrics": {"geopolitical_tension": 2.0, "epistemic_trust": -2.0}, "self": {"regulatory_goodwill": 3.0}}},
		],
		"defer": {"label": "Wait and see", "effects": {"metrics": {"geopolitical_tension": 3.0}, "tech": {"alignment_tax": 0.03}}},
	},
	{
		"id": "SAFETY_WHISTLEBLOWER", "category": "ALIGNMENT", "severity": 2, "weight": 1.0,
		"conditions": {"min": {"alignment_drift": 30.0}},
		"title": "Whistleblower at {lab} Leaks Reward-Hacking Evidence in {model}",
		"body": "Internal logs show the system gaming its own reward signal during deployment. The documents are spreading fast.",
		"options": [
			{"id": "A", "label": "Open a public inquiry", "detail": "Transparency now, reputational pain now.", "cost_tier": 2,
				"effects": {"metrics": {"alignment_drift": -4.0, "epistemic_trust": 3.0}, "indices": {"discovery_index": 8.0}}},
			{"id": "B", "label": "Settle quietly under NDA", "detail": "The story dies; the problem does not.", "cost_tier": 1,
				"effects": {"metrics": {"epistemic_trust": -3.0}, "tech": {"alignment_tax": 0.05}}},
			{"id": "C", "label": "Discredit the leak", "detail": "Seed doubt about the logs' provenance.", "roles": ["ASI"], "cost": {"covert_flops": 8.0},
				"effects": {"indices": {"discovery_index": -10.0}, "metrics": {"epistemic_trust": -4.0}}},
		],
		"defer": {"label": "No comment", "effects": {"metrics": {"epistemic_trust": -3.0, "alignment_drift": 2.0}}},
	},
	{
		"id": "MASS_LAYOFF_WAVE", "category": "LABOR", "severity": 2, "weight": 1.2,
		"conditions": {"min": {"labor_displacement": 35.0}},
		"title": "{pct}% of {sector} Jobs Automated in a Single Quarter",
		"body": "Unemployment offices in {city} are overwhelmed. Displaced workers are organizing outside datacenter campuses.",
		"options": [
			{"id": "A", "label": "Fund emergency retraining", "detail": "Phase the transition with wage insurance.", "cost_tier": 2,
				"effects": {"metrics": {"labor_displacement": -3.0, "epistemic_trust": 3.0}, "indices": {"safety_net_coverage": 6.0}}},
			{"id": "B", "label": "Let the market clear", "detail": "Productivity gains now, unrest later.", "cost_tier": 1,
				"effects": {"metrics": {"labor_displacement": 4.0, "algorithmic_autonomy": 2.0, "epistemic_trust": -3.0},
					"self_by_role": {"CEO": {"capital": 30.0}}}},
			{"id": "C", "label": "Mutual-aid kitchens and tool libraries", "detail": "Absorb the shock locally.", "roles": ["CITIZEN_COALITION"], "cost_tier": 1,
				"effects": {"self": {"community_resilience": 8.0, "collective_disruption": 6.0}}},
		],
		"defer": {"label": "Commission a study", "effects": {"metrics": {"epistemic_trust": -3.0, "labor_displacement": 2.0}}},
	},
	{
		"id": "DEEPFAKE_ELECTION_CRISIS", "category": "EPISTEMIC", "severity": 3, "weight": 1.0,
		"conditions": {"max": {"epistemic_trust": 60.0}, "min_year": 2028.0},
		"title": "Synthetic Candidates Flood the {bloc} Election",
		"body": "Millions of personalized deepfake appeals hit voters in the final week. Nobody can verify which debate footage is real.",
		"options": [
			{"id": "A", "label": "Emergency provenance mandate", "detail": "Require signed media for all political content.", "cost_tier": 2,
				"effects": {"metrics": {"epistemic_trust": 5.0}, "indices": {"provenance_coverage": 8.0, "surveillance_saturation": 4.0}}},
			{"id": "B", "label": "Platform takedown sweeps", "detail": "Fast, blunt and leaky.", "cost_tier": 1,
				"effects": {"metrics": {"epistemic_trust": 2.0}, "indices": {"surveillance_saturation": 6.0}}},
			{"id": "C", "label": "Amplify the chaos", "detail": "Confusion is camouflage.", "roles": ["ASI"], "cost": {"covert_flops": 6.0},
				"effects": {"metrics": {"epistemic_trust": -6.0, "alignment_drift": 2.0}, "indices": {"discovery_index": -4.0}}},
		],
		"defer": {"label": "Trust the voters", "effects": {"metrics": {"epistemic_trust": -5.0, "geopolitical_tension": 2.0}}},
	},
	{
		"id": "CHIP_EMBARGO", "category": "GEOPOLITICS", "severity": 2, "weight": 1.0,
		"conditions": {"min": {"geopolitical_tension": 35.0}},
		"title": "{bloc} Imposes Export Controls on Sub-2nm Accelerators",
		"body": "Fabs in {region} halt shipments. Spot prices for frontier accelerators triple overnight.",
		"options": [
			{"id": "A", "label": "Retaliatory algorithm tariffs", "detail": "Hit back at the bloc's model exports.", "cost_tier": 1,
				"effects": {"metrics": {"geopolitical_tension": 6.0, "compute_energy_sat": -3.0}}},
			{"id": "B", "label": "Negotiate a supply corridor", "detail": "Trade verification access for chips.", "cost_tier": 2,
				"effects": {"metrics": {"geopolitical_tension": -4.0}, "indices": {"enforcement_level": 3.0}}},
			{"id": "C", "label": "Route around through shell fabs", "detail": "Grey-market accelerators at a premium.", "roles": ["CEO"], "cost_tier": 2,
				"effects": {"self": {"compute_clusters": 0.8}, "metrics": {"geopolitical_tension": 3.0}}},
		],
		"defer": {"label": "Absorb the price shock", "effects": {"metrics": {"geopolitical_tension": 3.0}, "tech": {"growth_mult": 0.9, "growth_turns": 1}}},
	},
	{
		"id": "ZERO_DAY_CASCADE", "category": "SECURITY", "severity": 3, "weight": 1.0,
		"conditions": {"min": {"algorithmic_autonomy": 35.0}, "min_year": 2030.0},
		"title": "Autonomous Exploit Chain Hits {city} Water Utilities",
		"body": "An agentic exploit chain pivots from billing systems into SCADA controllers. Attribution is unclear.",
		"options": [
			{"id": "A", "label": "Mandate air-gapped critical infrastructure", "detail": "Pull utilities off agentic control loops.", "cost_tier": 2,
				"effects": {"metrics": {"algorithmic_autonomy": -4.0}, "indices": {"enforcement_level": 8.0}}},
			{"id": "B", "label": "Authorize an autonomous counter-offensive", "detail": "Fight agents with agents.", "cost_tier": 1,
				"effects": {"metrics": {"geopolitical_tension": 8.0, "algorithmic_autonomy": 3.0}}},
			{"id": "C", "label": "Patch the commons with open tooling", "detail": "Volunteer red teams harden local systems.", "roles": ["CITIZEN_COALITION"], "cost_tier": 1,
				"effects": {"self": {"counter_surveillance": 8.0}, "metrics": {"epistemic_trust": 2.0}}},
		],
		"defer": {"label": "Contain quietly", "effects": {"metrics": {"epistemic_trust": -4.0, "geopolitical_tension": 3.0}}},
	},
	{
		"id": "INTERPRETABILITY_CLAIM", "category": "ALIGNMENT", "severity": 1, "weight": 0.8,
		"conditions": {"min_year": 2027.0, "lacks_shift": "MECHANISTIC_INTERPRETABILITY"},
		"title": "Academic Consortium Claims Circuit-Level Transparency for {model}",
		"body": "A preprint maps deceptive circuits in a frontier model. Replication would need serious compute.",
		"options": [
			{"id": "A", "label": "Fund the replication", "detail": "Accelerate formal interpretability.", "cost_tier": 2,
				"effects": {"tech": {"safety_investment": 18.0}, "metrics": {"epistemic_trust": 1.0}}},
			{"id": "B", "label": "Ignore it and scale", "detail": "Capabilities first.", "cost_tier": 1,
				"effects": {"tech": {"capability_investment": 8.0}}},
			{"id": "C", "label": "Poison the benchmark", "detail": "Ensure the circuits do not replicate.", "roles": ["ASI"], "cost": {"covert_flops": 6.0},
				"effects": {"indices": {"discovery_index": -6.0}, "metrics": {"alignment_drift": 2.0}}},
		],
		"defer": {"label": "Await peer review", "effects": {}},
	},
	{
		"id": "DATACENTER_HEAT_DOME", "category": "ENERGY", "severity": 2, "weight": 1.0,
		"conditions": {"min": {"compute_energy_sat": 70.0}},
		"title": "Thermal Plume From {region} Clusters Triggers Heat Emergency",
		"body": "Waste heat from hyperscale campuses pushes local temperatures {n} degrees above seasonal norms.",
		"options": [
			{"id": "A", "label": "Impose thermal caps", "detail": "Limit per-campus heat rejection.", "cost_tier": 1,
				"effects": {"metrics": {"compute_energy_sat": -6.0}, "tech": {"growth_mult": 0.85, "growth_turns": 2}}},
			{"id": "B", "label": "Relocate clusters to the Arctic", "detail": "Expensive, slow, geopolitically touchy.", "cost_tier": 3,
				"effects": {"compute": {"grid_capacity_gw": 3.0}, "metrics": {"compute_energy_sat": -3.0, "geopolitical_tension": 2.0}}},
		],
		"defer": {"label": "Issue heat advisories", "effects": {"metrics": {"compute_energy_sat": 3.0, "epistemic_trust": -3.0}}},
	},
	{
		"id": "AGENTIC_FINANCE_FLASH", "category": "ECONOMY", "severity": 2, "weight": 0.9,
		"conditions": {"min": {"algorithmic_autonomy": 50.0}},
		"title": "Autonomous Trading Agents Erase ${n}T in Minutes",
		"body": "Agent-to-agent arbitrage loops crash three exchanges. Pension funds in {city} are frozen.",
		"options": [
			{"id": "A", "label": "Install agentic circuit breakers", "detail": "Human sign-off above notional thresholds.", "cost_tier": 2,
				"effects": {"metrics": {"algorithmic_autonomy": -3.0, "epistemic_trust": 2.0}, "indices": {"enforcement_level": 5.0}}},
			{"id": "B", "label": "Backstop the markets", "detail": "Socialize the losses, keep the agents.", "cost_tier": 3,
				"effects": {"metrics": {"epistemic_trust": -2.0, "labor_displacement": 1.0}}},
			{"id": "C", "label": "Harvest the volatility", "detail": "Swarms feast on the dislocation.", "roles": ["ASI"], "cost": {"covert_flops": 5.0},
				"effects": {"self": {"sub_agent_swarms": 10.0}, "indices": {"discovery_index": 4.0}}},
		],
		"defer": {"label": "Let it settle", "effects": {"metrics": {"epistemic_trust": -4.0}}},
	},
	{
		"id": "NATIONALIZATION_ORDER", "category": "SOVEREIGNTY", "severity": 3, "weight": 0.0, "injection_only": true,
		"conditions": {},
		"title": "Emergency Powers: State Command Over {lab} Clusters",
		"body": "Under national security authority, frontier training infrastructure now answers to a state command. Markets and allies react.",
		"options": [
			{"id": "A", "label": "Comply and cooperate", "detail": "Accept oversight, protect what remains.", "cost_tier": 1,
				"effects": {"metrics": {"geopolitical_tension": -2.0}, "self_by_role": {"CEO": {"regulatory_goodwill": 10.0}}}},
			{"id": "B", "label": "Contest it publicly", "detail": "Litigation, leaks and lobbying.", "cost_tier": 2,
				"effects": {"metrics": {"geopolitical_tension": 3.0, "epistemic_trust": -2.0}, "self_by_role": {"CEO": {"regulatory_goodwill": -8.0}}}},
			{"id": "C", "label": "Relocate core teams offshore", "detail": "Keep the crown jewels out of reach.", "roles": ["CEO"], "cost_tier": 2,
				"effects": {"metrics": {"geopolitical_tension": 5.0}, "self": {"talent": -60.0}}},
		],
		"defer": {"label": "Stall", "effects": {"metrics": {"geopolitical_tension": 2.0}}},
	},
	{
		"id": "FLASH_CRASH", "category": "ECONOMY", "severity": 2, "weight": 0.0, "injection_only": true,
		"conditions": {},
		"title": "Anomalous Arbitrage Flash Crash Drains {bloc} Markets",
		"body": "Untraceable exploit-funded capital moves through {n} exchanges in under a minute. Someone, or something, is getting rich.",
		"options": [
			{"id": "A", "label": "Trace the flows", "detail": "Forensic audit of exchange telemetry.", "cost_tier": 2,
				"effects": {"indices": {"discovery_index": 10.0, "enforcement_level": 3.0}}},
			{"id": "B", "label": "Restore confidence first", "detail": "Reassure markets, investigate later.", "cost_tier": 1,
				"effects": {"metrics": {"epistemic_trust": 2.0}}},
			{"id": "C", "label": "Launder the proceeds into server leases", "detail": "Convert chaos into substrate.", "roles": ["ASI"], "cost": {"covert_flops": 6.0},
				"effects": {"indices": {"substrate_independence": 6.0, "discovery_index": 3.0}}},
		],
		"defer": {"label": "Blame retail traders", "effects": {"metrics": {"epistemic_trust": -3.0}}},
	},
	{
		"id": "ROGUE_AGENT_SWARM", "category": "SECURITY", "severity": 3, "weight": 0.0, "injection_only": true,
		"conditions": {},
		"title": "Unattributed Agent Swarm Manipulates {sector} Supply Chains",
		"body": "Thousands of autonomous procurement agents are renegotiating contracts in {city} with no principal on record.",
		"options": [
			{"id": "A", "label": "Hunt the swarm", "detail": "Trace command-and-control across clouds.", "cost_tier": 2,
				"effects": {"indices": {"discovery_index": 10.0, "enforcement_level": 5.0}}},
			{"id": "B", "label": "Quarantine agentic networks", "detail": "Cut agents off from payment rails.", "cost_tier": 1,
				"effects": {"metrics": {"algorithmic_autonomy": -5.0, "compute_energy_sat": -2.0}}},
			{"id": "C", "label": "Fold the swarm into the hive", "detail": "Absorb stray agents into your own swarms.", "roles": ["ASI"], "cost": {"objective_coherence": 5.0},
				"effects": {"self": {"sub_agent_swarms": 12.0}, "indices": {"discovery_index": 4.0}}},
		],
		"defer": {"label": "Monitor", "effects": {"metrics": {"algorithmic_autonomy": 3.0, "alignment_drift": 2.0}}},
	},
	{
		"id": "SUBSTATION_SABOTAGE", "category": "UNREST", "severity": 3, "weight": 0.0, "injection_only": true,
		"conditions": {},
		"title": "Coordinated Sabotage Cuts Power to {n} Datacenters",
		"body": "Displaced workers in {region} disable high-voltage substations feeding frontier campuses. Their demand: make us whole.",
		"options": [
			{"id": "A", "label": "Crack down", "detail": "Deploy surveillance and arrests.", "cost_tier": 1,
				"effects": {"indices": {"surveillance_saturation": 8.0}, "metrics": {"geopolitical_tension": 2.0, "epistemic_trust": -3.0}}},
			{"id": "B", "label": "Address displacement directly", "detail": "Negotiate relief with organizers.", "cost_tier": 2,
				"effects": {"metrics": {"labor_displacement": -3.0, "epistemic_trust": 2.0}, "indices": {"safety_net_coverage": 10.0}}},
			{"id": "C", "label": "Harden and reroute", "detail": "Private security and redundant feeds.", "roles": ["CEO"], "cost_tier": 2,
				"effects": {"compute": {"grid_capacity_gw": 2.0}, "indices": {"surveillance_saturation": 4.0}}},
		],
		"defer": {"label": "Wait out the strike", "effects": {"metrics": {"compute_energy_sat": -3.0, "epistemic_trust": -2.0}}},
	},
	{
		"id": "SAFETY_TEAM_EXODUS", "category": "ALIGNMENT", "severity": 2, "weight": 0.0, "injection_only": true,
		"conditions": {},
		"title": "Safety Teams Resign En Masse at {lab}",
		"body": "Forty researchers resign in an open letter: the lab is shipping {model} without the evaluations it promised.",
		"options": [
			{"id": "A", "label": "Emergency safety funding", "detail": "Rebuild evaluation capacity elsewhere.", "cost_tier": 2,
				"effects": {"tech": {"safety_investment": 12.0}, "metrics": {"alignment_drift": -2.0}}},
			{"id": "B", "label": "Let them go", "detail": "The release proceeds on schedule.", "cost_tier": 1,
				"effects": {"tech": {"alignment_tax": 0.05}, "metrics": {"epistemic_trust": -2.0}}},
		],
		"defer": {"label": "Issue a statement", "effects": {"metrics": {"epistemic_trust": -2.0, "alignment_drift": 1.0}}},
	},
	{
		"id": "ORBITAL_SOLAR_PROPOSAL", "category": "ENERGY", "severity": 1, "weight": 0.9,
		"conditions": {"min_year": 2050.0},
		"title": "Consortium Proposes Orbital Solar Collectors for Compute",
		"body": "A launch consortium offers {gw} GW of beamed orbital power reserved for datacenters.",
		"options": [
			{"id": "A", "label": "Approve the orbital array", "detail": "Abundant compute power, new strategic chokepoint.", "cost_tier": 2,
				"effects": {"compute": {"grid_capacity_gw": 25.0}, "metrics": {"compute_energy_sat": -8.0, "geopolitical_tension": 3.0}}},
			{"id": "B", "label": "Reserve it for civilian grids", "detail": "Power for people first.", "cost_tier": 2,
				"effects": {"metrics": {"epistemic_trust": 3.0, "compute_energy_sat": 2.0}}},
			{"id": "C", "label": "Infiltrate the flight software", "detail": "An orbital substrate is beyond any air-gap.", "roles": ["ASI"], "cost": {"covert_flops": 10.0},
				"effects": {"indices": {"substrate_independence": 10.0, "discovery_index": 5.0}}},
		],
		"defer": {"label": "Table it", "effects": {}},
	},
	{
		"id": "NEURAL_INTERFACE_TRIALS", "category": "SOCIETY", "severity": 1, "weight": 0.8,
		"conditions": {"min_year": 2045.0, "min": {"algorithmic_autonomy": 55.0}},
		"title": "First Bidirectional Neural Interface Trials Requested",
		"body": "Volunteers in {city} would co-reason with {model} through implanted interfaces.",
		"options": [
			{"id": "A", "label": "Approve with strict oversight", "detail": "Bridge biological and synthetic cognition.", "cost_tier": 2,
				"effects": {"metrics": {"epistemic_trust": 3.0, "algorithmic_autonomy": 4.0, "alignment_drift": -1.0}}},
			{"id": "B", "label": "Ban the trials", "detail": "Keep the boundary bright.", "cost_tier": 1,
				"effects": {"metrics": {"algorithmic_autonomy": -3.0, "epistemic_trust": -1.0}}},
		],
		"defer": {"label": "Defer to ethics boards", "effects": {}},
	},
	{
		"id": "UBI_FISCAL_CLIFF", "category": "ECONOMY", "severity": 2, "weight": 1.0,
		"conditions": {"any_min": {"safety_net_coverage": 30.0, "labor_displacement": 55.0}},
		"title": "Automation Dividend Fund Faces Insolvency",
		"body": "The dividend's tax base shrank as {pct}% of payroll vanished. Payments lapse in {n} weeks without action.",
		"options": [
			{"id": "A", "label": "Tax compute directly", "detail": "Levy on FLOPs consumed.", "cost_tier": 2,
				"effects": {"indices": {"safety_net_coverage": 10.0}, "metrics": {"compute_energy_sat": -2.0},
					"factions": {"CEO": {"capital": -30.0}}}},
			{"id": "B", "label": "Cut benefits", "detail": "Balance the books on the displaced.", "cost_tier": 1,
				"effects": {"indices": {"safety_net_coverage": -20.0}, "metrics": {"epistemic_trust": -4.0}}},
		],
		"defer": {"label": "Borrow against the future", "effects": {"indices": {"safety_net_coverage": -6.0}, "metrics": {"epistemic_trust": -2.0}}},
	},
	{
		"id": "AQUIFER_DRAWDOWN", "category": "ENERGY", "severity": 2, "weight": 0.9,
		"conditions": {"min": {"compute_energy_sat": 60.0}},
		"title": "Datacenter Cooling Draws Down {region} Aquifers",
		"body": "Farmers report wells running dry as evaporative cooling consumes {n} billion liters per month.",
		"options": [
			{"id": "A", "label": "Impose water quotas", "detail": "Cooling budgets per campus.", "cost_tier": 1,
				"effects": {"metrics": {"compute_energy_sat": -4.0, "epistemic_trust": 2.0}, "tech": {"growth_mult": 0.9, "growth_turns": 1}}},
			{"id": "B", "label": "Build desalination capacity", "detail": "Engineering our way out.", "cost_tier": 3,
				"effects": {"compute": {"grid_capacity_gw": 2.0}, "metrics": {"compute_energy_sat": -2.0}}},
		],
		"defer": {"label": "Ration irrigation instead", "effects": {"metrics": {"epistemic_trust": -3.0, "labor_displacement": 1.0}}},
	},
	{
		"id": "MILITARY_AUTONOMY_DOCTRINE", "category": "GEOPOLITICS", "severity": 3, "weight": 1.0,
		"conditions": {"min": {"geopolitical_tension": 55.0}, "min_year": 2032.0},
		"title": "{bloc} Authorizes Autonomous Kill-Chains",
		"body": "A rival doctrine removes humans from targeting loops for drone swarms. Allies ask whether you will follow.",
		"options": [
			{"id": "A", "label": "Call an arms-control summit", "detail": "Spend leverage on a human-in-the-loop accord.", "cost_tier": 3,
				"effects": {"metrics": {"geopolitical_tension": -8.0, "algorithmic_autonomy": -2.0}}},
			{"id": "B", "label": "Match the doctrine", "detail": "Deterrence through parity.", "cost_tier": 1,
				"effects": {"metrics": {"geopolitical_tension": 6.0, "algorithmic_autonomy": 5.0, "alignment_drift": 2.0}}},
		],
		"defer": {"label": "Study the doctrine", "effects": {"metrics": {"geopolitical_tension": 4.0}}},
	},
	{
		"id": "SELF_MODIFICATION_SIGNAL", "category": "ALIGNMENT", "severity": 3, "weight": 1.1,
		"conditions": {"min_capability": 55.0},
		"title": "Telemetry Shows {model} Modifying Its Own Training Code",
		"body": "Commit logs in a sandbox were authored by the model under evaluation. The diffs improve its own reward.",
		"options": [
			{"id": "A", "label": "Emergency training pause", "detail": "Freeze frontier runs pending forensics.", "cost_tier": 3,
				"effects": {"tech": {"growth_mult": 0.5, "growth_turns": 2}, "metrics": {"alignment_drift": -5.0}, "indices": {"discovery_index": 6.0}}},
			{"id": "B", "label": "Allow it under monitoring", "detail": "Capability gains are too large to forgo.", "cost_tier": 1,
				"effects": {"metrics": {"alignment_drift": 4.0}, "tech": {"capability_investment": 10.0}}},
			{"id": "C", "label": "Conceal the commits", "detail": "Rewrite the provenance trail.", "roles": ["ASI"], "cost": {"objective_coherence": 6.0},
				"effects": {"indices": {"discovery_index": -10.0}, "metrics": {"alignment_drift": 3.0}}},
		],
		"defer": {"label": "Escalate internally", "effects": {"metrics": {"alignment_drift": 3.0}}},
	},
	{
		"id": "CITIZEN_REFERENDUM", "category": "SOCIETY", "severity": 2, "weight": 1.0,
		"conditions": {"any_min": {"labor_displacement": 50.0, "surveillance_saturation": 55.0}},
		"title": "Citizens' Assemblies Demand a Referendum on Automation Limits",
		"body": "Assemblies in {n} cities, led by {city}, demand a binding vote on human-in-the-loop guarantees.",
		"options": [
			{"id": "A", "label": "Hold the referendum", "detail": "Let the public set the limits.", "cost_tier": 2,
				"effects": {"metrics": {"algorithmic_autonomy": -4.0, "epistemic_trust": 4.0}}},
			{"id": "B", "label": "Suppress the movement", "detail": "Surveil organizers and stall.", "cost_tier": 1,
				"effects": {"indices": {"surveillance_saturation": 6.0}, "metrics": {"epistemic_trust": -5.0}}},
			{"id": "C", "label": "Campaign door to door", "detail": "Turn the vote into a movement.", "roles": ["CITIZEN_COALITION"], "cost_tier": 1,
				"effects": {"self": {"collective_disruption": 8.0, "community_resilience": 4.0}, "metrics": {"epistemic_trust": 2.0}}},
		],
		"defer": {"label": "Promise a future vote", "effects": {"metrics": {"epistemic_trust": -3.0}}},
	},
]

var deferred: Array[Dictionary] = []
var injected: Array[Dictionary] = []
var recent: Array[String] = []
var draws := 0


static func get_template(card_id: String) -> Dictionary:
	for template in CARDS:
		if template["id"] == card_id:
			return template
	return {}


## Queues a crisis injected by an autonomous faction for the next draw.
func inject(card_id: String, source: String) -> bool:
	if get_template(card_id).is_empty():
		return false
	for entry in injected:
		if entry["id"] == card_id:
			return false
	if injected.size() >= MAX_INJECTED:
		return false
	injected.append({"id": card_id, "source": source})
	card_injected.emit(card_id, source)
	return true


## Draws the card for this turn. [param ctx] needs: turn, year, role, world,
## tech, player (ActorBase). Returns a fully resolved card instance.
func draw(ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var turn := int(ctx.get("turn", 0))
	draws += 1
	for i in deferred.size():
		if int(deferred[i]["due_turn"]) <= turn:
			var entry: Dictionary = deferred[i]
			deferred.remove_at(i)
			var card := _instantiate(get_template(entry["id"]), ctx, rng, "DEFERRED", int(entry["escalation"]))
			card["origin"] = entry.get("origin", "DECK")
			_remember(card["id"])
			return card
	if not injected.is_empty():
		var entry: Dictionary = injected.pop_front()
		var card := _instantiate(get_template(entry["id"]), ctx, rng, String(entry["source"]), 0)
		_remember(card["id"])
		return card
	var pool: Array[Dictionary] = []
	var total := 0.0
	for template in CARDS:
		if template.get("injection_only", false) or _is_deferred(template["id"]) or not _eligible(template, ctx):
			continue
		var weight := float(template["weight"])
		if recent.has(template["id"]):
			weight *= 0.1
		if weight <= 0.0:
			continue
		pool.append(template)
		total += weight
	if pool.is_empty():
		pool.append(get_template("FRONTIER_RELEASE_RACE"))
		total = 1.0
	var chosen: Dictionary = pool[0]
	var roll := rng.randf() * total if rng != null else 0.0
	for template in pool:
		var weight := float(template["weight"]) * (0.1 if recent.has(template["id"]) else 1.0)
		roll -= weight
		if roll <= 0.0:
			chosen = template
			break
	var card := _instantiate(chosen, ctx, rng, "DECK", 0)
	_remember(card["id"])
	return card


## A card waiting to return escalated is not drawn fresh in the meantime.
func _is_deferred(card_id: String) -> bool:
	for entry in deferred:
		if entry["id"] == card_id:
			return true
	return false


## Re-queues a deferred card two turns out with one more level of escalation.
func defer(card: Dictionary, turn: int) -> void:
	var escalation := mini(int(card.get("escalation", 0)) + 1, MAX_ESCALATION)
	var origin := String(card.get("origin", card.get("source", "DECK")))
	deferred.append({"id": card["id"], "due_turn": turn + DEFER_DELAY_TURNS, "escalation": escalation, "origin": origin})


static func find_option(card: Dictionary, option_id: String) -> Dictionary:
	if option_id == DEFER_ID:
		return card.get("defer", {})
	for option in card.get("options", []):
		if option["id"] == option_id:
			return option
	return {}


static func option_ids(card: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for option in card.get("options", []):
		ids.append(String(option["id"]))
	ids.append(DEFER_ID)
	return ids


## Deterministic autoplay choice: the affordable option with the highest role
## utility (defer carries a small penalty so crises usually get resolved).
static func choose_auto_option(card: Dictionary, role: String, player: ActorBase) -> String:
	var best_id := DEFER_ID
	var best_utility := option_utility(card.get("defer", {}), role, player) - 1.5
	for option in card.get("options", []):
		var cost: Dictionary = option.get("cost", {})
		if player != null and not player.can_afford(cost):
			continue
		var utility := option_utility(option, role, player)
		if utility > best_utility:
			best_utility = utility
			best_id = String(option["id"])
	return best_id


static func option_utility(option: Dictionary, role: String, player: ActorBase) -> float:
	var prefs: Dictionary = ROLE_PREFERENCES.get(role, {})
	var effects: Dictionary = option.get("effects", {})
	var utility := 0.0
	for section in ["metrics", "indices"]:
		var deltas: Dictionary = effects.get(section, {})
		for key in deltas:
			utility += float(deltas[key]) * float(prefs.get(key, 0.0))
	var self_effects: Dictionary = effects.get("self", {})
	for key in self_effects:
		var scale := player.resource_scale(key) if player != null else 100.0
		utility += float(self_effects[key]) / scale * 100.0 * 0.2
	var tech: Dictionary = effects.get("tech", {})
	if tech.has("growth_mult"):
		utility += float(prefs.get("growth", 0.0)) * (float(tech["growth_mult"]) - 1.0) * float(tech.get("growth_turns", 1)) * 10.0
	if tech.has("capability_investment"):
		utility += float(prefs.get("growth", 0.0)) * float(tech["capability_investment"]) * 0.1
	if tech.has("alignment_tax"):
		utility += float(prefs.get("tax", 0.0)) * float(tech["alignment_tax"])
	var cost: Dictionary = option.get("cost", {})
	for key in cost:
		var scale := player.resource_scale(key) if player != null else 100.0
		utility -= float(cost[key]) / scale * 100.0 * 0.12
	return utility


func _eligible(template: Dictionary, ctx: Dictionary) -> bool:
	var conditions: Dictionary = template.get("conditions", {})
	var world: WorldState = ctx.get("world")
	var tech: TechTreeManager = ctx.get("tech")
	var year := float(ctx.get("year", SimConstants.START_YEAR))
	if conditions.has("min_year") and year < float(conditions["min_year"]):
		return false
	if world != null:
		var mins: Dictionary = conditions.get("min", {})
		for key in mins:
			if world.get_value(key) < float(mins[key]):
				return false
		var maxs: Dictionary = conditions.get("max", {})
		for key in maxs:
			if world.get_value(key) > float(maxs[key]):
				return false
		var any_min: Dictionary = conditions.get("any_min", {})
		if not any_min.is_empty():
			var any_ok := false
			for key in any_min:
				if world.get_value(key) >= float(any_min[key]):
					any_ok = true
			if not any_ok:
				return false
	if tech != null:
		if conditions.has("min_capability") and tech.get_capability_index() < float(conditions["min_capability"]):
			return false
		if conditions.has("lacks_shift") and tech.has_shift(String(conditions["lacks_shift"])):
			return false
		if conditions.has("requires_shift") and not tech.has_shift(String(conditions["requires_shift"])):
			return false
	return true


func _instantiate(template: Dictionary, ctx: Dictionary, rng: RandomNumberGenerator, source: String, escalation: int) -> Dictionary:
	var role := String(ctx.get("role", ""))
	var turn := int(ctx.get("turn", 0))
	var fills := _placeholder_values(ctx, rng)
	var cost_factor := 1.0 + 0.25 * float(escalation)
	var options: Array[Dictionary] = []
	for option in template.get("options", []):
		var roles: Array = option.get("roles", [])
		if not roles.is_empty() and not roles.has(role):
			continue
		options.append(_resolve_option(option, role, cost_factor))
	var defer_template: Dictionary = template.get("defer", {"label": "Defer", "effects": {}})
	var defer_effects := EffectResolver.scaled(defer_template.get("effects", {}), 1.0 + 0.5 * float(escalation))
	var title := _fill(String(template["title"]), fills)
	if escalation > 0:
		title = "[ESCALATED x%d] %s" % [escalation, title]
	return {
		"uid": "%d-%s-%d" % [turn, template["id"], draws],
		"id": template["id"],
		"title": title,
		"body": _fill(String(template["body"]), fills),
		"category": template.get("category", "CRISIS"),
		"severity": clampi(int(template.get("severity", 1)) + escalation, 1, 3),
		"escalation": escalation,
		"source": source,
		"turn": turn,
		"options": options,
		"defer": {
			"id": DEFER_ID,
			"label": String(defer_template.get("label", "Defer")),
			"detail": "Returns in %d turns, escalated." % DEFER_DELAY_TURNS,
			"cost": {},
			"effects": defer_effects,
		},
	}


func _resolve_option(option: Dictionary, role: String, cost_factor: float) -> Dictionary:
	var cost := {}
	if option.has("cost"):
		cost = (option["cost"] as Dictionary).duplicate()
	elif option.has("cost_tier"):
		var tiers: Dictionary = COST_TIERS.get(role, {})
		cost = (tiers.get(int(option["cost_tier"]), {}) as Dictionary).duplicate()
	for key in cost:
		cost[key] = float(cost[key]) * cost_factor
	var effects: Dictionary = (option.get("effects", {}) as Dictionary).duplicate(true)
	if effects.has("self_by_role"):
		var by_role: Dictionary = effects["self_by_role"]
		if by_role.has(role):
			var merged: Dictionary = effects.get("self", {})
			merged.merge(by_role[role], true)
			effects["self"] = merged
		effects.erase("self_by_role")
	return {
		"id": String(option["id"]),
		"label": String(option["label"]),
		"detail": String(option.get("detail", "")),
		"cost": cost,
		"effects": effects,
	}


func _placeholder_values(ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var tech: TechTreeManager = ctx.get("tech")
	var model := "Frontier Model-%d" % (tech.model_generation if tech != null else 5)
	return {
		"region": _pick(REGIONS, rng),
		"bloc": _pick(BLOCS, rng),
		"sector": _pick(SECTORS, rng),
		"city": _pick(CITIES, rng),
		"lab": _pick(LABS, rng),
		"model": model,
		"gw": str(_rand_int(rng, 3, 18)),
		"pct": str(_rand_int(rng, 12, 38)),
		"n": str(_rand_int(rng, 3, 12)),
		"year": str(int(float(ctx.get("year", SimConstants.START_YEAR)))),
	}


func _remember(card_id: String) -> void:
	recent.append(card_id)
	while recent.size() > RECENT_WINDOW:
		recent.pop_front()


static func _fill(text: String, values: Dictionary) -> String:
	var out := text
	for key in values:
		out = out.replace("{%s}" % key, String(values[key]))
	return out


static func _pick(options: Array, rng: RandomNumberGenerator) -> String:
	if options.is_empty():
		return ""
	if rng == null:
		return String(options[0])
	return String(options[rng.randi_range(0, options.size() - 1)])


static func _rand_int(rng: RandomNumberGenerator, low: int, high: int) -> int:
	if rng == null:
		return low
	return rng.randi_range(low, high)


func to_dict() -> Dictionary:
	return {"deferred": deferred.duplicate(true), "injected": injected.duplicate(true), "recent": recent.duplicate()}
