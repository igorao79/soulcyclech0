extends RefCounted

# Сохранения — тома книги «Цикл душ». Записываются сами, когда герой доходит до чекпоинта
# (checkpoint): выбирать ничего не нужно. Чекпоинтов в главах пока нет, поэтому и сохранений нет;
# главный экран показывает их в «Сохранениях».
# Тома лежат в user://tomes.cfg, по секции на том: глава, её название и место.

const PATH := "user://tomes.cfg"
const TOMES := 3
const NUMERALS: Array[String] = ["I", "II", "III"]

## Откуда продолжить, когда главу открывают из «Сохранений»: пусто — с начала.
static var resume_place := &""


static func _file() -> ConfigFile:
	var file := ConfigFile.new()
	file.load(PATH)
	return file


## Записанный том или пустой словарь.
static func read(tome: int) -> Dictionary:
	var file := _file()
	var section := "tome_%d" % tome
	if not file.has_section(section):
		return {}
	return {
		"chapter": int(file.get_value(section, "chapter", 1)),
		"title": String(file.get_value(section, "title", "")),
		"place": StringName(file.get_value(section, "place", &"library")),
		"place_name": String(file.get_value(section, "place_name", "")),
		"saved_at": int(file.get_value(section, "saved_at", 0)),
	}


static func write(tome: int, chapter: int, title: String, place: StringName, place_name: String) -> void:
	var file := _file()
	var section := "tome_%d" % tome
	file.set_value(section, "chapter", chapter)
	file.set_value(section, "title", title)
	file.set_value(section, "place", place)
	file.set_value(section, "place_name", place_name)
	file.set_value(section, "saved_at", int(Time.get_unix_time_from_system()))
	file.save(PATH)


## Чекпоинт: путь сам вписывается в том текущего прохождения (пока он один — первый).
static func checkpoint(chapter: int, title: String, place: StringName, place_name: String) -> void:
	write(0, chapter, title, place, place_name)


static func has_any() -> bool:
	for tome in range(TOMES):
		if not read(tome).is_empty():
			return true
	return false


## Подпись тома в меню: «Том I · Звездопад, библиотека» или «Том II · чистые страницы».
static func label(tome: int) -> String:
	var data := read(tome)
	if data.is_empty():
		return "Том %s · чистые страницы" % NUMERALS[tome]
	return "Том %s · %s, %s" % [NUMERALS[tome], data["title"], data["place_name"]]
