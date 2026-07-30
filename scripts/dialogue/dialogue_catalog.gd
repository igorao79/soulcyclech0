class_name SoulcycleDialogueCatalog
extends RefCounted

const THEMES := {
	&"crimson": preload("res://data/dialogue/themes/crimson.tres"),
	&"frost": preload("res://data/dialogue/themes/frost.tres"),
	&"amber": preload("res://data/dialogue/themes/amber.tres"),
}

const SEQUENCES := {
	&"keeper_first_meeting": [
		{
			"character": &"keeper",
			"text": "Ты снова проснулся у колокола. Значит, цикл ещё не разомкнут.",
		},
		{
			"character": &"nameless",
			"text": "Я не помню, как сюда попал… Только лестницу, которой не было.",
		},
		{
			"character": &"keeper",
			"text": "В этом саду дороги помнят тебя лучше, чем ты сам. Найди чёрный цветок — и не верь его голосу.",
		},
		{
			"character": &"keeper",
			"text": "А теперь иди. Когда колокол прозвонит трижды, эта ночь начнётся сначала.",
		},
	],
}


static func get_theme(theme_id: StringName) -> SoulcycleDialogueTheme:
	return THEMES.get(theme_id, THEMES[&"crimson"]) as SoulcycleDialogueTheme


static func get_sequence(sequence_id: StringName) -> Array:
	var source: Array = SEQUENCES.get(sequence_id, []) as Array
	return source.duplicate(true)
