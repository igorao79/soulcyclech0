class_name SoulcycleBattleCatalog
extends RefCounted

enum Phase {
	DAWN,
	ZENITH,
	DUSK,
	MIDNIGHT,
}

const ACTORS := {
	&"nameless": preload("res://data/battle/actors/nameless.tres"),
	&"bell_wraith": preload("res://data/battle/actors/bell_wraith.tres"),
}

# Колесо души: каждое действие поворачивает его на одну фазу вперёд.
const PHASES := [
	{
		"name": "Рассвет",
		"color": Color("#e9a58c"),
		"hint": "Рассвет — время исцеления",
	},
	{
		"name": "Полдень",
		"color": Color("#f1d27b"),
		"hint": "Полдень — клинок в полной силе",
	},
	{
		"name": "Сумерки",
		"color": Color("#aa8ddc"),
		"hint": "Сумерки — время клятв и парирования",
	},
	{
		"name": "Полночь",
		"color": Color("#6fa6dc"),
		"hint": "Полночь — жатва, но эхо бьёт сильнее",
	},
]

# Воспоминания — навыки души. Использованное в своей фазе даёт резонанс,
# отпущенное навсегда исчезает из боя, высвобождая свою силу.
const MEMORIES := {
	&"thrust": {
		"name": "Выпад",
		"phase": Phase.ZENITH,
		"description": "Удар рапирой. Резонанс в Полдень: двойной урон.",
		"release_name": "Солнечный разлом",
		"release_description": "Отпустить: тройной урон сквозь любую защиту.",
	},
	&"vow": {
		"name": "Клятва",
		"phase": Phase.DUSK,
		"description": "Защита −60% урона. Резонанс в Сумерки: полное парирование и контрудар.",
		"release_name": "Нерушимая клятва",
		"release_description": "Отпустить: неуязвимость на два удара врага.",
	},
	&"lullaby": {
		"name": "Колыбельная",
		"phase": Phase.DAWN,
		"description": "Исцеление. Резонанс на Рассвете: сильнее и снимает печати забвения.",
		"release_name": "Последняя колыбельная",
		"release_description": "Отпустить: полное исцеление, колокол затихает.",
	},
	&"harvest": {
		"name": "Жатва",
		"phase": Phase.MIDNIGHT,
		"description": "Урон, половина возвращается жизнью. Резонанс в Полночь: чем ближе смерть, тем сильнее.",
		"release_name": "Полуночная жатва",
		"release_description": "Отпустить: вырвать треть оставшейся жизни врага.",
	},
}

const ENCOUNTERS := {
	&"first_wraith": {
		"player": &"nameless",
		"enemy": &"bell_wraith",
		"memories": [&"thrust", &"vow", &"lullaby", &"harvest"],
		"rebirths": 1,
	},
}


static func get_actor(actor_id: StringName) -> SoulcycleBattleActor:
	return ACTORS.get(actor_id, ACTORS[&"nameless"]) as SoulcycleBattleActor


static func get_encounter(encounter_id: StringName) -> Dictionary:
	var fallback: Dictionary = ENCOUNTERS[&"first_wraith"] as Dictionary
	return (ENCOUNTERS.get(encounter_id, fallback) as Dictionary).duplicate(true)


static func get_memory(memory_id: StringName) -> Dictionary:
	return MEMORIES.get(memory_id, {}) as Dictionary


static func get_phase(phase_index: int) -> Dictionary:
	return PHASES[wrapi(phase_index, 0, PHASES.size())] as Dictionary
