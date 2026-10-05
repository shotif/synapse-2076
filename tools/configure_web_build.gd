extends SceneTree
## Points a web export at its LLM backend before `--export-release "Web"`.
## Reads environment variables (in CI: the GitHub repository variables wired up
## in .github/workflows/pages.yml) and writes the matching synapse/llm/*
## project settings into project.godot.
##
##   SYNAPSE_LLM_ENDPOINT=https://synapse-llm-proxy.<you>.workers.dev/v1/messages \
##       godot --headless --path . --script res://tools/configure_web_build.gd
##
## The backend is usually the shared proxy in proxy/: it holds the key, picks
## the model (the build sends none unless SYNAPSE_LLM_MODEL names one) and
## keeps a daily budget, and players only switch the LLM on or off. Nothing
## here is secret. A static web build is public, so an API key baked into it
## would be public too: SYNAPSE_LLM_API_KEY is refused.

const CLAUDE_DEFAULT_MODEL := LLMService.CLAUDE_DEFAULT_MODEL
## Claude answers over the internet in seconds, not the 5 s budget the PRD
## sets for a local model, so Claude builds wait longer before falling back.
const CLAUDE_DEFAULT_TIMEOUT_SEC := LLMService.CLAUDE_TIMEOUT_SEC
const API_FORMATS := ["auto", "openai", "anthropic"]
## Claude thinking effort; "none" leaves the model default.
const EFFORT_LEVELS := ["low", "medium", "high", "none"]
const SWITCH_WORDS := {"on": true, "true": true, "yes": true, "1": true, "off": false, "false": false, "no": false, "0": false}
const VARIABLES := ["SYNAPSE_LLM_ENDPOINT", "SYNAPSE_LLM_MODEL", "SYNAPSE_LLM_TIMEOUT",
	"SYNAPSE_LLM_API_FORMAT", "SYNAPSE_LLM_EFFORT", "SYNAPSE_LLM_WRITE_CRISES", "SYNAPSE_LLM_API_KEY"]


func _initialize() -> void:
	var env := {}
	for variable in VARIABLES:
		env[variable] = OS.get_environment(variable)
	var plan := plan_settings(env)
	for warning in plan["warnings"]:
		print("WARNING: " + warning)
	if not (plan["errors"] as Array).is_empty():
		for error in plan["errors"]:
			printerr("ERROR: " + error)
		quit(1)
		return
	var settings: Dictionary = plan["settings"]
	if settings.is_empty():
		print("No LLM endpoint configured: the web build has no LLM and its factions run on the heuristic engine.")
		quit(0)
		return
	print("Web build LLM settings:")
	for key in settings:
		ProjectSettings.set_setting(key, settings[key])
		print("  %s = %s" % [key, settings[key]])
	quit(0 if ProjectSettings.save() == OK else 1)


## Turns the environment into project settings. Returns
## {"settings": {setting: value}, "errors": [String], "warnings": [String]}.
static func plan_settings(env: Dictionary) -> Dictionary:
	var settings := {}
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if String(env.get("SYNAPSE_LLM_API_KEY", "")).strip_edges() != "":
		warnings.append("SYNAPSE_LLM_API_KEY is ignored: a web build is public, so a key baked into it would be public too.")
	var endpoint := String(env.get("SYNAPSE_LLM_ENDPOINT", "")).strip_edges()
	if endpoint == "":
		return {"settings": settings, "errors": errors, "warnings": warnings}
	if not endpoint.begins_with("https://"):
		errors.append("SYNAPSE_LLM_ENDPOINT must be an https:// URL: a page served over https cannot call plain http.")
	settings["synapse/llm/endpoint_url"] = endpoint
	settings["synapse/llm/enabled"] = true

	var api_format := String(env.get("SYNAPSE_LLM_API_FORMAT", "")).strip_edges().to_lower()
	if api_format != "" and not api_format in API_FORMATS:
		errors.append("SYNAPSE_LLM_API_FORMAT must be one of %s." % ", ".join(API_FORMATS))
	elif api_format != "":
		settings["synapse/llm/api_format"] = api_format
	var claude := api_format == "anthropic" or (api_format in ["", "auto"] and endpoint.trim_suffix("/").ends_with("/messages"))

	var model := String(env.get("SYNAPSE_LLM_MODEL", "")).strip_edges()
	if model != "":
		settings["synapse/llm/model_name"] = model
	elif claude and LLMService.host_for_endpoint(endpoint) == LLMService.ANTHROPIC_HOST:
		settings["synapse/llm/model_name"] = CLAUDE_DEFAULT_MODEL
	elif claude:
		# A proxy: the backend's first allowed model answers.
		settings["synapse/llm/model_name"] = ""
	else:
		warnings.append("SYNAPSE_LLM_MODEL is empty: the build keeps the default local model name.")

	var timeout_text := String(env.get("SYNAPSE_LLM_TIMEOUT", "")).strip_edges()
	if timeout_text != "":
		if timeout_text.is_valid_float() and timeout_text.to_float() >= 1.0 and timeout_text.to_float() <= 120.0:
			settings["synapse/llm/timeout_sec"] = timeout_text.to_float()
		else:
			errors.append("SYNAPSE_LLM_TIMEOUT must be a number of seconds between 1 and 120.")
	elif claude:
		settings["synapse/llm/timeout_sec"] = CLAUDE_DEFAULT_TIMEOUT_SEC

	var effort := String(env.get("SYNAPSE_LLM_EFFORT", "")).strip_edges().to_lower()
	if effort != "":
		if effort in EFFORT_LEVELS:
			settings["synapse/llm/effort"] = "" if effort == "none" else effort
		else:
			errors.append("SYNAPSE_LLM_EFFORT must be one of %s." % ", ".join(EFFORT_LEVELS))

	var write_crises := String(env.get("SYNAPSE_LLM_WRITE_CRISES", "")).strip_edges().to_lower()
	if write_crises != "":
		if SWITCH_WORDS.has(write_crises):
			settings["synapse/llm/write_crises"] = bool(SWITCH_WORDS[write_crises])
		else:
			errors.append("SYNAPSE_LLM_WRITE_CRISES must be on or off.")
	return {"settings": settings, "errors": errors, "warnings": warnings}
