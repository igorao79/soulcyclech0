class_name SoulcycleSoulWheel
extends Control

const BattleCatalog := preload("res://scripts/battle/battle_catalog.gd")
const WHEEL_FONT := preload("res://assets/fonts/CormorantGaramond.ttf")

# Рассвет слева, Полдень сверху, Сумерки справа, Полночь снизу — путь солнца.
const START_ANGLE := PI
const STEP_ANGLE := PI * 0.5

var phase := 0
var pointer_angle := START_ANGLE
var flare := 0.0
var pulse := 0.0
var _steps := 0
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	pulse += delta
	flare = maxf(0.0, flare - delta * 1.6)
	queue_redraw()


func reset(start_phase: int) -> void:
	phase = start_phase
	_steps = start_phase
	pointer_angle = START_ANGLE + STEP_ANGLE * _steps


func rotate_by(steps: int) -> void:
	_steps += steps
	phase = wrapi(_steps, 0, BattleCatalog.PHASES.size())
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_BACK)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "pointer_angle", START_ANGLE + STEP_ANGLE * _steps, 0.42)


func flash() -> void:
	flare = 1.0


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 18.0
	var active_color: Color = BattleCatalog.get_phase(phase)["color"]

	var halo := active_color
	halo.a = 0.10 + sin(pulse * 1.8) * 0.03 + flare * 0.25
	draw_circle(center, radius + 14.0 + flare * 10.0, halo)
	draw_circle(center, radius + 4.0, Color(0.02, 0.025, 0.05, 0.88))

	for index in range(BattleCatalog.PHASES.size()):
		var data := BattleCatalog.get_phase(index)
		var color: Color = data["color"]
		var mid_angle := START_ANGLE + STEP_ANGLE * index
		var is_active := index == phase
		var segment_color := color
		segment_color.a = 1.0 if is_active else 0.28
		draw_arc(center, radius - 6.0, mid_angle - STEP_ANGLE * 0.5 + 0.06,
			mid_angle + STEP_ANGLE * 0.5 - 0.06, 24, segment_color, 11.0 if is_active else 7.0, true)

		var label_position := center + Vector2.from_angle(mid_angle) * (radius - 34.0)
		var font_size := 15 if is_active else 13
		var text: String = data["name"]
		var text_size := WHEEL_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var label_color := color if is_active else Color(0.72, 0.74, 0.82, 0.55)
		draw_string(WHEEL_FONT, label_position + Vector2(-text_size.x * 0.5, font_size * 0.35),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)

	for ring_index in range(3):
		var ring_color := active_color
		ring_color.a = 0.12 - ring_index * 0.03
		draw_arc(center, radius * (0.28 + ring_index * 0.1), 0.0, TAU, 40, ring_color, 1.5, true)

	_draw_soul_flame(center, radius * 0.24, active_color)

	var tip := center + Vector2.from_angle(pointer_angle) * (radius + 8.0)
	var base_left := center + Vector2.from_angle(pointer_angle - 0.11) * (radius - 16.0)
	var base_right := center + Vector2.from_angle(pointer_angle + 0.11) * (radius - 16.0)
	draw_colored_polygon(PackedVector2Array([tip, base_left, base_right]), Color("#f6efe3"))


func _draw_soul_flame(center: Vector2, flame_size: float, color: Color) -> void:
	var sway := sin(pulse * 3.1) * 0.12
	var height := flame_size * (1.25 + sin(pulse * 4.3) * 0.06 + flare * 0.3)
	var points := PackedVector2Array()
	for step in range(25):
		var t := float(step) / 24.0
		var angle := TAU * t
		# Капля: круглое основание и вытянутый вверх язык пламени.
		var bulge := 1.0 - maxf(0.0, -sin(angle)) * 0.55
		var x := cos(angle) * flame_size * 0.62 * bulge
		var y := sin(angle) * flame_size * 0.55
		if sin(angle) < 0.0:
			y = sin(angle) * height
			x += sway * flame_size * absf(sin(angle))
		points.append(center + Vector2(x, y + flame_size * 0.25))
	var outer := color
	outer.a = 0.85
	draw_colored_polygon(points, outer)

	var inner_points := PackedVector2Array()
	for point in points:
		inner_points.append(center + (point - center) * 0.52 + Vector2(0, flame_size * 0.14))
	draw_colored_polygon(inner_points, Color(1.0, 0.98, 0.93, 0.9))
