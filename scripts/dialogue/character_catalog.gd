class_name SoulcycleCharacterCatalog
extends RefCounted

const CharacterProfile := preload("res://scripts/dialogue/character_profile.gd")

const PROFILES := {
	&"nameless": preload("res://data/dialogue/characters/nameless.tres"),
	&"wanderer": preload("res://data/dialogue/characters/wanderer.tres"),
	&"keeper": preload("res://data/dialogue/characters/keeper.tres"),
}

const PLAYABLE_ORDER: Array[StringName] = [
	&"nameless",
	&"wanderer",
]


static func get_profile(character_id: StringName) -> CharacterProfile:
	return PROFILES.get(character_id, PROFILES[&"nameless"]) as CharacterProfile


static func get_playable_profile(index: int) -> CharacterProfile:
	if index < 0 or index >= PLAYABLE_ORDER.size():
		return get_profile(&"nameless")
	return get_profile(PLAYABLE_ORDER[index])


static func get_playable_count() -> int:
	return PLAYABLE_ORDER.size()
