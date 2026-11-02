extends CanvasLayer

# Автозагрузка PauseMenu: Escape в игре ставит мир на паузу и открывает меню из символов.
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
var _menu: SoulcycleAsciiMenu
var _settings: SoulcycleAsciiMenu


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

	_menu = SoulcycleAsciiMenu.new()
	_menu.heading = "Пауза"
	_menu.heading_size = 40.0
	_menu.columns = 30
	_menu.spacing = 2
	_menu.add_button(&"resume", "продолжить")
	_menu.add_button(&"settings", "настройки")
	_menu.add_button(&"title", "главное меню")
	_menu.add_button(&"quit", "выйти из игры")
	_menu.activated.connect(_on_menu)
	_menu.cancelled.connect(close)
	_root.add_child(_menu)

	_settings = SoulcycleAsciiMenu.make_settings(get_node("/root/GameSettings"))
	_settings.activated.connect(func(_id: StringName) -> void: _back_to_menu())
	_settings.cancelled.connect(_back_to_menu)
	_settings.hide()
	_root.add_child(_settings)

	_root.hide()


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.show()
	_settings.hide()
	_menu.open()
	get_tree().paused = true


func close() -> void:
	_root.hide()
	get_tree().paused = false


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
			close()
			get_tree().change_scene_to_file(TITLE_SCENE)
		&"quit":
			get_tree().quit()


func _back_to_menu() -> void:
	_settings.hide()
	_menu.open()
