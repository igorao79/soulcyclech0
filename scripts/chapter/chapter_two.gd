extends Node

# Глава вторая. Карточка главы, затем пробуждение в красной комнате храма от первого лица
# (temple_wake.gd): веки открываются, он садится в кровати, встаёт; на тумбочке ваза с цветком,
# за раздвижными дверями воин ведёт по коридору. Снаружи — двор в графике старой игры (old_yard.gd),
# бог поправляет оплошность дважды, и тот же двор наконец в настоящем ASCII-движке: летний день,
# воин ведёт к воротам. Потом «продолжение следует» и главный экран.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const FontAtlas := preload("res://scripts/ascii/ascii_font_atlas.gd")
const GlyphTitle := preload("res://scripts/ui/glyph_title.gd")
const Ornament := preload("res://scripts/ui/ornament.gd")
const TempleWake := preload("res://scripts/chapter/temple_wake.gd")
const OldYard := preload("res://scripts/chapter/old_yard.gd")
const AsciiDemo := preload("res://scripts/ascii/ascii_demo.gd")
const SaveBook := preload("res://scripts/save/save_book.gd")
const TITLE_SCENE := "res://scenes/title.tscn"

const BASE_FONT_SIZE := 8
const CHAPTER_LABEL := "глава II"
const CHAPTER_NAME := "Пробуждение"
const CARD_TIME := 4.4
# Настоящий двор: тропа воина, его ход и насколько он даёт отстать; как близко подойти к воротам.
const WARRIOR_END := Vector2(60.0, 72.0)
const WARRIOR_SPEED := 1.55
const WARRIOR_STEP := 0.72
const WARRIOR_WAIT := 6.5
const GATE_REACH := 4.0
const WARRIOR_LINES: Array[Dictionary] = [
	{"speaker": &"warrior", "text": "Что встал? Идём, к воротам."},
]

enum Beat { CARD, ROOM, YARD, TRUE_YARD, ENDING }

var beat := Beat.CARD
var beat_time := 0.0
var elapsed := 0.0
var overlay: Control
var curtain: ColorRect
var title: Control
var mono: Font
var temple: Node
var yard: Node
var demo: Node
var spoke := false
var warrior_at := Vector2(60.0, 36.0)
var warrior_yaw := 0.0
var warrior_phase := 0.0
var warrior_walk := 0.0
var shown := ""


func _ready() -> void:
	get_tree().paused = false
	SaveBook.reach_chapter(2)
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.title = "Цикл душ — Глава вторая"
	mono = FontAtlas.create_font()
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	curtain = ColorRect.new()
	curtain.color = Color(0.0, 0.0, 0.01, 1.0)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(curtain)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	layer.add_child(overlay)
	title = GlyphTitle.new()
	layer.add_child(title)
	# Для проверки: --temple-yard сразу выводит из ворот храма во двор.
	if "--temple-yard" in OS.get_cmdline_user_args():
		curtain.color.a = 0.0
		_start_yard()


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	elapsed += delta
	beat_time += delta
	match beat:
		Beat.CARD:
			if beat_time > CARD_TIME:
				# Под карточкой уже темно: пробуждение начинается с закрытых век.
				curtain.color.a = 0.0
				temple = TempleWake.new()
				temple.finished.connect(_start_yard)
				add_child(temple)
				_go(Beat.ROOM)
		Beat.TRUE_YARD:
			_true_yard(delta)
		Beat.ENDING:
			curtain.color.a = 1.0
			if demo != null:
				demo.queue_free()
				demo = null
			if beat_time > 5.0:
				set_process(false)
				get_tree().change_scene_to_file(TITLE_SCENE)
	overlay.queue_redraw()


# Храм уже погас: снаружи та же темнота, из неё проступает двор.
func _start_yard() -> void:
	if temple != null:
		temple.queue_free()
		temple = null
	yard = OldYard.new()
	yard.second_try.connect(_prepare_true_yard)
	yard.finished.connect(_start_true_yard)
	add_child(yard)
	_go(Beat.YARD)


# Бог всё-таки нашёл нужную игру: тот же двор, тот же воин, но уже движком первой главы.
# Он собирается заранее под кашей старого двора, чтобы та могла прогореть сразу после реплики.
func _prepare_true_yard() -> void:
	demo = AsciiDemo.new()
	demo.world_layout = &"temple_yard"
	demo.chapter_mode = true
	add_child(demo)
	yard.waiting_for = demo


func _start_true_yard() -> void:
	yard.queue_free()
	yard = null
	_go(Beat.TRUE_YARD)


func _true_yard(delta: float) -> void:
	if not spoke and beat_time > 0.8:
		spoke = true
		demo.say(WARRIOR_LINES)
	var talking: bool = not spoke or not demo.dialogue_lines.is_empty()
	var hero: Vector2 = demo.player_position
	var lagging := hero.distance_to(warrior_at) > WARRIOR_WAIT
	var moving := not talking and not lagging and warrior_at != WARRIOR_END
	warrior_walk = move_toward(warrior_walk, 1.0 if moving else 0.0, delta * 3.0)
	# К воротам идёт лицом к нам; стоя, оборачивается к Дэйлу и ждёт.
	warrior_yaw = lerp_angle(warrior_yaw, 0.0 if moving else PI, minf(delta * 4.0, 1.0))
	if moving:
		var step := WARRIOR_SPEED * delta
		warrior_at = warrior_at.move_toward(WARRIOR_END, step)
		warrior_phase += step * PI / WARRIOR_STEP
	demo.set_warrior(warrior_at, warrior_yaw, warrior_phase, warrior_walk)
	if warrior_at == WARRIOR_END and hero.distance_to(WARRIOR_END) < GATE_REACH:
		_go(Beat.ENDING)


func _go(next: Beat) -> void:
	beat = next
	beat_time = 0.0


func _notification(what: int) -> void:
	if (what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED) and title != null:
		title.visible = what == NOTIFICATION_UNPAUSED


func _draw_overlay() -> void:
	var size := overlay.get_rect().size
	var scale := size.y / UiStyle.LOGICAL_HEIGHT
	var cap := size.y / UiStyle.SERIF_CAP
	var want := ""
	var alpha := 0.0
	if beat == Beat.CARD:
		want = "card"
		alpha = clampf((beat_time - 0.4) / 0.6, 0.0, 1.0) * clampf((CARD_TIME - 0.2 - beat_time) / 0.9, 0.0, 1.0)
		Ornament.draw(overlay, mono, Vector2(size.x * 0.5, size.y * 0.6),
			size.y * 0.16 * clampf((beat_time - 1.4) / 0.8, 0.0, 1.0), roundi(9 * scale), alpha, elapsed)
	elif beat == Beat.ENDING:
		want = "end"
		alpha = clampf((beat_time - 0.8) / 0.8, 0.0, 1.0) * clampf((4.6 - beat_time) / 0.8, 0.0, 1.0)
	if want != shown:
		shown = want
		var lines: Array[Dictionary] = []
		if want == "card":
			lines.append({"text": CHAPTER_LABEL, "size": roundi(cap * 0.04), "center": size * Vector2(0.5, 0.42), "small": true, "kind": GlyphTitle.DIM})
			lines.append({"text": CHAPTER_NAME, "size": roundi(cap * 0.1), "center": size * Vector2(0.5, 0.55), "tracking": 0.06})
		elif want == "end":
			lines.append({"text": "продолжение следует", "size": roundi(cap * 0.05), "center": size * Vector2(0.5, 0.52), "small": true})
		title.set_lines(lines)
		title.restart()
	title.fade = alpha
