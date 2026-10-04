class_name LLMService
extends Node
## REST client for OpenAI-compatible chat-completions endpoints (PRD section 7):
## Claude API proxies, local Ollama, vLLM and similar servers.
##
## Contract: every call to [method query_actor_decision] produces exactly one
## [signal actor_decision_received] for that faction. When the service is
## offline, the endpoint is unreachable, the request exceeds the timeout
## (5000 ms by default) or the reply fails schema validation, the decision
## comes from HeuristicFallback instead, tagged with a fallback reason.
## After [member max_consecutive_failures] transport failures the service
## marks itself offline and re-probes periodically.
##
## Configuration precedence (lowest to highest): defaults, project settings
## (synapse/llm/*), user://synapse_llm.cfg [llm] section, environment variables
## SYNAPSE_LLM_ENDPOINT / SYNAPSE_LLM_MODEL / SYNAPSE_LLM_API_KEY /
## SYNAPSE_LLM_ENABLED / SYNAPSE_LLM_TIMEOUT / SYNAPSE_LLM_JSON_MODE. API keys are never read from
## project settings, so they cannot end up in version control.

signal llm_status_changed(is_online: bool, provider_name: String)
signal actor_decision_received(faction: String, action_payload: Dictionary)
signal probe_finished(is_online: bool, detail: String)

const DEFAULT_ENDPOINT := "http://127.0.0.1:11434/v1/chat/completions"
const DEFAULT_MODEL := "llama3:8b"
const DEFAULT_TIMEOUT_SEC := 5.0
const USER_CONFIG_PATH := "user://synapse_llm.cfg"

var is_online: bool = false
var endpoint_url: String = DEFAULT_ENDPOINT
var api_key: String = ""
var model_name: String = DEFAULT_MODEL
var enabled := true
var request_timeout_sec := DEFAULT_TIMEOUT_SEC
var json_mode := true
var temperature := 0.4
var max_tokens := 400
var max_consecutive_failures := 2
## Seconds between automatic re-probes while offline (0 disables).
var reprobe_interval_sec := 60.0
var is_probing := false
var last_error := ""
var stats := {"requests": 0, "llm_decisions": 0, "fallbacks": 0, "timeouts": 0, "invalid": 0}

var _pending := {}
var _next_request_id := 1
var _consecutive_failures := 0
var _probe_request: HTTPRequest
var _probe_deadline: SceneTreeTimer
var _reprobe_timer: Timer


func _ready() -> void:
	_reprobe_timer = Timer.new()
	_reprobe_timer.one_shot = false
	_reprobe_timer.timeout.connect(_on_reprobe_timer)
	add_child(_reprobe_timer)
	_update_reprobe_timer()


## Applies settings from a dictionary (keys match the member names).
func configure(settings: Dictionary) -> void:
	endpoint_url = String(settings.get("endpoint_url", endpoint_url)).strip_edges()
	model_name = String(settings.get("model_name", model_name)).strip_edges()
	api_key = String(settings.get("api_key", api_key)).strip_edges()
	enabled = bool(settings.get("enabled", enabled))
	request_timeout_sec = maxf(0.1, float(settings.get("request_timeout_sec", request_timeout_sec)))
	json_mode = bool(settings.get("json_mode", json_mode))
	if not enabled and is_online:
		set_online(false, "disabled")


func load_configuration() -> void:
	configure({
		"endpoint_url": ProjectSettings.get_setting("synapse/llm/endpoint_url", DEFAULT_ENDPOINT),
		"model_name": ProjectSettings.get_setting("synapse/llm/model_name", DEFAULT_MODEL),
		"enabled": ProjectSettings.get_setting("synapse/llm/enabled", true),
		"request_timeout_sec": ProjectSettings.get_setting("synapse/llm/timeout_sec", DEFAULT_TIMEOUT_SEC),
		"json_mode": ProjectSettings.get_setting("synapse/llm/json_mode", true),
	})
	var config := ConfigFile.new()
	if config.load(USER_CONFIG_PATH) == OK:
		var from_file := {}
		for key in ["endpoint_url", "model_name", "api_key", "enabled", "request_timeout_sec", "json_mode"]:
			if config.has_section_key("llm", key):
				from_file[key] = config.get_value("llm", key)
		configure(from_file)
	var from_env := {}
	if OS.has_environment("SYNAPSE_LLM_ENDPOINT"):
		from_env["endpoint_url"] = OS.get_environment("SYNAPSE_LLM_ENDPOINT")
	if OS.has_environment("SYNAPSE_LLM_MODEL"):
		from_env["model_name"] = OS.get_environment("SYNAPSE_LLM_MODEL")
	if OS.has_environment("SYNAPSE_LLM_API_KEY"):
		from_env["api_key"] = OS.get_environment("SYNAPSE_LLM_API_KEY")
	if OS.has_environment("SYNAPSE_LLM_ENABLED"):
		from_env["enabled"] = OS.get_environment("SYNAPSE_LLM_ENABLED").to_lower() in ["1", "true", "yes", "on"]
	if OS.has_environment("SYNAPSE_LLM_TIMEOUT"):
		from_env["request_timeout_sec"] = OS.get_environment("SYNAPSE_LLM_TIMEOUT").to_float()
	if OS.has_environment("SYNAPSE_LLM_JSON_MODE"):
		from_env["json_mode"] = OS.get_environment("SYNAPSE_LLM_JSON_MODE").to_lower() in ["1", "true", "yes", "on"]
	configure(from_env)


## Persists endpoint settings to user://. The API key is only written when
## [param include_api_key] is true.
func save_user_configuration(include_api_key: bool = false) -> Error:
	var config := ConfigFile.new()
	config.load(USER_CONFIG_PATH)
	config.set_value("llm", "endpoint_url", endpoint_url)
	config.set_value("llm", "model_name", model_name)
	config.set_value("llm", "enabled", enabled)
	config.set_value("llm", "request_timeout_sec", request_timeout_sec)
	if include_api_key:
		config.set_value("llm", "api_key", api_key)
	return config.save(USER_CONFIG_PATH)


## Human-readable "MODEL / PROVIDER" label, e.g. "LLAMA3:8B / LOCAL-OLLAMA".
func get_provider_name() -> String:
	return "%s / %s" % [model_name.to_upper(), provider_for_endpoint(endpoint_url)]


static func provider_for_endpoint(url: String) -> String:
	var host_port := url
	var scheme_end := host_port.find("://")
	if scheme_end >= 0:
		host_port = host_port.substr(scheme_end + 3)
	host_port = host_port.get_slice("/", 0)
	var host := host_port.get_slice(":", 0).to_lower()
	var port := host_port.get_slice(":", 1) if host_port.contains(":") else ""
	if host in ["127.0.0.1", "localhost", "0.0.0.0", "[::1]"]:
		match port:
			"11434":
				return "LOCAL-OLLAMA"
			"8000":
				return "LOCAL-VLLM"
			"1234":
				return "LOCAL-LMSTUDIO"
		return "LOCAL-ENDPOINT"
	for known in ["anthropic", "openai", "openrouter", "groq", "together", "mistral", "deepseek"]:
		if host.contains(known):
			return known.to_upper()
	return host.to_upper()


## Text for the dashboard header badge (PRD 7.2).
func get_status_text() -> String:
	if is_probing and not is_online:
		return "◌ [LLM PROBING: %s]" % get_provider_name()
	if is_online:
		return "● [LLM ONLINE: %s]" % get_provider_name()
	return "▲ [LLM OFFLINE - RUNNING HEURISTIC FALLBACK ENGINE]"


func set_online(online: bool, reason: String = "") -> void:
	var previous := is_online
	is_online = online and enabled
	if reason != "":
		last_error = reason if not is_online else ""
	if is_online:
		_consecutive_failures = 0
	_update_reprobe_timer()
	if previous != is_online:
		llm_status_changed.emit(is_online, get_provider_name())


## Checks connectivity with GET {base}/models. Reachable servers that do not
## implement the listing (404/405) count as online; auth failures do not.
func probe_connection() -> void:
	if not enabled:
		set_online(false, "disabled")
		probe_finished.emit(false, "LLM disabled in settings")
		return
	if not is_inside_tree() or is_probing:
		return
	is_probing = true
	llm_status_changed.emit(is_online, get_provider_name())
	_probe_request = HTTPRequest.new()
	_probe_request.timeout = request_timeout_sec
	add_child(_probe_request)
	_probe_request.request_completed.connect(_on_probe_completed)
	var error := _probe_request.request(models_url(), _headers(), HTTPClient.METHOD_GET)
	if error != OK:
		_finish_probe(false, "probe request failed (error %d)" % error)
		return
	_probe_deadline = get_tree().create_timer(request_timeout_sec + 0.5)
	_probe_deadline.timeout.connect(_on_probe_deadline)


func models_url() -> String:
	if endpoint_url.ends_with("/chat/completions"):
		return endpoint_url.trim_suffix("/chat/completions") + "/models"
	if endpoint_url.ends_with("/completions"):
		return endpoint_url.trim_suffix("/completions") + "/models"
	return endpoint_url.trim_suffix("/") + "/models"


## PRD 7.1 entry point: resolve one autonomous actor's decision.
func query_actor_decision(faction_name: String, world_state: Dictionary) -> void:
	if not is_online or not enabled:
		_emit_fallback(faction_name, world_state, "offline")
		return
	if not is_inside_tree():
		_emit_fallback(faction_name, world_state, "service not in scene tree")
		return
	_send_api_request(faction_name, world_state)


func pending_request_count() -> int:
	return _pending.size()


func _send_api_request(faction_name: String, world_state: Dictionary) -> void:
	stats["requests"] += 1
	var request_id := _next_request_id
	_next_request_id += 1
	var http := HTTPRequest.new()
	http.timeout = request_timeout_sec
	add_child(http)
	http.request_completed.connect(_on_request_completed.bind(request_id))
	var body := PromptTemplates.build_request_body(model_name, faction_name, world_state, json_mode, temperature, max_tokens)
	var error := http.request(endpoint_url, _headers(), HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		http.queue_free()
		_register_failure("request error %d" % error)
		_emit_fallback(faction_name, world_state, "request error %d" % error)
		return
	var deadline := get_tree().create_timer(request_timeout_sec + 0.25)
	deadline.timeout.connect(_on_request_deadline.bind(request_id))
	_pending[request_id] = {"faction": faction_name, "state": world_state, "http": http, "started": Time.get_ticks_msec()}


func _on_request_completed(result: int, response_code: int, _headers_in: PackedStringArray, body: PackedByteArray, request_id: int) -> void:
	if not _pending.has(request_id):
		return
	var entry: Dictionary = _pending[request_id]
	_pending.erase(request_id)
	(entry["http"] as HTTPRequest).queue_free()
	var faction_name := String(entry["faction"])
	var state: Dictionary = entry["state"]
	if result != HTTPRequest.RESULT_SUCCESS:
		var reason := "timeout" if result == HTTPRequest.RESULT_TIMEOUT else "transport error %d" % result
		if result == HTTPRequest.RESULT_TIMEOUT:
			stats["timeouts"] += 1
		_register_failure(reason)
		_emit_fallback(faction_name, state, reason)
		return
	if response_code < 200 or response_code >= 300:
		_register_failure("HTTP %d" % response_code)
		_emit_fallback(faction_name, state, "HTTP %d" % response_code)
		return
	# The endpoint answered: transport is healthy even if the content is bad.
	_consecutive_failures = 0
	var parsed := PromptTemplates.parse_completion(body.get_string_from_utf8())
	if not parsed["ok"]:
		stats["invalid"] += 1
		_emit_fallback(faction_name, state, "invalid response: " + String(parsed["error"]))
		return
	var validation := PromptTemplates.validate_decision(faction_name, int(state.get("turn", 0)),
		parsed["payload"], state.get("available_actions", []))
	if not validation["ok"]:
		stats["invalid"] += 1
		_emit_fallback(faction_name, state, "schema violation: " + "; ".join(validation["errors"]))
		return
	stats["llm_decisions"] += 1
	var decision: Dictionary = validation["decision"]
	decision["latency_ms"] = Time.get_ticks_msec() - int(entry["started"])
	actor_decision_received.emit(faction_name, decision)


func _on_request_deadline(request_id: int) -> void:
	if not _pending.has(request_id):
		return
	var entry: Dictionary = _pending[request_id]
	_pending.erase(request_id)
	var http: HTTPRequest = entry["http"]
	http.cancel_request()
	http.queue_free()
	stats["timeouts"] += 1
	_register_failure("timeout")
	_emit_fallback(String(entry["faction"]), entry["state"], "timeout after %.1fs" % request_timeout_sec)


func _emit_fallback(faction_name: String, world_state: Dictionary, reason: String) -> void:
	var decision := HeuristicFallback.evaluate(faction_name, world_state)
	if reason != "offline":
		decision["source"] = "HEURISTIC_FALLBACK"
	decision["fallback_reason"] = reason
	stats["fallbacks"] += 1
	actor_decision_received.emit(faction_name, decision)


func _register_failure(reason: String) -> void:
	last_error = reason
	_consecutive_failures += 1
	if _consecutive_failures >= max_consecutive_failures and is_online:
		set_online(false, reason)


func _on_probe_completed(result: int, response_code: int, _headers_in: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish_probe(false, "unreachable (result %d)" % result)
	elif response_code == 401 or response_code == 403:
		_finish_probe(false, "authentication failed (HTTP %d)" % response_code)
	elif response_code >= 500:
		_finish_probe(false, "server error (HTTP %d)" % response_code)
	else:
		_finish_probe(true, "HTTP %d" % response_code)


func _on_probe_deadline() -> void:
	if is_probing:
		_finish_probe(false, "probe timed out")


func _finish_probe(online: bool, detail: String) -> void:
	if not is_probing:
		return
	is_probing = false
	if _probe_request != null:
		_probe_request.cancel_request()
		_probe_request.queue_free()
		_probe_request = null
	var was_online := is_online
	set_online(online, detail)
	if was_online == is_online:
		# Always refresh listeners once a probe settles (the badge left PROBING).
		llm_status_changed.emit(is_online, get_provider_name())
	probe_finished.emit(is_online, detail)


func _on_reprobe_timer() -> void:
	if enabled and not is_online and not is_probing:
		probe_connection()


func _update_reprobe_timer() -> void:
	if _reprobe_timer == null:
		return
	if enabled and not is_online and reprobe_interval_sec > 0.0:
		if _reprobe_timer.is_stopped():
			_reprobe_timer.start(reprobe_interval_sec)
	else:
		_reprobe_timer.stop()


func _headers() -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if api_key != "":
		headers.append("Authorization: Bearer " + api_key)
	return headers
