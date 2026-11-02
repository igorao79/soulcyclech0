class_name SoulcycleAsciiHud
extends Control

const DIALOGUE_COLUMNS := 68

var font: Font
var font_size := 14
var cell := Vector2i(8, 16)
var grid := Vector2i(160, 45)

var hint_text := "WASD ходить   E действие   1/2 персонаж   ESC меню"
var title_alpha := 1.0
var tags: Array[Dictionary] = []
var dialogue_speaker := ""
var dialogue_color := Color.WHITE
var dialogue_text := ""
var dialogue_visible_chars := 0
var notice_text := ""
var notice_alpha := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	for tag in tags:
		_text_centered(tag["col"], tag["row"], tag["text"], tag["color"], true, tag["shift"])

	_text_centered(grid.x / 2, grid.y - 2, hint_text, Color(0.60, 0.66, 0.78, 0.85), true)

	if title_alpha > 0.0:
		var title_color := Color(0.88, 0.92, 1.0, title_alpha)
		_text_centered(grid.x / 2, 3, "S O U L C Y C L E", title_color, true)
		_text_centered(grid.x / 2, 4, "ночь, нарисованная символами", Color(0.56, 0.66, 0.84, title_alpha), true)

	if notice_alpha > 0.0:
		var notice_color := Color(0.92, 0.34, 0.40, notice_alpha)
		_text_centered(grid.x / 2, grid.y / 2 - 8, notice_text, notice_color, true)

	if dialogue_speaker != "":
		_draw_dialogue()


func _draw_dialogue() -> void:
	var width := mini(DIALOGUE_COLUMNS, grid.x - 6)
	var lines := _wrap(dialogue_text, width - 6)
	var height := lines.size() + 4
	var left := (grid.x - width) / 2
	var top := grid.y - height - 4
	var frame := Color(0.55, 0.60, 0.72)

	draw_rect(
		Rect2(Vector2(left * cell.x, top * cell.y), Vector2(width * cell.x, height * cell.y)),
		Color(0.012, 0.014, 0.026, 0.96)
	)
	var label := "─ %s " % dialogue_speaker
	_text(left, top, "┌", frame)
	_text(left + 1, top, label, dialogue_color)
	var rule_start := left + 1 + label.length()
	_text(rule_start, top, "─".repeat(left + width - 1 - rule_start) + "┐", frame)

	for row in range(1, height - 1):
		_text(left, top + row, "│", frame)
		_text(left + width - 1, top + row, "│", frame)

	var remaining := dialogue_visible_chars
	for index in range(lines.size()):
		var line: String = lines[index]
		_text(left + 3, top + 1 + index, line.substr(0, maxi(remaining, 0)), Color(0.88, 0.90, 0.95))
		remaining -= line.length() + 1

	var prompt := "[E]"
	if remaining >= 0:
		_text(left + width - prompt.length() - 3, top + height - 2, prompt, Color(0.94, 0.77, 0.42))
	_text(left, top + height - 1, "└" + "─".repeat(width - 2) + "┘", frame)


func _wrap(text: String, width: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	for word in text.split(" "):
		if line.length() + word.length() + 1 > width and line != "":
			lines.append(line)
			line = word
		else:
			line = word if line == "" else "%s %s" % [line, word]
	lines.append(line)
	return lines


func _text_centered(col: int, row: int, text: String, color: Color, backed: bool, shift := Vector2.ZERO) -> void:
	var start := col - text.length() / 2
	if backed:
		draw_rect(
			Rect2(
				Vector2((start - 1) * cell.x, row * cell.y) + shift,
				Vector2((text.length() + 2) * cell.x, cell.y)
			),
			Color(0.01, 0.012, 0.024, minf(color.a, 0.82))
		)
	_text(start, row, text, color, shift)


# Каждый знак встаёт ровно в ячейку той же сетки, что и мир под ним.
func _text(col: int, row: int, text: String, color: Color, shift := Vector2.ZERO) -> void:
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var baseline := (cell.y + ascent - descent) * 0.5
	for index in range(text.length()):
		var code := text.unicode_at(index)
		var advance := font.get_char_size(code, font_size).x
		var origin := Vector2((col + index) * cell.x + (cell.x - advance) * 0.5, row * cell.y + baseline) + shift
		font.draw_char(get_canvas_item(), origin.floor(), code, font_size, color)
