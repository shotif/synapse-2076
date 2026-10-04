extends "res://tests/framework/test_case.gd"
## LLMService against a real local HTTP server (tests/support/mock_llm_server.gd):
## online decisions, every fallback path, timeouts, probing and status signals.

const MockServer := preload("res://tests/support/mock_llm_server.gd")
const WebBuildConfig := preload("res://tools/configure_web_build.gd")

var server: Node
var service: LLMService
var received: Array = []
var statuses: Array = []


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
	service.actor_decision_received.connect(func(f: String, p: Dictionary): received.append({"faction": f, "payload": p}))
	service.llm_status_changed.connect(func(online: bool, provider: String): statuses.append([online, provider]))


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
