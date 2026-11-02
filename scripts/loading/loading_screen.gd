class_name SoulcycleLoadingScreen
extends Node

# Загрузочный экран: сцена игры грузится в фоне, а на экране луна из символов
# набирает фазу вместе с прогрессом. Полная луна — всё готово: бьёт колокол,
# любая клавиша запускает ночь. Картинку рисует loading_screen.gdshader,
# надписи — этот скрипт, в ту же символьную сетку.

const FontAtlas := preload("res://scripts/ascii/ascii_font_atlas.gd")
const BellSynth := preload("res://scripts/audio/bell_synth.gd")
const SCREEN_SHADER := preload("res://scripts/loading/loading_screen.gdshader")

const TITLE_SCENE := "res://scenes/title.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const ASCII_SCENE := "res://scenes/ascii_demo.tscn"
# С флагами предпросмотра экран не ждёт клавишу: их запускают для снимков.
const PREVIEW_FLAGS: Array[String] = ["--dialogue-preview", "--battle-preview", "--travel-preview"]

const BASE_FONT_SIZE := 8
# Даже мгновенная загрузка показывает луну целиком: фаза растёт не быстрее этого.
const MIN_DURATION := 3.4
const INTRO_TIME := 1.1
const OUTRO_TIME := 1.25
const AUTO_CONTINUE := 1.8
const TOLL_FADE := 0.55
const LORE_PERIOD := 4.6
const TITLE := "S O U L C Y C L E"
const SUBTITLE := "ночь начинается сначала"
const SCRAMBLE_GLYPHS := "#%&@$*+=-:;!?/\\|"
const LORE: Array[String] = [
	"Колокол бьёт трижды — и ночь начинается сначала.",
	"Вода помнит каждого, кто в неё смотрел.",
	"Смотритель не спит. Он ждёт, пока ты вспомнишь.",
	"Безымянный не помнит имени. Имя помнит его.",
	"Чёрный цветок звенит только для тех, кто уже стоял у воды.",
]

var target_path := TITLE_SCENE
var skip_screen := false
var font: SystemFont
var font_size := BASE_FONT_SIZE
var cell := Vector2i(5, 8)
var grid := Vector2i(192, 67)

var screen_material: ShaderMaterial
var overlay: Control
var bell_player: AudioStreamPlayer
var bell_task := -1
var bell_stream: AudioStreamWAV

var elapsed := 0.0
var loaded := 0.0
var shown := 0.0
var load_failed := false
var ready_time := -1.0
var leaving := false
var outro := 0.0
var toll := 0.0
var bell_angle := 0.0
var bell_velocity := 0.0
var drawing := false
var saved_scale_mode := Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
var random := RandomNumberGenerator.new()


func _ready() -> void:
	random.randomize()
	var args := OS.get_cmdline_user_args()
	if "--ascii" in args:
		target_path = ASCII_SCENE
	elif "--main" in args:
		target_path = MAIN_SCENE
	for flag in PREVIEW_FLAGS:
		if flag in args:
			skip_screen = true

	if ResourceLoader.load_threaded_request(target_path) != OK:
		load_failed = true
	if skip_screen:
		return

	# Колокол синтезируется в фоне: полсекунды расчёта не должны подвешивать первый кадр.
	bell_task = WorkerThreadPool.add_task(func() -> void: bell_stream = BellSynth.create(0.94))
	bell_player = AudioStreamPlayer.new()
	bell_player.volume_db = -9.0
	bell_player.bus = &"SFX"
	add_child(bell_player)

	var window := get_window()
	saved_scale_mode = window.content_scale_mode
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	font_size = roundi(BASE_FONT_SIZE * DisplayServer.screen_get_scale())
	font = FontAtlas.create_font()
	cell = FontAtlas.measure_cell(font, font_size)
	var atlas := await FontAtlas.build(self, font, font_size, cell)
	_build_screen(atlas)
	window.size_changed.connect(_fit_screen)
	_fit_screen()
	drawing = true


func _process(delta: float) -> void:
	_poll_loading()
	if skip_screen:
		if loaded >= 1.0:
			_enter_game()
		return
	if not drawing:
		return

	elapsed += delta
	if bell_task >= 0 and WorkerThreadPool.is_task_completed(bell_task):
		WorkerThreadPool.wait_for_task_completion(bell_task)
		bell_task = -1
		bell_player.stream = bell_stream

	# Фаза догоняет настоящую загрузку плавно, но не обгоняет минимальное время показа.
	var allowed := minf(loaded, clampf((elapsed - INTRO_TIME * 0.5) / MIN_DURATION, 0.0, 1.0))
	shown = move_toward(shown, allowed, delta * 0.9)
	if ready_time < 0.0 and shown >= 1.0 and loaded >= 1.0:
		ready_time = elapsed
		_toll(1.6)
	# Полная луна держится мгновение, потом ночь начинается сама. Клавиша — не ждать.
	if ready_time >= 0.0 and not leaving and elapsed - ready_time > AUTO_CONTINUE:
		_leave()

	# Колокол — затухающий маятник, как в ASCII-ночи.
	bell_velocity += (-bell_angle * 7.0 - bell_velocity * 0.4) * delta
	bell_angle += bell_velocity * delta
	toll = maxf(toll - delta * TOLL_FADE, 0.0)
	# В покое колокол чуть покачивает ветер.
	var breeze := sin(elapsed * 0.7) * 0.05

	screen_material.set_shader_parameter("time", elapsed)
	screen_material.set_shader_parameter("progress", _ease(shown))
	screen_material.set_shader_parameter("intro", clampf(elapsed / INTRO_TIME, 0.0, 1.0))
	screen_material.set_shader_parameter("outro", outro)
	screen_material.set_shader_parameter("ready_glow", _ready_glow())
	screen_material.set_shader_parameter("bell_angle", bell_angle + breeze)
	screen_material.set_shader_parameter("toll", toll)
	overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if ready_time < 0.0 or leaving:
		return
	if not event.is_pressed() or event.is_echo():
		return
	if not (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton):
		return
	get_viewport().set_input_as_handled()
	_leave()


func _poll_loading() -> void:
	if load_failed:
		return
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(target_path, progress)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		loaded = maxf(loaded, float(progress[0]) if not progress.is_empty() else 0.0)
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		loaded = 1.0
	else:
		load_failed = true
		push_error("Soulcycle: не удалось загрузить %s" % target_path)


func _leave() -> void:
	leaving = true
	_toll(0.6)
	var tween := create_tween()
	tween.tween_property(self, "outro", 1.0, OUTRO_TIME).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(_enter_game)


func _enter_game() -> void:
	var scene := ResourceLoader.load_threaded_get(target_path) as PackedScene
	if scene == null:
		load_failed = true
		return
	set_process(false)
	if not skip_screen:
		get_window().content_scale_mode = saved_scale_mode
	get_tree().change_scene_to_packed(scene)


func _toll(strength: float) -> void:
	bell_velocity += strength if bell_angle <= 0.0 else -strength
	toll = 1.0
	if bell_player.stream != null:
		bell_player.pitch_scale = random.randf_range(0.97, 1.03)
		bell_player.play()


func _ready_glow() -> float:
	return 0.0 if ready_time < 0.0 else clampf((elapsed - ready_time) / 0.8, 0.0, 1.0)


# Начало и конец фазы медленнее середины: луна «набирается» и «дозревает».
func _ease(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)


func _build_screen(atlas: Texture2D) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	screen_material = ShaderMaterial.new()
	screen_material.shader = SCREEN_SHADER
	screen_material.set_shader_parameter("atlas_tex", atlas)
	screen_material.set_shader_parameter("cell_px", Vector2(cell))
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.material = screen_material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)

	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	layer.add_child(overlay)


func _fit_screen() -> void:
	var window_size := get_window().size
	grid = Vector2i(window_size.x / cell.x, window_size.y / cell.y)
	screen_material.set_shader_parameter("screen_px", Vector2(window_size))


func _draw_overlay() -> void:
	var fade := clampf((elapsed - 0.3) / 0.8, 0.0, 1.0) * (1.0 - clampf(outro * 2.5, 0.0, 1.0))
	if fade <= 0.0:
		return

	_decoded_line(grid.x / 2, 3, TITLE, 0.5, Color(0.90, 0.93, 1.0, fade))
	_decoded_line(grid.x / 2, 5, SUBTITLE, 1.1, Color(0.55, 0.62, 0.80, 0.9 * fade))

	var bottom := grid.y - 4
	if load_failed:
		_centered(grid.x / 2, bottom, "луна не взошла: сцену не удалось загрузить", Color(0.95, 0.35, 0.40, fade))
		return

	if ready_time < 0.0:
		var percent := "— %d —" % roundi(_ease(shown) * 100.0)
		_centered(grid.x / 2, bottom - 3, percent, Color(0.62, 0.68, 0.86, 0.8 * fade))
	else:
		var pulse := 0.55 + 0.45 * sin((elapsed - ready_time) * 3.0)
		var prompt := "ночь начинается…"
		_centered(grid.x / 2, bottom - 3, prompt, Color(0.96, 0.74, 0.44, pulse * fade))

	_draw_lore(grid.x / 2, bottom, fade)


# Строки предания сменяют друг друга: печатаются, держатся и растворяются.
func _draw_lore(col: int, row: int, fade: float) -> void:
	var since := elapsed - INTRO_TIME
	if since <= 0.0:
		return
	var index := int(since / LORE_PERIOD) % LORE.size()
	var moment := fmod(since, LORE_PERIOD)
	var text: String = LORE[index]
	var typed := mini(int(moment * 34.0), text.length())
	var alpha := clampf((LORE_PERIOD - moment) / 0.5, 0.0, 1.0) * fade
	var shown_text := text.substr(0, typed)
	# Две последние набранные буквы ещё мечутся, пока строка не допечатана.
	if typed < text.length():
		shown_text += _noise_char(index * 31 + typed) + _noise_char(index * 17 + typed + 3)
	var start := col - text.length() / 2
	_backing(start, row, text.length(), alpha)
	_text(start, row, shown_text, Color(0.74, 0.78, 0.90, alpha))


# Заголовок собирается из шума: каждая буква встаёт на место со своей задержкой.
func _decoded_line(col: int, row: int, text: String, delay: float, color: Color) -> void:
	var result := ""
	for index in range(text.length()):
		var settle := delay + index * 0.045
		var letter := text[index]
		if elapsed >= settle or letter == " ":
			result += letter
		else:
			result += _noise_char(index * 13 + int(elapsed * 22.0))
	var start := col - text.length() / 2
	_backing(start, row, text.length(), color.a)
	_text(start, row, result, color)


func _noise_char(seed_value: int) -> String:
	var index := posmod(seed_value * 7919 + int(elapsed * 18.0) * 31, SCRAMBLE_GLYPHS.length())
	return SCRAMBLE_GLYPHS[index]


func _centered(col: int, row: int, text: String, color: Color) -> void:
	var start := col - text.length() / 2
	_backing(start, row, text.length(), color.a)
	_text(start, row, text, color)


func _backing(start: int, row: int, length: int, alpha: float) -> void:
	overlay.draw_rect(
		Rect2(Vector2((start - 1) * cell.x, row * cell.y), Vector2((length + 2) * cell.x, cell.y)),
		Color(0.008, 0.01, 0.02, 0.8 * alpha)
	)


# Каждый знак встаёт ровно в ячейку той же сетки, что и луна под ним.
func _text(col: int, row: int, text: String, color: Color) -> void:
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var baseline := (cell.y + ascent - descent) * 0.5
	for index in range(text.length()):
		var code := text.unicode_at(index)
		var advance := font.get_char_size(code, font_size).x
		var origin := Vector2((col + index) * cell.x + (cell.x - advance) * 0.5, row * cell.y + baseline)
		font.draw_char(overlay.get_canvas_item(), origin.floor(), code, font_size, color)
