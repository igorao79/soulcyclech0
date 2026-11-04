extends RefCounted

# Бог в видении: каждый раз, когда садишься читать книгу и остаёшься с ним, у него новый разговор.
# Что он скажет, зависит от того, читают ли впервые, как давно читали и до какой главы дошли.
# Он помнит несколько последних разговоров и не повторяется. Счётчик лежит отдельно от
# прогресса, в user://god.cfg: сброс прогресса не заставит бога знакомиться заново.

const PATH := "user://god.cfg"
# Дольше трёх дней не приходили — значит, успели забыть.
const LONG_ABSENCE := 3 * 24 * 60 * 60
const REMEMBERED := 4

const FIRST_EVER: Array[String] = [
	"Не вставай. Ты всё равно сидишь.",
	"Это книга. Она про тебя, но ты пока на первой странице.",
]
const LONG: Array = [
	["Долго тебя не было.", "Я успел дописать том. И потерял."],
	["О. Я думал, ты больше не придёшь.", "Убрал твой стул. Вернул, как видишь."],
	["Пока тебя не было, ничего не случилось.", "Совсем ничего. Я проверял."],
]
const FIRST_CHAPTER: Array = [
	["Опять за книгу? Там ничего не поменялось."],
	["Страницы сами не допишутся.", "Хотя кто их знает."],
	["Ты читаешь медленно. Я засекал."],
	["Звёзды падают по расписанию.", "Почти всегда."],
	["Океан я рисовал с запасом. Не заплывай."],
	["Снова ты.", "Ладно, я рад. Немного."],
]
const SECOND_CHAPTER: Array = [
	["Снова ты. Вторую страницу я вписал сам.", "Почти без ошибок."],
	["Про тот двор в книге ничего нет.", "И не будет."],
	["Упс был один раз.", "Ладно, два."],
	["Дэйл не знает, что ты знаешь.", "Молчи."],
	["Воин спрашивал про тебя.", "Я сказал, что ты вышел."],
	["Цветок на тумбочке не я ставил.", "Честно."],
]


## Разговор для этого чтения; заодно запоминает, что он был.
static func greet(chapter: int) -> Array[Dictionary]:
	var file := ConfigFile.new()
	file.load(PATH)
	var visits := int(file.get_value("god", "visits", 0))
	var now := int(Time.get_unix_time_from_system())
	var since := now - int(file.get_value("god", "last_at", now))
	var recent: PackedStringArray = file.get_value("god", "recent", PackedStringArray())
	var talk := pick(chapter, visits, since, recent, randi())
	recent.append(talk[0])
	if recent.size() > REMEMBERED:
		recent = recent.slice(recent.size() - REMEMBERED)
	file.set_value("god", "visits", visits + 1)
	file.set_value("god", "last_at", now)
	file.set_value("god", "recent", recent)
	file.save(PATH)
	var lines: Array[Dictionary] = []
	for text in talk:
		lines.append({"speaker": &"god", "text": text})
	return lines


## Выбор без побочных эффектов; разговор узнаётся по первой реплике, seed задаёт, какой выпадет.
static func pick(chapter: int, visits: int, since: int, recent: PackedStringArray, seed_value: int) -> Array:
	if visits == 0:
		return FIRST_EVER
	var pool: Array = FIRST_CHAPTER
	if since > LONG_ABSENCE:
		pool = LONG
	elif chapter >= 2:
		pool = SECOND_CHAPTER
	var fresh: Array = []
	for talk in pool:
		if not recent.has(talk[0]):
			fresh.append(talk)
	# Всё в этой кучке уже звучало: тогда хотя бы не самый последний разговор.
	if fresh.is_empty():
		for talk in pool:
			if recent.is_empty() or talk[0] != recent[-1]:
				fresh.append(talk)
	return fresh[posmod(seed_value, fresh.size())]
