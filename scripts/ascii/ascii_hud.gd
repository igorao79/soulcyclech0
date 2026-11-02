class_name SoulcycleAsciiHud
extends Control


var font: Font
var font_size := 14
var cell := Vector2i(8, 16)
var grid := Vector2i(160, 45)

var tags: Array[Dictionary] = []
var dialogue_speaker := ""
var dialogue_color := Color.WHITE
var dialogue_text := ""
var dialogue_visible_chars := 0
var notice_text := ""
var notice_alpha := 0.0
var _serif: Font
var _clock := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_clock += delta


func _draw() -> void:
	for tag in tags:
		_text_centered(tag["col"], tag["row"], tag["text"], tag["color"], true, tag["shift"])

	if notice_alpha > 0.0:
		var notice_color := Color(0.92, 0.34, 0.40, notice_alpha)
		_text_centered(grid.x / 2, grid.y / 2 - 8, notice_text, notice_color, true)

	if dialogue_speaker != "":
		_draw_dialogue()


func _draw_dialogue() -> void:
	if _serif == null:
		_serif = SoulcycleUiStyle.serif(600.0)
	SoulcycleDialogueView.draw(
		self, font, _serif, dialogue_speaker, Color(0.86, 0.89, 0.98), dialogue_text, dialogue_visible_chars, _clock
	)


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
