extends "res://tests/framework/test_case.gd"
## LLMService against a real local HTTP server (tests/support/mock_llm_server.gd):
## online decisions, every fallback path, timeouts, probing and status signals.

const MockServer := preload("res://tests/support/mock_llm_server.gd")
const WebBuildConfig := preload("res://tools/configure_web_build.gd")

var server: Node
var service: LLMService
var received: Array = []
var statuses: Array = []
var completions: Array = []


func before_each() -> void:
	server = MockServer.new()
	tree.root.add_child(server)
	server.start()
	service = LLMService.new()
	service.reprobe_interval_sec = 0.0
	tree.root.add_child(service)
	service.configure({"endpoint_url": server.url(), "model_name": "mock-model", "request_timeout_sec": 2.0})
	received = []
	statuses = []
	completions = []
	service.actor_decision_received.connect(func(f: String, p: Dictionary): received.append({"faction": f, "payload": p}))
	service.llm_status_changed.connect(func(online: bool, provider: String): statuses.append([online, provider]))
	service.completion_received.connect(func(id: int, ok: bool, text: String, error: String):
		completions.append({"id": id, "ok": ok, "text": text, "error": error}))


func after_each() -> void:
	service.queue_free()
	server.queue_free()
	await tree.process_frame


func _state(faction: String = "GOVERNANCE_COUNCIL") -> Dictionary:
	var engine := SimulationEngine.new()
	engine.start_campaign("CEO", 9)
	engine.turn = 1
	return engine.build_observation(faction)


func _wait_for_decisions(count: int, timeout_sec: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while received.size() < count and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	return received.size() >= count


func _wait_for_completions(count: int, timeout_sec: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while completions.size() < count and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	return completions.size() >= count


func test_defaults_match_prd() -> void:
	var fresh := LLMService.new()
	assert_eq(fresh.endpoint_url, "http://127.0.0.1:11434/v1/chat/completions")
	assert_eq(fresh.model_name, "llama3:8b")
	assert_eq(fresh.request_timeout_sec, 5.0, "5000 ms timeout")
	assert_false(fresh.is_online)
	assert_eq(fresh.get_status_text(), "▲ [LLM OFFLINE - RUNNING HEURISTIC FALLBACK ENGINE]")
	fresh.free()


func test_offline_returns_heuristic_immediately() -> void:
	var state := _state()
	service.query_actor_decision("GOVERNANCE_COUNCIL", state)
	assert_eq(received.size(), 1, "synchronous fallback")
	var payload: Dictionary = received[0]["payload"]
	assert_eq(payload["source"], "HEURISTIC")
	assert_eq(payload["action"], HeuristicFallback.evaluate("GOVERNANCE_COUNCIL", state)["action"])
	assert_eq(server.requests.size(), 0, "no network traffic while offline")


func test_online_decision_round_trip() -> void:
	service.api_key = "sk-test-123"
	service.set_online(true)
	var state := _state()
	service.query_actor_decision("GOVERNANCE_COUNCIL", state)
	assert_true(await _wait_for_decisions(1, 3.0), "decision arrived")
	var payload: Dictionary = received[0]["payload"]
	assert_eq(payload["source"], "LLM")
	assert_eq(payload["selected_action"], "PASS_AUTOMATION_DIVIDEND")
	assert_eq(payload["turn"], 1)
	assert_eq(float(payload["resource_expenditure"]["political_capital"]), 35.0)
	var request: Dictionary = server.requests[0]
	assert_eq(request["method"], "POST")
	assert_eq(request["path"], "/v1/chat/completions")
	assert_eq(request["headers"].get("authorization", ""), "Bearer sk-test-123")
	assert_eq(request["body"]["model"], "mock-model")
	assert_eq((request["body"]["messages"] as Array).size(), 2)
	assert_eq(service.stats["llm_decisions"], 1)


func test_fenced_json_is_accepted() -> void:
	server.mode = "fenced"
	service.set_online(true)
	service.query_actor_decision("GOVERNANCE_COUNCIL", _state())
	assert_true(await _wait_for_decisions(1, 3.0))
	assert_eq(received[0]["payload"]["source"], "LLM")


func test_garbage_content_falls_back_without_going_offline() -> void:
	server.mode = "garbage"
	service.set_online(true)
	service.query_actor_decision("GOVERNANCE_COUNCIL", _state())
	assert_true(await _wait_for_decisions(1, 3.0))
	var payload: Dictionary = received[0]["payload"]
	assert_eq(payload["source"], "HEURISTIC_FALLBACK")
	assert_string_contains(String(payload["fallback_reason"]), "invalid response")
	assert_true(service.is_online, "a bad answer is not a connectivity failure")


func test_invalid_action_falls_back() -> void:
	server.mode = "invalid_action"
	service.set_online(true)
	service.query_actor_decision("GOVERNANCE_COUNCIL", _state())
	assert_true(await _wait_for_decisions(1, 3.0))
	assert_string_contains(String(received[0]["payload"]["fallback_reason"]), "schema violation")
	assert_eq(service.stats["invalid"], 1)


func test_http_errors_fall_back_and_trip_offline() -> void:
	server.mode = "http_500"
	service.set_online(true)
	service.query_actor_decision("GOVERNANCE_COUNCIL", _state())
	service.query_actor_decision("ASI", _state("ASI"))
	assert_true(await _wait_for_decisions(2, 4.0))
	for entry in received:
		assert_eq(entry["payload"]["source"], "HEURISTIC_FALLBACK")
	assert_false(service.is_online, "two consecutive transport failures mark the service offline")
	assert_eq(statuses[-1][0], false)


func test_timeout_falls_back_within_deadline() -> void:
	server.mode = "hang"
	service.configure({"request_timeout_sec": 0.5})
	service.set_online(true)
	var started := Time.get_ticks_msec()
	service.query_actor_decision("CITIZEN_COALITION", _state("CITIZEN_COALITION"))
	assert_true(await _wait_for_decisions(1, 3.0), "fallback delivered")
	var elapsed := Time.get_ticks_msec() - started
	assert_lt(float(elapsed), 1500.0, "resolved shortly after the 0.5 s timeout")
	assert_string_contains(String(received[0]["payload"]["fallback_reason"]), "timeout")
	assert_eq(service.pending_request_count(), 0)


func test_probe_marks_online() -> void:
	service.probe_connection()
	var deadline := Time.get_ticks_msec() + 3000
	while service.is_probing and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	assert_true(service.is_online)
	assert_eq(server.requests[0]["path"], "/v1/models")
	assert_eq(statuses[-1], [true, "MOCK-MODEL / LOCAL-ENDPOINT"])
	assert_string_contains(service.get_status_text(), "● [LLM ONLINE: MOCK-MODEL")


func test_probe_fails_on_auth_error() -> void:
	server.mode = "unauthorized"
	service.probe_connection()
	var deadline := Time.get_ticks_msec() + 3000
	while service.is_probing and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	assert_false(service.is_online)
	assert_string_contains(service.last_error, "authentication")


func test_probe_fails_when_nothing_listens() -> void:
	service.configure({"endpoint_url": "http://127.0.0.1:9/v1/chat/completions", "request_timeout_sec": 1.0})
	service.probe_connection()
	var deadline := Time.get_ticks_msec() + 4000
	while service.is_probing and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	assert_false(service.is_online)
	assert_false(service.is_probing)


func test_disabled_service_never_goes_online() -> void:
	service.configure({"enabled": false})
	service.set_online(true)
	assert_false(service.is_online)
	service.query_actor_decision("ASI", _state("ASI"))
	assert_eq(received[0]["payload"]["source"], "HEURISTIC")


func test_engine_runs_turns_through_llm_service() -> void:
	server.decision = {"selected_action": "CONSERVE_RESOURCES", "rationale": "Mock model conserves.", "public_statement": "Holding."}
	service.set_online(true)
	var engine := SimulationEngine.new()
	engine.start_campaign("CEO", 21)
	engine.set_decision_provider(service)
	engine.advance()
	var deadline := Time.get_ticks_msec() + 5000
	while engine.phase != SimulationEngine.Phase.PLAYER_ACTION and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	assert_eq(engine.phase, SimulationEngine.Phase.PLAYER_ACTION, "pipeline resumed after async replies")
	for faction_id in ["GOVERNANCE_COUNCIL", "ASI", "CITIZEN_COALITION"]:
		assert_eq(engine.turn_actions[faction_id]["source"], "LLM", faction_id)
		assert_eq(engine.turn_actions[faction_id]["action"], "CONSERVE_RESOURCES", faction_id)
	assert_eq(server.requests.size(), 3)


func test_auto_probe_respects_enabled_flag() -> void:
	assert_true(service.should_auto_probe(), "desktop builds probe a configured endpoint")
	service.configure({"enabled": false})
	assert_false(service.should_auto_probe(), "disabled service never probes on its own")


func test_claude_messages_round_trip() -> void:
	service.configure({"endpoint_url": server.claude_url(), "api_key": "sk-ant-test", "model_name": "claude-mock"})
	assert_true(service.uses_anthropic_format(), "a /v1/messages endpoint speaks the Claude format")
	service.set_online(true)
	service.query_actor_decision("GOVERNANCE_COUNCIL", _state())
	assert_true(await _wait_for_decisions(1, 3.0), "decision arrived")
	var payload: Dictionary = received[0]["payload"]
	assert_eq(payload["source"], "LLM")
	assert_eq(payload["selected_action"], "PASS_AUTOMATION_DIVIDEND")
	var request: Dictionary = server.requests[0]
	assert_eq(request["path"], "/v1/messages")
	assert_eq(request["headers"].get("x-api-key", ""), "sk-ant-test")
	assert_eq(request["headers"].get("anthropic-version", ""), LLMService.ANTHROPIC_VERSION)
	assert_false(request["headers"].has("authorization"), "Claude takes the key in x-api-key")
	assert_false(request["headers"].has("anthropic-dangerous-direct-browser-access"), "browser header only on web builds")
	var body: Dictionary = request["body"]
	assert_eq(body["model"], "claude-mock")
	assert_string_contains(String(body["system"]), "GLOBAL AI GOVERNANCE")
	assert_eq((body["messages"] as Array).size(), 1, "system prompt is a top-level field")
	assert_eq(body["messages"][0]["role"], "user")
	assert_eq(int(body["max_tokens"]), LLMService.CLAUDE_MAX_TOKENS, "room for adaptive thinking plus the answer")
	assert_eq(body["output_config"], {"effort": "low"}, "short thinking for a latency-bound decision")
	assert_false(body.has("temperature"), "current Claude models reject non-default sampling parameters")
	assert_false(body.has("response_format"), "no OpenAI-only fields")


func test_effort_support_by_model() -> void:
	for model in ["claude-sonnet-5-5", "claude-opus-5-5", "claude-fable-5-1", "claude-sonnet-4-6", "claude-opus-4-5",
			"claude-opus-4-5-20251101", "claude-mock"]:
		assert_true(LLMService.supports_effort(model), model)
	for model in ["claude-haiku-4-5", "claude-haiku-4-5-20251001", "claude-sonnet-4-5", "claude-sonnet-4-5-20250929",
			"claude-sonnet-4-20250514", "claude-opus-4-1", "claude-3-7-sonnet-latest"]:
		assert_false(LLMService.supports_effort(model), model)
	server.mode = "ok"
	service.configure({"endpoint_url": server.claude_url(), "model_name": "claude-haiku-4-5", "effort": "medium"})
	service.set_online(true)
	service.query_actor_decision("CEO", _state("CEO"))
	assert_true(await _wait_for_decisions(1, 3.0))
	assert_false((server.requests[0]["body"] as Dictionary).has("output_config"), "Haiku 4.5 rejects effort")
	service.configure({"effort": "extreme"})
	assert_eq(service.effort, "", "unknown levels fall back to the model default")


func test_claude_errors_explain_the_fallback() -> void:
	server.mode = "not_found"
	service.configure({"endpoint_url": server.claude_url(), "api_key": "sk-ant-test"})
	service.set_online(true)
	service.query_actor_decision("ASI", _state("ASI"))
	assert_true(await _wait_for_decisions(1, 3.0))
	assert_eq(received[0]["payload"]["source"], "HEURISTIC_FALLBACK")
	assert_eq(String(received[0]["payload"]["fallback_reason"]), "HTTP 404: model: mock-missing")


func test_claude_probe_uses_models_listing() -> void:
	service.configure({"endpoint_url": server.claude_url(), "api_key": "sk-ant-test"})
	assert_eq(service.models_url(), server.claude_url().trim_suffix("/messages") + "/models")
	service.probe_connection()
	var deadline := Time.get_ticks_msec() + 3000
	while service.is_probing and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	assert_true(service.is_online)
	assert_eq(server.requests[0]["headers"].get("x-api-key", ""), "sk-ant-test")


func test_auth_failure_stops_automatic_probing() -> void:
	server.mode = "unauthorized"
	service.configure({"endpoint_url": server.claude_url(), "api_key": "wrong"})
	assert_true(service.should_auto_probe())
	service.probe_connection()
	var deadline := Time.get_ticks_msec() + 3000
	while service.is_probing and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	assert_false(service.is_online)
	assert_string_contains(service.last_error, "invalid x-api-key")
	assert_false(service.should_auto_probe(), "a rejected key is not retried every minute")
	service.configure({"api_key": "a-new-key"})
	assert_true(service.should_auto_probe(), "a settings change re-enables probing")


func test_api_format_selection() -> void:
	var fresh := LLMService.new()
	for url in ["https://api.anthropic.com/v1/messages", "https://proxy.example.workers.dev/v1/messages/"]:
		fresh.configure({"endpoint_url": url, "api_format": "auto"})
		assert_true(fresh.uses_anthropic_format(), url)
	fresh.configure({"endpoint_url": "http://127.0.0.1:11434/v1/chat/completions"})
	assert_false(fresh.uses_anthropic_format())
	fresh.configure({"api_format": "anthropic"})
	assert_true(fresh.uses_anthropic_format(), "explicit format wins")
	fresh.configure({"endpoint_url": "https://example.com/v1/messages", "api_format": "OpenAI"})
	assert_false(fresh.uses_anthropic_format())
	fresh.configure({"api_format": "nonsense"})
	assert_eq(fresh.api_format, "auto")
	fresh.configure({"endpoint_url": "https://proxy.example.workers.dev/v1/messages/"})
	assert_eq(fresh.models_url(), "https://proxy.example.workers.dev/v1/models")
	fresh.free()


func test_browser_access_header_only_for_anthropic_from_the_web() -> void:
	assert_true(LLMService.wants_browser_access_header("https://api.anthropic.com/v1/messages", true))
	assert_false(LLMService.wants_browser_access_header("https://api.anthropic.com/v1/messages", false), "desktop builds")
	assert_false(LLMService.wants_browser_access_header("https://my-proxy.example.workers.dev/v1/messages", true), "proxies hold the key")


func test_url_fragment_settings() -> void:
	assert_eq(LLMService.parse_url_fragment("#llm-key=sk-ant-abc%2Bdef&llm=on"), {"api_key": "sk-ant-abc+def", "enabled": true})
	assert_eq(LLMService.parse_url_fragment("#llm=OFF"), {"enabled": false})
	assert_eq(LLMService.parse_url_fragment("#llm-key="), {"api_key": ""}, "an empty key forgets the stored one")
	assert_eq(LLMService.parse_url_fragment("#LLM-KEY=sk-1"), {"api_key": "sk-1"})
	assert_eq(LLMService.parse_url_fragment("#llm-endpoint=https://evil.example/v1/messages&llm-model=x"), {},
		"a link can never redirect a stored key to another endpoint")
	assert_eq(LLMService.parse_url_fragment(""), {})
	assert_eq(LLMService.parse_url_fragment("#section-2"), {})


func test_provider_labels() -> void:
	assert_eq(LLMService.provider_for_endpoint("http://127.0.0.1:11434/v1/chat/completions"), "LOCAL-OLLAMA")
	assert_eq(LLMService.provider_for_endpoint("http://localhost:8000/v1/chat/completions"), "LOCAL-VLLM")
	assert_eq(LLMService.provider_for_endpoint("https://api.anthropic.com/v1/chat/completions"), "ANTHROPIC")
	assert_eq(LLMService.provider_for_endpoint("https://api.anthropic.com/v1/messages"), "ANTHROPIC")
	assert_eq(LLMService.provider_for_endpoint("https://my-proxy.example.com/v1/chat/completions"), "MY-PROXY")
	assert_eq(LLMService.provider_for_endpoint("https://synapse-llm-proxy.someone.workers.dev/v1/messages"), "SYNAPSE-LLM-PROXY")
	assert_eq(LLMService.provider_for_endpoint("http://192.168.1.20:9000/v1/chat/completions"), "192.168.1.20")
	service.configure({"model_name": "claude-sonnet-5-5", "endpoint_url": "https://api.anthropic.com/v1/chat/completions"})
	assert_eq(service.get_provider_name(), "CLAUDE-SONNET-5-5 / ANTHROPIC")
	assert_eq(service.models_url(), "https://api.anthropic.com/v1/models")


func test_web_build_config_from_repository_variables() -> void:
	assert_eq(WebBuildConfig.plan_settings({})["settings"], {}, "no variables: defaults stay")
	var claude: Dictionary = WebBuildConfig.plan_settings({"SYNAPSE_LLM_ENDPOINT": " https://api.anthropic.com/v1/messages "})
	assert_eq(claude["errors"], [])
	assert_eq(claude["settings"], {
		"synapse/llm/endpoint_url": "https://api.anthropic.com/v1/messages",
		"synapse/llm/enabled": true,
		"synapse/llm/model_name": WebBuildConfig.CLAUDE_DEFAULT_MODEL,
		"synapse/llm/timeout_sec": WebBuildConfig.CLAUDE_DEFAULT_TIMEOUT_SEC,
	}, "Claude endpoints get a Claude model and a longer timeout")
	var custom: Dictionary = WebBuildConfig.plan_settings({"SYNAPSE_LLM_ENDPOINT": "https://proxy.example.workers.dev/v1/messages",
		"SYNAPSE_LLM_MODEL": "claude-haiku-4-5-20251001", "SYNAPSE_LLM_TIMEOUT": "12", "SYNAPSE_LLM_API_KEY": "sk-ant-secret"})
	assert_eq(custom["settings"]["synapse/llm/model_name"], "claude-haiku-4-5-20251001")
	assert_eq(float(custom["settings"]["synapse/llm/timeout_sec"]), 12.0)
	assert_false(str(custom["settings"]).contains("sk-ant-secret"), "keys never reach the build")
	assert_string_contains(String(custom["warnings"][0]), "ignored")
	var bad: Dictionary = WebBuildConfig.plan_settings({"SYNAPSE_LLM_ENDPOINT": "http://127.0.0.1:11434/v1/chat/completions",
		"SYNAPSE_LLM_TIMEOUT": "0", "SYNAPSE_LLM_API_FORMAT": "soap", "SYNAPSE_LLM_EFFORT": "max"})
	assert_eq((bad["errors"] as Array).size(), 4, "http endpoint, timeout, format and effort rejected: %s" % [bad["errors"]])
	var effort: Dictionary = WebBuildConfig.plan_settings({"SYNAPSE_LLM_ENDPOINT": "https://api.anthropic.com/v1/messages",
		"SYNAPSE_LLM_EFFORT": "none"})
	assert_eq(effort["settings"]["synapse/llm/effort"], "", "none leaves the model's default effort")
	var proxy: Dictionary = WebBuildConfig.plan_settings({"SYNAPSE_LLM_ENDPOINT": "https://synapse-llm-proxy.x.workers.dev/v1/messages"})
	assert_eq(proxy["errors"], [])
	assert_eq(proxy["settings"]["synapse/llm/model_name"], "", "the shared backend picks the model")
	assert_eq(float(proxy["settings"]["synapse/llm/timeout_sec"]), WebBuildConfig.CLAUDE_DEFAULT_TIMEOUT_SEC)
	var no_cards: Dictionary = WebBuildConfig.plan_settings({"SYNAPSE_LLM_ENDPOINT": "https://synapse-llm-proxy.x.workers.dev/v1/messages",
		"SYNAPSE_LLM_WRITE_CRISES": "Off"})
	assert_eq(no_cards["settings"]["synapse/llm/write_crises"], false, "a build can leave Claude's crisis cards out")
	var bad_switch: Dictionary = WebBuildConfig.plan_settings({"SYNAPSE_LLM_ENDPOINT": "https://synapse-llm-proxy.x.workers.dev/v1/messages",
		"SYNAPSE_LLM_WRITE_CRISES": "sometimes"})
	assert_eq((bad_switch["errors"] as Array).size(), 1)


# --- Generic completions (crisis writer, negotiations) --------------------------------

## A conversation as a feature would build it: a stray assistant turn first,
## then alternating turns and two user turns in a row at the end.
const CONVERSATION := [
	{"role": "assistant", "content": "Dropped: a conversation starts with the user."},
	{"role": "user", "content": "What do you want?"},
	{"role": "assistant", "content": "{\"say\": \"Calm borders.\", \"offer\": null}"},
	{"role": "system", "content": "Dropped: only user and assistant turns."},
	{"role": "user", "content": "Lower tension"},
	{"role": "user", "content": "Please."},
]


func test_completion_round_trip_openai_compatible() -> void:
	service.api_key = "sk-test-123"
	server.reply_text = "{\"say\": \"Calm costs.\"}"
	service.set_online(true)
	var request_id := service.request_completion("negotiation", "You are Nadia Esposito.", CONVERSATION, 300)
	assert_eq(service.pending_completion_count(), 1)
	assert_true(await _wait_for_completions(1, 3.0), "reply arrived")
	assert_eq(completions[0]["id"], request_id)
	assert_true(completions[0]["ok"], String(completions[0]["error"]))
	assert_eq(completions[0]["text"], "{\"say\": \"Calm costs.\"}", "the raw reply text; the feature parses it")
	var request: Dictionary = server.requests[0]
	assert_eq(request["path"], "/v1/chat/completions")
	assert_eq(request["headers"].get("authorization", ""), "Bearer sk-test-123")
	var body: Dictionary = request["body"]
	var messages: Array = body["messages"]
	assert_eq(messages[0], {"role": "system", "content": "You are Nadia Esposito."})
	assert_eq(messages.size(), 4, "system + user + assistant + user: %s" % str(messages))
	assert_eq(messages[-1], {"role": "user", "content": "Lower tension\n\nPlease."}, "consecutive user turns merge")
	assert_eq(int(body["max_tokens"]), 300)
	assert_eq(body["response_format"], {"type": "json_object"}, "JSON mode by default")
	assert_true(body.has("temperature"), "local models keep their sampling settings")
	assert_eq(service.pending_completion_count(), 0)
	service.request_completion("negotiation", "", [{"role": "user", "content": "Plain text, please."}], 300, {"json": false})
	assert_true(await _wait_for_completions(2, 3.0))
	var plain: Dictionary = server.requests[1]["body"]
	assert_false(plain.has("response_format"), "callers can turn JSON mode off")
	assert_eq((plain["messages"] as Array).size(), 1, "no empty system message")
	assert_eq(service.stats["completions"], 2)


func test_completion_round_trip_claude() -> void:
	service.configure({"endpoint_url": server.claude_url(), "api_key": "sk-ant-test", "model_name": "claude-mock", "effort": "low"})
	server.reply_text = "{\"title\": \"A card\"}"
	server.thinking_block = true
	service.set_online(true)
	var request_id := service.request_completion("crisis_writer", "Write one crisis card.", CONVERSATION, 1200)
	assert_true(await _wait_for_completions(1, 3.0), "reply arrived")
	assert_eq(completions[0]["id"], request_id)
	assert_true(completions[0]["ok"], String(completions[0]["error"]))
	assert_eq(completions[0]["text"], "{\"title\": \"A card\"}", "text blocks only, never content[0] (a thinking block here)")
	var request: Dictionary = server.requests[0]
	assert_eq(request["path"], "/v1/messages")
	assert_eq(request["headers"].get("x-api-key", ""), "sk-ant-test")
	assert_eq(request["headers"].get("anthropic-version", ""), LLMService.ANTHROPIC_VERSION)
	assert_false(request["headers"].has("authorization"))
	var body: Dictionary = request["body"]
	assert_eq(body["system"], "Write one crisis card.", "the system prompt is a top-level field")
	var messages: Array = body["messages"]
	assert_eq(messages.size(), 3)
	assert_eq(messages[0]["role"], "user", "starts with the user")
	assert_eq(messages[-1]["role"], "user", "no assistant prefill: current Claude models reject it")
	for i in range(1, messages.size()):
		assert_ne(messages[i]["role"], messages[i - 1]["role"], "roles alternate")
	assert_eq(int(body["max_tokens"]), LLMService.CLAUDE_MAX_TOKENS, "room for adaptive thinking")
	assert_eq(body["output_config"], {"effort": "low"})
	for key in ["temperature", "top_p", "top_k", "response_format", "stream"]:
		assert_false(body.has(key), "no %s for Claude" % key)
	service.request_completion("crisis_writer", "x", [{"role": "user", "content": "y"}], 3000)
	assert_true(await _wait_for_completions(2, 3.0))
	assert_eq(int(server.requests[1]["body"]["max_tokens"]), 3000, "a bigger budget is kept")
	service.configure({"model_name": "claude-haiku-mock"})
	assert_false(LLMService.supports_effort(service.model_name))
	service.request_completion("crisis_writer", "x", [{"role": "user", "content": "y"}], 400)
	assert_true(await _wait_for_completions(3, 3.0))
	assert_false((server.requests[2]["body"] as Dictionary).has("output_config"), "no effort where the model rejects it")


func test_completion_fails_fast_without_traffic() -> void:
	var request_id := service.request_completion("negotiation", "x", [{"role": "user", "content": "hello"}])
	assert_eq(completions.size(), 0, "never answered before the caller has the id")
	await wait_frames(2)
	assert_eq(completions.size(), 1, "offline: answered on the next frame")
	assert_eq(completions[0]["id"], request_id)
	assert_false(completions[0]["ok"])
	assert_eq(completions[0]["error"], "offline")
	service.set_online(true)
	service.request_completion("negotiation", "x", [{"role": "assistant", "content": "a prefill only"}])
	service.configure({"enabled": false})
	service.request_completion("negotiation", "x", [{"role": "user", "content": "hello"}])
	await wait_frames(2)
	assert_eq(completions.size(), 3)
	assert_eq(completions[1]["error"], "no user message to send")
	assert_eq(completions[2]["error"], "disabled")
	assert_eq(server.requests.size(), 0, "no network traffic")
	assert_eq(service.stats["completion_failures"], 3)
	var outside := LLMService.new()
	outside.set_online(true)
	var outside_results: Array = []
	outside.completion_received.connect(func(_id: int, ok: bool, _text: String, error: String): outside_results.append([ok, error]))
	outside.request_completion("negotiation", "x", [{"role": "user", "content": "hello"}])
	await wait_frames(2)
	assert_eq(outside_results, [[false, "service not in scene tree"]])
	outside.free()


func test_completion_errors_and_timeouts() -> void:
	server.mode = "not_found"
	service.configure({"endpoint_url": server.claude_url(), "api_key": "sk-ant-test"})
	service.set_online(true)
	service.request_completion("negotiation", "x", [{"role": "user", "content": "hello"}])
	assert_true(await _wait_for_completions(1, 3.0))
	assert_false(completions[0]["ok"])
	assert_eq(completions[0]["error"], "HTTP 404: model: mock-missing")
	assert_true(service.is_online, "one failure does not trip the breaker")
	server.mode = "hang"
	var started := Time.get_ticks_msec()
	service.configure({"request_timeout_sec": 0.4})
	service.request_completion("crisis_writer", "x", [{"role": "user", "content": "hello"}], 400, {"timeout_sec": 0.6})
	assert_true(await _wait_for_completions(2, 3.0))
	assert_false(completions[1]["ok"])
	assert_string_contains(String(completions[1]["error"]), "timeout")
	assert_gte(float(Time.get_ticks_msec() - started), 550.0, "a feature may wait longer than the decisions")
	assert_false(service.is_online, "transport failures count toward the circuit breaker")
	assert_eq(service.pending_completion_count(), 0)


func test_completion_can_be_cancelled() -> void:
	server.mode = "hang"
	service.set_online(true)
	var request_id := service.request_completion("negotiation", "x", [{"role": "user", "content": "hello"}])
	assert_eq(service.pending_completion_count(), 1)
	service.cancel_completion(request_id)
	assert_eq(service.pending_completion_count(), 0)
	await wait_seconds(0.3)
	assert_eq(completions.size(), 0, "a cancelled request stays silent")
	assert_true(service.is_online, "and is not a failure")


# --- The build's backend, the device's key and the player's switch ----------------------

func test_only_a_key_is_kept_on_the_device() -> void:
	var path := "user://test_synapse_llm_%d.cfg" % Time.get_ticks_usec()
	var legacy := ConfigFile.new()
	for key in ["endpoint_url", "model_name", "enabled", "write_crises", "api_key"]:
		legacy.set_value("llm", key, {"endpoint_url": "https://old.example/v1/messages", "model_name": "old-model",
			"enabled": false, "write_crises": false, "api_key": "access-code-1"}[key])
	legacy.save(path)
	var loaded := LLMService.new()
	loaded.config_path = path
	loaded.load_configuration()
	assert_eq(loaded.endpoint_url, String(ProjectSettings.get_setting("synapse/llm/endpoint_url")),
		"an endpoint an older version saved on the device is ignored: the build decides")
	assert_eq(loaded.model_name, String(ProjectSettings.get_setting("synapse/llm/model_name")))
	assert_true(loaded.enabled, "and so is an old off switch")
	assert_true(loaded.write_crises, "crisis writing follows the build")
	assert_eq(loaded.api_key, "access-code-1", "the key stays")
	assert_eq(loaded.store_api_key("access-code-2"), OK)
	var config := ConfigFile.new()
	config.load(path)
	assert_eq(config.get_value("llm", "api_key"), "access-code-2")
	loaded.store_api_key("")
	config = ConfigFile.new()
	config.load(path)
	assert_false(config.has_section_key("llm", "api_key"), "an empty key forgets the stored one")
	loaded.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_claude_key_without_a_backend_means_claude() -> void:
	var path := "user://test_synapse_llm_%d.cfg" % Time.get_ticks_usec()
	var fresh := LLMService.new()
	fresh.config_path = path
	fresh.store_api_key("not-a-claude-key")
	assert_eq(fresh.endpoint_url, LLMService.DEFAULT_ENDPOINT, "another key keeps the local endpoint")
	fresh.store_api_key("sk-ant-player-key")
	assert_eq(fresh.endpoint_url, LLMService.ANTHROPIC_ENDPOINT)
	assert_eq(fresh.model_name, LLMService.CLAUDE_DEFAULT_MODEL)
	assert_gte(fresh.request_timeout_sec, LLMService.CLAUDE_TIMEOUT_SEC)
	var proxied := LLMService.new()
	proxied.config_path = path
	proxied.configure({"endpoint_url": "https://proxy.example.workers.dev/v1/messages", "model_name": ""})
	proxied.store_api_key("sk-ant-player-key")
	assert_eq(proxied.endpoint_url, "https://proxy.example.workers.dev/v1/messages", "a build's backend is kept")
	fresh.free()
	proxied.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_which_backends_a_platform_may_use() -> void:
	assert_true(LLMService.backend_usable(LLMService.DEFAULT_ENDPOINT, "", false), "desktop: a local model")
	assert_false(LLMService.backend_usable(LLMService.DEFAULT_ENDPOINT, "", true), "the web never reaches into the visitor's machine")
	assert_false(LLMService.backend_usable(LLMService.ANTHROPIC_ENDPOINT, "", true), "nor Anthropic without a key")
	assert_true(LLMService.backend_usable(LLMService.ANTHROPIC_ENDPOINT, "sk-ant-x", true))
	assert_true(LLMService.backend_usable("https://synapse-llm-proxy.x.workers.dev/v1/messages", "", true), "the shared backend")
	assert_false(LLMService.backend_usable(" ", "", false))
	assert_true(service.has_backend())
	service.configure({"enabled": false})
	assert_false(service.has_backend(), "a build can switch the LLM off entirely")
	assert_eq(service.get_state(), LLMService.STATE_NONE)


func test_the_player_switch() -> void:
	assert_eq(service.get_state(), LLMService.STATE_OFFLINE)
	service.set_online(true)
	assert_eq(service.get_state(), LLMService.STATE_ONLINE)
	statuses.clear()
	service.set_switched_on(false)
	assert_false(service.is_online)
	assert_eq(service.get_state(), LLMService.STATE_OFF)
	assert_false(statuses.is_empty(), "listeners hear about it")
	assert_false(service.should_auto_probe(), "nothing leaves the game while it is off")
	service.query_actor_decision("ASI", _state("ASI"))
	assert_eq(received[0]["payload"]["source"], "HEURISTIC")
	service.request_completion("negotiation", "x", [{"role": "user", "content": "hello"}])
	assert_true(await _wait_for_completions(1, 1.0))
	assert_eq(completions[0]["error"], "disabled")
	service.set_online(true)
	assert_false(service.is_online, "cannot go online while switched off")
	service.probe_connection()
	assert_eq(server.requests.size(), 0, "no traffic at all")
	service.set_switched_on(true)
	assert_true(service.is_probing, "switching on probes the backend again")
	var probes := service.find_children("*", "HTTPRequest", false, false).size()
	service.set_switched_on(false)
	assert_false(service.is_probing, "switching off mid-probe drops the probe")
	await tree.process_frame
	assert_lt(service.find_children("*", "HTTPRequest", false, false).size(), probes, "and frees its request")
	service.set_switched_on(true)
	var deadline := Time.get_ticks_msec() + 3000
	while service.is_probing and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	assert_eq(service.get_state(), LLMService.STATE_ONLINE)


func test_a_daily_limit_takes_the_llm_offline_until_it_lifts() -> void:
	service.configure({"endpoint_url": server.claude_url(), "model_name": ""})
	service.set_online(true)
	server.mode = "daily_limit"
	service.query_actor_decision("ASI", _state("ASI"))
	assert_true(await _wait_for_decisions(1, 3.0))
	assert_eq(received[0]["payload"]["source"], "HEURISTIC_FALLBACK")
	assert_false(service.is_online, "offline at the first refusal: the backend says no for the rest of the day")
	assert_eq(service.limited, "daily")
	assert_eq(service.get_state(), LLMService.STATE_LIMITED)
	service.probe_connection()
	var deadline := Time.get_ticks_msec() + 3000
	while service.is_probing and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	assert_false(service.is_online)
	assert_string_contains(service.last_error, "daily limit reached")
	assert_eq(service.get_state(), LLMService.STATE_LIMITED)
	server.mode = "ok"
	service.probe_connection()
	deadline = Time.get_ticks_msec() + 3000
	while service.is_probing and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	assert_true(service.is_online, "a probe that gets through lifts it")
	assert_eq(service.limited, "")
	assert_eq(LLMService.limit_in(429, "{\"type\": \"error\", \"error\": {\"limit\": \"player\"}}"), "player")
	assert_eq(LLMService.limit_in(429, "{\"type\": \"error\", \"error\": {\"limit\": \"minute\"}}"), "",
		"the per-minute limit is an ordinary failure")
	assert_eq(LLMService.limit_in(500, "{\"error\": {\"limit\": \"daily\"}}"), "")
	assert_eq(LLMService.limit_in(429, "not json"), "")


func test_a_minute_limit_counts_as_an_ordinary_failure() -> void:
	service.configure({"endpoint_url": server.claude_url(), "model_name": ""})
	service.set_online(true)
	server.mode = "minute_limit"
	service.query_actor_decision("ASI", _state("ASI"))
	assert_true(await _wait_for_decisions(1, 3.0))
	assert_true(service.is_online, "one refusal is not enough to go offline")
	assert_eq(service.limited, "")


func test_the_backend_picks_the_model() -> void:
	service.configure({"endpoint_url": server.claude_url(), "model_name": ""})
	assert_eq(service.get_provider_name(), "LOCAL-ENDPOINT", "no model named yet")
	service.probe_connection()
	var deadline := Time.get_ticks_msec() + 3000
	while service.is_probing and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	assert_true(service.is_online)
	assert_eq(service.served_model, "mock-model", "the model listing names it")
	assert_eq(service.get_provider_name(), "MOCK-MODEL / LOCAL-ENDPOINT")
	service.query_actor_decision("ASI", _state("ASI"))
	assert_true(await _wait_for_decisions(1, 3.0))
	var body: Dictionary = server.requests[-1]["body"]
	assert_false(body.has("model"), "the request leaves the model to the backend")
	assert_eq(body["output_config"], {"effort": "low"}, "the backend drops the effort if its model takes none")
	service.request_completion("negotiation", "x", [{"role": "user", "content": "hello"}])
	assert_true(await _wait_for_completions(1, 3.0))
	assert_false((server.requests[-1]["body"] as Dictionary).has("model"))
