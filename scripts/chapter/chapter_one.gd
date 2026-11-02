class_name SoulcycleChapterOne
extends Node

# Глава первая, «Звездопад».
# 1. Заставка сбоку (chapter_one.gdshader): Безымянный сидит на снежном склоне над озером,
#    над ним идёт звездопад. Под конец болид, он встаёт.
# 2. Вид сверху со свободным управлением (движок ASCII-ночи, раскладка «тропа у озера»):
#    он стоит на тропе у воды, решает, что пора домой, и игрок ведёт его через ельник к дому.
# 3. У дома кадр гаснет: «продолжение следует», возврат на главный экран.

const FontAtlas := preload("res://scripts/ascii/ascii_font_atlas.gd")
const AsciiDemo := preload("res://scripts/ascii/ascii_demo.gd")
const SCREEN_SHADER := preload("res://scripts/chapter/chapter_one.gdshader")
const THEME_MUSIC := preload("res://assets/music/snowbound_crossroads.ogg")
const TITLE_SCENE := "res://scenes/title.tscn"

const BASE_FONT_SIZE := 8
const SIT_X := 2.4
# Сидя он смотрит на озеро и чуть от нас.
const YAW_SIT := -2.1
const CUTSCENE_TIME := 15.0
const STAND_TIME := 2.0
const TO_TOP_TIME := 1.4
const HOME_REACH := 4.0

const CHAPTER_LABEL := "Глава первая"
const CHAPTER_NAME := "Звездопад"
const LINES: Array[Dictionary] = [
	{"speaker": &"nameless", "text": "Опять звездопад. Каждый год в эту ночь — и каждый раз будто впервые."},
	{"speaker": &"nameless", "text": "…Уже совсем поздно. Пора закругляться."},
	{"speaker": &"nameless", "text": "Тропа к дому — через ельник, вверх по склону. Пойду."},
]

enum Beat { CARD, SITTING, STANDING, TO_TOP, TOP, ENDING }

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
var demo: SoulcycleAsciiDemo

var beat := Beat.CARD
var beat_time := 0.0
var elapsed := 0.0
var drawing := false
var sit := 1.0
var lean := Vector2.ZERO
var cam := Vector2(SIT_X - 2.4, 1.3)
var view := 7.4
var fade := 1.0
var big_meteor_at := -1.0
var spoke := false
var end_alpha := 0.0


func _ready() -> void:
	get_tree().paused = false
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.title = "Цикл душ — Глава первая"
	serif = SoulcycleUiStyle.serif(600.0)
	_build_audio()
	var mono := FontAtlas.create_font()
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
		Beat.TO_TOP:
			_to_top()
		Beat.TOP:
			_top()
		Beat.ENDING:
			_ending()
	if screen_material != null:
		_follow_camera()
		_push_uniforms()
	overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not drawing or beat != Beat.SITTING or beat_time < 2.0:
		return
	var key := event as InputEventKey
	var skip := key != null and key.pressed and not key.echo and key.physical_keycode in [KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	if skip or event.is_action_pressed("ui_accept"):
		# Заставку можно пропустить: он просто встаёт раньше.
		_go(Beat.STANDING)
		get_viewport().set_input_as_handled()


func _go(next: Beat) -> void:
	beat = next
	beat_time = 0.0


# Вставая, корпус уходит вперёд над стопами и выпрямляется.
func _standing() -> void:
	fade = 0.0
	var t := clampf(beat_time / STAND_TIME, 0.0, 1.0)
	sit = 1.0 - _ease(t)
	lean = Vector2(0.0, sin(t * PI) * 0.26)
	if beat_time > STAND_TIME + 0.6:
		_go(Beat.TO_TOP)


# Кадр гаснет, а в темноте уже собирается вид сверху: та же ночь, тот же берег.
func _to_top() -> void:
	fade = clampf(beat_time / TO_TOP_TIME, 0.0, 1.0)
	if beat_time >= TO_TOP_TIME and demo == null:
		curtain.color.a = 1.0
		screen_layer.queue_free()
		screen_material = null
		demo = AsciiDemo.new()
		demo.world_layout = &"lake_trail"
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
	var door := demo.world.chapel + Vector2(0.0, 5.0)
	if spoke and demo.dialogue_lines.is_empty() and demo.player_position.distance_to(door) < HOME_REACH:
		_go(Beat.ENDING)


func _ending() -> void:
	curtain.color.a = clampf(beat_time / 1.8, 0.0, 1.0)
	music.volume_db = lerpf(-17.0, -40.0, clampf(beat_time / 5.5, 0.0, 1.0))
	end_alpha = clampf((beat_time - 1.8) / 0.8, 0.0, 1.0) * clampf((5.6 - beat_time) / 0.8, 0.0, 1.0)
	if beat_time > 6.0:
		set_process(false)
		get_tree().change_scene_to_file(TITLE_SCENE)


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


# Совпадает с ground_height в chapter_one.gdshader.
static func ground_height(x: float) -> float:
	var hill := 6.2 * smoothstep(-2.5, 17.0, x) - 0.45 + 0.10 * sin(x * 1.3) + 0.05 * sin(x * 3.7 + 1.0)
	return hill - 9.0 * (1.0 - smoothstep(-2.4, 0.6, x))


# Заставка: камера медленно подходит к сидящему от неба; когда он встаёт — чуть выше.
func _follow_camera() -> void:
	var t := 1.0
	if beat == Beat.CARD:
		t = 0.0
	elif beat == Beat.SITTING:
		t = _ease(clampf(beat_time / CUTSCENE_TIME, 0.0, 1.0))
	cam = Vector2(SIT_X - 2.4, 1.3).lerp(Vector2(SIT_X - 0.9, 1.25), t)
	view = lerpf(7.4, 5.4, t)


func _push_uniforms() -> void:
	var m := screen_material
	m.set_shader_parameter("time", elapsed)
	m.set_shader_parameter("cam_center", cam)
	m.set_shader_parameter("view_height", view)
	m.set_shader_parameter("fade", fade)
	m.set_shader_parameter("player_pos", Vector3(SIT_X, ground_height(SIT_X), 0.0))
	m.set_shader_parameter("player_yaw", YAW_SIT)
	m.set_shader_parameter("player_phase", 0.0)
	m.set_shader_parameter("player_move", 0.0)
	m.set_shader_parameter("player_lean", lean)
	m.set_shader_parameter("player_sit", sit)
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
	get_window().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	if screen_material != null:
		screen_material.set_shader_parameter("screen_px", get_viewport().get_visible_rect().size)


func _draw_overlay() -> void:
	var size := overlay.get_rect().size
	var scale := size.y / SoulcycleUiStyle.LOGICAL_HEIGHT
	if beat == Beat.CARD:
		var alpha := clampf((beat_time - 0.6) / 0.9, 0.0, 1.0) * clampf((4.2 - beat_time) / 0.9, 0.0, 1.0)
		if alpha > 0.0:
			_draw_spaced(CHAPTER_LABEL, size * Vector2(0.5, 0.42), roundi(18 * scale), Color(SILVER, alpha * 0.8), 0.32)
			_draw_spaced(CHAPTER_NAME, size * Vector2(0.5, 0.53), roundi(46 * scale), Color(BONE, alpha), 0.12)
			_draw_rule(Vector2(size.x * 0.5, size.y * 0.585), 70.0 * scale, scale, alpha)
	elif beat == Beat.ENDING and end_alpha > 0.0:
		_draw_spaced("продолжение следует", size * Vector2(0.5, 0.5), roundi(20 * scale), Color(SILVER, end_alpha), 0.18)


func _draw_spaced(text: String, center: Vector2, font_size: int, color: Color, tracking: float) -> void:
	var width := 0.0
	for i in range(text.length()):
		width += serif.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + font_size * tracking
	width -= font_size * tracking
	var x := center.x - width * 0.5
	for i in range(text.length()):
		serif.draw_string(overlay.get_canvas_item(), Vector2(x, center.y).floor(), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		x += serif.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + font_size * tracking


func _draw_rule(mid: Vector2, reach: float, scale: float, alpha: float) -> void:
	var gap := 7.0 * scale
	overlay.draw_line(mid - Vector2(reach, 0), mid - Vector2(gap, 0), Color(RULE, 0.8 * alpha), 1.0)
	overlay.draw_line(mid + Vector2(gap, 0), mid + Vector2(reach, 0), Color(RULE, 0.8 * alpha), 1.0)
	var tip := 3.5 * scale
	overlay.draw_colored_polygon(
		PackedVector2Array([mid + Vector2(0, -tip), mid + Vector2(tip, 0), mid + Vector2(0, tip), mid + Vector2(-tip, 0)]),
		Color(EMBER, alpha)
	)


func _build_audio() -> void:
	var looped := THEME_MUSIC.duplicate() as AudioStreamOggVorbis
	looped.loop = true
	music = AudioStreamPlayer.new()
	music.stream = looped
	music.bus = &"Music"
	music.volume_db = -17.0
	add_child(music)
	music.play()
