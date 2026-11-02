class_name SoulcycleTitleScreen
extends Node

# Главный экран целиком из символов: иллюстрация с двумя героями, заголовок «ЦИКЛ ДУШ»,
# сложенный знаками по форме шрифта Soulcycle Thorn, и меню той же моноширинной сеткой.

const FontAtlas := preload("res://scripts/ascii/ascii_font_atlas.gd")
const BellSynth := preload("res://scripts/audio/bell_synth.gd")
const SCREEN_SHADER := preload("res://scripts/title/title_screen.gdshader")
const ART := preload("res://assets/title/duo_moon.jpg")
const THEME_MUSIC := preload("res://assets/music/snowbound_crossroads.ogg")

const ASCII_SCENE := "res://scenes/ascii_demo.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const TITLE := "ЦИКЛ ДУШ"
const SUBTITLE := "S O U L C Y C L E"
const HINT := "↑↓ выбор    enter — принять    esc — назад"
const BASE_FONT_SIZE := 8
# Заголовок: центр по высоте и высота букв в долях экрана.
const TITLE_CENTER := 0.37
const TITLE_HEIGHT := 0.15
const INTRO_TIME := 1.4
const OUTRO_TIME := 1.1

var screen_material: ShaderMaterial
var mask_viewport: SubViewport
var mask_label: Label
var ui_root: Control
var caption: Control
var menu: SoulcycleAsciiMenu
var settings_menu: SoulcycleAsciiMenu
var caption_font: Font
var music: AudioStreamPlayer
var bell_player: AudioStreamPlayer
var bell_stream: AudioStreamWAV
var bell_task := -1
var elapsed := 0.0
var outro := 0.0
var leaving := false
var drawing := false


func _ready() -> void:
	get_tree().paused = false
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.title = "Цикл душ"
	bell_task = WorkerThreadPool.add_task(func() -> void: bell_stream = BellSynth.create(0.9))
	_build_audio()

	var font := FontAtlas.create_font()
	caption_font = font
	var font_size := roundi(BASE_FONT_SIZE * DisplayServer.screen_get_scale())
	var cell := FontAtlas.measure_cell(font, font_size)
	var atlas := await FontAtlas.build(self, font, font_size, cell)
	_build_title_mask()
	_build_screen(atlas, cell)
	_build_ui()
	window.size_changed.connect(_fit)
	_fit()
	drawing = true


func _process(delta: float) -> void:
	if not drawing:
		return
	elapsed += delta
	if bell_task >= 0 and WorkerThreadPool.is_task_completed(bell_task):
		WorkerThreadPool.wait_for_task_completion(bell_task)
		bell_task = -1
		bell_player.stream = bell_stream

	screen_material.set_shader_parameter("time", elapsed)
	screen_material.set_shader_parameter("intro", clampf(elapsed / INTRO_TIME, 0.0, 1.0))
	screen_material.set_shader_parameter("outro", outro)
	screen_material.set_shader_parameter("title_time", elapsed - INTRO_TIME * 0.5)
	var fade := 1.0 - clampf(outro * 3.0, 0.0, 1.0)
	ui_root.modulate.a = clampf((elapsed - INTRO_TIME) / 0.4, 0.0, 1.0) * fade
	_update_calm_rect()
	caption.queue_redraw()


# Маска букв: заголовок шрифтом Soulcycle Thorn рисуется вне экрана, шейдер читает его форму.
func _build_title_mask() -> void:
	mask_viewport = SubViewport.new()
	mask_viewport.transparent_bg = true
	mask_viewport.disable_3d = true
	mask_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(mask_viewport)
	mask_label = Label.new()
	mask_label.text = TITLE
	mask_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mask_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mask_label.add_theme_font_override("font", SoulcycleUiStyle.DISPLAY_FONT)
	mask_label.add_theme_color_override("font_color", Color.WHITE)
	mask_viewport.add_child(mask_label)


func _build_screen(atlas: Texture2D, cell: Vector2i) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	screen_material = ShaderMaterial.new()
	screen_material.shader = SCREEN_SHADER
	screen_material.set_shader_parameter("atlas_tex", atlas)
	screen_material.set_shader_parameter("art_tex", ART)
	screen_material.set_shader_parameter("art_aspect", float(ART.get_width()) / ART.get_height())
	screen_material.set_shader_parameter("cell_px", Vector2(cell))
	screen_material.set_shader_parameter("title_mask", mask_viewport.get_texture())
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.material = screen_material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)

	caption = Control.new()
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.draw.connect(_draw_caption)
	ui_root.add_child(caption)

	menu = SoulcycleAsciiMenu.new()
	menu.columns = 36
	menu.spacing = 2
	menu.center = Vector2(0.5, 0.71)
	menu.add_button(&"ascii", "начать путь")
	menu.add_button(&"winter", "зимний перекрёсток")
	menu.add_button(&"settings", "настройки")
	menu.add_button(&"quit", "выход")
	menu.activated.connect(_on_menu)
	ui_root.add_child(menu)

	settings_menu = SoulcycleAsciiMenu.make_settings(get_node("/root/GameSettings"))
	settings_menu.center = Vector2(0.5, 0.73)
	settings_menu.activated.connect(func(_id: StringName) -> void: _close_settings())
	settings_menu.cancelled.connect(_close_settings)
	settings_menu.hide()
	ui_root.add_child(settings_menu)
	menu.open()


# Подпись под заголовком и подсказка внизу — той же сеткой, что и меню.
func _draw_caption() -> void:
	var size := caption.get_rect().size
	var scale := size.y / SoulcycleUiStyle.LOGICAL_HEIGHT
	var font_size := maxi(roundi(10.0 * scale), 8)
	var subtitle_y := size.y * (TITLE_CENTER + TITLE_HEIGHT * 0.86)
	var flicker := 0.75 + 0.25 * sin(elapsed * 1.3)
	_draw_centered(SUBTITLE, subtitle_y, font_size, Color(0.62, 0.66, 0.80, 0.85 * flicker))
	_draw_centered(HINT, size.y - font_size * 2.2, font_size, Color(0.42, 0.46, 0.58, 0.8))


func _draw_centered(text: String, y: float, font_size: int, color: Color) -> void:
	var width := caption_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := (caption.get_rect().size.x - width) * 0.5
	caption.draw_rect(
		Rect2(x - font_size, y - font_size * 1.1, width + font_size * 2.0, font_size * 1.6),
		Color(0.004, 0.004, 0.012, 0.75 * color.a)
	)
	caption.draw_string(caption_font, Vector2(x, y).floor(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _fit() -> void:
	var screen := get_viewport().get_visible_rect().size
	screen_material.set_shader_parameter("screen_px", screen)
	mask_viewport.size = Vector2i(screen)
	var letters := roundi(screen.y * TITLE_HEIGHT)
	mask_label.add_theme_font_size_override("font_size", letters)
	mask_label.position = Vector2(0.0, screen.y * TITLE_CENTER - letters * 0.75)
	mask_label.size = Vector2(screen.x, letters * 1.5)
	mask_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Рамка заголовка по ширине надписи: в ней горят угли и дёргаются строки.
	var width := SoulcycleUiStyle.DISPLAY_FONT.get_string_size(TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, letters).x
	screen_material.set_shader_parameter(
		"title_box",
		Vector4((screen.x - width) * 0.5, screen.y * TITLE_CENTER - letters * 0.5, width, letters * 1.05)
	)


# Картина притушена под заголовком и меню, чтобы символы текста не тонули в символах картины.
func _update_calm_rect() -> void:
	var screen := get_viewport().get_visible_rect().size
	var title_area := Rect2(
		screen.x * 0.27, screen.y * (TITLE_CENTER - TITLE_HEIGHT * 0.7), screen.x * 0.46, screen.y * TITLE_HEIGHT * 1.6
	)
	var active := settings_menu if settings_menu.visible else menu
	var area := title_area.merge(active.box_rect().grow(8.0))
	screen_material.set_shader_parameter("calm_rect", Vector4(area.position.x, area.position.y, area.size.x, area.size.y))


func _on_menu(id: StringName) -> void:
	match id:
		&"ascii":
			_start(ASCII_SCENE)
		&"winter":
			_start(MAIN_SCENE)
		&"settings":
			menu.hide()
			settings_menu.open()
		&"quit":
			get_tree().quit()


func _close_settings() -> void:
	settings_menu.hide()
	menu.open()


func _start(scene_path: String) -> void:
	if leaving:
		return
	leaving = true
	menu.hide()
	if bell_player.stream != null:
		bell_player.pitch_scale = 0.95
		bell_player.volume_db = -10.0
		bell_player.play()
	var tween := create_tween()
	tween.tween_property(self, "outro", 1.0, OUTRO_TIME).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(music, "volume_db", -40.0, OUTRO_TIME)
	tween.tween_callback(func() -> void:
		# Основная игра нарисована под растяжение 960×540, ASCII-ночь настраивает окно сама.
		if scene_path == MAIN_SCENE:
			get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		get_tree().change_scene_to_file(scene_path)
	)


func _build_audio() -> void:
	var looped := THEME_MUSIC.duplicate() as AudioStreamOggVorbis
	looped.loop = true
	music = AudioStreamPlayer.new()
	music.stream = looped
	music.bus = &"Music"
	music.volume_db = -14.0
	add_child(music)
	music.play()
	bell_player = AudioStreamPlayer.new()
	bell_player.bus = &"SFX"
	add_child(bell_player)
