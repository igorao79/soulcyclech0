class_name SoulcycleBattleSilhouette
extends Control

var accent_color := Color("#8eb5cf")
var pulse := 0.0
var tolls := 0
var hit_flash := 0.0
var guarded := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	pulse += delta * (1.0 + tolls * 0.45)
	hit_flash = maxf(0.0, hit_flash - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var glow := accent_color.lerp(Color("#d9485f"), tolls / 3.0)
	glow.a = 0.11 + sin(pulse * 2.2) * 0.025 + tolls * 0.04
	draw_circle(size * Vector2(0.5, 0.48), size.x * (0.31 + tolls * 0.03), glow)

	var center := size * Vector2(0.5, 0.50)
	var body_color := Color(0.025, 0.035, 0.065, 0.96).lerp(Color.WHITE, hit_flash * 0.8)
	var edge_color := accent_color.darkened(0.18)

	draw_circle(center + Vector2(0, -56), 34.0, body_color)
	draw_arc(center + Vector2(0, -56), 36.0, 0.0, TAU, 48, edge_color, 3.0)
	draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(-66, 78),
			center + Vector2(-47, -30),
			center + Vector2(0, -18),
			center + Vector2(47, -30),
			center + Vector2(66, 78),
		]),
		body_color
	)

	draw_arc(center + Vector2(0, 6), 72.0, 0.18, PI - 0.18, 42, edge_color, 3.0)
	var eye_color := accent_color.lerp(Color("#ff6b7d"), tolls / 3.0)
	draw_line(center + Vector2(-17, -58), center + Vector2(-5, -58), eye_color, 4.0)
	draw_line(center + Vector2(5, -58), center + Vector2(17, -58), eye_color, 4.0)

	# Кольца звона расходятся тем сильнее, чем ближе набат.
	for ring_index in range(3 + tolls * 2):
		var radius := 52.0 + ring_index * 16.0 + fmod(pulse * 14.0, 16.0)
		var ring_color := glow
		ring_color.a = maxf(0.0, 0.26 - ring_index * 0.035)
		draw_arc(center + Vector2(0, -7), radius, 0.12, PI - 0.12, 40, ring_color, 2.0)

	if guarded:
		var shield := accent_color
		shield.a = 0.35 + sin(pulse * 5.0) * 0.1
		draw_arc(center + Vector2(0, -10), 98.0, -PI * 0.85, -PI * 0.15, 40, shield, 4.0, true)
