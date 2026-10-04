extends "res://tests/framework/test_case.gd"
## The shareable ending: ShareCard's one-line text, its front page of The
## Ledger, rendering (an empty image under the headless dummy renderer) and
## delivery to a file.

var engine: SimulationEngine
var result := {}
var share_dir := ""


func before_all() -> void:
	share_dir = "user://test_output/shares_%d" % OS.get_process_id()
	engine = SimulationEngine.new()
	engine.start_campaign(SimConstants.CEO, 2076, {"autoplay": true, "human_roles": [SimConstants.CITIZEN],
		"scenario": "chip_war", "difficulty": Difficulty.HARD, "total_turns": 50})
	result = engine.run_headless()


func after_all() -> void:
	var dir := DirAccess.open(share_dir)
	if dir != null:
		for file_name in dir.get_files():
			dir.remove(file_name)
		DirAccess.remove_absolute(share_dir)


func _eden(role: String = SimConstants.CEO) -> Dictionary:
	return {"outcome": VictoryMatrix.get_outcome(VictoryMatrix.SYNTHETIC_EDEN), "player_role": role,
		"verdict": {"verdict": "VICTORY", "score": 72.4}, "seed": 2076}


func _labels(root_control: Node) -> Array:
	var out: Array = []
	for label in root_control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func test_one_line_to_share() -> void:
	assert_eq(ShareCard.share_text(_eden(), {"daily": "2026-10-04"}),
		"SYNAPSE-2076 · Daily 2026-10-04 · Frontier Lab · End-state 3: Synthetic Eden · VICTORY 72 — https://shotif.github.io/synapse-2076/")
	assert_eq(ShareCard.share_text(_eden(SimConstants.ASI)),
		"SYNAPSE-2076 · Emergent ASI · End-state 3: Synthetic Eden · VICTORY 72 — https://shotif.github.io/synapse-2076/")
	var text := ShareCard.share_text(result, {"mode": CampaignModes.QUARTER})
	assert_true(text.begins_with("SYNAPSE-2076 · "))
	assert_string_contains(text, "End-state %d: %s" % [int(result["outcome"]["number"]), result["outcome"]["name"]])
	assert_string_contains(text, "%s %d" % [result["verdict"]["verdict"], int(round(float(result["verdict"]["score"])))])
	assert_true(text.ends_with(" — " + ShareCard.SITE))
	assert_eq(ShareCard.file_name(_eden(), {"daily": "2026-10-04"}), "synapse-2076-synthetic-eden-daily-2026-10-04.png")
	assert_eq(ShareCard.file_name(_eden()), "synapse-2076-synthetic-eden-seed-2076.png")


func test_the_page_carries_the_ending() -> void:
	var extra := {"daily": "2026-10-04", "mode": CampaignModes.QUARTER}
	var page := ShareCard.build_page(result, extra)
	assert_eq(page.custom_minimum_size, Vector2(ShareCard.SIZE))
	var texts := _labels(page)
	assert_has(texts, "The Ledger")
	var outcome_id := String(result["outcome"]["id"])
	assert_has(texts, StoryCopy.capitalize_first(String(StoryCopy.OUTCOME_HEADS[outcome_id])), "the end-state is the headline")
	assert_has(texts, String(result["verdict"]["verdict"]))
	assert_has(texts, "Directive score %d of 100" % int(round(float(result["verdict"]["score"]))))
	assert_has(texts, UiFormat.role_title(String(result["player_role"])))
	for badge in ["DAILY 2026-10-04", "THE CHIP WAR", "HARD", "QUARTER CENTURY", "2 PLAYERS"]:
		assert_has(texts, badge)
	for key in [WorldState.EPISTEMIC_TRUST, WorldState.ALIGNMENT_DRIFT, WorldState.ALGORITHMIC_AUTONOMY]:
		var stat: Label = page.find_child("Stat_" + key, true, false)
		assert_not_null(stat, key)
		assert_eq(stat.text, str(int(round(float(result["final_values"][key])))))
	assert_string_contains(" ".join(texts), "At the same table: the ", "the other player's verdict")
	page.free()
	var plain := ShareCard.build_page(_eden(), {})
	var plain_texts := _labels(plain)
	assert_does_not_have(plain_texts, "2 PLAYERS")
	assert_eq(plain_texts.filter(func(t: String) -> bool: return t.begins_with("DAILY")).size(), 0, "no daily badge")
	assert_has(plain_texts, "STANDARD")
	plain.free()


func test_render_in_the_tree_and_out_of_it() -> void:
	var card := ShareCard.new()
	tree.root.add_child(card)
	var image: Image = await card.render(result, {"daily": "2026-10-04"})
	assert_not_null(image)
	if DisplayServer.get_name() == "headless":
		assert_true(image.is_empty(), "the dummy renderer draws nothing")
	else:
		assert_eq(image.get_size(), ShareCard.SIZE)
	await wait_frames(2)
	assert_null(card.get_node_or_null("ShareViewport"), "the offscreen viewport is gone")
	card.queue_free()
	var loose := ShareCard.new()
	var none: Image = await loose.render(result)
	assert_true(none.is_empty(), "outside the tree there is nothing to draw with")
	loose.free()


func test_deliver_writes_a_png() -> void:
	var image := Image.create(8, 10, false, Image.FORMAT_RGBA8)
	image.fill(ShareCard.PAPER)
	var path := ShareCard.deliver(image, "my ending?.png", share_dir)
	assert_eq(path, share_dir.path_join("my-ending-.png"))
	assert_true(FileAccess.file_exists(path))
	var saved := Image.load_from_file(path)
	assert_eq(saved.get_size(), Vector2i(8, 10), "a real PNG")
	assert_eq(ShareCard.deliver(image, "", share_dir), share_dir.path_join("synapse-2076.png"))
	assert_eq(ShareCard.deliver(image, "../escape", share_dir), share_dir.path_join("-escape.png"), "stays in its folder")
	assert_eq(ShareCard.deliver(Image.new(), "empty.png", share_dir), "", "nothing to save")
	assert_eq(ShareCard.deliver(null, "none.png", share_dir), "")
