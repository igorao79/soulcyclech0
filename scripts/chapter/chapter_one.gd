class_name SoulcycleChapterOne
extends Node

# Свои скрипты подключены по пути, а не по имени класса: игра, запущенная без редактора,
# не всегда знает новые глобальные классы, и сцена падала при переходе.
const UiStyle := preload("res://scripts/ui/ui_style.gd")
const DialogueView := preload("res://scripts/ui/dialogue_view.gd")
const GlyphTitle := preload("res://scripts/ui/glyph_title.gd")
const Ornament := preload("res://scripts/ui/ornament.gd")

# Глава первая, «Звездопад».
# 1. Заставка сбоку (chapter_one.gdshader): Безымянный сидит на снежном берегу острова над
#    океаном, над ним идёт звездопад. Под конец болид. Он тяжело встаёт, потягивается, оглядывается
#    на океан и небо, говорит пару слов — и неторопливо уходит по ровной тропе вдоль берега;
#    камера ведёт его, и кадр гаснет.
# 2. Вид сверху со свободным управлением (движок ASCII-ночи, раскладка «тропа на острове»):
#    он стоит на тропе у воды, вспоминает о смене в библиотеке, и игрок ведёт его через
#    ельник в городок с каменными домиками, по улице к библиотеке.
# 3. Библиотека изнутри (library_scene.gd): взять книгу с полки, сесть за стол — видение.
# 4. Видение гаснет, и сразу начинается вторая глава.

const FontAtlas := preload("res://scripts/ascii/ascii_font_atlas.gd")
const AsciiDemo := preload("res://scripts/ascii/ascii_demo.gd")
const LibraryScene := preload("res://scripts/chapter/library_scene.gd")
const SaveBook := preload("res://scripts/save/save_book.gd")
const SCREEN_SHADER := preload("res://scripts/chapter/chapter_one.gdshader")
# Зимняя тема собрана генератором tools/compose_winter_theme.py: петля начинается после вступления.
const THEME_MUSIC := preload("res://assets/music/snowbound_crossroads.ogg")
const THEME_LOOP_START := 4 * 3 * 60.0 / 66.0
const TITLE_SCENE := "res://scenes/title.tscn"
# После видения — вторая глава.
const NEXT_SCENE := "res://scenes/chapter_two.tscn"

const BASE_FONT_SIZE := 8
const SIT_X := 2.4
# Сидя он смотрит на океан и чуть от нас.
const YAW_SIT := -2.1
const CUTSCENE_TIME := 15.0
const STAND_TIME := 2.9
const STRETCH_TIME := 2.8
const LOOK_TIME := 1.6
const TO_TOP_TIME := 1.4
const TURN_TIME := 1.5
const WALK_SPEED := 0.95
# Совпадает с GAIT_REACH * FIGURE_SCALE / GAIT_STANCE в ascii_figures.gdshaderinc.
const STEP_LENGTH := 0.68
# Шаг звучит чуть раньше касания: у записи удар не в самом начале, плюс задержка звука.
const STEP_LEAD := 0.35
# Идёт вправо, вполоборота к нам; оглядываясь, смотрит на нас и чуть вверх, на небо.
const YAW_WALK := PI * 0.5 - 0.35
const YAW_LOOK := -0.55
const WALK_TIME := 6.5
const SNOW_STEPS: Array[AudioStream] = [
	preload("res://assets/audio/footsteps/snow_01.wav"),
	preload("res://assets/audio/footsteps/snow_02.wav"),
	preload("res://assets/audio/footsteps/snow_03.wav"),
]
const DOOR_REACH := 2.2
const TO_LIBRARY_TIME := 1.4

const CHAPTER_LABEL := "глава I"
const CHAPTER_NAME := "Звездопад"
# На берегу, встав и оглянувшись на небо.
const SHORE_LINES: Array[String] = [
	"…Падают. А загадать всё так же нечего.",
	"Пора.",
]
# Сверху, на тропе.
const LINES: Array[Dictionary] = [
	{"speaker": &"nameless", "text": "Смена в библиотеке до рассвета. Через ельник — успею."},
]

enum Beat { CARD, SITTING, STANDING, STRETCH, LOOK, TALK, TURNING, WALKING, TO_TOP, TOP, TO_LIBRARY, LIBRARY }

const SILVER := Color(0.86, 0.89, 0.98)
const BONE := Color(0.95, 0.91, 0.84)
const EMBER := Color(1.0, 0.72, 0.42)
const RULE := Color(0.55, 0.58, 0.72)

var screen_layer: CanvasLayer
var screen_material: ShaderMaterial
var overlay: Control
var curtain: ColorRect
var serif: Font
var music: AudioStreamPlayer
var demo: AsciiDemo
var library: Node
var card_title: Control
var card_shown := ""
var music_tween: Tween

var beat := Beat.CARD
var beat_time := 0.0
var elapsed := 0.0
var drawing := false
var sit := 1.0
var lean := Vector2.ZERO
var hero_x := SIT_X
var hero_yaw := YAW_SIT
var phase := 0.0
var move := 0.0
var step_player: AudioStreamPlayer
var stretch := 0.0
var mono_font: Font
var shore_line := 0
var shore_typed := 0.0
var turn_from := YAW_SIT
var cam := Vector2(SIT_X - 2.4, 1.3)
var view := 7.4
var fade := 1.0
var big_meteor_at := -1.0
var spoke := false


func _ready() -> void:
	get_tree().paused = false
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.title = "Цикл душ — Глава первая"
	serif = UiStyle.serif(600.0)
	_build_audio()
	var mono := FontAtlas.create_font()
	mono_font = mono
	var font_size := roundi(BASE_FONT_SIZE * DisplayServer.screen_get_scale())
	var cell := FontAtlas.measure_cell(mono, font_size)
	var atlas := await FontAtlas.build(self, mono, font_size, cell)
	_build_screen(atlas, cell)
	drawing = true
	# «Продолжить» с главного экрана: путь вписан в том у стола — сразу в библиотеку.
	if SaveBook.resume_place == &"library":
		SaveBook.resume_place = &""
		screen_layer.queue_free()
		screen_material = null
		if music_tween != null:
			music_tween.kill()
		music.volume_db = -26.0
		_enter_library()


func _process(delta: float) -> void:
	if not drawing:
		return
	delta = minf(delta, 0.05)
	elapsed += delta
	beat_time += delta
	match beat:
		Beat.CARD:
			fade = clampf(1.0 - (beat_time - 3.0) / 2.0, 0.0, 1.0)
			if beat_time > 4.4:
				_go(Beat.SITTING)
		Beat.SITTING:
			fade = clampf(1.0 - (beat_time + 1.4) / 2.0, 0.0, 1.0)
			if big_meteor_at < 0.0 and beat_time > CUTSCENE_TIME * 0.66:
				big_meteor_at = elapsed
			if beat_time > CUTSCENE_TIME:
				_go(Beat.STANDING)
		Beat.STANDING:
			_standing()
		Beat.STRETCH:
			_stretching()
		Beat.LOOK:
			_looking()
		Beat.TALK:
			shore_typed = minf(shore_typed + delta * 36.0, SHORE_LINES[shore_line].length())
		Beat.TURNING:
			_turning()
		Beat.WALKING:
			_walking(delta)
		Beat.TO_TOP:
			_to_top()
		Beat.TOP:
			_top()
		Beat.TO_LIBRARY:
			_to_library()
		Beat.LIBRARY:
			pass
	if screen_material != null:
		_follow_camera()
		_push_uniforms()
	overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var skip := key != null and key.pressed and not key.echo and key.physical_keycode in [KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	if drawing and beat == Beat.TALK and (skip or event.is_action_pressed("ui_accept")):
		get_viewport().set_input_as_handled()
		# Первое нажатие допечатывает реплику, второе листает дальше.
		if shore_typed < SHORE_LINES[shore_line].length():
			shore_typed = SHORE_LINES[shore_line].length()
			return
		shore_line += 1
		shore_typed = 0.0
		if shore_line >= SHORE_LINES.size():
			turn_from = hero_yaw
			_go(Beat.TURNING)
		return
	if not drawing or beat != Beat.SITTING or beat_time < 2.0:
		return
	if skip or event.is_action_pressed("ui_accept"):
		# Заставку можно пропустить: он просто встаёт раньше.
		_go(Beat.STANDING)
		get_viewport().set_input_as_handled()


# Пауза перерисовывает надписи: под меню их не видно, после паузы они возвращаются.
func _notification(what: int) -> void:
	if (what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED) and overlay != null:
		overlay.queue_redraw()
		if card_title != null:
			card_title.visible = what == NOTIFICATION_UNPAUSED


func _go(next: Beat) -> void:
	beat = next
	beat_time = 0.0


# Встаёт с усилием: сначала подаётся вперёд, перенося вес на ступни, потом поднимается,
# под конец чуть откидывается и выпрямляется.
func _standing() -> void:
	fade = 0.0
	var t := beat_time
	var rise := smoothstep(0.75, 2.3, t)
	sit = lerpf(1.0, 0.9, smoothstep(0.0, 0.75, t)) * (1.0 - rise)
	var forward := 0.34 * smoothstep(0.0, 0.8, t) * (1.0 - smoothstep(1.3, 2.4, t))
	var settle := -0.04 * sin(clampf((t - 2.2) / 0.7, 0.0, 1.0) * PI)
	lean = Vector2(0.0, forward + settle)
	if t > STAND_TIME:
		_go(Beat.STRETCH)


# Потягивается: руки над головой, прогибается, выдыхает и опускает руки.
func _stretching() -> void:
	var t := beat_time
	stretch = smoothstep(0.0, 1.0, t) * (1.0 - smoothstep(1.6, STRETCH_TIME, t))
	lean = Vector2(0.0, -0.05 * stretch)
	if t > STRETCH_TIME + 0.2:
		stretch = 0.0
		_go(Beat.LOOK)


# Оглядывается через плечо на океан и небо.
func _looking() -> void:
	var t := clampf(beat_time / LOOK_TIME, 0.0, 1.0)
	hero_yaw = lerp_angle(YAW_SIT, YAW_LOOK, _ease(t))
	lean = lean.lerp(Vector2.ZERO, 0.1)
	if beat_time > LOOK_TIME + 0.4:
		shore_line = 0
		shore_typed = 0.0
		_go(Beat.TALK)


# Разворот шагами, как человек: корпус поворачивается вслед за ногами, первые шаги
# короткие, почти на месте, и уже во второй половине поворота он трогается вперёд.
func _turning() -> void:
	var delta := get_process_delta_time()
	var t := clampf(beat_time / TURN_TIME, 0.0, 1.0)
	hero_yaw = lerp_angle(turn_from, YAW_WALK, _ease(t))
	move = move_toward(move, 0.4, delta * 1.2)
	var drift := WALK_SPEED * 0.35 * smoothstep(0.4, 1.0, t)
	var before := hero_x
	hero_x += drift * delta
	# Переступает: фаза шага идёт и без продвижения, но медленнее.
	var previous := phase
	phase += ((hero_x - before) * PI / STEP_LENGTH) + delta * 2.6 * (1.0 - smoothstep(0.5, 1.0, t))
	if floori((phase + STEP_LEAD) / PI) != floori((previous + STEP_LEAD) / PI):
		_play_step()
	lean = lean.lerp(Vector2(0.0, 0.03), 1.0 - exp(-delta * 3.0))
	if t >= 1.0:
		_go(Beat.WALKING)


# Уходит по ровному берегу; под конец кадр гаснет и открывается вид сверху.
func _walking(delta: float) -> void:
	# Разгоняется не сразу; шаг живой: скорость чуть плавает, корпус покачивается.
	move = move_toward(move, 1.0, delta * 0.7)
	var pace := 1.0 + 0.06 * sin(elapsed * 0.9) + 0.03 * sin(elapsed * 2.3 + 1.0)
	var before := hero_x
	hero_x += WALK_SPEED * move * pace * delta
	var previous := phase
	phase += (hero_x - before) * PI / STEP_LENGTH
	if floori((phase + STEP_LEAD) / PI) != floori((previous + STEP_LEAD) / PI):
		_play_step()
	var sway := 0.015 * sin(phase)
	lean = lean.lerp(Vector2(sway, 0.045 * move + 0.01 * sin(phase * 2.0)), 1.0 - exp(-delta * 4.0))
	# Голову и плечи чуть разворачивает к океану, пока идёт.
	hero_yaw = lerp_angle(hero_yaw, YAW_WALK - 0.08 * sin(elapsed * 0.4), 1.0 - exp(-delta * 2.0))
	if beat_time > WALK_TIME:
		_go(Beat.TO_TOP)


func _play_step() -> void:
	step_player.stream = SNOW_STEPS[randi() % SNOW_STEPS.size()]
	step_player.pitch_scale = randf_range(0.97, 1.02)
	step_player.volume_db = -14.0 + randf_range(-0.8, 0.8)
	step_player.play()


# Кадр гаснет, а в темноте уже собирается вид сверху: та же ночь, тот же берег.
func _to_top() -> void:
	fade = clampf(beat_time / TO_TOP_TIME, 0.0, 1.0)
	# Пока гаснет кадр, он ещё идёт.
	_walking_on(get_process_delta_time())
	if beat_time >= TO_TOP_TIME and screen_material != null:
		curtain.color.a = 1.0
		screen_layer.queue_free()
		screen_material = null
		demo = AsciiDemo.new()
		demo.world_layout = &"island_trail"
		demo.chapter_mode = true
		add_child(demo)
		_go(Beat.TOP)


func _top() -> void:
	if not demo.ready_to_play:
		beat_time = 0.0
		return
	curtain.color.a = clampf(1.0 - beat_time / 1.6, 0.0, 1.0)
	if not spoke and beat_time > 1.8:
		spoke = true
		demo.say(LINES)
	# Дверь библиотеки — в торце башни, к югу.
	var door := demo.world.chapel + Vector2(0.0, 3.4)
	if spoke and demo.dialogue_lines.is_empty() and demo.player_position.distance_to(door) < DOOR_REACH:
		_go(Beat.TO_LIBRARY)


# У двери кадр гаснет, музыка улицы стихает, внутри — тишина библиотеки.
func _to_library() -> void:
	curtain.color.a = clampf(beat_time / TO_LIBRARY_TIME, 0.0, 1.0)
	music.volume_db = lerpf(-17.0, -26.0, clampf(beat_time / TO_LIBRARY_TIME, 0.0, 1.0))
	if beat_time >= TO_LIBRARY_TIME and demo != null:
		demo.queue_free()
		demo = null
		_enter_library()


func _enter_library() -> void:
	library = LibraryScene.new()
	library.music = music
	# Отложенно: смена сцены сразу убирает её из дерева, а библиотека ещё дорисовывает кадр.
	library.finished.connect(func() -> void: get_tree().change_scene_to_file.call_deferred(NEXT_SCENE))
	add_child(library)
	curtain.color.a = 0.0
	_go(Beat.LIBRARY)


func _walking_on(delta: float) -> void:
	var before := hero_x
	hero_x += WALK_SPEED * move * delta
	var previous := phase
	phase += (hero_x - before) * PI / STEP_LENGTH
	if floori((phase + STEP_LEAD) / PI) != floori((previous + STEP_LEAD) / PI) and fade < 0.7:
		_play_step()


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


# Совпадает с ground_height в chapter_one.gdshader.
static func ground_height(x: float) -> float:
	var bank := 0.9 * smoothstep(-1.5, 4.0, x) - 0.35 + 0.05 * sin(x * 0.9) + 0.025 * sin(x * 2.3 + 1.0)
	return bank - 9.0 * (1.0 - smoothstep(-2.4, 0.6, x))


# Заставка: камера медленно подходит к сидящему от неба; когда он идёт — ведёт его,
# чуть забегая вперёд.
func _follow_camera() -> void:
	var t := 1.0
	if beat == Beat.CARD:
		t = 0.0
	elif beat == Beat.SITTING:
		t = _ease(clampf(beat_time / CUTSCENE_TIME, 0.0, 1.0))
	var seated := Vector2(SIT_X - 2.4, 1.3).lerp(Vector2(SIT_X - 0.9, 1.25), t)
	if beat in [Beat.CARD, Beat.SITTING]:
		cam = seated
		view = lerpf(7.4, 5.4, t)
		return
	# Дальше камера плавно садится на героя и держит его в центре кадра.
	var k := 1.0 - exp(-get_process_delta_time() * 1.4)
	cam = cam.lerp(Vector2(hero_x + 0.15 * move, ground_height(hero_x) + 0.95), k)
	view = lerpf(view, 5.2, k)


func _push_uniforms() -> void:
	var m := screen_material
	m.set_shader_parameter("time", elapsed)
	m.set_shader_parameter("cam_center", cam)
	m.set_shader_parameter("view_height", view)
	m.set_shader_parameter("fade", fade)
	m.set_shader_parameter("player_pos", Vector3(hero_x, ground_height(hero_x), 0.0))
	m.set_shader_parameter("player_yaw", hero_yaw)
	m.set_shader_parameter("player_phase", phase)
	m.set_shader_parameter("player_move", move)
	m.set_shader_parameter("player_lean", lean)
	m.set_shader_parameter("player_sit", sit)
	m.set_shader_parameter("player_stretch", stretch)
	m.set_shader_parameter("coat_lag", Vector2.ZERO)
	# Звёзды падают всё чаще, пока он сидит.
	var rate := 0.7
	if beat == Beat.SITTING:
		rate = lerpf(0.8, 2.2, clampf(beat_time / CUTSCENE_TIME, 0.0, 1.0))
	m.set_shader_parameter("meteor_rate", rate)
	var aspect := get_viewport().get_visible_rect().size.aspect()
	m.set_shader_parameter(
		"big_meteor",
		Vector4(elapsed - big_meteor_at if big_meteor_at >= 0.0 else -1.0, aspect * 0.86, 0.02, 2.62)
	)


func _build_screen(atlas: Texture2D, cell: Vector2i) -> void:
	screen_layer = CanvasLayer.new()
	add_child(screen_layer)
	screen_material = ShaderMaterial.new()
	screen_material.shader = SCREEN_SHADER
	screen_material.set_shader_parameter("atlas_tex", atlas)
	screen_material.set_shader_parameter("cell_px", Vector2(cell))
	# Смотрителя в главе нет: уводим его подальше, чтобы швы ткани считались от героя.
	screen_material.set_shader_parameter("keeper_pos", Vector3(9999.0, 0.0, 9999.0))
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.material = screen_material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_layer.add_child(rect)

	# Затемнение и надписи поверх всего, в том числе поверх вида сверху.
	var top_layer := CanvasLayer.new()
	top_layer.layer = 50
	add_child(top_layer)
	curtain = ColorRect.new()
	curtain.color = Color(0.0, 0.0, 0.01, 0.0)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_layer.add_child(curtain)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	top_layer.add_child(overlay)
	# Карточка главы — знаками по форме букв, как заголовок игры.
	card_title = GlyphTitle.new()
	top_layer.add_child(card_title)
	get_window().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	if screen_material != null:
		screen_material.set_shader_parameter("screen_px", get_viewport().get_visible_rect().size)


func _draw_overlay() -> void:
	# Под паузой надписи главы не просвечивают сквозь меню.
	if get_tree().paused:
		return
	var size := overlay.get_rect().size
	var scale := size.y / UiStyle.LOGICAL_HEIGHT
	if beat == Beat.TALK:
		DialogueView.draw(
			overlay, mono_font, serif, "Безымянный", SILVER, SHORE_LINES[shore_line], int(shore_typed), elapsed
		)
	var cap := size.y / UiStyle.SERIF_CAP
	var shown := ""
	var alpha := 0.0
	if beat == Beat.CARD:
		alpha = clampf((beat_time - 0.4) / 0.6, 0.0, 1.0) * clampf((4.2 - beat_time) / 0.9, 0.0, 1.0)
		shown = "card"
		Ornament.draw(overlay, mono_font, Vector2(size.x * 0.5, size.y * 0.6),
			size.y * 0.16 * clampf((beat_time - 1.4) / 0.8, 0.0, 1.0), roundi(9 * scale), alpha, elapsed)
	if card_title != null:
		if shown != card_shown:
			card_shown = shown
			var lines: Array[Dictionary] = []
			if shown == "card":
				lines.append({"text": CHAPTER_LABEL, "size": roundi(cap * 0.04), "center": size * Vector2(0.5, 0.42), "small": true, "kind": GlyphTitle.DIM})
				lines.append({"text": CHAPTER_NAME, "size": roundi(cap * 0.1), "center": size * Vector2(0.5, 0.55), "tracking": 0.06})
			card_title.set_lines(lines)
			card_title.restart()
		card_title.fade = alpha


func _build_audio() -> void:
	var looped := THEME_MUSIC.duplicate() as AudioStreamOggVorbis
	looped.loop = true
	looped.loop_offset = THEME_LOOP_START
	music = AudioStreamPlayer.new()
	music.stream = looped
	music.bus = &"Music"
	# Глава начинается под гул колокола с главного экрана: музыка входит тихо и нарастает.
	music.volume_db = -40.0
	add_child(music)
	music.play()
	step_player = AudioStreamPlayer.new()
	step_player.bus = &"SFX"
	add_child(step_player)
	_start_music()


func _start_music() -> void:
	if music_tween != null:
		music_tween.kill()
	music_tween = create_tween()
	music_tween.tween_property(music, "volume_db", -17.0, 6.0).set_delay(1.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
