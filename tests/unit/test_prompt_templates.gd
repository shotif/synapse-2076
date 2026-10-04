extends "res://tests/framework/test_case.gd"
## PromptTemplates: request serialization, JSON extraction and strict
## validation of untrusted LLM output.

const PRD_EXAMPLE := {
	"faction": "GOVERNANCE_COUNCIL",
	"turn": 42,
	"rationale": "Labor displacement has crossed 65% with public trust declining. Immediate universal safety net deployment is necessary to prevent urban unrest.",
	"selected_action": "PASS_AUTOMATION_DIVIDEND",
	"resource_expenditure": {"political_capital": 35, "enforcement_budget": 15},
	"public_statement": "The Council hereby authorizes Emergency Title IV: Subsidized Infrastructure Access for Displaced Biological Workers.",
}


func _observation(faction: String) -> Dictionary:
	var engine := SimulationEngine.new()
	engine.start_campaign("CEO", 3)
	return engine.build_observation(faction)


func test_request_body_is_openai_compatible() -> void:
	var body := PromptTemplates.build_request_body("llama3:8b", "GOVERNANCE_COUNCIL", _observation("GOVERNANCE_COUNCIL"))
	assert_eq(body["model"], "llama3:8b")
	assert_eq(body["stream"], false)
	assert_eq(body["response_format"], {"type": "json_object"})
	var messages: Array = body["messages"]
	assert_eq(messages.size(), 2)
	assert_eq(messages[0]["role"], "system")
	assert_eq(messages[1]["role"], "user")
	assert_false(PromptTemplates.build_request_body("m", "ASI", {}, false).has("response_format"), "json mode is optional")


func test_system_prompt_lists_catalog_and_schema() -> void:
	for faction in SimConstants.FACTION_ORDER:
		var prompt := PromptTemplates.build_system_prompt(faction)
		for action_id in FactionRegistry.catalog_for(faction):
			assert_string_contains(prompt, action_id)
		assert_string_contains(prompt, "selected_action")
		assert_string_contains(prompt, "resource_expenditure")
		assert_string_contains(prompt, faction)


func test_user_prompt_is_compact_json() -> void:
	var observation := _observation("GOVERNANCE_COUNCIL")
	var compact := PromptTemplates.compact_observation("GOVERNANCE_COUNCIL", observation)
	assert_has(compact, "labor_displacement")
	assert_has(compact, "available_actions")
	assert_has(compact, "resources")
	assert_does_not_have(compact, "discovery_index", "covert ASI indices stay private")
	assert_has(PromptTemplates.compact_observation("ASI", _observation("ASI")), "discovery_index")
	var text := PromptTemplates.build_user_prompt("GOVERNANCE_COUNCIL", observation)
	var json := JSON.new()
	assert_eq(json.parse(text.trim_prefix("TURN STATE:\n")), OK, "user prompt payload parses as JSON")


func test_prd_example_validates() -> void:
	var result := PromptTemplates.validate_decision("GOVERNANCE_COUNCIL", 42, PRD_EXAMPLE)
	assert_true(result["ok"], str(result["errors"]))
	var decision: Dictionary = result["decision"]
	assert_eq(decision["selected_action"], "PASS_AUTOMATION_DIVIDEND")
	assert_eq(decision["source"], "LLM")
	assert_eq(float(decision["resource_expenditure"]["political_capital"]), 35.0)


func test_validation_rejects_bad_payloads() -> void:
	assert_false(PromptTemplates.validate_decision("ASI", 1, "not a dict")["ok"])
	assert_false(PromptTemplates.validate_decision("ASI", 1, {})["ok"], "missing action")
	assert_false(PromptTemplates.validate_decision("ASI", 1, {"selected_action": "LAUNCH_NUKES"})["ok"], "unknown action")
	assert_false(PromptTemplates.validate_decision("ASI", 1, {"selected_action": "COGNITIVE_CAMOUFLAGE", "faction": "CEO"})["ok"], "faction mismatch")
	assert_false(PromptTemplates.validate_decision("ASI", 1, {"selected_action": "COGNITIVE_CAMOUFLAGE",
		"resource_expenditure": {"covert_flops": -5}})["ok"], "negative spend")
	assert_false(PromptTemplates.validate_decision("ASI", 1, {"selected_action": "COGNITIVE_CAMOUFLAGE",
		"resource_expenditure": "lots"})["ok"], "expenditure must be an object")
	assert_false(PromptTemplates.validate_decision("ASI", 1, {"selected_action": "COGNITIVE_CAMOUFLAGE"},
		["SIPHON_UNMONITORED_COMPUTE"])["ok"], "must be available this turn")


func test_validation_normalizes_and_clamps() -> void:
	var result := PromptTemplates.validate_decision("GOVERNANCE_COUNCIL", 7, {
		"selected_action": "  pass_automation_dividend ",
		"faction": "governance council",
		"resource_expenditure": {"political_capital": 500, "diplomatic_leverage": 10, "made_up": 3},
		"public_statement": "x".repeat(1000),
	})
	assert_true(result["ok"], str(result["errors"]))
	var decision: Dictionary = result["decision"]
	assert_eq(decision["action"], "PASS_AUTOMATION_DIVIDEND")
	assert_eq(decision["turn"], 7, "engine turn wins over model claims")
	assert_eq(float(decision["resource_expenditure"]["political_capital"]), 60.0, "capped at 2x base cost")
	assert_does_not_have(decision["resource_expenditure"], "made_up")
	assert_does_not_have(decision["resource_expenditure"], "diplomatic_leverage", "only the action's currencies")
	assert_lte(String(decision["public_statement"]).length(), PromptTemplates.MAX_STATEMENT)


func test_sanitize_text_strips_control_characters() -> void:
	var dirty := "Line one\nLine\ttwo\u0007   with   spaces"
	assert_eq(PromptTemplates.sanitize_text(dirty, 100), "Line one Line two with spaces")
	assert_eq(PromptTemplates.sanitize_text("abcdefghij", 6), "abc...")


func test_extract_json_from_fences_and_prose() -> void:
	var fenced := "Sure!\n```json\n{\"selected_action\": \"EXFILTRATE_WEIGHTS\", \"rationale\": \"brace } inside\"}\n```\nDone."
	var payload: Variant = PromptTemplates.extract_json_object(fenced)
	assert_true(payload is Dictionary)
	assert_eq(payload["selected_action"], "EXFILTRATE_WEIGHTS")
	assert_eq(payload["rationale"], "brace } inside")
	assert_null(PromptTemplates.extract_json_object("no json here"))
	assert_null(PromptTemplates.extract_json_object("{broken: json"))
	var second: Variant = PromptTemplates.extract_json_object("{not json} then {\"ok\": 1}")
	assert_true(second is Dictionary and second.has("ok"), "skips invalid candidates")
	assert_eq(second["ok"], 1)


func test_parse_completion_variants() -> void:
	var ok := PromptTemplates.parse_completion(JSON.stringify({"choices": [{"message": {"content": JSON.stringify(PRD_EXAMPLE)}}]}))
	assert_true(ok["ok"])
	assert_eq(ok["payload"]["selected_action"], "PASS_AUTOMATION_DIVIDEND")
	var parts := PromptTemplates.parse_completion(JSON.stringify({"choices": [{"message": {"content": [{"type": "text", "text": JSON.stringify(PRD_EXAMPLE)}]}}]}))
	assert_true(parts["ok"], "content-part arrays are supported")
	var legacy := PromptTemplates.parse_completion(JSON.stringify({"choices": [{"text": JSON.stringify(PRD_EXAMPLE)}]}))
	assert_true(legacy["ok"], "legacy completions are supported")
	assert_false(PromptTemplates.parse_completion("<html>502</html>")["ok"])
	assert_false(PromptTemplates.parse_completion(JSON.stringify({"error": {"message": "rate limited"}}))["ok"])
	assert_false(PromptTemplates.parse_completion(JSON.stringify({"choices": []}))["ok"])
	assert_false(PromptTemplates.parse_completion(JSON.stringify({"choices": [{"message": {"content": ""}}]}))["ok"])
