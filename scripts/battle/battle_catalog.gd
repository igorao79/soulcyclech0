class_name SoulcycleBattleCatalog
extends RefCounted

const ACTORS := {
	&"nameless": preload("res://data/battle/actors/nameless.tres"),
	&"bell_wraith": preload("res://data/battle/actors/bell_wraith.tres"),
}

const ENCOUNTERS := {
	&"first_wraith": {
		"player": &"nameless",
		"enemy": &"bell_wraith",
	},
}


static func get_actor(actor_id: StringName) -> SoulcycleBattleActor:
	return ACTORS.get(actor_id, ACTORS[&"nameless"]) as SoulcycleBattleActor


static func get_encounter(encounter_id: StringName) -> Dictionary:
	var fallback: Dictionary = ENCOUNTERS[&"first_wraith"] as Dictionary
	return (ENCOUNTERS.get(encounter_id, fallback) as Dictionary).duplicate(true)
