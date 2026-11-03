extends Node

# Глава вторая. Карточка главы, затем пробуждение в красной комнате храма от первого лица
# (temple_wake.gd): веки открываются, он садится, встаёт; меч в столбе света на помосте,
# выйти через раздвижные двери. Потом «продолжение следует» и главный экран.

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const FontAtlas := preload("res://scripts/ascii/ascii_font_atlas.gd")
const GlyphTitle := preload("res://scripts/ui/glyph_title.gd")
const Ornament := preload("res://scripts/ui/ornament.gd")
const TempleWake := preload("res://scripts/chapter/temple_wake.gd")
const TITLE_SCENE := "res://scenes/title.tscn"

const BASE_FONT_SIZE := 8
const CHAPTER_LABEL := "глава II"
const CHAPTER_NAME := "Пробуждение"
const CARD_TIME := 4.4

enum Beat { CARD, ROOM, ENDING }

var beat := Beat.CARD
var beat_time := 0.0
var elapsed := 0.0
var overlay: Control
var curtain: ColorRect
var title: Control
var mono: Font
var temple: Node
var shown := ""


func _ready() -> void:
	get_tree().paused = false
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
				temple.finished.connect(func() -> void: _go(Beat.ENDING))
				add_child(temple)
				_go(Beat.ROOM)
		Beat.ENDING:
			curtain.color.a = 1.0
			if temple != null:
				temple.queue_free()
				temple = null
			if beat_time > 5.0:
				set_process(false)
				get_tree().change_scene_to_file(TITLE_SCENE)
	overlay.queue_redraw()


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
