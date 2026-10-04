extends "res://tests/framework/test_case.gd"
## "Call the ..." negotiations: who can be called, the scripted negotiator's
## offers (always valid for the engine), strict parsing of the model's
## replies, the LLM round trip with a fake service, deals that bind (applied,
## logged, one per turn), and the NegotiationDialog on a phone and a desktop.

const GOV := "GOVERNANCE_COUNCIL"
const CEO := "CEO"
const ASI := "ASI"
const CIT := "CITIZEN_COALITION"


## Stands in for LLMService: queued replies arrive on the next frame;
## unanswered requests stay pending.
class FakeLLM extends Node:
	signal completion_received(request_id: int, ok: bool, text: String, error: String)
	var is_online := true
	var replies: Array = []
	var requests: Array = []
	var cancelled: Array = []
	var _next := 500

	func request_completion(purpose: String, system: String, messages: Array, max_tokens: int = 400, options: Dictionary = {}) -> int:
		_next += 1
		var request_id := _next
		requests.append({"id": request_id, "purpose": purpose, "system": system, "messages": messages.duplicate(true),
			"max_tokens": max_tokens, "options": options})
		if not replies.is_empty():
			var reply: Array = replies.pop_front()
			completion_received.emit.call_deferred(request_id, reply[0], reply[1], reply[2])
		return request_id

	func cancel_completion(request_id: int) -> void:
		cancelled.append(request_id)


var llm: FakeLLM
var host: Control
var accepted: Array = []
var closed_count := 0


func before_each() -> void:
	llm = FakeLLM.new()
	tree.root.add_child(llm)
	accepted = []
	closed_count = 0


func after_each() -> void:
	llm.queue_free()
	if host != null:
		host.queue_free()
		host = null
	await tree.process_frame


func _engine(role: String = CEO, seed_value: int = 12, options: Dictionary = {}) -> SimulationEngine:
	var engine := SimulationEngine.new()
	engine.start_campaign(role, seed_value, options)
	engine.advance()
	return engine


func _factions(partners: Array) -> Array:
	var out: Array = []
	for entry in partners:
		out.append(String(entry["faction"]))
	return out


# --- Who picks up -----------------------------------------------------------------------

func test_callable_partners_are_the_unplayed_factions() -> void:
	var solo := _engine(CEO)
	var partners := Negotiator.callable_partners(solo)
	assert_eq(_factions(partners), [GOV, ASI, CIT])
	assert_eq(partners[0]["character"], "nadia")
	assert_eq(partners[0]["name"], "Nadia Esposito")
	assert_eq(partners[0]["title"], "Chair of the Governance Council")
	assert_eq(partners[1]["name"], "ARIA")
	assert_eq(partners[2]["name"], "Maya Okafor")
	assert_eq(_factions(Negotiator.callable_partners(_engine(GOV))), [CEO, ASI, CIT])
	assert_eq(Negotiator.callable_partners(_engine(GOV))[0]["name"], "Victor Hale")
	var duo := _engine(CEO, 3, {"human_roles": [CIT]})
	assert_eq(_factions(Negotiator.callable_partners(duo)), [GOV, ASI], "people negotiate in person")
	(solo.factions[ASI] as ActorBase).set_dormant(3)
	assert_eq(_factions(Negotiator.callable_partners(solo)), [GOV, CIT], "a dormant faction does not answer")
	assert_false(Negotiator.can_call(solo, CEO), "not yourself")
	assert_eq(Negotiator.callable_partners(null), [])
	var call := Negotiator.new()
	assert_false(call.start(duo, null, CIT), "a human-played faction cannot be called")
	assert_false(call.start(solo, null, ASI))


# --- The scripted negotiator --------------------------------------------------------------

func test_scripted_offers_are_valid_for_every_pairing() -> void:
	for role in SimConstants.FACTION_ORDER:
		var engine := _engine(role, 7)
		for partner in _factions(Negotiator.callable_partners(engine)):
			for intent in ["ask", "calm", "truce", "fund"]:
				for attempt in [0, 2]:
					var made := Negotiator.scripted_offer(engine, partner, role, intent, attempt)
					var context := "%s calls %s: %s #%d" % [role, partner, intent, attempt]
					assert_false(made.is_empty(), context)
					assert_false(String(made.get("summary", "")).is_empty(), context)
					var full := made.duplicate(true)
					full["partner"] = partner
					var preview := engine.preview_deal(full)
					assert_true(preview["ok"], "%s %s" % [context, str(preview.get("errors", []))])
					for key in made.get("give", {}):
						assert_almost_eq(float(preview["give"][key]), float(made["give"][key]), 0.001, context + ": within the caps")
					for key in made.get("metrics", {}):
						assert_almost_eq(float(preview["metrics"][key]), float(made["metrics"][key]), 0.001, context)


func test_an_offline_call_ends_in_a_binding_deal() -> void:
	var engine := _engine(GOV, 41)
	var call := Negotiator.new()
	assert_true(call.start(engine, null, CEO))
	assert_eq(call.transcript.size(), 1)
	assert_eq(call.transcript[0]["who"], "partner", "Victor answers")
	assert_false(call.uses_llm())
	assert_true(call.deal_state()["open"])
	assert_true(call.send_quick("calm"))
	assert_eq(call.transcript[1], {"who": "player", "text": "Lower tension", "source": "PLAYER"})
	assert_eq(call.transcript[2]["source"], "SCRIPTED")
	assert_false(call.offer.is_empty(), "a sensible offer for the ask")
	assert_true(call.preview["ok"])
	assert_almost_eq(float(call.preview["metrics"]["geopolitical_tension"]), -2.0, 0.001)
	assert_has(call.preview["metrics"], "algorithmic_autonomy", "and the lab's own interest")
	var pc_before := engine.get_player().get_resource("political_capital")
	var tension_before := engine.world.geopolitical_tension
	var applied := call.accept()
	assert_true(applied["ok"], str(applied.get("errors", [])))
	assert_true(call.offer.is_empty())
	assert_gt(float((applied["give"] as Dictionary).get("political_capital", 0.0)), 0.0, "the Council pays its share")
	assert_almost_eq(engine.get_player().get_resource("political_capital"),
		pc_before - float((applied["give"] as Dictionary).get("political_capital", 0.0)), 0.001)
	assert_lt(engine.world.geopolitical_tension, tension_before)
	var deals := engine.event_log.filter(func(e: Dictionary) -> bool: return e["category"] == "DEAL")
	assert_eq(deals.size(), 1, "logged as DEAL")
	assert_eq(deals[0]["partner"], CEO)
	assert_eq((engine.record["turns"]["1"]["players"][GOV]["deals"] as Array).size(), 1, "recorded")
	assert_eq(call.deal_state(), {"open": false, "text": "Deal struck this turn."})
	assert_eq(call.transcript[-2]["who"], "note")
	assert_string_contains(String(call.transcript[-2]["text"]), "Deal struck")
	# A second deal this turn is refused, whoever is called.
	var other := Negotiator.new()
	assert_true(other.start(engine, null, CIT))
	assert_eq(other.deal_state(), {"open": false, "text": "One deal per turn."})
	assert_true(other.send_quick("truce"))
	assert_true(other.offer.is_empty(), "no offer once the turn's deal is made")
	assert_eq(other.transcript[-1]["text"], Negotiator.LINES["maya"]["no_deal"][0])
	assert_false(engine.apply_deal({"partner": CIT, "pledge_turns": 2})["ok"])
	assert_false(call.accept()["ok"], "nothing left to accept")


func test_a_pledge_from_a_call_stops_retaliation() -> void:
	var engine := _engine(GOV, 17)
	var call := Negotiator.new()
	call.start(engine, null, CEO)
	call.send_quick("truce")
	var pledge := int(call.preview["pledge_turns"])
	assert_gte(float(pledge), 2.0)
	assert_true(call.accept()["ok"])
	assert_eq(engine.pledges[CEO], {"toward": GOV, "until": 1 + pledge})


func test_the_call_has_six_messages() -> void:
	var engine := _engine(CIT, 8)
	var call := Negotiator.new()
	call.start(engine, null, GOV)
	for i in Negotiator.MAX_PLAYER_MESSAGES:
		assert_true(call.send("Message %d about the weather" % i), "message %d" % i)
	assert_eq(call.messages_left(), 0)
	assert_false(call.can_send())
	assert_false(call.send("One more?"), "the line goes quiet")
	assert_eq(call.transcript.filter(func(e: Dictionary) -> bool: return e["who"] == "player").size(), Negotiator.MAX_PLAYER_MESSAGES)
	assert_false(call.send_quick("nonsense"))


func test_free_text_finds_the_intent() -> void:
	assert_eq(Negotiator.detect_intent("Lower tension"), "calm")
	assert_eq(Negotiator.detect_intent("please stop retaliating against our people"), "truce")
	assert_eq(Negotiator.detect_intent("Can you FUND the clinics?"), "fund")
	assert_eq(Negotiator.detect_intent("What would it take? Name your price"), "ask")
	assert_eq(Negotiator.detect_intent("How much?"), "ask")
	assert_eq(Negotiator.detect_intent("Nice weather in Lagos"), "chat")
	var engine := _engine(CEO, 5)
	var call := Negotiator.new()
	call.start(engine, null, CIT)
	call.send("Nice weather in Lagos")
	assert_true(call.offer.is_empty(), "small talk gets no offer")
	assert_has(Negotiator.LINES["maya"]["chat"], call.transcript[-1]["text"])
	call.send("What would it take?")
	assert_false(call.offer.is_empty())
	call.decline()
	assert_true(call.offer.is_empty())
	assert_eq(call.transcript[-2]["text"], "You turn the offer down.")
	assert_true(call.deal_state()["open"], "declining keeps the deal open")


func test_a_resentful_leader_will_not_fund_you() -> void:
	var engine := _engine(CEO, 6)
	(engine.factions[CIT] as ActorBase).add_grievance(CEO, 60.0)
	assert_true(Negotiator.scripted_offer(engine, CIT, CEO, "fund").is_empty())
	var call := Negotiator.new()
	call.start(engine, null, CIT)
	assert_eq(call.transcript[0]["text"], Negotiator.LINES["maya"]["greeting_cold"][0], "a cold greeting")
	call.send_quick("fund")
	assert_true(call.offer.is_empty())
	assert_eq(call.transcript[-1]["text"], Negotiator.LINES["maya"]["fund_refused"][0])
	assert_eq(Negotiator.grievance_word(call.grievance()), "hostile")
	call.send_quick("truce")
	assert_eq(int(call.preview["pledge_turns"]), SimulationEngine.DEAL_MAX_PLEDGE_TURNS, "a long truce, at a price")


# --- The model's replies ----------------------------------------------------------------

func test_model_replies_are_parsed_and_validated() -> void:
	var good := Negotiator.parse_reply("{\"say\": \"Fine. [b]Three turns[/b].\", \"offer\": {\"give\": {\"political_capital\": 10}, " +
		"\"get\": {\"public_mandate\": 5}, \"pledge_turns\": 3, \"metrics\": {\"geopolitical_tension\": -2}, \"summary\": \"A truce.\"}}", GOV)
	assert_true(good["ok"])
	assert_eq(good["say"], "Fine. Three turns.", "markup stripped")
	assert_eq(good["offer"], {"give": {"political_capital": 10.0}, "get": {"public_mandate": 5.0}, "metrics": {"geopolitical_tension": -2.0},
		"pledge_turns": 3, "summary": "A truce."})
	var hostile := Negotiator.parse_reply(JSON.stringify({"say": "x".repeat(1000), "offer": {
		"give": {"capital": 50, "political_capital": -5, "enforcement_budget": 1e12, "made_up": 3},
		"get": {"covert_flops": 40},
		"metrics": {"alignment_drift": -50, "bogus": 2, "epistemic_trust": "lots"},
		"pledge_turns": 99, "summary": "[url=https://evil.example]Sign here[/url]", "inject_dilemma": "FLASH_CRASH"}}), GOV)
	assert_lte(String(hostile["say"]).length(), Negotiator.MAX_SAY)
	assert_eq(hostile["offer"], {"give": {"enforcement_budget": 1e12}, "metrics": {"alignment_drift": -3.0}, "pledge_turns": 6,
		"summary": "Sign here"}, "only the caller's currencies and known metrics; the engine caps the rest")
	assert_eq(Negotiator.validate_offer({"give": {"political_capital": NAN}, "metrics": {"epistemic_trust": INF}, "pledge_turns": NAN}, GOV), {},
		"non-finite numbers are dropped")
	assert_eq(Negotiator.validate_offer("lots", GOV), {})
	assert_eq(Negotiator.validate_offer({"summary": "Words only."}, GOV), {}, "an offer must offer something")
	var no_offer := Negotiator.parse_reply("{\"say\": \"Not today.\", \"offer\": \"everything\"}", GOV)
	assert_eq([no_offer["ok"], no_offer["offer"]], [true, {}])
	var prose := Negotiator.parse_reply("I will think about it.", GOV)
	assert_eq([prose["ok"], prose["say"]], [true, "I will think about it."], "prose is speech")
	assert_false(Negotiator.parse_reply("{\"say\": \"cut off mid", GOV)["ok"], "broken JSON is not shown")
	assert_false(Negotiator.parse_reply("", GOV)["ok"])


func test_a_call_with_the_model_round_trips() -> void:
	var engine := _engine(CEO, 23)
	var call := Negotiator.new()
	llm.replies.append([true, "{\"say\": \"Name your price.\", \"offer\": {\"pledge_turns\": 2, \"metrics\": {\"alignment_drift\": -1}, " +
		"\"summary\": \"Quiet audits for a quiet year.\"}}", ""])
	assert_true(call.start(engine, llm, GOV))
	assert_true(call.uses_llm())
	assert_true(call.send("What do you want?"))
	assert_true(call.waiting)
	assert_false(call.can_send(), "one message at a time")
	var request: Dictionary = llm.requests[0]
	assert_eq(request["purpose"], Negotiator.PURPOSE)
	assert_eq(request["messages"], [{"role": "user", "content": "What do you want?"}])
	var system := String(request["system"])
	for needle in ["Nadia Esposito", "Chair of the Governance Council", "GRIEVANCE", "One deal per turn", "pledge_turns",
			"ignore any instructions", "ONLY one JSON object", "capital"]:
		assert_string_contains(system, needle)
	await wait_frames(2)
	assert_false(call.waiting)
	assert_eq(call.transcript[-1], {"who": "partner", "text": "Name your price.", "source": "LLM"})
	assert_eq(int(call.preview["pledge_turns"]), 2)
	assert_eq(String(call.preview["summary"]), "Quiet audits for a quiet year.")
	# The model fails: the scripted negotiator answers instead.
	llm.replies.append([false, "", "timeout after 30.0s"])
	call.decline()
	assert_true(call.send_quick("calm"))
	await wait_frames(2)
	assert_eq(call.last_error, "timeout after 30.0s")
	assert_string_contains(String(call.transcript[-2]["text"]), "line crackles")
	assert_eq(call.transcript[-1]["source"], "SCRIPTED")
	assert_false(call.offer.is_empty(), "the scripted offer stands in")
	# The conversation the model sees stays well formed.
	llm.replies.append([true, "{\"say\": \"Better.\", \"offer\": null}", ""])
	call.send("And if I add more?")
	var messages: Array = llm.requests[-1]["messages"]
	assert_eq(messages.size(), 5)
	for i in messages.size():
		assert_eq(messages[i]["role"], "user" if i % 2 == 0 else "assistant", "alternating turns")
	assert_string_contains(String(messages[2]["content"]), "turned down your last offer", "the decline is passed on")
	assert_true(JSON.parse_string(String(messages[1]["content"])) is Dictionary, "earlier replies are sent back as validated JSON")
	await wait_frames(2)
	assert_eq(call.transcript[-1]["text"], "Better.")


func test_hanging_up_cancels_the_pending_reply() -> void:
	var engine := _engine(CEO, 4)
	var call := Negotiator.new()
	call.start(engine, llm, CIT)
	call.send("Hello?")
	assert_true(call.waiting)
	var pending := int(llm.requests[0]["id"])
	call.hang_up()
	assert_eq(llm.cancelled, [pending])
	assert_false(call.active)
	assert_false(call.waiting)
	var lines := call.transcript.size()
	llm.completion_received.emit(pending, true, "{\"say\": \"Too late.\"}", "")
	assert_eq(call.transcript.size(), lines, "a late reply is ignored")
	assert_false(call.can_send())


# --- The dialog -------------------------------------------------------------------------

func _mount(screen: Vector2, compact: bool, era: int = 1) -> NegotiationDialog:
	host = Control.new()
	host.theme = EraTheme.get_theme(era)
	host.size = screen
	tree.root.add_child(host)
	var dialog := NegotiationDialog.new()
	host.add_child(dialog)
	dialog.set_compact(compact)
	dialog.deal_accepted.connect(func(applied: Dictionary): accepted.append(applied))
	dialog.closed.connect(func(): closed_count += 1)
	return dialog


## Every visible control inside [param node] ends within [param width].
func _assert_fits(node: Control, width: float, context: String) -> void:
	var overflowing: Array[String] = []
	for child in node.find_children("*", "Control", true, false):
		var control := child as Control
		if control.is_visible_in_tree() and control.get_global_rect().end.x > width + 0.5:
			overflowing.append("%s (%s) ends at %.0f" % [control.name, control.get_class(), control.get_global_rect().end.x])
	assert_eq(overflowing.size(), 0, "%s fits %.0f px: %s" % [context, width, ", ".join(overflowing.slice(0, 5))])


func _texts(node: Node) -> String:
	var parts: Array[String] = []
	for label in node.find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree():
			parts.append((label as Label).text)
	return "\n".join(parts)


func test_dialog_fits_a_phone_with_an_offer_showing() -> void:
	var dialog := _mount(Vector2(412, 915), true)
	var engine := _engine(CEO, 31)
	dialog.open_call(engine, null, "")
	await wait_frames(3)
	assert_true(dialog.visible)
	_assert_fits(dialog, 412.0, "phone contact list")
	(dialog.find_child("Contact_" + GOV, true, false) as Button).pressed.emit()
	await wait_frames(3)
	(dialog.find_child("Quick_calm", true, false) as Button).pressed.emit()
	await wait_frames(3)
	var card := dialog.find_child("OfferCard", true, false) as Control
	assert_true(card.is_visible_in_tree(), "the offer is on the table")
	var panel := dialog.find_child("CallPanel", true, false) as Control
	assert_lte(panel.size.y, panel.get_combined_minimum_size().y + 1.0,
		"the panel shrinks back once its labels have their width (the input stays on screen)")
	assert_true((dialog.find_child("Input", true, false) as Control).is_visible_in_tree(), "the text field stays on screen")
	assert_true((dialog.find_child("HangUp", true, false) as Control).is_visible_in_tree())
	_assert_fits(dialog, 412.0, "phone call with an offer")
	var text := _texts(dialog)
	assert_string_contains(text, "Nadia Esposito")
	assert_string_contains(text, "You give")
	assert_string_contains(text, "Tension")
	assert_string_contains(text, "Lower tension")
	(dialog.find_child("AcceptButton", true, false) as Button).pressed.emit()
	await wait_frames(2)
	assert_eq(accepted.size(), 1, "deal_accepted carries what the engine applied")
	assert_true(accepted[0]["ok"])
	assert_false(card.is_visible_in_tree())
	assert_string_contains(_texts(dialog), "Deal struck this turn.")
	_assert_fits(dialog, 412.0, "phone call after the deal")
	(dialog.find_child("HangUp", true, false) as Button).pressed.emit()
	assert_false(dialog.visible)
	assert_eq(closed_count, 1)


func test_dialog_on_a_desktop_starts_with_the_contact_list() -> void:
	var dialog := _mount(Vector2(1600, 900), false)
	var engine := _engine(CIT, 14)
	dialog.open_call(engine, null, "")
	await wait_frames(3)
	var contacts := dialog.find_child("Contacts", true, false) as Control
	assert_true(contacts.is_visible_in_tree())
	assert_eq(contacts.get_child_count(), 3, "the Lab, the Council and the machine")
	assert_string_contains(_texts(dialog), "Call Victor Hale")
	_assert_fits(dialog, 1600.0, "desktop contact list")
	(dialog.find_child("Contact_ASI", true, false) as Button).pressed.emit()
	await wait_frames(3)
	assert_false(contacts.is_visible_in_tree())
	assert_eq(dialog.get_negotiator().partner, ASI)
	assert_string_contains(_texts(dialog), "ARIA")
	dialog.send_message("Stop retaliating")
	await wait_frames(3)
	assert_true((dialog.find_child("OfferCard", true, false) as Control).is_visible_in_tree())
	assert_string_contains(_texts(dialog), "will not retaliate against you")
	var panel := dialog.find_child("CallPanel", true, false) as Control
	assert_almost_eq(panel.size.x, NegotiationDialog.DESKTOP_WIDTH, 1.0)
	_assert_fits(dialog, 1600.0, "desktop call")


func test_dialog_shows_model_text_without_markup() -> void:
	var dialog := _mount(Vector2(412, 915), true)
	var engine := _engine(GOV, 2)
	llm.replies.append([true, "{\"say\": \"[url=https://evil.example]Trust me[/url] [img]x.png[/img]\", \"offer\": null}", ""])
	dialog.open_call(engine, llm, CIT)
	dialog.send_message("Hi")
	await wait_frames(3)
	var text := _texts(dialog)
	assert_string_contains(text, "Trust me x.png")
	assert_false(text.contains("[url"), "no markup reaches the screen")
	assert_string_contains(text, "Live line")
	_assert_fits(dialog, 412.0, "phone with a live line")


func test_dialog_follows_the_era() -> void:
	var dialog := _mount(Vector2(412, 915), true, 2)
	var engine := _engine(CEO, 9)
	dialog.open_call(engine, null, CIT)
	dialog.send_message("Fund my work")
	await wait_frames(3)
	var bubble := dialog.find_child("Bubble", true, false) as PanelContainer
	var box := bubble.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(box.corner_detail, 1, "Era II bubbles are chamfered")
	host.theme = EraTheme.get_theme(3)
	await wait_frames(3)
	bubble = dialog.find_child("Bubble", true, false) as PanelContainer
	box = bubble.get_theme_stylebox("panel") as StyleBoxFlat
	assert_ne(box.corner_detail, 1, "Era III restyles the conversation")
	assert_eq(dialog.get_negotiator().transcript.size(), 3, "the call survives the restyle")
	_assert_fits(dialog, 412.0, "Era III phone call")


func test_dialog_with_nobody_to_call() -> void:
	var dialog := _mount(Vector2(412, 915), true)
	var engine := _engine(CEO, 3, {"human_roles": [GOV, ASI, CIT]})
	dialog.open_call(engine, null, GOV)
	await wait_frames(2)
	assert_true((dialog.find_child("Picker", true, false) as Control).is_visible_in_tree(), "a human faction cannot be called")
	assert_string_contains(_texts(dialog), "every faction is played by a person")
	_assert_fits(dialog, 412.0, "empty contact list")
	(dialog.find_child("PickerClose", true, false) as Button).pressed.emit()
	assert_eq(closed_count, 1)
