class_name SoulcycleChapterOne
extends Node

# Глава первая, «Звездопад». Заставка: Безымянный сидит на снежном склоне над озером,
# по небу летят звёзды. Потом он встаёт, поднимается по тропинке на плато и решает,
# что пора домой. Картинку рисует chapter_one.gdshader, здесь — время, камера, звук и текст.

const FontAtlas := preload("res://scripts/ascii/ascii_font_atlas.gd")
const SCREEN_SHADER := preload("res://scripts/chapter/chapter_one.gdshader")
const THEME_MUSIC := preload("res://assets/music/snowbound_crossroads.ogg")
const SNOW_STEPS: Array[AudioStream] = [
	preload("res://assets/audio/footsteps/snow_01.wav"),
	preload("res://assets/audio/footsteps/snow_02.wav"),
	preload("res://assets/audio/footsteps/snow_03.wav"),
]
const TITLE_SCENE := "res://scenes/title.tscn"

const BASE_FONT_SIZE := 8
const SIT_X := 2.4
const TOP_X := 15.0
const HOME_X := 28.5
const WALK_SPEED := 1.05
# Совпадает с GAIT_REACH * FIGURE_SCALE / GAIT_STANCE в ascii_figures.gdshaderinc.
const STEP_LENGTH := 0.68
# Сидя он смотрит на озеро и чуть от нас, наверху оборачивается к нам вполоборота.
const YAW_SIT := -2.1
const YAW_WALK := PI * 0.5
const YAW_LOOK_BACK := -0.93
const CUTSCENE_TIME := 13.0
const STAND_TIME := 1.9
const TURN_TIME := 0.9

const CHAPTER_LABEL := "Глава первая"
const CHAPTER_NAME := "Звездопад"
const SPEAKER := "Безымянный"
const LINES: Array[String] = [
	"Опять звездопад. Каждый год в эту ночь — и каждый раз будто впервые.",
	"…Уже совсем поздно. Пора закругляться.",
	"Дома, наверное, давно не спят и ждут. Пойду.",
]
const TYPE_SPEED := 36.0
const SCRAMBLE := "#%&@$*+=-:;!?/\\|<>~^"

enum Beat { CARD, SITTING, STANDING, TURNING, WALKING, LOOKING, DIALOGUE, LEAVING, ENDING }

const SILVER := Color(0.86, 0.89, 0.98)
const BONE := Color(0.95, 0.91, 0.84)
const TEXT := Color(0.72, 0.76, 0.88)
const EMBER := Color(1.0, 0.72, 0.42)
const RULE := Color(0.55, 0.58, 0.72)

var screen_material: ShaderMaterial
var overlay: Control
var serif: Font
var mono: Font
var music: AudioStreamPlayer
var step_player: AudioStreamPlayer
var random := RandomNumberGenerator.new()

var beat := Beat.CARD
var beat_time := 0.0
var elapsed := 0.0
var drawing := false

var hero_x := SIT_X
var hero_yaw := YAW_SIT
var sit := 1.0
var move := 0.0
var phase := 0.0
var lean := Vector2.ZERO
var cam := Vector2(SIT_X - 2.4, 1.3)
var view := 7.4
var fade := 1.0
var big_meteor_at := -1.0

var line_index := 0
var typed := 0.0
var end_alpha := 0.0


func _ready() -> void:
	random.randomize()
	get_tree().paused = false
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.title = "Цикл душ — Глава первая"
	serif = SoulcycleUiStyle.serif(600.0)
	mono = FontAtlas.create_font()
	_build_audio()
	var font_size := roundi(BASE_FONT_SIZE * DisplayServer.screen_get_scale())
	var cell := FontAtlas.measure_cell(mono, font_size)
	var atlas := await FontAtlas.build(self, mono, font_size, cell)
	_build_screen(atlas, cell)
	drawing = true


func _process(delta: float) -> void:
	if not drawing:
		return
	delta = minf(delta, 0.05)
	elapsed += delta
	beat_time += delta
	match beat:
		Beat.CARD:
			_card(delta)
		Beat.SITTING:
			_sitting(delta)
		Beat.STANDING:
			_standing()
		Beat.TURNING:
			_turning()
		Beat.WALKING:
			_walking(delta)
		Beat.LOOKING:
			_looking()
		Beat.DIALOGUE:
			typed = minf(typed + delta * TYPE_SPEED, LINES[line_index].length())
		Beat.LEAVING:
			_leaving(delta)
		Beat.ENDING:
			_ending()
	_follow_camera(delta)
	_push_uniforms()
	overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not drawing or not _is_advance(event):
		return
	if beat == Beat.SITTING and beat_time > 2.0:
		# Заставку можно пропустить: он просто встаёт раньше.
		_go(Beat.STANDING)
		get_viewport().set_input_as_handled()
	elif beat == Beat.DIALOGUE:
		var line := LINES[line_index]
		if typed < line.length():
			typed = line.length()
		elif line_index + 1 < LINES.size():
			line_index += 1
			typed = 0.0
		else:
			_go(Beat.LEAVING)
		get_viewport().set_input_as_handled()


func _is_advance(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		return key.physical_keycode in [KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		return true
	return event.is_action_pressed("ui_accept")


func _go(next: Beat) -> void:
	beat = next
	beat_time = 0.0


# --- Сцена по шагам --------------------------------------------------------

func _card(delta: float) -> void:
	fade = clampf(1.0 - (beat_time - 3.0) / 2.0, 0.0, 1.0)
	_breathe()
	if beat_time > 4.4:
		_go(Beat.SITTING)


# Он сидит и смотрит на небо; звёзды падают всё чаще, под конец — большой болид.
func _sitting(delta: float) -> void:
	fade = clampf(1.0 - (beat_time + 1.4) / 2.0, 0.0, 1.0)
	_breathe()
	if big_meteor_at < 0.0 and beat_time > CUTSCENE_TIME * 0.62:
		big_meteor_at = elapsed
	if beat_time > CUTSCENE_TIME:
		_go(Beat.STANDING)


func _standing() -> void:
	fade = 0.0
	var t := clampf(beat_time / STAND_TIME, 0.0, 1.0)
	sit = 1.0 - _ease(t)
	# Вставая, корпус уходит вперёд над стопами и выпрямляется.
	lean = Vector2(0.0, sin(t * PI) * 0.26)
	if t >= 1.0:
		_go(Beat.TURNING)


func _turning() -> void:
	var t := clampf(beat_time / TURN_TIME, 0.0, 1.0)
	hero_yaw = lerp_angle(YAW_SIT, YAW_WALK, _ease(t))
	lean = Vector2.ZERO
	if t >= 1.0:
		_go(Beat.WALKING)


# Подъём по тропинке: корпус наклонён в склон, шаг укорачивается на крутизне.
func _walking(delta: float) -> void:
	_step_forward(delta, TOP_X)
	if hero_x >= TOP_X - 0.01:
		_go(Beat.LOOKING)


func _looking() -> void:
	move = move_toward(move, 0.0, get_process_delta_time() * 3.0)
	lean = lean.lerp(Vector2.ZERO, 0.1)
	var t := clampf((beat_time - 0.4) / 1.2, 0.0, 1.0)
	hero_yaw = lerp_angle(YAW_WALK, YAW_LOOK_BACK, _ease(t))
	if beat_time > 1.9:
		line_index = 0
		typed = 0.0
		_go(Beat.DIALOGUE)


func _leaving(delta: float) -> void:
	var t := clampf(beat_time / TURN_TIME, 0.0, 1.0)
	hero_yaw = lerp_angle(YAW_LOOK_BACK, YAW_WALK, _ease(t))
	if t >= 1.0:
		_step_forward(delta, HOME_X)
	fade = clampf((beat_time - 3.2) / 2.0, 0.0, 1.0)
	if beat_time > 5.4:
		_go(Beat.ENDING)


func _ending() -> void:
	fade = 1.0
	end_alpha = clampf(beat_time / 0.8, 0.0, 1.0) * clampf((4.2 - beat_time) / 0.8, 0.0, 1.0)
	if beat_time > 4.4:
		set_process(false)
		get_tree().change_scene_to_file(TITLE_SCENE)


func _step_forward(delta: float, limit: float) -> void:
	move = move_toward(move, 1.0, delta * 2.5)
	var slope := (ground_height(hero_x + 0.3) - ground_height(hero_x - 0.3)) / 0.6
	var speed := WALK_SPEED * move / (1.0 + maxf(slope, 0.0) * 0.6)
	var before := Vector2(hero_x, ground_height(hero_x))
	hero_x = minf(hero_x + speed * delta, limit)
	var after := Vector2(hero_x, ground_height(hero_x))
	var previous_phase := phase
	phase += before.distance_to(after) * PI / STEP_LENGTH
	lean = lean.lerp(Vector2(0.0, 0.05 + clampf(slope, 0.0, 0.8) * 0.22) * move, 1.0 - exp(-delta * 4.0))
	if floori(phase / PI) != floori(previous_phase / PI):
		_play_step()


func _breathe() -> void:
	sit = 1.0
	move = 0.0
	lean = Vector2.ZERO


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


# Совпадает с ground_height в chapter_one.gdshader.
static func ground_height(x: float) -> float:
	var hill := 6.2 * smoothstep(-2.5, 17.0, x) - 0.45 + 0.10 * sin(x * 1.3) + 0.05 * sin(x * 3.7 + 1.0)
	return hill - 9.0 * (1.0 - smoothstep(-2.4, 0.6, x))


# --- Камера и шейдер -------------------------------------------------------

func _follow_camera(delta: float) -> void:
	var target := cam
	var target_view := view
	match beat:
		Beat.CARD, Beat.SITTING:
			# Заставка: камера медленно подходит к сидящему с высоты неба.
			var t := clampf((beat_time + (0.0 if beat == Beat.SITTING else -4.4)) / CUTSCENE_TIME, 0.0, 1.0)
			target = Vector2(SIT_X - 2.4, 1.3).lerp(Vector2(SIT_X - 0.9, 1.2), _ease(t))
			target_view = lerpf(7.4, 5.4, _ease(t))
			cam = target
			view = target_view
			return
		Beat.DIALOGUE, Beat.LOOKING:
			target = Vector2(hero_x - 1.0, ground_height(hero_x) + 1.3)
			target_view = 5.6
		_:
			target = Vector2(hero_x + 1.0, ground_height(hero_x) + 1.0)
			target_view = 6.0
	var k := 1.0 - exp(-delta * 2.2)
	cam = cam.lerp(target, k)
	view = lerpf(view, target_view, k)


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
	m.set_shader_parameter("coat_lag", Vector2(0.0, -0.12 * move))
	var rate := 0.55
	if beat == Beat.SITTING:
		rate = lerpf(0.6, 1.7, clampf(beat_time / CUTSCENE_TIME, 0.0, 1.0))
	m.set_shader_parameter("meteor_rate", rate)
	var aspect := get_viewport().get_visible_rect().size.aspect()
	m.set_shader_parameter(
		"big_meteor",
		Vector4(elapsed - big_meteor_at if big_meteor_at >= 0.0 else -1.0, aspect * 0.78, 0.02, 2.55)
	)


func _build_screen(atlas: Texture2D, cell: Vector2i) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
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
	layer.add_child(rect)

	var text_layer := CanvasLayer.new()
	text_layer.layer = 5
	add_child(text_layer)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	text_layer.add_child(overlay)
	get_window().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	screen_material.set_shader_parameter("screen_px", get_viewport().get_visible_rect().size)


# --- Текст поверх картинки -------------------------------------------------

func _draw_overlay() -> void:
	var size := overlay.get_rect().size
	var scale := size.y / SoulcycleUiStyle.LOGICAL_HEIGHT
	if beat == Beat.CARD or (beat == Beat.SITTING and beat_time < 0.1):
		var alpha := clampf((beat_time - 0.6) / 0.9, 0.0, 1.0) * clampf((4.2 - beat_time) / 0.9, 0.0, 1.0)
		_draw_card(size, scale, alpha)
	elif beat == Beat.DIALOGUE:
		_draw_dialogue(size, scale)
	elif beat == Beat.ENDING:
		_draw_spaced(serif, "продолжение следует", size * Vector2(0.5, 0.5), roundi(20 * scale), Color(SILVER, end_alpha), 0.18)


func _draw_card(size: Vector2, scale: float, alpha: float) -> void:
	if alpha <= 0.0:
		return
	_draw_spaced(serif, CHAPTER_LABEL, size * Vector2(0.5, 0.42), roundi(18 * scale), Color(SILVER, alpha * 0.8), 0.32)
	_draw_spaced(serif, CHAPTER_NAME, size * Vector2(0.5, 0.53), roundi(46 * scale), Color(BONE, alpha), 0.12)
	_draw_rule(Vector2(size.x * 0.5, size.y * 0.585), 70.0 * scale, scale, alpha)


# Диалог без рамки: имя антиквой, черта с ромбом, реплика моноширинной сеткой, как в меню.
func _draw_dialogue(size: Vector2, scale: float) -> void:
	var top := size.y * 0.7
	overlay.draw_polygon(
		PackedVector2Array([Vector2(0, top), Vector2(size.x, top), Vector2(size.x, size.y), Vector2(0, size.y)]),
		PackedColorArray([Color(0, 0, 0.01, 0.0), Color(0, 0, 0.01, 0.0), Color(0, 0, 0.01, 0.9), Color(0, 0, 0.01, 0.9)])
	)
	var block_w := size.x * 0.52
	var left := (size.x - block_w) * 0.5
	var name_size := roundi(17 * scale)
	var name_end := _draw_spaced_left(serif, SPEAKER, Vector2(left, size.y * 0.79), name_size, SILVER, 0.22)
	var rule_y := size.y * 0.79 + name_size * 0.45
	overlay.draw_line(Vector2(left, rule_y), Vector2(name_end, rule_y), Color(RULE, 0.8), 1.0)
	_draw_diamond(Vector2(name_end + name_size * 0.4, rule_y), name_size * 0.16, EMBER)

	var text_size := roundi(12 * scale)
	var advance := mono.get_char_size("M".unicode_at(0), text_size).x
	var columns := maxi(int(block_w / advance), 20)
	var line: String = LINES[line_index]
	var shown := int(typed)
	var y := size.y * 0.79 + text_size * 2.6
	var remaining := shown
	for row in _wrap(line, columns):
		var visible := row.substr(0, clampi(remaining, 0, row.length()))
		var x := left
		for i in range(visible.length()):
			var letter := visible[i]
			var color := TEXT
			# Две последние набранные буквы ещё мечутся, пока строка не допечатана.
			if shown < line.length() and i >= visible.length() - 2 and remaining <= row.length():
				letter = SCRAMBLE[(i * 7 + int(elapsed * 24.0)) % SCRAMBLE.length()]
				color = Color(0.78, 0.30, 0.36)
			mono.draw_string(overlay.get_canvas_item(), Vector2(x, y).floor(), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, color)
			x += advance
		remaining -= row.length() + 1
		y += text_size * 1.7
	if shown >= line.length():
		var pulse := 0.5 + 0.5 * sin(elapsed * 4.0)
		mono.draw_string(
			overlay.get_canvas_item(), Vector2(left + block_w - advance * 2.0, y).floor(), "»",
			HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, Color(EMBER, 0.4 + 0.6 * pulse)
		)


func _wrap(text: String, columns: int) -> PackedStringArray:
	var rows := PackedStringArray()
	var row := ""
	for word in text.split(" "):
		if row.length() + word.length() + 1 > columns and row != "":
			rows.append(row)
			row = word
		else:
			row = word if row == "" else row + " " + word
	rows.append(row)
	return rows


func _draw_spaced(font: Font, text: String, center: Vector2, font_size: int, color: Color, tracking: float) -> void:
	var width := _spaced_width(font, text, font_size, tracking)
	_draw_spaced_left(font, text, Vector2(center.x - width * 0.5, center.y), font_size, color, tracking)


func _draw_spaced_left(font: Font, text: String, origin: Vector2, font_size: int, color: Color, tracking: float) -> float:
	var x := origin.x
	for i in range(text.length()):
		font.draw_string(overlay.get_canvas_item(), Vector2(x, origin.y).floor(), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		x += font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + font_size * tracking
	return x - font_size * tracking


func _spaced_width(font: Font, text: String, font_size: int, tracking: float) -> float:
	var width := 0.0
	for i in range(text.length()):
		width += font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + font_size * tracking
	return width - font_size * tracking


func _draw_rule(mid: Vector2, reach: float, scale: float, alpha: float) -> void:
	var gap := 7.0 * scale
	overlay.draw_line(mid - Vector2(reach, 0), mid - Vector2(gap, 0), Color(RULE, 0.8 * alpha), 1.0)
	overlay.draw_line(mid + Vector2(gap, 0), mid + Vector2(reach, 0), Color(RULE, 0.8 * alpha), 1.0)
	_draw_diamond(mid, 3.5 * scale, Color(EMBER, alpha))


func _draw_diamond(mid: Vector2, tip: float, color: Color) -> void:
	overlay.draw_colored_polygon(
		PackedVector2Array([mid + Vector2(0, -tip), mid + Vector2(tip, 0), mid + Vector2(0, tip), mid + Vector2(-tip, 0)]),
		color
	)


# --- Звук ------------------------------------------------------------------

func _build_audio() -> void:
	var looped := THEME_MUSIC.duplicate() as AudioStreamOggVorbis
	looped.loop = true
	music = AudioStreamPlayer.new()
	music.stream = looped
	music.bus = &"Music"
	music.volume_db = -17.0
	add_child(music)
	music.play()
	step_player = AudioStreamPlayer.new()
	step_player.bus = &"SFX"
	add_child(step_player)


func _play_step() -> void:
	step_player.stream = SNOW_STEPS[random.randi_range(0, SNOW_STEPS.size() - 1)]
	step_player.pitch_scale = random.randf_range(0.95, 1.05)
	step_player.volume_db = random.randf_range(-13.0, -10.0)
	step_player.play()
