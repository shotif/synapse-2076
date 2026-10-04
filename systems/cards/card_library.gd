class_name CardLibrary
extends RefCounted
## Every crisis template the deck can deal: the core set (DilemmaDeck.CARDS),
## the era decks in systems/cards/ and the injection families
## (InjectionCards). Era cards carry their own story copy ("copy", in the
## StoryCopy.CARDS schema), swipe hints ("swipe_hints": [left, right]) and, for
## injection-only cards, the newswire line that announces them
## ("injection_head"). Each era file also lists MEMORIES: what a recurring
## character remembers about the players (see Characters).

static var _all: Array = []
static var _by_id := {}


static func all_cards() -> Array:
	if _all.is_empty():
		_all = DilemmaDeck.CARDS + Era1Cards.CARDS + Era2Cards.CARDS + Era3Cards.CARDS + InjectionCards.CARDS
		_by_id = {}
		for template in _all:
			_by_id[String(template["id"])] = template
	return _all


static func get_template(card_id: String) -> Dictionary:
	all_cards()
	return _by_id.get(card_id, {})


## Memory lines from every era file: [{character, text, flag | min | max}].
static func memories() -> Array:
	return Era1Cards.MEMORIES + Era2Cards.MEMORIES + Era3Cards.MEMORIES
