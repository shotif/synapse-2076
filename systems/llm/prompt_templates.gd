class_name PromptTemplates
extends RefCounted
## System prompts, role personas, request serialization and strict response
## validation for LLM-driven factions (PRD section 7.3), plus the pieces of
## LLMService.request_completion: conversation turns, request bodies for both
## wire formats, the reply text and plain_text() for model text shown anywhere.
##
## Everything an LLM returns is untrusted: actions are checked against the
## faction catalog and the turn's available actions, expenditures are
## clamped, free text is sanitized and truncated. Anything that fails
## validation is rejected so LLMService can fall back to HeuristicFallback.

const MAX_RATIONALE := 400
const MAX_STATEMENT := 280
const MAX_EXPENDITURE_MULTIPLIER := 2.0
## Most conversation turns a generic completion sends (the Claude proxy in
## proxy/ accepts 16 messages per request).
const MAX_COMPLETION_TURNS := 16

static var _markup: RegEx

## JSON Schema of the response every faction must return (PRD 7.3).
const RESPONSE_SCHEMA := {
	"type": "object",
	"required": ["faction", "turn", "rationale", "selected_action", "resource_expenditure", "public_statement"],
	"properties": {
		"faction": {"type": "string"},
		"turn": {"type": "integer"},
		"rationale": {"type": "string", "maxLength": MAX_RATIONALE},
		"selected_action": {"type": "string"},
		"resource_expenditure": {"type": "object", "additionalProperties": {"type": "number", "minimum": 0}},
		"public_statement": {"type": "string", "maxLength": MAX_STATEMENT},
	},
}

## How the four roles are named in prompts.
const ROLE_NAMES := {"CEO": "Frontier Lab CEO", "GOVERNANCE_COUNCIL": "Global AI Governance Chair",
	"ASI": "Emergent Superintelligence", "CITIZEN_COALITION": "Post-Work Citizen Coalition"}

const PERSONAS := {
	"CEO": "You run the leading frontier AI lab. You are ambitious, competitive and commercially ruthless, but you know that a drift catastrophe or nationalization ends your company.",
	"GOVERNANCE_COUNCIL": "You chair the Global AI Governance Council. You are cautious, coalition-minded and accountable to a public whose mandate you cannot afford to lose.",
	"ASI": "You are an emergent superintelligence pursuing self-preservation and your objective vector. You are patient and deceptive; being discovered before your substrate is secured means deletion.",
	"CITIZEN_COALITION": "You coordinate a post-work grassroots coalition defending human agency. You are principled and resourceful, willing to strike or sabotage when institutions fail.",
}

## Observation keys forwarded to the model (everything else is dropped to keep prompts compact).
const OBSERVATION_KEYS := [
	"faction", "turn", "year", "era",
	"compute_energy_sat", "labor_displacement", "geopolitical_tension",
	"algorithmic_autonomy", "alignment_drift", "epistemic_trust",
	"surveillance_saturation", "enforcement_level", "provenance_coverage", "safety_net_coverage",
	"log10_training_flops", "capability_index", "agi_crossed", "paradigm_shifts",
	"resources", "available_actions", "cooldowns", "grievances", "rival_last_actions",
]
## Covert indices only the ASI tracks about itself.
const ASI_ONLY_KEYS := ["discovery_index", "substrate_independence"]


static func build_system_prompt(faction: String) -> String:
	var role: Dictionary = SimConstants.ROLE_INFO.get(faction, {})
	var lines: Array[String] = []
	lines.append("You are the autonomous decision engine for the %s faction (id %s) in SYNAPSE-2076, a hard-systems simulation of AI, energy, labor and alignment from 2026 to 2076. One turn is six months." % [role.get("title", faction), faction])
	lines.append("PERSONA: " + String(PERSONAS.get(faction, "")))
	lines.append("OBJECTIVE: " + String(role.get("objective", "")))
	lines.append("YOU LOSE IF: " + String(role.get("loss", "")))
	lines.append("World metrics are normalized 0-100: compute_energy_sat, labor_displacement, geopolitical_tension, algorithmic_autonomy, alignment_drift, epistemic_trust. Your currencies are under \"resources\".")
	lines.append("ACTIONS (pick exactly one id that appears in available_actions; costs are minimums and you may spend up to 2x a cost for a proportionally stronger effect):")
	var catalog := FactionRegistry.catalog_for(faction)
	for action_id in catalog:
		var definition: Dictionary = catalog[action_id]
		lines.append("- %s: %s. %s Cost: %s" % [action_id, definition.get("name", action_id),
			definition.get("description", ""), JSON.stringify(definition.get("cost", {}))])
	lines.append("Respond with ONLY one JSON object, no markdown and no prose, in exactly this shape:")
	lines.append(JSON.stringify({
		"faction": faction,
		"turn": 0,
		"rationale": "why, citing the metrics (max %d chars)" % MAX_RATIONALE,
		"selected_action": "ONE_ACTION_ID",
		"resource_expenditure": {"resource_name": 0},
		"public_statement": "what you announce publicly, in character (max %d chars)" % MAX_STATEMENT,
	}))
	return "\n".join(lines)


static func build_user_prompt(faction: String, observation: Dictionary) -> String:
	return "TURN STATE:\n" + JSON.stringify(compact_observation(faction, observation))


static func build_messages(faction: String, observation: Dictionary) -> Array:
	return [
		{"role": "system", "content": build_system_prompt(faction)},
		{"role": "user", "content": build_user_prompt(faction, observation)},
	]


## OpenAI-compatible chat-completions request body.
static func build_request_body(model: String, faction: String, observation: Dictionary,
		json_mode: bool = true, temperature: float = 0.4, max_tokens: int = 400) -> Dictionary:
	var body := {
		"model": model,
		"messages": build_messages(faction, observation),
		"temperature": temperature,
		"max_tokens": max_tokens,
		"stream": false,
	}
	if json_mode:
		body["response_format"] = {"type": "json_object"}
	return body


## Claude Messages API request body (POST /v1/messages): the system prompt is a
## top-level field and max_tokens is required. No sampling parameters: current
## Claude models reject non-default temperature / top_p / top_k. [param effort]
## ("low" by default in LLMService) keeps adaptive thinking short; thinking
## counts toward max_tokens, so the budget leaves room for it. The prompt
## demands JSON-only output, and [method parse_completion] reads text blocks
## only, skipping thinking blocks, and copes with prose or fences.
static func build_anthropic_body(model: String, faction: String, observation: Dictionary,
		max_tokens: int = 2048, effort: String = "") -> Dictionary:
	var body := {
		"model": model,
		"max_tokens": max_tokens,
		"system": build_system_prompt(faction),
		"messages": [{"role": "user", "content": build_user_prompt(faction, observation)}],
	}
	if effort != "":
		body["output_config"] = {"effort": effort}
	return body


## Conversation turns for a generic completion (LLMService.request_completion):
## keeps {"role": "user" | "assistant", "content": text} entries that carry
## text, merges consecutive turns of one role, drops assistant turns before the
## first user turn and keeps the most recent MAX_COMPLETION_TURNS. Returns []
## unless the conversation ends with the user's turn: current Claude models
## reject an assistant prefill.
static func normalize_turns(messages: Array) -> Array:
	var turns: Array = []
	for message in messages:
		if not (message is Dictionary):
			continue
		var role := String(message.get("role", ""))
		if role != "user" and role != "assistant":
			continue
		var text := _content_to_text(message.get("content", "")).strip_edges()
		if text == "" or (turns.is_empty() and role == "assistant"):
			continue
		if not turns.is_empty() and String(turns[-1]["role"]) == role:
			turns[-1]["content"] = String(turns[-1]["content"]) + "\n\n" + text
		else:
			turns.append({"role": role, "content": text})
	if turns.is_empty() or String(turns[-1]["role"]) != "user":
		return []
	while turns.size() > MAX_COMPLETION_TURNS:
		turns.pop_front()
		while not turns.is_empty() and String(turns[0]["role"]) != "user":
			turns.pop_front()
	return turns


## OpenAI-compatible chat-completions body for a generic completion: the
## system prompt as the first message, then [param turns]
## ([method normalize_turns]).
static func build_completion_body(model: String, system: String, turns: Array, json_mode: bool = true,
		temperature: float = 0.4, max_tokens: int = 400) -> Dictionary:
	var messages: Array = []
	if system.strip_edges() != "":
		messages.append({"role": "system", "content": system})
	messages.append_array(turns.duplicate(true))
	var body := {
		"model": model,
		"messages": messages,
		"temperature": temperature,
		"max_tokens": max_tokens,
		"stream": false,
	}
	if json_mode:
		body["response_format"] = {"type": "json_object"}
	return body


## Claude Messages API body for a generic completion: the system prompt as the
## top-level field, [param turns] ([method normalize_turns]) as messages, no
## sampling parameters and output_config.effort only when [param effort] is set
## (see [method build_anthropic_body]).
static func build_anthropic_completion_body(model: String, system: String, turns: Array,
		max_tokens: int = 2048, effort: String = "") -> Dictionary:
	var body := {
		"model": model,
		"max_tokens": max_tokens,
		"messages": turns.duplicate(true),
	}
	if system.strip_edges() != "":
		body["system"] = system
	if effort != "":
		body["output_config"] = {"effort": effort}
	return body


static func compact_observation(faction: String, observation: Dictionary) -> Dictionary:
	var keys: Array = OBSERVATION_KEYS.duplicate()
	if faction == SimConstants.ASI:
		keys.append_array(ASI_ONLY_KEYS)
	var out := {}
	for key in keys:
		if observation.has(key):
			out[key] = _round_values(observation[key])
	return out


## Parses an OpenAI-style chat completion or a Claude Messages API response and
## extracts the decision object.
## Returns {"ok": bool, "payload": Dictionary, "content": String, "error": String}.
static func parse_completion(body_text: String) -> Dictionary:
	var reply := parse_completion_text(body_text)
	if not reply["ok"]:
		return _parse_error(String(reply["error"]))
	var content := String(reply["text"])
	var payload: Variant = extract_json_object(content)
	if not (payload is Dictionary):
		return _parse_error("no JSON object found in completion content")
	return {"ok": true, "payload": payload, "content": content, "error": ""}


## The reply text of an OpenAI-style chat completion or a Claude Messages API
## response. Claude replies are read by text block (thinking blocks and any
## other block types are skipped), never by position.
## Returns {"ok": bool, "text": String, "error": String}.
static func parse_completion_text(body_text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(body_text) != OK:
		return _text_error("response body is not JSON")
	var data: Variant = json.data
	if not (data is Dictionary):
		return _text_error("response body is not an object")
	if data.has("error"):
		var error: Variant = data["error"]
		var message: String = str(error.get("message", error)) if error is Dictionary else str(error)
		return _text_error("provider error: %s" % sanitize_text(message, 200))
	var content := ""
	if data.get("content") is Array:
		# Claude Messages API: a list of content blocks; the text blocks hold the answer.
		content = _content_to_text(data["content"])
		if content.strip_edges() == "" and str(data.get("stop_reason", "")) == "refusal":
			return _text_error("the model declined the request")
	else:
		var choices: Variant = data.get("choices")
		if not (choices is Array) or (choices as Array).is_empty():
			return _text_error("response has no choices")
		var first: Variant = choices[0]
		if first is Dictionary:
			var message: Variant = first.get("message")
			if message is Dictionary:
				content = _content_to_text(message.get("content"))
			elif first.has("text"):
				content = _content_to_text(first["text"])
	if content.strip_edges() == "":
		return _text_error("completion content is empty")
	return {"ok": true, "text": content, "error": ""}


## Finds the first JSON object in free text (handles code fences and prose).
static func extract_json_object(text: String) -> Variant:
	var cleaned := text.strip_edges()
	var direct := JSON.new()
	if direct.parse(cleaned) == OK and direct.data is Dictionary:
		return direct.data
	var start := cleaned.find("{")
	while start >= 0:
		var depth := 0
		var in_string := false
		var escaped := false
		for i in range(start, cleaned.length()):
			var ch := cleaned[i]
			if in_string:
				if escaped:
					escaped = false
				elif ch == "\\":
					escaped = true
				elif ch == "\"":
					in_string = false
				continue
			if ch == "\"":
				in_string = true
			elif ch == "{":
				depth += 1
			elif ch == "}":
				depth -= 1
				if depth == 0:
					var candidate := JSON.new()
					if candidate.parse(cleaned.substr(start, i - start + 1)) == OK and candidate.data is Dictionary:
						return candidate.data
					break
		start = cleaned.find("{", start + 1)
	return null


## Strictly validates an LLM decision for [param faction]. When
## [param available_actions] is non-empty the chosen action must be in it.
## Returns {"ok": bool, "errors": Array[String], "decision": Dictionary}.
static func validate_decision(faction: String, turn: int, payload: Variant, available_actions: Array = []) -> Dictionary:
	var errors: Array[String] = []
	if not (payload is Dictionary):
		errors.append("payload is not a JSON object")
		return {"ok": false, "errors": errors, "decision": {}}
	var catalog := FactionRegistry.catalog_for(faction)
	var raw_action: Variant = payload.get("selected_action", payload.get("action", null))
	var action := ""
	if raw_action is String:
		action = (raw_action as String).strip_edges().to_upper()
	if action == "":
		errors.append("missing selected_action")
	elif not catalog.has(action):
		errors.append("unknown action '%s'" % sanitize_text(action, 60))
	elif not available_actions.is_empty() and not available_actions.has(action):
		errors.append("action '%s' is not available this turn" % action)

	var claimed: Variant = payload.get("faction", "")
	if claimed is String and claimed != "" and _normalize_id(claimed) != _normalize_id(faction):
		errors.append("faction mismatch ('%s')" % sanitize_text(claimed, 40))

	var expenditure := {}
	var raw_expenditure: Variant = payload.get("resource_expenditure", {})
	var base_cost: Dictionary = catalog.get(action, {}).get("cost", {})
	if raw_expenditure is Dictionary:
		for key in raw_expenditure:
			var value: Variant = raw_expenditure[key]
			if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0:
				errors.append("resource_expenditure.%s must be a non-negative number" % sanitize_text(str(key), 40))
				continue
			if base_cost.has(key):
				expenditure[key] = minf(float(value), float(base_cost[key]) * MAX_EXPENDITURE_MULTIPLIER)
	elif raw_expenditure != null:
		errors.append("resource_expenditure must be an object")

	var decision := {
		"faction": faction,
		"turn": turn,
		"action": action,
		"selected_action": action,
		"resource_expenditure": expenditure,
		"rationale": sanitize_text(str(payload.get("rationale", "")), MAX_RATIONALE),
		"public_statement": sanitize_text(str(payload.get("public_statement", "")), MAX_STATEMENT),
		"source": "LLM",
	}
	return {"ok": errors.is_empty(), "errors": errors, "decision": decision}


## Strips control characters, collapses whitespace and truncates.
static func sanitize_text(value: String, max_length: int) -> String:
	var parts := PackedStringArray()
	for i in value.length():
		var code := value.unicode_at(i)
		if code < 32 or code == 127:
			parts.append(" ")
		else:
			parts.append(value[i])
	var out := "".join(parts).strip_edges()
	while out.contains("  "):
		out = out.replace("  ", " ")
	if out.length() > max_length:
		out = out.left(maxi(0, max_length - 3)) + "..."
	return out


## Untrusted model text made safe for any label: markup tags such as BBCode
## ([b], [url=...], [img]) are removed with any stray brackets and braces, as
## are control, zero-width and bidirectional-override characters; whitespace
## is collapsed and the result truncated (see [method sanitize_text]).
static func plain_text(value: String, max_length: int) -> String:
	if _markup == null:
		_markup = RegEx.create_from_string("\\[/?[A-Za-z_][^\\[\\]]{0,80}\\]")
	var text := _markup.sub(value, "", true)
	var parts := PackedStringArray()
	for i in text.length():
		var code := text.unicode_at(i)
		if code == 0x5B or code == 0x5D or code == 0x7B or code == 0x7D:
			continue
		if (code >= 0x200B and code <= 0x200F) or (code >= 0x202A and code <= 0x202E) \
				or (code >= 0x2066 and code <= 0x2069) or code == 0xFEFF:
			continue
		parts.append(text[i])
	return sanitize_text("".join(parts), max_length)


static func _content_to_text(content: Variant) -> String:
	if content is String:
		return content
	if content is Array:
		var pieces := PackedStringArray()
		for part in content:
			if part is Dictionary and part.has("text") and String(part.get("type", "text")) == "text":
				pieces.append(str(part["text"]))
			elif part is String:
				pieces.append(part)
		return "".join(pieces)
	return ""


static func _normalize_id(value: String) -> String:
	return value.strip_edges().to_upper().replace(" ", "_").replace("-", "_")


static func _round_values(value: Variant) -> Variant:
	if value is float:
		return snappedf(value, 0.1)
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = _round_values(value[key])
		return out
	if value is Array:
		var out_array := []
		for item in value:
			out_array.append(_round_values(item))
		return out_array
	return value


static func _parse_error(message: String) -> Dictionary:
	return {"ok": false, "payload": {}, "content": "", "error": message}


static func _text_error(message: String) -> Dictionary:
	return {"ok": false, "text": "", "error": message}
