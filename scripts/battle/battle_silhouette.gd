class_name SoulcycleBattleSilhouette
extends Control

var accent_color := Color("#8eb5cf")
var pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	pulse += delta
	queue_redraw()


func _draw() -> void:
	var glow := accent_color
	glow.a = 0.11 + sin(pulse * 2.2) * 0.025
	draw_circle(size * Vector2(0.5, 0.48), size.x * 0.31, glow)

	var center := size * Vector2(0.5, 0.50)
	var body_color := Color(0.025, 0.035, 0.065, 0.96)
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
	draw_line(center + Vector2(-17, -58), center + Vector2(-5, -58), accent_color, 4.0)
	draw_line(center + Vector2(5, -58), center + Vector2(17, -58), accent_color, 4.0)

	for ring_index in range(3):
		var radius := 52.0 + ring_index * 16.0
		var ring_color := accent_color
		ring_color.a = 0.20 - ring_index * 0.045
		draw_arc(center + Vector2(0, -7), radius, 0.12, PI - 0.12, 40, ring_color, 2.0)
