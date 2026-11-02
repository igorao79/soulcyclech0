class_name SoulcycleAsciiMenu
extends Control

# Меню из символов: те же моноширинные знаки, что и мир. Рамка ┌─┐, ползунки [███░░░],
# переключатели [x]. Пункты расшифровываются из шума при появлении, выбранный тлеет.
# Управление: стрелки или WASD, Enter / Space / E, Escape; мышь — наведение и щелчок.

signal activated(id: StringName)
signal cancelled

const BASE_SIZE := 11.0
const SCRAMBLE := "#%&@$*+=-:;!?/\\|<>~^"
const DECODE_TIME := 0.55
const BAR_CELLS := 12
const LABEL_COLUMNS := 22

const TEXT := Color(0.66, 0.70, 0.82)
const DIM := Color(0.40, 0.44, 0.56)
const EMBER := Color(1.0, 0.72, 0.42)
const BONE := Color(0.94, 0.90, 0.84)
const FRAME := Color(0.58, 0.16, 0.22)
const NOISE := Color(0.78, 0.22, 0.30)

## Заголовок в верхней кромке рамки. Пусто — меню без рамки.
var heading := ""
var columns := 40
## Строк на пункт: 2 — с просветом, 1 — плотно.
var spacing := 1
## Центр меню в долях своего прямоугольника.
var center := Vector2(0.5, 0.5)
var entries: Array[Dictionary] = []
var selected := 0
var settings: Node

var _font: Font
var _font_size := 16
var _cell := Vector2i(10, 20)
var _time := 0.0
var _opened_at := 0.0
var _flash_at := -10.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = SoulcycleAsciiFontAtlas.create_font()
	resized.connect(_fit)
	_fit()


## Меню настроек: громкость по шинам, полный экран и вертикальная синхронизация.
static func make_settings(game_settings: Node) -> SoulcycleAsciiMenu:
	var menu := SoulcycleAsciiMenu.new()
	menu.heading = "НАСТРОЙКИ"
	menu.columns = 50
	menu.spacing = 2
	menu.settings = game_settings
	menu.add_slider(&"master_volume", "общая громкость")
	menu.add_slider(&"music_volume", "музыка")
	menu.add_slider(&"sfx_volume", "звуки")
	menu.add_toggle(&"fullscreen", "полный экран")
	menu.add_toggle(&"vsync", "вертикальная синхр.")
	menu.add_button(&"back", "назад")
	return menu


func add_button(id: StringName, label: String) -> void:
	entries.append({"id": id, "label": label, "kind": &"button"})


func add_slider(option: StringName, label: String) -> void:
	entries.append({"id": option, "label": label, "kind": &"slider"})


func add_toggle(option: StringName, label: String) -> void:
	entries.append({"id": option, "label": label, "kind": &"toggle"})


func open() -> void:
	show()
	selected = 0
	_opened_at = _time
	_flash_at = _time
	queue_redraw()


## Прямоугольник рамки в координатах этого Control: под ним притушивают фон.
func box_rect() -> Rect2:
	var origin := _origin()
	var size := _box_size()
	return Rect2(Vector2(origin * _cell), Vector2(size * _cell))


func _process(delta: float) -> void:
	_time += delta
	if visible:
		queue_redraw()


func _fit() -> void:
	var scale := maxf(get_viewport_rect().size.y / SoulcycleUiStyle.LOGICAL_HEIGHT, 0.5)
	_font_size = maxi(roundi(BASE_SIZE * scale), 8)
	var advance := _font.get_char_size("M".unicode_at(0), _font_size).x
	_cell = Vector2i(ceili(advance), roundi(_font_size * 1.35))


func _box_size() -> Vector2i:
	var rows := entries.size() * spacing
	if heading != "":
		rows += 4
	return Vector2i(columns, rows)


func _origin() -> Vector2i:
	var size := _box_size()
	var middle := get_rect().size * center / Vector2(_cell)
	return Vector2i(floori(middle.x - size.x * 0.5), floori(middle.y - size.y * 0.5))


func _entry_row(index: int) -> int:
	return _origin().y + (2 if heading != "" else 0) + index * spacing


func _draw() -> void:
	var origin := _origin()
	var size := _box_size()
	if heading != "":
		draw_rect(Rect2(Vector2(origin * _cell), Vector2(size * _cell)), Color(0.008, 0.008, 0.02, 0.93))
		_draw_frame(origin, size)

	for index in range(entries.size()):
		var row := _entry_row(index)
		var text := _entry_text(entries[index])
		var is_selected := index == selected
		var marker := "» " if is_selected else "  "
		var line := marker + text
		var start := origin.x + (3 if heading != "" else (size.x - line.length()) / 2)
		_draw_line(start, row, line, index, is_selected)


func _draw_frame(origin: Vector2i, size: Vector2i) -> void:
	var right := origin.x + size.x - 1
	var bottom := origin.y + size.y - 1
	var title := _spaced(heading)
	var lead := (size.x - title.length() - 4) / 2
	_draw_text(origin.x, origin.y, "┌" + "─".repeat(lead - 1) + "┤ ", FRAME)
	_draw_text(origin.x + lead + 2, origin.y, title, BONE)
	var tail := size.x - lead - 2 - title.length()
	_draw_text(origin.x + lead + 2 + title.length(), origin.y, " ├" + "─".repeat(tail - 3) + "┐", FRAME)
	for row in range(origin.y + 1, bottom):
		_draw_text(origin.x, row, "│", FRAME)
		_draw_text(right, row, "│", FRAME)
	_draw_text(origin.x, bottom, "└" + "─".repeat(size.x - 2) + "┘", FRAME)


# Строка пункта: при появлении знаки встают на место слева направо, выбранный пункт
# вспыхивает при переходе и тлеет, а в остальных изредка проскакивает чужой знак.
func _draw_line(column: int, row: int, line: String, index: int, is_selected: bool) -> void:
	var since_open := _time - _opened_at
	var since_flash := _time - _flash_at
	for i in range(line.length()):
		var letter := line[i]
		var color := TEXT
		if is_selected:
			var ember := 0.82 + 0.18 * sin(_time * 5.0 + i * 0.7) * sin(_time * 2.3 + i * 1.9)
			color = Color(EMBER.r * ember, EMBER.g * ember, EMBER.b * ember)
		var settle := DECODE_TIME * float(i) / maxf(line.length(), 1.0) + index * 0.07
		var scrambled := since_open < settle
		if is_selected and since_flash < 0.22 and _hash(i, int(_time * 30.0)) < 0.45:
			scrambled = true
		if not is_selected and _hash(i + index * 31, int(_time * 24.0)) > 0.9993:
			scrambled = true
		if scrambled and letter != " ":
			letter = SCRAMBLE[int(_hash(i * 7 + index, int(_time * 24.0)) * SCRAMBLE.length()) % SCRAMBLE.length()]
			color = NOISE
		_draw_text(column + i, row, letter, color)


func _entry_text(entry: Dictionary) -> String:
	var label: String = entry["label"]
	match entry["kind"]:
		&"slider":
			var value := float(settings.get(entry["id"])) if settings != null else 0.0
			var filled := roundi(value * BAR_CELLS)
			return "%s[%s%s] %3d%%" % [
				label.rpad(LABEL_COLUMNS), "█".repeat(filled), "░".repeat(BAR_CELLS - filled), roundi(value * 100.0)
			]
		&"toggle":
			var on := bool(settings.get(entry["id"])) if settings != null else false
			return "%s[%s]" % [label.rpad(LABEL_COLUMNS), "x" if on else " "]
	return label


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	var key := event as InputEventKey
	if key != null and key.pressed:
		match key.physical_keycode:
			KEY_UP, KEY_W:
				_move(-1)
			KEY_DOWN, KEY_S:
				_move(1)
			KEY_LEFT, KEY_A:
				_adjust(-1)
			KEY_RIGHT, KEY_D:
				_adjust(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E:
				if not key.echo:
					_activate()
			KEY_ESCAPE:
				if not key.echo:
					cancelled.emit()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_up"):
		_move(-1)
	elif event.is_action_pressed("ui_down"):
		_move(1)
	elif event.is_action_pressed("ui_left"):
		_adjust(-1)
	elif event.is_action_pressed("ui_right"):
		_adjust(1)
	elif event.is_action_pressed("ui_accept"):
		_activate()
	elif event.is_action_pressed("ui_cancel"):
		cancelled.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	var click := event as InputEventMouseButton
	var point := Vector2.ZERO
	if motion != null:
		point = motion.position
	elif click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		point = click.position
	else:
		return
	var row := floori(point.y / _cell.y)
	for index in range(entries.size()):
		if _entry_row(index) != row:
			continue
		if index != selected:
			selected = index
			_flash_at = _time
		if click != null:
			if entries[index]["kind"] == &"slider":
				_click_slider(entries[index], floori(point.x / _cell.x))
			else:
				_activate()
		accept_event()
		return


func _move(step: int) -> void:
	if entries.is_empty():
		return
	selected = posmod(selected + step, entries.size())
	_flash_at = _time


func _adjust(step: int) -> void:
	if entries.is_empty() or settings == null:
		return
	var entry := entries[selected]
	if entry["kind"] == &"slider":
		var value := clampf(float(settings.get(entry["id"])) + step * 0.05, 0.0, 1.0)
		settings.set_option(entry["id"], snappedf(value, 0.05))
	elif entry["kind"] == &"toggle":
		settings.set_option(entry["id"], not bool(settings.get(entry["id"])))


func _activate() -> void:
	if entries.is_empty():
		return
	var entry := entries[selected]
	if entry["kind"] == &"toggle" and settings != null:
		settings.set_option(entry["id"], not bool(settings.get(entry["id"])))
	elif entry["kind"] == &"button":
		activated.emit(entry["id"])


func _click_slider(entry: Dictionary, column: int) -> void:
	var bar_start := _origin().x + (3 if heading != "" else 0) + 2 + LABEL_COLUMNS + 1
	var fraction := clampf(float(column - bar_start + 1) / BAR_CELLS, 0.0, 1.0)
	settings.set_option(entry["id"], snappedf(fraction, 0.05))


func _spaced(text: String) -> String:
	var letters := PackedStringArray()
	for i in range(text.length()):
		letters.append(text[i])
	return " ".join(letters)


func _hash(a: int, b: int) -> float:
	var h := (a * 374761393 + b * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


func _draw_text(column: int, row: int, text: String, color: Color) -> void:
	var ascent := _font.get_ascent(_font_size)
	var descent := _font.get_descent(_font_size)
	var baseline := (_cell.y + ascent - descent) * 0.5
	for i in range(text.length()):
		var code := text.unicode_at(i)
		var advance := _font.get_char_size(code, _font_size).x
		var origin := Vector2((column + i) * _cell.x + (_cell.x - advance) * 0.5, row * _cell.y + baseline)
		_font.draw_char(get_canvas_item(), origin.floor(), code, _font_size, color)
