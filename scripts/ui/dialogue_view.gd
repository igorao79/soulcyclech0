class_name SoulcycleDialogueView
extends RefCounted

# Свои скрипты подключены по пути, а не по имени класса: игра, запущенная без редактора,
# не всегда знает новые глобальные классы, и сцена падала при переходе.
const UiStyle := preload("res://scripts/ui/ui_style.gd")

# Реплика внизу экрана без рамки: тень снизу, имя антиквой вразрядку, черта с ромбом,
# текст моноширинной сеткой печатается по буквам, последние две ещё мечутся.
# Когда реплика допечатана, мигает «»» — можно листать дальше.

const SCRAMBLE := "#%&@$*+=-:;!?/\\|<>~^"
const TEXT := Color(0.74, 0.78, 0.90)
const NOISE := Color(0.78, 0.30, 0.36)
const EMBER := Color(1.0, 0.72, 0.42)
const RULE := Color(0.55, 0.58, 0.72)


static func draw(
	canvas: Control, mono: Font, serif: Font, speaker: String, speaker_color: Color,
	text: String, visible_chars: int, time: float
) -> void:
	var size := canvas.get_rect().size
	var scale := size.y / UiStyle.LOGICAL_HEIGHT
	var top := size.y * 0.68
	canvas.draw_polygon(
		PackedVector2Array([Vector2(0, top), Vector2(size.x, top), Vector2(size.x, size.y), Vector2(0, size.y)]),
		PackedColorArray([Color(0, 0, 0.01, 0.0), Color(0, 0, 0.01, 0.0), Color(0, 0, 0.01, 0.9), Color(0, 0, 0.01, 0.9)])
	)
	var block_w := size.x * 0.52
	var left := (size.x - block_w) * 0.5
	var name_size := roundi(17 * scale)
	var name_y := size.y * 0.79
	var x := left
	var tracking := name_size * 0.22
	for i in range(speaker.length()):
		serif.draw_string(canvas.get_canvas_item(), Vector2(x, name_y).floor(), speaker[i], HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, speaker_color)
		x += serif.get_string_size(speaker[i], HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x + tracking
	var name_end := x - tracking
	var rule_y := name_y + name_size * 0.45
	canvas.draw_line(Vector2(left, rule_y), Vector2(name_end, rule_y), Color(RULE, 0.8), 1.0)
	var mid := Vector2(name_end + name_size * 0.4, rule_y)
	var tip := name_size * 0.16
	canvas.draw_colored_polygon(
		PackedVector2Array([mid + Vector2(0, -tip), mid + Vector2(tip, 0), mid + Vector2(0, tip), mid + Vector2(-tip, 0)]),
		EMBER
	)

	var text_size := roundi(12 * scale)
	var advance := mono.get_char_size("M".unicode_at(0), text_size).x
	var columns := maxi(int(block_w / advance), 20)
	var y := name_y + text_size * 2.6
	var remaining := visible_chars
	for row in wrap_text(text, columns):
		var shown := row.substr(0, clampi(remaining, 0, row.length()))
		var cx := left
		for i in range(shown.length()):
			var letter := shown[i]
			var color := TEXT
			if visible_chars < text.length() and i >= shown.length() - 2 and remaining <= row.length():
				letter = SCRAMBLE[(i * 7 + int(time * 24.0)) % SCRAMBLE.length()]
				color = NOISE
			mono.draw_string(canvas.get_canvas_item(), Vector2(cx, y).floor(), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, color)
			cx += advance
		remaining -= row.length() + 1
		y += text_size * 1.7
	if visible_chars >= text.length():
		var pulse := 0.5 + 0.5 * sin(time * 4.0)
		mono.draw_string(
			canvas.get_canvas_item(), Vector2(left + block_w - advance * 2.0, y).floor(), "»",
			HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, Color(EMBER, 0.4 + 0.6 * pulse)
		)


static func wrap_text(text: String, columns: int) -> PackedStringArray:
	var rows := PackedStringArray()
	var row := ""
	for word in text.split(" "):
		if row.length() + word.length() + 1 > columns and row != "":
			rows.append(row)
			row = word
		else:
			row = word if row == "" else row + " " + word
	rows.append(row)
	return rows
