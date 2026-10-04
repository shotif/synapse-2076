class_name LLMService
extends Node
## REST client for the LLM decision layer (PRD section 7). Speaks two wire
## formats: Claude's Messages API (endpoint ending in /v1/messages: Anthropic
## directly or a proxy) and OpenAI-compatible chat completions (local Ollama,
## vLLM, LM Studio, OpenRouter and similar).
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
## SYNAPSE_LLM_ENABLED / SYNAPSE_LLM_TIMEOUT / SYNAPSE_LLM_JSON_MODE /
## SYNAPSE_LLM_API_FORMAT / SYNAPSE_LLM_EFFORT. API keys are never read from project settings, so
## they cannot end up in version control or in an exported build. Web builds
## can also take a key from the page URL (#llm-key=...), see
## [method import_page_url_settings].
##
## Besides the faction decisions, [method request_completion] sends any
## system prompt and conversation over the same transport (Claude's crisis
## writer and the "Call the ..." negotiations) and answers with
## [signal completion_received].

signal llm_status_changed(is_online: bool, provider_name: String)
signal actor_decision_received(faction: String, action_payload: Dictionary)
signal probe_finished(is_online: bool, detail: String)
## The reply to one [method request_completion] call: [param text] is the
## model's text (Claude: its text blocks) when [param ok], otherwise
## [param error] says why it failed.
signal completion_received(request_id: int, ok: bool, text: String, error: String)

const DEFAULT_ENDPOINT := "http://127.0.0.1:11434/v1/chat/completions"
const DEFAULT_MODEL := "llama3:8b"
const DEFAULT_TIMEOUT_SEC := 5.0
const USER_CONFIG_PATH := "user://synapse_llm.cfg"
const API_FORMATS := ["auto", "openai", "anthropic"]
const ANTHROPIC_VERSION := "2023-06-01"
const ANTHROPIC_HOST := "api.anthropic.com"
## Claude's adaptive thinking counts toward max_tokens, so Claude requests get
## more room than the 400 tokens a local model needs for the decision JSON.
const CLAUDE_MAX_TOKENS := 2048
const EFFORT_LEVELS := ["low", "medium", "high"]

var is_online: bool = false
var endpoint_url: String = DEFAULT_ENDPOINT
var api_key: String = ""
var model_name: String = DEFAULT_MODEL
var enabled := true
var request_timeout_sec := DEFAULT_TIMEOUT_SEC
var json_mode := true
## "anthropic" (Claude Messages API), "openai" (chat completions) or "auto",
## which picks Claude for endpoints ending in /messages.
var api_format := "auto"
## Claude thinking effort ("low", "medium", "high", or "" to leave the model
## default). Low skips thinking on most simple requests: one faction decision
## is a small, latency-bound task.
var effort := "low"
var temperature := 0.4
var max_tokens := 400
var max_consecutive_failures := 2
## Seconds between automatic re-probes while offline (0 disables).
var reprobe_interval_sec := 60.0
## Lets the model write a crisis card for the human players every few turns
## (CrisisWriter). Off by default; saved in user://synapse_llm.cfg.
var write_crises := false
## Where [method load_configuration] and [method save_user_configuration] keep
## the player's settings (tests point it elsewhere).
var config_path := USER_CONFIG_PATH
var is_probing := false
var last_error := ""
var stats := {"requests": 0, "llm_decisions": 0, "fallbacks": 0, "timeouts": 0, "invalid": 0,
	"completions": 0, "completion_failures": 0}

var _pending := {}
var _completions := {}
var _next_request_id := 1
var _consecutive_failures := 0
var _probe_request: HTTPRequest
var _probe_deadline: SceneTreeTimer
var _reprobe_timer: Timer
## Set when the endpoint rejected the credentials; automatic probing stops
## until the endpoint, key or format changes.
var _auth_failed := false


func _ready() -> void:
	_reprobe_timer = Timer.new()
	_reprobe_timer.one_shot = false
	_reprobe_timer.timeout.connect(_on_reprobe_timer)
	add_child(_reprobe_timer)
	_update_reprobe_timer()


## Applies settings from a dictionary (keys match the member names).
func configure(settings: Dictionary) -> void:
	var previous := [endpoint_url, api_key, api_format]
	endpoint_url = String(settings.get("endpoint_url", endpoint_url)).strip_edges()
	model_name = String(settings.get("model_name", model_name)).strip_edges()
	api_key = String(settings.get("api_key", api_key)).strip_edges()
	enabled = bool(settings.get("enabled", enabled))
	request_timeout_sec = maxf(0.1, float(settings.get("request_timeout_sec", request_timeout_sec)))
	json_mode = bool(settings.get("json_mode", json_mode))
	var format := String(settings.get("api_format", api_format)).strip_edges().to_lower()
	api_format = format if format in API_FORMATS else "auto"
	var level := String(settings.get("effort", effort)).strip_edges().to_lower()
	effort = level if level in EFFORT_LEVELS else ""
	write_crises = bool(settings.get("write_crises", write_crises))
	if previous != [endpoint_url, api_key, api_format]:
		_auth_failed = false
	if not enabled and is_online:
		set_online(false, "disabled")
	_update_reprobe_timer()


func load_configuration() -> void:
	configure({
		"endpoint_url": ProjectSettings.get_setting("synapse/llm/endpoint_url", DEFAULT_ENDPOINT),
		"model_name": ProjectSettings.get_setting("synapse/llm/model_name", DEFAULT_MODEL),
		"enabled": ProjectSettings.get_setting("synapse/llm/enabled", true),
		"request_timeout_sec": ProjectSettings.get_setting("synapse/llm/timeout_sec", DEFAULT_TIMEOUT_SEC),
		"json_mode": ProjectSettings.get_setting("synapse/llm/json_mode", true),
		"api_format": ProjectSettings.get_setting("synapse/llm/api_format", "auto"),
		"effort": ProjectSettings.get_setting("synapse/llm/effort", "low"),
	})
	var config := ConfigFile.new()
	if config.load(config_path) == OK:
		var from_file := {}
		for key in ["endpoint_url", "model_name", "api_key", "enabled", "request_timeout_sec", "json_mode", "api_format", "effort",
				"write_crises"]:
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
	if OS.has_environment("SYNAPSE_LLM_API_FORMAT"):
		from_env["api_format"] = OS.get_environment("SYNAPSE_LLM_API_FORMAT")
	if OS.has_environment("SYNAPSE_LLM_EFFORT"):
		from_env["effort"] = OS.get_environment("SYNAPSE_LLM_EFFORT")
	configure(from_env)


## Persists endpoint settings to user:// (in a browser: the site's storage).
## The API key is only written when [param include_api_key] is true; an empty
## key then removes a stored one.
func save_user_configuration(include_api_key: bool = false) -> Error:
	var config := ConfigFile.new()
	config.load(config_path)
	config.set_value("llm", "endpoint_url", endpoint_url)
	config.set_value("llm", "model_name", model_name)
	config.set_value("llm", "enabled", enabled)
	config.set_value("llm", "request_timeout_sec", request_timeout_sec)
	config.set_value("llm", "api_format", api_format)
	config.set_value("llm", "effort", effort)
	config.set_value("llm", "write_crises", write_crises)
	if include_api_key:
		if api_key != "":
			config.set_value("llm", "api_key", api_key)
		elif config.has_section_key("llm", "api_key"):
			config.erase_section_key("llm", "api_key")
	return config.save(config_path)


## Reads settings from a URL fragment such as "#llm-key=sk-ant-...&llm=on", so
## a phone can receive a key without typing. Only the key and the on/off
## switch are accepted: a crafted link must never be able to redirect a stored
## key to another endpoint. Returns {} when the fragment has no LLM settings.
static func parse_url_fragment(fragment: String) -> Dictionary:
	var out := {}
	for pair in fragment.trim_prefix("#").split("&", false):
		var separator := pair.find("=")
		var key := (pair if separator < 0 else pair.left(separator)).strip_edges().to_lower()
		var value := "" if separator < 0 else pair.substr(separator + 1).uri_decode().strip_edges()
		if key == "llm-key":
			out["api_key"] = value
		elif key == "llm" and value.to_lower() in ["on", "off"]:
			out["enabled"] = value.to_lower() == "on"
	return out


## Web builds: applies #llm-key=... / #llm=on|off from the page URL, stores the
## key on this device, then strips the fragment from the address bar and
## history. Returns true when something was applied.
func import_page_url_settings() -> bool:
	if not OS.has_feature("web"):
		return false
	var fragment := str(JavaScriptBridge.eval("window.location.hash", true))
	var settings := parse_url_fragment(fragment)
	if settings.is_empty():
		return false
	configure(settings)
	# Store only what the link carried: the endpoint and model keep following the
	# build, so a redeploy with a new endpoint reaches devices that imported a key.
	var config := ConfigFile.new()
	config.load(config_path)
	for key in settings:
		if key == "api_key" and String(settings[key]) == "":
			if config.has_section_key("llm", key):
				config.erase_section_key("llm", key)
		else:
			config.set_value("llm", key, settings[key])
	config.save(config_path)
	JavaScriptBridge.eval("history.replaceState(null, '', window.location.pathname + window.location.search)", true)
	return true


## Whether [param model] accepts output_config.effort. Haiku 4.5 and the
## Claude 3 / early Claude 4 models reject it with a 400.
static func supports_effort(model: String) -> bool:
	var id := model.strip_edges().to_lower()
	for prefix in ["claude-haiku", "claude-3", "claude-instant", "claude-2"]:
		if id.begins_with(prefix):
			return false
	# Exact ids, or the id plus an 8-digit snapshot date ("claude-sonnet-4-5-20250929").
	for older in ["claude-sonnet-4", "claude-sonnet-4-5", "claude-opus-4", "claude-opus-4-1"]:
		var suffix := id.trim_prefix(older + "-")
		if id == older or (id.begins_with(older + "-") and suffix.length() == 8 and suffix.is_valid_int()):
			return false
	return true


## True when requests use the Claude Messages API wire format.
func uses_anthropic_format() -> bool:
	if api_format == "anthropic":
		return true
	if api_format == "openai":
		return false
	return endpoint_url.trim_suffix("/").ends_with("/messages")


## Whether to contact the endpoint without an explicit user action (startup
## probe, periodic re-probe). Web builds never auto-probe the default localhost
## endpoint (a public page reaching into the visitor's machine triggers
## permission prompts and CORS failures), nor Anthropic directly without a key
## (visitors without one never contact Anthropic). After an authentication
## failure only a settings change or the dialog's TEST button probes again.
func should_auto_probe() -> bool:
	if not enabled or _auth_failed:
		return false
	if OS.has_feature("web"):
		if endpoint_url == DEFAULT_ENDPOINT:
			return false
		if api_key == "" and host_for_endpoint(endpoint_url) == ANTHROPIC_HOST:
			return false
	return true


## Human-readable "MODEL / PROVIDER" label, e.g. "LLAMA3:8B / LOCAL-OLLAMA".
func get_provider_name() -> String:
	return "%s / %s" % [model_name.to_upper(), provider_for_endpoint(endpoint_url)]


static func host_for_endpoint(url: String) -> String:
	var host_port := url
	var scheme_end := host_port.find("://")
	if scheme_end >= 0:
		host_port = host_port.substr(scheme_end + 3)
	return host_port.get_slice("/", 0).get_slice(":", 0).to_lower()


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
	if host.is_valid_ip_address():
		return host
	# A proxy such as synapse-llm-proxy.example.workers.dev reads as SYNAPSE-LLM-PROXY.
	return host.get_slice(".", 0).to_upper()


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
	var url := endpoint_url.trim_suffix("/")
	for suffix in ["/messages", "/chat/completions", "/completions"]:
		if url.ends_with(suffix):
			return url.trim_suffix(suffix) + "/models"
	return url + "/models"


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


## Sends [param system] and the conversation [param messages] ({"role":
## "user" | "assistant", "content": text}, ending with the user's turn) for a
## feature other than the faction decisions; [param purpose] names it in errors.
## Uses the same endpoint, wire format, headers, timeout and failure accounting
## as the decisions. Claude requests get at least CLAUDE_MAX_TOKENS (thinking
## counts toward max_tokens), no sampling parameters and output_config.effort
## only where [method supports_effort] allows it. [param options]:
##   "timeout_sec"  a longer timeout for long replies (never below request_timeout_sec)
##   "json"         false: do not ask OpenAI-compatible servers for a JSON object
## Returns the request id. Each call emits exactly one [signal completion_received]
## for that id (unless cancelled). A request that cannot be sent (offline,
## disabled, outside the scene tree, no user turn) fails fast: ok=false on the
## next idle frame, with no network traffic.
func request_completion(purpose: String, system: String, messages: Array, max_reply_tokens: int = 400,
		options: Dictionary = {}) -> int:
	var request_id := _next_request_id
	_next_request_id += 1
	var turns := PromptTemplates.normalize_turns(messages)
	var refusal := ""
	if not enabled:
		refusal = "disabled"
	elif not is_online:
		refusal = "offline"
	elif not is_inside_tree():
		refusal = "service not in scene tree"
	elif turns.is_empty():
		refusal = "no user message to send"
	if refusal != "":
		_fail_completion_soon(request_id, refusal)
		return request_id
	stats["requests"] += 1
	stats["completions"] += 1
	var timeout := maxf(request_timeout_sec, float(options.get("timeout_sec", 0.0)))
	var body := PromptTemplates.build_anthropic_completion_body(model_name, system, turns,
			maxi(max_reply_tokens, CLAUDE_MAX_TOKENS), effort if supports_effort(model_name) else "") \
		if uses_anthropic_format() \
		else PromptTemplates.build_completion_body(model_name, system, turns, json_mode and bool(options.get("json", true)),
			temperature, maxi(max_reply_tokens, 16))
	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	http.request_completed.connect(_on_completion_completed.bind(request_id))
	var error := http.request(endpoint_url, _headers(), HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		http.queue_free()
		_register_failure("request error %d" % error)
		_fail_completion_soon(request_id, "%s: request error %d" % [purpose, error])
		return request_id
	var deadline := get_tree().create_timer(timeout + 0.25)
	deadline.timeout.connect(_on_completion_deadline.bind(request_id))
	_completions[request_id] = {"purpose": purpose, "http": http, "timeout": timeout}
	return request_id


## Drops a pending [method request_completion]; no signal follows for it.
func cancel_completion(request_id: int) -> void:
	if not _completions.has(request_id):
		return
	var entry: Dictionary = _completions[request_id]
	_completions.erase(request_id)
	var http: HTTPRequest = entry["http"]
	http.cancel_request()
	http.queue_free()


func pending_completion_count() -> int:
	return _completions.size()


func _on_completion_completed(result: int, response_code: int, _headers_in: PackedStringArray, body: PackedByteArray,
		request_id: int) -> void:
	if not _completions.has(request_id):
		return
	var entry: Dictionary = _completions[request_id]
	_completions.erase(request_id)
	(entry["http"] as HTTPRequest).queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		var reason := "timeout" if result == HTTPRequest.RESULT_TIMEOUT else "transport error %d" % result
		if result == HTTPRequest.RESULT_TIMEOUT:
			stats["timeouts"] += 1
		_register_failure(reason)
		_finish_completion(request_id, false, "", reason)
		return
	if response_code < 200 or response_code >= 300:
		var reason := describe_http_error(response_code, body.get_string_from_utf8())
		_register_failure(reason)
		_finish_completion(request_id, false, "", reason)
		return
	# The endpoint answered: transport is healthy even if the content is bad.
	_consecutive_failures = 0
	var reply := PromptTemplates.parse_completion_text(body.get_string_from_utf8())
	if not reply["ok"]:
		_finish_completion(request_id, false, "", "invalid response: " + String(reply["error"]))
		return
	_finish_completion(request_id, true, String(reply["text"]), "")


func _on_completion_deadline(request_id: int) -> void:
	if not _completions.has(request_id):
		return
	var entry: Dictionary = _completions[request_id]
	_completions.erase(request_id)
	var http: HTTPRequest = entry["http"]
	http.cancel_request()
	http.queue_free()
	stats["timeouts"] += 1
	_register_failure("timeout")
	_finish_completion(request_id, false, "", "timeout after %.1fs" % float(entry["timeout"]))


func _fail_completion_soon(request_id: int, reason: String) -> void:
	stats["completion_failures"] += 1
	_finish_completion.call_deferred(request_id, false, "", reason, false)


func _finish_completion(request_id: int, ok: bool, text: String, error: String, count_failure: bool = true) -> void:
	if not ok and count_failure:
		stats["completion_failures"] += 1
	completion_received.emit(request_id, ok, text, error)


func _send_api_request(faction_name: String, world_state: Dictionary) -> void:
	stats["requests"] += 1
	var request_id := _next_request_id
	_next_request_id += 1
	var http := HTTPRequest.new()
	http.timeout = request_timeout_sec
	add_child(http)
	http.request_completed.connect(_on_request_completed.bind(request_id))
	var body := PromptTemplates.build_anthropic_body(model_name, faction_name, world_state, CLAUDE_MAX_TOKENS,
			effort if supports_effort(model_name) else "") \
		if uses_anthropic_format() \
		else PromptTemplates.build_request_body(model_name, faction_name, world_state, json_mode, temperature, max_tokens)
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
		var reason := describe_http_error(response_code, body.get_string_from_utf8())
		_register_failure(reason)
		_emit_fallback(faction_name, state, reason)
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


## "HTTP 404: model: claude-x" style summary of an error response (the
## provider's message is untrusted text, so it is sanitized and truncated).
static func describe_http_error(response_code: int, body_text: String) -> String:
	var parsed := PromptTemplates.parse_completion(body_text)
	var detail := String(parsed.get("error", ""))
	if detail.begins_with("provider error: "):
		return "HTTP %d: %s" % [response_code, detail.trim_prefix("provider error: ")]
	return "HTTP %d" % response_code


func _on_probe_completed(result: int, response_code: int, _headers_in: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish_probe(false, "unreachable (result %d)" % result)
	elif response_code == 401 or response_code == 403:
		_auth_failed = true
		_finish_probe(false, "authentication failed (%s)" % describe_http_error(response_code, body.get_string_from_utf8()))
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
	if should_auto_probe() and not is_online and reprobe_interval_sec > 0.0:
		if _reprobe_timer.is_stopped():
			_reprobe_timer.start(reprobe_interval_sec)
	else:
		_reprobe_timer.stop()


func _headers() -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if uses_anthropic_format():
		headers.append("anthropic-version: " + ANTHROPIC_VERSION)
		if api_key != "":
			headers.append("x-api-key: " + api_key)
		if wants_browser_access_header(endpoint_url, OS.has_feature("web")):
			headers.append("anthropic-dangerous-direct-browser-access: true")
	elif api_key != "":
		headers.append("Authorization: Bearer " + api_key)
	return headers


## Anthropic only answers browser (CORS) requests that carry this header. It
## is "dangerous" because a key shipped inside a public page would leak; here
## the key comes from the player's own device, never from the build.
static func wants_browser_access_header(url: String, is_web: bool) -> bool:
	return is_web and host_for_endpoint(url) == ANTHROPIC_HOST
