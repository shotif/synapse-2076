class_name FactionRegistry
extends RefCounted
## Factory and static catalog lookup for the four factions.


static func create(faction_id: String) -> ActorBase:
	match faction_id:
		SimConstants.CEO:
			return CeoFaction.new()
		SimConstants.GOVERNANCE:
			return GovernanceFaction.new()
		SimConstants.ASI:
			return AsiFaction.new()
		SimConstants.CITIZEN:
			return CitizenFaction.new()
	push_error("FactionRegistry: unknown faction '%s'" % faction_id)
	return null


## Directive catalog for a faction without instantiating it.
static func catalog_for(faction_id: String) -> Dictionary:
	match faction_id:
		SimConstants.CEO:
			return CeoFaction.ACTIONS
		SimConstants.GOVERNANCE:
			return GovernanceFaction.ACTIONS
		SimConstants.ASI:
			return AsiFaction.ACTIONS
		SimConstants.CITIZEN:
			return CitizenFaction.ACTIONS
	return {}


static func resource_info_for(faction_id: String) -> Dictionary:
	match faction_id:
		SimConstants.CEO:
			return CeoFaction.RESOURCE_INFO
		SimConstants.GOVERNANCE:
			return GovernanceFaction.RESOURCE_INFO
		SimConstants.ASI:
			return AsiFaction.RESOURCE_INFO
		SimConstants.CITIZEN:
			return CitizenFaction.RESOURCE_INFO
	return {}
