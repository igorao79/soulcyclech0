class_name SoulcycleBattlePips
extends Control

var total := 3
var filled := 0
var color := Color("#f1d27b")
var diamond := false


func _init(pip_total: int = 3, pip_color: Color = Color("#f1d27b"), use_diamonds: bool = false) -> void:
	total = pip_total
	color = pip_color
	diamond = use_diamonds
	custom_minimum_size = Vector2(pip_total * 18.0, 16.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_filled(value: int) -> void:
	filled = clampi(value, 0, total)
	queue_redraw()


func _draw() -> void:
	for index in range(total):
		var center := Vector2(8.0 + index * 18.0, size.y * 0.5)
		var is_filled := index < filled
		if diamond:
			var points := PackedVector2Array([
				center + Vector2(0, -6.5), center + Vector2(5.5, 0),
				center + Vector2(0, 6.5), center + Vector2(-5.5, 0),
			])
			if is_filled:
				draw_colored_polygon(points, color)
			points.append(points[0])
			draw_polyline(points, color.darkened(0.25), 1.5, true)
		else:
			if is_filled:
				draw_circle(center, 6.0, color)
			draw_arc(center, 6.0, 0.0, TAU, 20, color.darkened(0.25), 1.5, true)
