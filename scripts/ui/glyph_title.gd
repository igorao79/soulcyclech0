extends Control

# Надписи из знаков атласа по форме антиквы — как «ЦИКЛ ДУШ» и книга в видении.
# Используется для заголовков меню, карточки главы и «продолжение следует».
# Строки задаются через set_lines: [{"text", "size" (кегль, px), "center" (Vector2,
# середина базовой линии), "kind" (NORMAL/HOT/DIM), "small" (мелкий текст — чёткими
# пиксельными буквами)}]. restart() — заново проступить из шума.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const SHADER := preload("res://scripts/ui/glyph_text.gdshader")
const FontAtlas := preload("res://scripts/ascii/ascii_font_atlas.gd")
const CELL_SHARE := 1.0 / 200.0

const NORMAL := Color(1.0, 0.0, 0.0)
const HOT := Color(0.0, 1.0, 0.0)
const DIM := Color(0.0, 0.0, 1.0)

## Общий атлас мелких знаков: строится один раз на высоту окна.
static var _atlas_cache := {}

var fade := 1.0
var _lines: Array[Dictionary] = []
var _font: Font
var _small_font: Font
var _mask: SubViewport
var _mask_canvas: Control
var _small: SubViewport
var _small_canvas: Control
var _material: ShaderMaterial
var _time := 0.0
var _started := 0.0
var _atlas_height := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiStyle.serif(700.0)
	_small_font = UiStyle.serif(600.0)
	_mask = _make_mask()
	_mask_canvas = _mask.get_child(0)
	_mask_canvas.draw.connect(_draw_mask.bind(false))
	_small = _make_mask()
	_small_canvas = _small.get_child(0)
	_small_canvas.draw.connect(_draw_mask.bind(true))
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("mask_tex", _mask.get_texture())
	_material.set_shader_parameter("small_tex", _small.get_texture())
	_material.set_shader_parameter("calm_rect", Vector4.ZERO)
	material = _material
	resized.connect(_fit)
	_fit()


func _make_mask() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var canvas := Control.new()
	viewport.add_child(canvas)
	return viewport


func set_lines(lines: Array[Dictionary]) -> void:
	_lines = lines


func restart() -> void:
	_started = _time


func _fit() -> void:
	var size := get_rect().size
	if size.y <= 0.0:
		return
	for viewport in [_mask, _small]:
		viewport.size = Vector2i(size)
		viewport.get_child(0).size = size
	_material.set_shader_parameter("screen_px", size)
	_build_atlas(size.y)


func _build_atlas(height: float) -> void:
	var font_size := maxi(roundi(height * CELL_SHARE), 4)
	if font_size == _atlas_height:
		return
	_atlas_height = font_size
	if not _atlas_cache.has(font_size):
		var mono := FontAtlas.create_font()
		var cell := FontAtlas.measure_cell(mono, font_size)
		_atlas_cache[font_size] = {"cell": cell, "atlas": await FontAtlas.build(self, mono, font_size, cell)}
	var entry: Dictionary = _atlas_cache[font_size]
	_material.set_shader_parameter("atlas_tex", entry["atlas"])
	_material.set_shader_parameter("cell_px", Vector2(entry["cell"]))


func _process(delta: float) -> void:
	_time += delta
	if not is_visible_in_tree():
		return
	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("appear", _time - _started)
	_material.set_shader_parameter("fade", fade)
	_mask_canvas.queue_redraw()
	_small_canvas.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_rect().size), Color.WHITE)


func _draw_mask(small: bool) -> void:
	var canvas: Control = _small_canvas if small else _mask_canvas
	for line in _lines:
		if bool(line.get("small", false)) != small:
			continue
		var text: String = line["text"]
		var font_size: int = line["size"]
		var kind: Color = line.get("kind", NORMAL)
		var font := _small_font if small else _font
		# Мелкий текст вразрядку: между буквами хотя бы знак просвета.
		var tracking := font_size * (0.14 if small else float(line.get("tracking", 0.04)))
		var width := 0.0
		for i in range(text.length()):
			width += font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + tracking
		width -= tracking
		var center: Vector2 = line["center"]
		var x := center.x - width * 0.5
		for i in range(text.length()):
			var letter := text[i]
			var at := Vector2(x, center.y).floor()
			if not small:
				# Обводка утолщает волосные штрихи антиквы: иначе в ячейку знака они не попадают.
				font.draw_string_outline(canvas.get_canvas_item(), at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
					maxi(roundi(font_size * 0.045), 2), kind)
			font.draw_string(canvas.get_canvas_item(), at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, kind)
			x += font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + tracking
