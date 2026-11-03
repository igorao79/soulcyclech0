class_name SoulcycleTitleScreen
extends Node

# Свои скрипты подключены по пути, а не по имени класса: игра, запущенная без редактора,
# не всегда знает новые глобальные классы, и сцена падала при переходе.
const UiStyle := preload("res://scripts/ui/ui_style.gd")
const AsciiMenu := preload("res://scripts/ui/ascii_menu.gd")
const SaveBook := preload("res://scripts/save/save_book.gd")

# Главный экран целиком из символов: иллюстрация с двумя героями, заголовок «ЦИКЛ / ДУШ»
# в две строки, сложенный знаками по форме Cormorant Garamond, и меню моноширинной сеткой.

const FontAtlas := preload("res://scripts/ascii/ascii_font_atlas.gd")
const SCREEN_SHADER := preload("res://scripts/title/title_screen.gdshader")
const ART := preload("res://assets/title/duo_moon.jpg")
# Тема главного экрана собрана генератором tools/compose_menu_theme.py.
const THEME_MUSIC := preload("res://assets/music/menu_theme.ogg")
const THEME_LOOP_START := 4 * 4 * 60.0 / 84.0
# Музыка уходит чуть дольше, чем растворяется экран: последние ноты тонут уже в темноте.
const MUSIC_FADE := 1.6

const CHAPTER_SCENE := "res://scenes/chapter_one.tscn"
const ASCII_SCENE := "res://scenes/ascii_demo.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const TITLE_LINES: Array[String] = ["ЦИКЛ", "ДУШ"]
const BASE_FONT_SIZE := 8
# Заголовок: центр блока и высота прописных в долях экрана, сдвиг второй строки вверх.
const TITLE_CENTER := 0.415
const TITLE_CAP := 0.105
const LINE_TIGHTEN := 0.05
# Холодное лунное серебро (стиль 1 в title_screen.gdshader).
const TITLE_STYLE := 1
const MENU_CENTER := 0.75
const INTRO_TIME := 1.4
const OUTRO_TIME := 1.1

var screen_material: ShaderMaterial
var mask_viewport: SubViewport
var mask_label: Label
var ui_root: Control
var menu: AsciiMenu
var settings_menu: AsciiMenu
var tomes_menu: AsciiMenu
var title_font: Font
var title_rect := Rect2()
var music: AudioStreamPlayer
var elapsed := 0.0
var outro := 0.0
var leaving := false
var drawing := false


func _ready() -> void:
	get_tree().paused = false
	if _skip_to_game():
		return
	title_font = UiStyle.serif(700.0)
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.title = "Цикл душ"
	_build_audio()

	var font := FontAtlas.create_font()
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
	screen_material.set_shader_parameter("time", elapsed)
	screen_material.set_shader_parameter("intro", clampf(elapsed / INTRO_TIME, 0.0, 1.0))
	screen_material.set_shader_parameter("outro", outro)
	screen_material.set_shader_parameter("title_time", elapsed - INTRO_TIME * 0.5)
	var fade := 1.0 - clampf(outro * 3.0, 0.0, 1.0)
	ui_root.modulate.a = clampf((elapsed - INTRO_TIME) / 0.4, 0.0, 1.0) * fade
	_update_calm_rect()


# Маска букв: заголовок рисуется вне экрана обычным шрифтом, шейдер читает его форму.
func _build_title_mask() -> void:
	mask_viewport = SubViewport.new()
	mask_viewport.transparent_bg = true
	mask_viewport.disable_3d = true
	mask_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(mask_viewport)
	mask_label = Label.new()
	mask_label.text = "\n".join(TITLE_LINES)
	mask_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mask_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mask_label.add_theme_font_override("font", title_font)
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
	screen_material.set_shader_parameter("title_style", TITLE_STYLE)
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

	menu = AsciiMenu.new()
	menu.columns = 36
	menu.spacing = 2
	menu.center = Vector2(0.5, MENU_CENTER)
	menu.add_button(&"chapter", "Начать путь")
	menu.add_button(&"saves", "Сохранения")
	menu.add_button(&"settings", "Настройки")
	menu.add_button(&"quit", "Выход")
	menu.activated.connect(_on_menu)
	ui_root.add_child(menu)

	settings_menu = AsciiMenu.make_settings(get_node("/root/GameSettings"))
	settings_menu.center = Vector2(0.5, MENU_CENTER - 0.02)
	settings_menu.activated.connect(func(_id: StringName) -> void: _close_settings())
	settings_menu.cancelled.connect(_close_settings)
	settings_menu.hide()
	ui_root.add_child(settings_menu)

	# Сохранения делаются сами на чекпоинтах (save_book.gd). Пока чекпоинтов нет — список пуст.
	tomes_menu = AsciiMenu.new()
	tomes_menu.heading = "Сохранения"
	tomes_menu.heading_size = 24.0
	tomes_menu.columns = 44
	tomes_menu.spacing = 2
	tomes_menu.center = Vector2(0.5, MENU_CENTER - 0.02)
	var any := false
	for tome in range(SaveBook.TOMES):
		if not SaveBook.read(tome).is_empty():
			tomes_menu.add_button(StringName("tome_%d" % tome), SaveBook.label(tome))
			any = true
	if not any:
		tomes_menu.add_button(&"none", "сохранений пока нет")
	tomes_menu.add_button(&"back", "Назад")
	tomes_menu.activated.connect(_on_tomes)
	tomes_menu.cancelled.connect(_close_tomes)
	tomes_menu.hide()
	ui_root.add_child(tomes_menu)
	menu.open()


func _fit() -> void:
	var screen := get_viewport().get_visible_rect().size
	screen_material.set_shader_parameter("screen_px", screen)
	mask_viewport.size = Vector2i(screen)
	# Кегль подбирается так, чтобы высота прописных была заданной долей экрана.
	var letters := roundi(screen.y * TITLE_CAP / UiStyle.SERIF_CAP)
	var tighten := roundi(screen.y * LINE_TIGHTEN)
	var block := letters * 1.21 * TITLE_LINES.size() - tighten * (TITLE_LINES.size() - 1)
	mask_label.add_theme_font_size_override("font_size", letters)
	mask_label.add_theme_constant_override("line_spacing", -tighten)
	mask_label.position = Vector2(0.0, screen.y * TITLE_CENTER - block * 0.5)
	mask_label.size = Vector2(screen.x, block)
	mask_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Рамка заголовка по ширине надписи: в ней горят угли и дёргаются строки.
	var width := 0.0
	for line in TITLE_LINES:
		width = maxf(width, title_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, letters).x)
	title_rect = Rect2((screen.x - width) * 0.5, mask_label.position.y + letters * 0.18, width, block - letters * 0.36)
	screen_material.set_shader_parameter(
		"title_box", Vector4(title_rect.position.x, title_rect.position.y, title_rect.size.x, title_rect.size.y)
	)


# Картина притушена под заголовком и меню, чтобы символы текста не тонули в символах картины.
func _update_calm_rect() -> void:
	var title_area := title_rect.grow(title_rect.size.y * 0.25)
	var active := menu
	if settings_menu.visible:
		active = settings_menu
	elif tomes_menu.visible:
		active = tomes_menu
	var area := title_area.merge(active.box_rect().grow(8.0))
	screen_material.set_shader_parameter("calm_rect", Vector4(area.position.x, area.position.y, area.size.x, area.size.y))


# Сразу в игру, минуя меню: --ascii — ASCII-ночь, --main и флаги предпросмотра — основная игра.
func _skip_to_game() -> bool:
	var args := OS.get_cmdline_user_args()
	var target := ""
	if "--chapter" in args:
		target = CHAPTER_SCENE
	elif "--ascii" in args:
		target = ASCII_SCENE
	elif "--main" in args or "--dialogue-preview" in args or "--battle-preview" in args or "--travel-preview" in args:
		target = MAIN_SCENE
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if target == "":
		return false
	get_tree().change_scene_to_file.call_deferred(target)
	return true


func _on_menu(id: StringName) -> void:
	match id:
		&"chapter":
			_start(CHAPTER_SCENE)
		&"saves":
			menu.hide()
			tomes_menu.open()
		&"settings":
			menu.hide()
			settings_menu.open()
		&"quit":
			get_tree().quit()


func _on_tomes(id: StringName) -> void:
	if id == &"back":
		_close_tomes()
		return
	if id == &"none":
		return
	var data := SaveBook.read(int(String(id).trim_prefix("tome_")))
	# Пустой том открыть нечем.
	if data.is_empty():
		return
	tomes_menu.hide()
	SaveBook.resume_place = data["place"]
	_start(CHAPTER_SCENE)


func _close_tomes() -> void:
	tomes_menu.hide()
	menu.open()


func _close_settings() -> void:
	settings_menu.hide()
	menu.open()


func _start(scene_path: String) -> void:
	if leaving:
		return
	leaving = true
	menu.hide()
	# Музыка не обрывается, а уходит: гаснет и одновременно замедляется и опускается,
	# как останавливающаяся пластинка. В этот же миг бьёт большой колокол.
	get_node("/root/SoundDirector").toll()
	var tween := create_tween()
	tween.tween_property(self, "outro", 1.0, OUTRO_TIME).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(music, "volume_db", -42.0, MUSIC_FADE).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(music, "pitch_scale", 0.78, MUSIC_FADE).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.tween_interval(maxf(MUSIC_FADE - OUTRO_TIME, 0.0))
	tween.tween_callback(func() -> void:
		# Основная игра нарисована под растяжение 960×540, ASCII-ночь настраивает окно сама.
		if scene_path == MAIN_SCENE:
			get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		get_tree().change_scene_to_file(scene_path)
	)


func _build_audio() -> void:
	var looped := THEME_MUSIC.duplicate() as AudioStreamOggVorbis
	looped.loop = true
	# Вступление шкатулки звучит один раз, дальше петля идёт с начала главной темы.
	looped.loop_offset = THEME_LOOP_START
	music = AudioStreamPlayer.new()
	music.stream = looped
	music.bus = &"Music"
	music.volume_db = -4.0
	add_child(music)
	music.play()
