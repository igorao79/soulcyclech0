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
const Ornament := preload("res://scripts/ui/ornament.gd")
# Знаки книги мельче, чем у мира, и считаются от высоты окна, а не от масштаба экрана:
# на Retina сетка знаков остаётся той же доли экрана и надписи читаются одинаково.
const FINE_CELL_SHARE := 1.0 / 200.0

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
var _small: SubViewport
var _small_canvas: Control
var _atlas_height := 0
var _plain: Control
var _plain_font: Font
var _name_font: Font
var _mono: Font
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
	_mono = FontAtlas.create_font()
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
	# Мелкие надписи — в отдельной маске: шейдер складывает их чёткими пиксельными буквами.
	_small = SubViewport.new()
	_small.transparent_bg = true
	_small.disable_3d = true
	_small.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_small)
	_small_canvas = Control.new()
	_small_canvas.draw.connect(_draw_small)
	_small.add_child(_small_canvas)
	_material.set_shader_parameter("small_tex", _small.get_texture())
	material = _material
	_plain_font = UiStyle.serif(500.0)
	_plain = Control.new()
	_plain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plain.draw.connect(_draw_plain)
	add_child(_plain)
	resized.connect(_layout)
	_layout()


func _build_fine_atlas(height: float) -> void:
	var size := maxi(roundi(height * FINE_CELL_SHARE), 4)
	if size == _atlas_height:
		return
	_atlas_height = size
	var mono := FontAtlas.create_font()
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


# Кегли — доли высоты окна. Блок слева и невысокий: справа парит двойник.
func _layout() -> void:
	var size := get_rect().size
	if size.y <= 0.0:
		return
	_build_fine_atlas(size.y)
	_mask.size = Vector2i(size)
	_mask_canvas.size = size
	_small.size = Vector2i(size)
	_small_canvas.size = size
	_plain.size = size
	var cap := size.y / UiStyle.SERIF_CAP
	var x := size.x * center.x
	_lines.clear()
	var y := size.y * (center.y - 0.17)
	_lines.append({"text": "Цикл душ", "kind": NORMAL, "size": roundi(cap * 0.075), "y": y, "x": x, "id": &"", "name": ""})
	y += size.y * 0.125
	var numeral_x := x - size.y * 0.17
	for index in range(tomes.size()):
		var tome: Dictionary = tomes[index]
		var written: bool = tome["title"] != ""
		_lines.append({
			"text": tome["numeral"], "kind": NORMAL if written else DIM, "size": roundi(cap * 0.055), "y": y,
			"x": numeral_x, "id": StringName("tome_%d" % index) if written else &"",
			"name": tome["title"] if written else "страницы пусты",
		})
		y += size.y * 0.08
	y += size.y * 0.02
	_lines.append({"text": "", "kind": NORMAL, "size": 0, "y": y, "x": x, "id": &"close", "name": "закрыть книгу"})
	_rows.clear()
	for line in _lines:
		if line["id"] != &"":
			_rows.append(Rect2(numeral_x - size.y * 0.06, line["y"] - size.y * 0.055, size.y * 0.45, size.y * 0.07))
	var top: float = _lines[0]["y"] - size.y * 0.08
	var bottom: float = _lines[-1]["y"] + size.y * 0.035
	var half := size.y * 0.34
	_material.set_shader_parameter("screen_px", size)
	_material.set_shader_parameter("calm_rect", Vector4(x - half, top - 16.0, half * 2.0, bottom - top + 32.0))


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


# Названия томов и «закрыть книгу» — тем же шрифтом, вразрядку, в мелкой маске.
func _draw_small() -> void:
	var size := get_rect().size
	var ids := _ids()
	var name_size := roundi(size.y / UiStyle.SERIF_CAP * 0.04)
	var tracking := name_size * 0.14
	for line in _lines:
		if line["name"] == "":
			continue
		var kind: Color = line["kind"]
		if line["id"] != &"" and ids.find(line["id"]) == selected:
			kind = HOT
		var text: String = line["name"]
		var at := Vector2(line["x"] + size.y * 0.06, line["y"] - size.y * 0.008)
		if line["id"] == &"close":
			var w := 0.0
			for i in range(text.length()):
				w += _name_font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x + tracking
			at = Vector2(size.x * center.x - (w - tracking) * 0.5, line["y"])
		for i in range(text.length()):
			var letter := text[i]
			_name_font.draw_string(_small_canvas.get_canvas_item(), at.floor(), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, kind)
			at.x += _name_font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x + tracking


# Названия томов антиквой вразрядку: проступают из шума вслед за цифрами.
func _draw_plain() -> void:
	var size := get_rect().size
	var ids := _ids()
	var since := _time - _opened_at
	var name_size := roundi(size.y / UiStyle.SERIF_CAP * 0.04)
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
		var y: float = line["y"] - size.y * 0.008
		var x: float = line["x"] + size.y * 0.075
		if line["id"] == &"close":
			var width := 0.0
			for i in range(text.length()):
				width += _plain_font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x + tracking
			x = size.x * center.x - width * 0.5
			y = line["y"]
		if is_selected:
			# Ромб-огонёк перед выбранной строкой.
			var mid := Vector2((line["x"] - size.y * 0.05) if line["id"] != &"close" else size.x * center.x - size.y * 0.15, y - name_size * 0.3)
			var tip := name_size * 0.18 * (0.85 + 0.15 * sin(_time * 6.0))
			_plain.draw_colored_polygon(PackedVector2Array([
				mid + Vector2(0, -tip), mid + Vector2(tip, 0), mid + Vector2(0, tip), mid + Vector2(-tip, 0)
			]), Color(EMBER, fade))
	# Под заголовком — разделитель из знаков с тлеющим ромбом.
	var title_y: float = _lines[0]["y"] + size.y * 0.04
	Ornament.draw(_plain, _mono, Vector2(size.x * center.x, title_y), size.y * 0.14 * clampf(since / 0.8, 0.0, 1.0),
		roundi(size.y / UiStyle.LOGICAL_HEIGHT * 9.0), fade, _time)


func _process(delta: float) -> void:
	_time += delta
	if not visible:
		return
	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("appear", _time - _opened_at)
	_material.set_shader_parameter("fade", fade)
	_mask_canvas.queue_redraw()
	_small_canvas.queue_redraw()
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
