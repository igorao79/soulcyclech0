extends CanvasLayer

# Свои скрипты подключены по пути, а не по имени класса: игра, запущенная без редактора,
# не всегда знает новые глобальные классы, и сцена падала при переходе.
const AsciiMenu := preload("res://scripts/ui/ascii_menu.gd")
const FontAtlas := preload("res://scripts/ascii/ascii_font_atlas.gd")
const ARCH_SHADER := preload("res://scripts/ui/winter_arch.gdshader")
const ARCH_ART := preload("res://assets/ui/winter_arch.jpg")
# Размер знаков рамки — как на главном экране.
const ARCH_FONT_SIZE := 8
const ARCH_REVEAL := 0.7
# Закрытие быстрее открытия: рамка уходит в шум к краям, меню гаснет, потом мир оживает.
const ARCH_HIDE := 0.4

# Автозагрузка PauseMenu: Escape в игре ставит мир на паузу и открывает меню из символов.
# Меню стоит в арке из двух зимних деревьев во весь экран (winter_arch.gdshader).
# На главном экране меню не открывается: там своё.

const TITLE_SCENE := "res://scenes/title.tscn"
const GAMEPLAY_SCENES: Array[String] = [
	"res://scenes/chapter_one.tscn", "res://scenes/main.tscn", "res://scenes/ascii_demo.tscn",
]
const VEIL_SHADER := """
shader_type canvas_item;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.6, 1.0);
	float edge = smoothstep(0.15, 0.85, length(p));
	COLOR = vec4(0.004, 0.004, 0.016, mix(0.84, 0.96, edge));
}
"""

var _root: Control
var _menu: AsciiMenu
var _settings: AsciiMenu
var _arch: ColorRect
var _arch_material: ShaderMaterial
var _time := 0.0
var _opened_at := 0.0
var _closing_at := -1.0
var _after_close := Callable()


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Мир под меню не исчезает: он гаснет к краям и остаётся различим в середине.
	var dim := ColorRect.new()
	var veil := ShaderMaterial.new()
	veil.shader = Shader.new()
	veil.shader.code = VEIL_SHADER
	dim.material = veil
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	# Арка из знаков. Атлас знаков строится при запуске игры, пока рамка не нужна.
	_arch_material = ShaderMaterial.new()
	_arch_material.shader = ARCH_SHADER
	_arch_material.set_shader_parameter("art_tex", ARCH_ART)
	_arch_material.set_shader_parameter("art_aspect", float(ARCH_ART.get_width()) / ARCH_ART.get_height())
	_arch = ColorRect.new()
	_arch.material = _arch_material
	_arch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arch.hide()
	_root.add_child(_arch)
	_build_arch_atlas()

	_menu = AsciiMenu.new()
	_menu.heading = "Затишье"
	_menu.heading_size = 40.0
	_menu.columns = 30
	_menu.spacing = 2
	# Чуть ниже середины: над меню висят луна и колокол арки.
	_menu.center = Vector2(0.5, 0.56)
	_menu.add_button(&"resume", "продолжить путь")
	_menu.add_button(&"settings", "настройки")
	_menu.add_button(&"title", "закрыть книгу")
	_menu.add_button(&"quit", "проснуться")
	_menu.activated.connect(_on_menu)
	_menu.cancelled.connect(close)
	_root.add_child(_menu)

	_settings = AsciiMenu.make_settings(get_node("/root/GameSettings"))
	_settings.activated.connect(func(_id: StringName) -> void: _back_to_menu())
	_settings.cancelled.connect(_back_to_menu)
	_settings.center = Vector2(0.5, 0.57)
	_settings.hide()
	_root.add_child(_settings)

	_root.hide()


func _build_arch_atlas() -> void:
	var font := FontAtlas.create_font()
	var font_size := roundi(ARCH_FONT_SIZE * DisplayServer.screen_get_scale())
	var cell := FontAtlas.measure_cell(font, font_size)
	var atlas := await FontAtlas.build(self, font, font_size, cell)
	_arch_material.set_shader_parameter("atlas_tex", atlas)
	_arch_material.set_shader_parameter("cell_px", Vector2(cell))
	_arch.show()


func _process(delta: float) -> void:
	if not _root.visible:
		return
	_time += delta
	_arch_material.set_shader_parameter("time", _time)
	var t := clampf((_time - _opened_at) / ARCH_REVEAL, 0.0, 1.0)
	var shown := 1.0 - pow(1.0 - t, 3.0)
	_root.modulate.a = clampf((_time - _opened_at) / 0.25, 0.0, 1.0)
	if _closing_at >= 0.0:
		var c := clampf((_time - _closing_at) / ARCH_HIDE, 0.0, 1.0)
		shown = minf(shown, 1.0 - c * c)
		_root.modulate.a = 1.0 - smoothstep(0.35, 1.0, c)
		if c >= 1.0:
			_finish_close()
	_arch_material.set_shader_parameter("reveal", shown)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.show()
	_closing_at = -1.0
	_after_close = Callable()
	_opened_at = _time
	_root.modulate.a = 0.0
	_arch_material.set_shader_parameter("reveal", 0.0)
	_settings.hide()
	_menu.open()
	get_tree().paused = true


## Закрывает меню с анимацией; after выполняется, когда рамка ушла (мир ещё на паузе до этого).
func close(after := Callable()) -> void:
	if _closing_at >= 0.0:
		return
	_closing_at = _time
	_after_close = after
	# Пока рамка уходит, пункты не откликаются.
	_menu.hide()
	_settings.hide()


func _finish_close() -> void:
	_closing_at = -1.0
	_root.hide()
	get_tree().paused = false
	var after := _after_close
	_after_close = Callable()
	if after.is_valid():
		after.call()


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible or not event.is_action_pressed(&"pause_menu"):
		return
	if _in_gameplay():
		get_viewport().set_input_as_handled()
		open()


func _in_gameplay() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path in GAMEPLAY_SCENES


func _on_menu(id: StringName) -> void:
	match id:
		&"resume":
			close()
		&"settings":
			_menu.hide()
			_settings.open()
		&"title":
			close(func() -> void: get_tree().change_scene_to_file(TITLE_SCENE))
		&"quit":
			get_tree().quit()


func _back_to_menu() -> void:
	_settings.hide()
	_menu.open()
