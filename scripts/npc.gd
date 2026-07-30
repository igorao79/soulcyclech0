class_name SoulcycleNpc
extends Area2D

signal dialogue_requested(sequence_id: StringName)

var player_is_near := false
var prompt: Polygon2D
var pulse := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	z_index = 8
	_build_trigger()
	_build_prompt()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	queue_redraw()


func _process(delta: float) -> void:
	pulse += delta
	z_index = int(global_position.y)
	if prompt != null and prompt.visible:
		var prompt_scale := 1.0 + sin(pulse * 4.0) * 0.12
		prompt.scale = Vector2(prompt_scale, prompt_scale)
	queue_redraw()


func _draw() -> void:
	var glow_strength := 0.10 + sin(pulse * 2.2) * 0.025
	draw_circle(Vector2(0, 4), 45.0, Color(0.58, 0.18, 0.22, glow_strength))
	draw_circle(Vector2(0, 16), 20.0, Color("#120f18"))
	draw_polygon(
		PackedVector2Array([
			Vector2(-23, 14), Vector2(-16, -14), Vector2(-8, -31),
			Vector2(8, -31), Vector2(16, -14), Vector2(23, 14)
		]),
		PackedColorArray([Color("#211b29")])
	)
	draw_circle(Vector2(0, -24), 10.0, Color("#d8c5ba"))
	draw_arc(Vector2(0, -24), 11.0, PI, TAU, 18, Color("#09080c"), 7.0)
	draw_circle(Vector2(-3.2, -23), 1.2, Color("#ad2633"))
	draw_circle(Vector2(3.2, -23), 1.2, Color("#ad2633"))
	draw_line(Vector2(-18, 15), Vector2(18, 15), Color("#7e2634"), 2.0)


func request_dialogue() -> void:
	dialogue_requested.emit(&"keeper_first_meeting")


func _build_trigger() -> void:
	var shape := CircleShape2D.new()
	shape.radius = 78.0
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)


func _build_prompt() -> void:
	prompt = Polygon2D.new()
	prompt.position = Vector2(0, -72)
	prompt.polygon = PackedVector2Array([
		Vector2(0, -7), Vector2(7, 0), Vector2(0, 7), Vector2(-7, 0)
	])
	prompt.color = Color("#f0c56b")
	prompt.visible = false
	add_child(prompt)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		set_player_near(true)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		set_player_near(false)


func set_player_near(value: bool) -> void:
	player_is_near = value
	if prompt != null:
		prompt.visible = value
