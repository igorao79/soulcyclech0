extends Control

# Раскрытая книга «Цикл душ» в видении — в том же стиле, что заголовок главного экрана:
# каждая надпись сложена из знаков атласа по форме букв антиквы (glyph_text.gdshader).
# Заголовок и написанный том — холодное серебро, выбранный пункт раскалён и дымит углями,
# ненаписанные тома бледные, выбрать их нельзя. Буквы проступают из шума при открытии.
# Управление: вверх/вниз, E / Enter / Space; Escape закрывает. Мышь — наведение и щелчок.

signal activated(id: StringName)

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const SHADER := preload("res://scripts/ui/glyph_text.gdshader")
const FontAtlas := preload("res://scripts/ascii/ascii_font_atlas.gd")
# Знаки книги мельче, чем у мира: так и названия томов складываются из знаков и читаются.
const FINE_FONT_SIZE := 5

const NORMAL := Color(1.0, 0.0, 0.0)
const HOT := Color(0.0, 1.0, 0.0)
const DIM := Color(0.0, 0.0, 1.0)
const SILVER := Color(0.86, 0.89, 0.98)
const EMBER := Color(1.0, 0.72, 0.42)
const FAINT := Color(0.42, 0.45, 0.58)
const RULE := Color(0.55, 0.58, 0.72)
const NOISE := Color(0.78, 0.30, 0.36)
const SCRAMBLE := "#%&@$*+=-:;!?/\\|<>~^"

## Тома: {"numeral": "I", "title": "Звездопад"} — пустой title значит «страницы пусты».
var tomes: Array[Dictionary] = []
## Центр блока в долях экрана.
var center := Vector2(0.27, 0.5)
var atlas: Texture2D
var cell := Vector2i(5, 8)
var selected := 0
var fade := 1.0

var _font: Font
var _mask: SubViewport
var _mask_canvas: Control
var _plain: Control
var _plain_font: Font
var _name_font: Font
var _material: ShaderMaterial
var _time := 0.0
var _opened_at := 0.0
# Строки блока: текст, канал, кегль, базовая линия, id (пусто — не выбирается).
var _lines: Array[Dictionary] = []
var _rows: Array[Rect2] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = UiStyle.serif(700.0)
	_name_font = UiStyle.serif(600.0)
	_mask = SubViewport.new()
	_mask.transparent_bg = true
	_mask.disable_3d = true
	_mask.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_mask)
	_mask_canvas = Control.new()
	_mask_canvas.draw.connect(_draw_mask)
	_mask.add_child(_mask_canvas)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("atlas_tex", atlas)
	_material.set_shader_parameter("cell_px", Vector2(cell))
	_material.set_shader_parameter("mask_tex", _mask.get_texture())
	material = _material
	_build_fine_atlas()
	_plain_font = UiStyle.serif(500.0)
	_plain = Control.new()
	_plain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plain.draw.connect(_draw_plain)
	add_child(_plain)
	resized.connect(_layout)
	_layout()


func _build_fine_atlas() -> void:
	var mono := FontAtlas.create_font()
	var size := maxi(roundi(FINE_FONT_SIZE * DisplayServer.screen_get_scale()), 4)
	var fine_cell := FontAtlas.measure_cell(mono, size)
	var fine := await FontAtlas.build(self, mono, size, fine_cell)
	_material.set_shader_parameter("atlas_tex", fine)
	_material.set_shader_parameter("cell_px", Vector2(fine_cell))


func open() -> void:
	show()
	_opened_at = _time
	selected = _ids().size() - 1


func _ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for line in _lines:
		if line["id"] != &"":
			ids.append(line["id"])
	return ids


# Знаками складываются только крупные формы — заголовок и римские цифры томов: мельче
# буквы в сетке знаков не читаются. Названия томов и «закрыть книгу» — обычной антиквой
# поверх, тем же серебром и углём. Кегли — доли высоты экрана.
func _layout() -> void:
	var size := get_rect().size
	if size.y <= 0.0:
		return
	_mask.size = Vector2i(size)
	_mask_canvas.size = size
	_plain.size = size
	var cap := size.y / UiStyle.SERIF_CAP
	var x := size.x * center.x
	_lines.clear()
	var y := size.y * (center.y - 0.22)
	_lines.append({"text": "Цикл душ", "kind": NORMAL, "size": roundi(cap * 0.1), "y": y, "x": x, "id": &"", "name": ""})
	y += size.y * 0.16
	var numeral_x := x - size.y * 0.24
	for index in range(tomes.size()):
		var tome: Dictionary = tomes[index]
		var written: bool = tome["title"] != ""
		_lines.append({
			"text": tome["numeral"], "kind": NORMAL if written else DIM, "size": roundi(cap * 0.085), "y": y,
			"x": numeral_x, "id": StringName("tome_%d" % index) if written else &"",
			"name": tome["title"] if written else "страницы пусты",
		})
		y += size.y * 0.115
	y += size.y * 0.01
	_lines.append({"text": "", "kind": NORMAL, "size": roundi(cap * 0.03), "y": y, "x": x, "id": &"close", "name": "закрыть книгу"})
	_rows.clear()
	for line in _lines:
		if line["id"] != &"":
			_rows.append(Rect2(numeral_x - size.y * 0.08, line["y"] - size.y * 0.075, size.y * 0.6, size.y * 0.1))
	var top: float = _lines[0]["y"] - size.y * 0.1
	var bottom: float = _lines[-1]["y"] + size.y * 0.05
	var half := size.y * 0.55
	_material.set_shader_parameter("screen_px", size)
	_material.set_shader_parameter("calm_rect", Vector4(x - half, top - 20.0, half * 2.0, bottom - top + 40.0))


func _draw_mask() -> void:
	var ids := _ids()
	for line in _lines:
		if line["text"] == "":
			continue
		var kind: Color = line["kind"]
		if line["id"] != &"" and ids.find(line["id"]) == selected:
			kind = HOT
		var w := _font.get_string_size(line["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, line["size"]).x
		var at := Vector2(line["x"] - w * 0.5, line["y"]).floor()
		# Обводка утолщает волосные штрихи антиквы: иначе в ячейку знака они не попадают.
		var outline := maxi(roundi(line["size"] * 0.045), 2)
		_font.draw_string_outline(_mask_canvas.get_canvas_item(), at, line["text"], HORIZONTAL_ALIGNMENT_LEFT, -1,
			line["size"], outline, kind)
		_font.draw_string(_mask_canvas.get_canvas_item(), at, line["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, line["size"], kind)
	# Названия томов и «закрыть книгу» — тоже знаками, тем же шрифтом, что заголовок.
	var size := get_rect().size
	var name_size := roundi(size.y / UiStyle.SERIF_CAP * 0.062)
	var tracking := name_size * 0.12
	for line in _lines:
		if line["name"] == "":
			continue
		var kind: Color = line["kind"]
		if line["id"] != &"" and ids.find(line["id"]) == selected:
			kind = HOT
		var text: String = line["name"]
		var at := Vector2(line["x"] + size.y * 0.075, line["y"] - size.y * 0.012)
		if line["id"] == &"close":
			var w := 0.0
			for i in range(text.length()):
				w += _name_font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x + tracking
			at = Vector2(size.x * center.x - (w - tracking) * 0.5, line["y"])
		# Строчные вразрядку: между буквами просвет хотя бы в знак, иначе они слипаются.
		for i in range(text.length()):
			var letter := text[i]
			_name_font.draw_string(_mask_canvas.get_canvas_item(), at.floor(), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, kind)
			at.x += _name_font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x + tracking


# Названия томов антиквой вразрядку: проступают из шума вслед за цифрами.
func _draw_plain() -> void:
	var size := get_rect().size
	var ids := _ids()
	var since := _time - _opened_at
	var name_size := roundi(size.y / UiStyle.SERIF_CAP * 0.032)
	for index in range(_lines.size()):
		var line: Dictionary = _lines[index]
		if line["name"] == "":
			continue
		var is_selected: bool = line["id"] != &"" and ids.find(line["id"]) == selected
		var glow := 0.82 + 0.18 * sin(_time * 4.0)
		var color := Color(SILVER, fade)
		if line["kind"] == DIM:
			color = Color(FAINT, 0.7 * fade)
		if is_selected:
			color = Color(EMBER.r * glow, EMBER.g * glow, EMBER.b * glow, fade)
		var text: String = line["name"]
		var tracking := name_size * (0.12 if line["kind"] != DIM else 0.22)
		var y: float = line["y"] - size.y * 0.025
		var x: float = line["x"] + size.y * 0.075
		if line["id"] == &"close":
			var width := 0.0
			for i in range(text.length()):
				width += _plain_font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x + tracking
			x = size.x * center.x - width * 0.5
			y = line["y"]
		if is_selected:
			# Ромб-огонёк перед выбранной строкой.
			var mid := Vector2((line["x"] - size.y * 0.06) if line["id"] != &"close" else size.x * center.x - size.y * 0.2, y - name_size * 0.3)
			var tip := name_size * 0.18 * (0.85 + 0.15 * sin(_time * 6.0))
			_plain.draw_colored_polygon(PackedVector2Array([
				mid + Vector2(0, -tip), mid + Vector2(tip, 0), mid + Vector2(0, tip), mid + Vector2(-tip, 0)
			]), Color(EMBER, fade))
	# Черта с ромбом под заголовком.
	var title_y: float = _lines[0]["y"] + size.y * 0.05
	var mid := Vector2(size.x * center.x, title_y)
	var reach := size.y * 0.12 * clampf(since / 0.8, 0.0, 1.0)
	_plain.draw_line(mid - Vector2(reach, 0), mid - Vector2(8, 0), Color(RULE, 0.8 * fade), 1.0)
	_plain.draw_line(mid + Vector2(8, 0), mid + Vector2(reach, 0), Color(RULE, 0.8 * fade), 1.0)
	_plain.draw_colored_polygon(PackedVector2Array([
		mid + Vector2(0, -4), mid + Vector2(4, 0), mid + Vector2(0, 4), mid + Vector2(-4, 0)
	]), Color(EMBER, fade))


func _process(delta: float) -> void:
	_time += delta
	if not visible:
		return
	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("appear", _time - _opened_at)
	_material.set_shader_parameter("fade", fade)
	_mask_canvas.queue_redraw()
	_plain.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_rect().size), Color.WHITE)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	var ids := _ids()
	match key.physical_keycode:
		KEY_UP, KEY_W:
			selected = posmod(selected - 1, ids.size())
		KEY_DOWN, KEY_S:
			selected = posmod(selected + 1, ids.size())
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E:
			if not key.echo:
				activated.emit(ids[selected])
		KEY_ESCAPE:
			if not key.echo:
				activated.emit(&"close")
		_:
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
	var ids := _ids()
	for index in range(_rows.size()):
		if _rows[index].has_point(point):
			selected = index
			if click != null:
				activated.emit(ids[index])
			accept_event()
			return
