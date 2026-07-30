class_name SoulcyclePlayer
extends CharacterBody2D

signal character_changed(index: int)

const CharacterCatalog := preload("res://scripts/dialogue/character_catalog.gd")
const FRAME_SIZE := 64
const SPEED := 145.0

var can_move := true
var facing := "down"
var character_index := 0
var animated_sprite: AnimatedSprite2D


func _ready() -> void:
	add_to_group("player")
	collision_layer = 1
	collision_mask = 2
	_install_input_actions()
	_build_sprite()
	_build_collision()
	z_index = 10


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("switch_character_1"):
		switch_character(0)
	elif Input.is_action_just_pressed("switch_character_2"):
		switch_character(1)

	var direction := Vector2.ZERO
	if can_move:
		direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	velocity = direction * SPEED
	move_and_slide()
	_update_animation(direction)
	z_index = int(global_position.y)


func _build_sprite() -> void:
	animated_sprite = AnimatedSprite2D.new()
	animated_sprite.name = "AnimatedSprite2D"
	animated_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 64 px frames at 1× occupy the same screen area as the former 32 px
	# frames at 2×, but retain twice the source detail on each axis.
	animated_sprite.scale = Vector2.ONE
	var profile := CharacterCatalog.get_playable_profile(character_index)
	animated_sprite.sprite_frames = _create_sprite_frames(profile.world_sprite_sheet)
	animated_sprite.play("down")
	animated_sprite.pause()
	add_child(animated_sprite)


func _create_sprite_frames(texture: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var animation_names := ["down", "up", "left", "right"]

	for row in range(animation_names.size()):
		var animation_name: String = animation_names[row]
		frames.add_animation(animation_name)
		frames.set_animation_speed(animation_name, 7.0)
		frames.set_animation_loop(animation_name, true)
		for column in range(4):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(
				column * FRAME_SIZE,
				row * FRAME_SIZE,
				FRAME_SIZE,
				FRAME_SIZE
			)
			frames.add_frame(animation_name, atlas)
	return frames


func switch_character(new_index: int) -> void:
	if (
		new_index < 0
		or new_index >= CharacterCatalog.get_playable_count()
		or new_index == character_index
	):
		return

	character_index = new_index
	var profile := CharacterCatalog.get_playable_profile(character_index)
	animated_sprite.sprite_frames = _create_sprite_frames(profile.world_sprite_sheet)
	animated_sprite.play(facing)
	if velocity == Vector2.ZERO:
		animated_sprite.pause()
		animated_sprite.frame = 0
	character_changed.emit(character_index)


func _build_collision() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(22, 14)
	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	collider.position = Vector2(0, 20)
	collider.shape = shape
	add_child(collider)


func _update_animation(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		animated_sprite.pause()
		animated_sprite.frame = 0
		return

	if abs(direction.x) > abs(direction.y):
		facing = "right" if direction.x > 0 else "left"
	else:
		facing = "down" if direction.y > 0 else "up"

	if animated_sprite.animation != facing or not animated_sprite.is_playing():
		animated_sprite.play(facing)


func _install_input_actions() -> void:
	_add_key_to_action("move_left", KEY_A)
	_add_key_to_action("move_left", KEY_LEFT)
	_add_key_to_action("move_right", KEY_D)
	_add_key_to_action("move_right", KEY_RIGHT)
	_add_key_to_action("move_up", KEY_W)
	_add_key_to_action("move_up", KEY_UP)
	_add_key_to_action("move_down", KEY_S)
	_add_key_to_action("move_down", KEY_DOWN)
	_add_key_to_action("interact", KEY_E)
	_add_key_to_action("interact", KEY_SPACE)
	_add_key_to_action("interact", KEY_ENTER)
	_add_key_to_action("switch_character_1", KEY_1)
	_add_key_to_action("switch_character_1", KEY_KP_1)
	_add_key_to_action("switch_character_2", KEY_2)
	_add_key_to_action("switch_character_2", KEY_KP_2)


func _add_key_to_action(action_name: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and existing_event.physical_keycode == keycode:
			return

	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	InputMap.action_add_event(action_name, key_event)
