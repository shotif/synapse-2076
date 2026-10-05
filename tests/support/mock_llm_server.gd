extends Node
## Minimal HTTP/1.1 server that impersonates an OpenAI-compatible endpoint
## (POST /v1/chat/completions) and Claude's Messages API (POST /v1/messages)
## for LLMService tests. Runs inside the SceneTree (polls in _process).
##
## Modes for both POST endpoints:
##   "ok"             200 with `decision` serialized as the message content
##   "fenced"         200 with the decision wrapped in prose and ```json fences
##   "garbage"        200 with non-JSON prose
##   "invalid_action" 200 with an action that is not in the catalog
##   "http_500"       500 Internal Server Error
##   "unauthorized"   401 Unauthorized (also applies to GET /v1/models)
##   "not_found"      404 with a provider error message (unknown model)
##   "hang"           accepts the connection and never answers (timeout path)
##   "daily_limit"    429 with the proxy's {"error": {"limit": "daily"}} (also GET /v1/models)
##   "minute_limit"   429 with the proxy's {"error": {"limit": "minute"}} (also GET /v1/models)
## GET /v1/models answers 200 unless the mode is "unauthorized", "hang" or a limit.
## [member reply_text], when set, replaces the decision as the reply text (the
## generic completions); [member thinking_block] puts a thinking block before
## Claude's text block.

var mode := "ok"
var reply_text := ""
var thinking_block := false
var decision := {
	"faction": "GOVERNANCE_COUNCIL",
	"turn": 1,
	"rationale": "Labor displacement is climbing; a safety net preserves the mandate.",
	"selected_action": "PASS_AUTOMATION_DIVIDEND",
	"resource_expenditure": {"political_capital": 35, "enforcement_budget": 15},
	"public_statement": "The Council hereby authorizes Emergency Title IV.",
}
var port := -1
var requests: Array[Dictionary] = []

var _server := TCPServer.new()
var _clients: Array[Dictionary] = []


func start() -> int:
	for candidate in range(18431, 18531):
		if _server.listen(candidate, "127.0.0.1") == OK:
			port = candidate
			return port
	return -1


func url() -> String:
	return "http://127.0.0.1:%d/v1/chat/completions" % port


func claude_url() -> String:
	return "http://127.0.0.1:%d/v1/messages" % port


func _exit_tree() -> void:
	for client in _clients:
		(client["peer"] as StreamPeerTCP).disconnect_from_host()
	_server.stop()


func _process(_delta: float) -> void:
	while _server.is_listening() and _server.is_connection_available():
		_clients.append({"peer": _server.take_connection(), "buffer": PackedByteArray(), "handled": false, "close_in": -1})
	var still_open: Array[Dictionary] = []
	for client in _clients:
		var peer: StreamPeerTCP = client["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var chunk: Array = peer.get_partial_data(available)
			if chunk[0] == OK:
				# Packed arrays held in a Dictionary are copy-on-write: reassign.
				var buffer: PackedByteArray = client["buffer"]
				buffer.append_array(chunk[1])
				client["buffer"] = buffer
		if not client["handled"] and _request_complete(client["buffer"]):
			client["handled"] = true
			_handle(client)
		if int(client["close_in"]) > 0:
			client["close_in"] = int(client["close_in"]) - 1
			if int(client["close_in"]) == 0:
				peer.disconnect_from_host()
				continue
		still_open.append(client)
	_clients = still_open


func _request_complete(buffer: PackedByteArray) -> bool:
	var header_end := _header_end(buffer)
	if header_end < 0:
		return false
	var head := buffer.slice(0, header_end).get_string_from_utf8()
	var content_length := 0
	for line in head.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			content_length = line.get_slice(":", 1).strip_edges().to_int()
	return buffer.size() >= header_end + 4 + content_length


func _header_end(buffer: PackedByteArray) -> int:
	for i in range(0, buffer.size() - 3):
		if buffer[i] == 13 and buffer[i + 1] == 10 and buffer[i + 2] == 13 and buffer[i + 3] == 10:
			return i
	return -1


func _handle(client: Dictionary) -> void:
	var buffer: PackedByteArray = client["buffer"]
	var header_end := _header_end(buffer)
	var head := buffer.slice(0, header_end).get_string_from_utf8()
	var body := buffer.slice(header_end + 4).get_string_from_utf8()
	var lines := head.split("\r\n")
	var request_line := lines[0].split(" ")
	var headers := {}
	for i in range(1, lines.size()):
		var header_name := lines[i].get_slice(":", 0).strip_edges().to_lower()
		headers[header_name] = lines[i].substr(lines[i].find(":") + 1).strip_edges()
	var parsed_body: Variant = null
	if body != "":
		var json := JSON.new()
		if json.parse(body) == OK:
			parsed_body = json.data
	requests.append({"method": request_line[0], "path": request_line[1] if request_line.size() > 1 else "",
		"headers": headers, "body": parsed_body})
	if mode == "hang":
		return
	var path := String(requests[-1]["path"])
	var claude := path.ends_with("/messages")
	if mode == "unauthorized":
		_respond(client, 401, _error_body(claude, "authentication_error", "invalid x-api-key"))
	elif mode == "daily_limit" or mode == "minute_limit":
		var limit := "daily" if mode == "daily_limit" else "minute"
		var error := {"type": "rate_limit_error", "message": "limit reached", "limit": limit}
		_respond(client, 429, {"type": "error", "error": error})
	elif path.ends_with("/models"):
		_respond(client, 200, {"object": "list", "data": [{"id": "mock-model", "object": "model"}]})
	elif mode == "http_500":
		_respond(client, 500, _error_body(claude, "api_error", "upstream exploded"))
	elif mode == "not_found":
		_respond(client, 404, _error_body(claude, "not_found_error", "model: mock-missing"))
	elif claude:
		var blocks: Array = [{"type": "text", "text": _content_for_mode()}]
		if thinking_block:
			blocks.push_front({"type": "thinking", "thinking": "{\"say\": \"not this\"}", "signature": "sig"})
		_respond(client, 200, {"id": "msg_mock", "type": "message", "role": "assistant", "model": "mock-model",
			"content": blocks, "stop_reason": "end_turn"})
	else:
		_respond(client, 200, {
			"id": "chatcmpl-mock",
			"object": "chat.completion",
			"model": "mock-model",
			"choices": [{"index": 0, "finish_reason": "stop", "message": {"role": "assistant", "content": _content_for_mode()}}],
		})


## Claude wraps errors as {"type": "error", "error": {...}}; OpenAI-style
## servers as {"error": {...}}.
func _error_body(claude: bool, error_type: String, message: String) -> Dictionary:
	var error := {"type": error_type, "message": message}
	return {"type": "error", "error": error} if claude else {"error": error}


func _content_for_mode() -> String:
	var content := JSON.stringify(decision) if reply_text == "" else reply_text
	match mode:
		"fenced":
			content = "Certainly. Here is my decision:\n```json\n%s\n```\nGood luck, humans." % JSON.stringify(decision, "  ")
		"garbage":
			content = "I believe the council should do something nice for everyone this turn."
		"invalid_action":
			var bad := decision.duplicate(true)
			bad["selected_action"] = "LAUNCH_ORBITAL_STRIKE"
			content = JSON.stringify(bad)
	return content


func _respond(client: Dictionary, status: int, payload: Dictionary) -> void:
	var reason: String = {200: "OK", 401: "Unauthorized", 404: "Not Found", 429: "Too Many Requests",
		500: "Internal Server Error"}.get(status, "OK")
	var body := JSON.stringify(payload).to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, reason, body.size()]
	var peer: StreamPeerTCP = client["peer"]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body)
	client["close_in"] = 30
