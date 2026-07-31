class_name SoulcycleTravelTransition
extends CanvasLayer

const TRAVEL_BACKGROUND := preload("res://assets/transitions/winter_forest_travel.png")
const ILLUSTRATED_WALK_FRAMES := [
	preload("res://assets/transitions/nameless_walk/frame_01.png"),
	preload("res://assets/transitions/nameless_walk/frame_02.png"),
	preload("res://assets/transitions/nameless_walk/frame_03.png"),
	preload("res://assets/transitions/nameless_walk/frame_04.png"),
	preload("res://assets/transitions/nameless_walk/frame_05.png"),
	preload("res://assets/transitions/nameless_walk/frame_06.png"),
	preload("res://assets/transitions/nameless_walk/frame_07.png"),
	preload("res://assets/transitions/nameless_walk/frame_08.png"),
]
const FOOTSTEP_SNOW := [
	preload("res://assets/audio/footsteps/snow_01.wav"),
	preload("res://assets/audio/footsteps/snow_02.wav"),
	preload("res://assets/audio/footsteps/snow_03.wav"),
]
const VIEWPORT_SIZE := Vector2(960, 540)
const TRAVEL_DURATION := 12.5
const STEP_INTERVAL := 0.73
const WALKER_START_X := -100.0
const WALKER_END_X := 1060.0
const WALKER_BASELINE_Y := 448.0
const WALKER_SCALE := 0.5

var root: Control
var background: TextureRect
var cold_veil: ColorRect
var black_cover: ColorRect
var walker: Node2D
var character_sprite: AnimatedSprite2D
var walker_shadow: Polygon2D
var snow: GPUParticles2D
var footstep_players: Array[AudioStreamPlayer] = []
var footstep_random := RandomNumberGenerator.new()
var footstep_voice := 0
var step_clock := 0.0
var walking := false


func _ready() -> void:
	layer = 90
	footstep_random.randomize()
	_build_visuals()
	_build_audio()
	visible = false
	set_process(true)


func _process(delta: float) -> void:
	if not walking:
		return

	step_clock += delta
	var frame_phase: float = float(character_sprite.frame) / float(
		maxi(character_sprite.sprite_frames.get_frame_count(&"walk") - 1, 1)
	)
	var shadow_pulse: float = 0.94 + sin(frame_phase * TAU * 2.0) * 0.06
	walker_shadow.scale = Vector2(1.0 / shadow_pulse, shadow_pulse)

	if step_clock >= STEP_INTERVAL:
		step_clock = fmod(step_clock, STEP_INTERVAL)
		_play_footstep()


func play(direction: int = 1) -> void:
	visible = true
	background.visible = true
	cold_veil.visible = true
	walker.visible = true
	snow.visible = true
	snow.emitting = true
	root.modulate = Color(1, 1, 1, 0)
	black_cover.color = Color(0.015, 0.02, 0.04, 0)
	background.scale = Vector2(1.055, 1.055)

	character_sprite.sprite_frames = _create_walk_frames()
	character_sprite.flip_h = direction < 0
	character_sprite.play(&"walk")
	walker.position = Vector2(
		WALKER_START_X if direction > 0 else WALKER_END_X,
		WALKER_BASELINE_Y
	)
	walker.scale = Vector2.ONE
	step_clock = 0.12
	walking = true

	var travel := create_tween().set_parallel(true)
	travel.tween_property(root, "modulate:a", 1.0, 0.35)
	travel.tween_property(
		walker,
		"position:x",
		WALKER_END_X if direction > 0 else WALKER_START_X,
		TRAVEL_DURATION
	).set_trans(Tween.TRANS_LINEAR)
	travel.tween_property(
		background,
		"scale",
		Vector2.ONE,
		TRAVEL_DURATION
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await travel.finished

	walking = false
	character_sprite.pause()
	var cover := create_tween()
	cover.tween_property(black_cover, "color:a", 1.0, 0.42)
	await cover.finished


func reveal_world() -> void:
	background.visible = false
	cold_veil.visible = false
	walker.visible = false
	snow.emitting = false
	snow.visible = false

	var reveal := create_tween()
	reveal.tween_property(black_cover, "color:a", 0.0, 0.62)
	await reveal.finished
	visible = false


func _build_visuals() -> void:
	root = Control.new()
	root.name = "TravelTransitionRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	background = TextureRect.new()
	background.name = "WinterForestBackground"
	background.texture = TRAVEL_BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.pivot_offset = VIEWPORT_SIZE * 0.5
	root.add_child(background)

	cold_veil = ColorRect.new()
	cold_veil.color = Color(0.07, 0.11, 0.24, 0.12)
	cold_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cold_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(cold_veil)

	_build_snow()
	_build_walker()

	black_cover = ColorRect.new()
	black_cover.name = "BlackCover"
	black_cover.color = Color(0.015, 0.02, 0.04, 0)
	black_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	black_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(black_cover)


func _build_walker() -> void:
	walker = Node2D.new()
	walker.name = "WalkingCharacter"
	root.add_child(walker)

	walker_shadow = Polygon2D.new()
	walker_shadow.name = "FootShadow"
	walker_shadow.position = Vector2(0, 1)
	walker_shadow.polygon = PackedVector2Array([
		Vector2(-30, -4),
		Vector2(30, -4),
		Vector2(42, 0),
		Vector2(30, 4),
		Vector2(-30, 4),
		Vector2(-42, 0),
	])
	walker_shadow.color = Color(0.015, 0.025, 0.06, 0.3)
	walker.add_child(walker_shadow)

	character_sprite = AnimatedSprite2D.new()
	character_sprite.name = "AnimatedWalker"
	character_sprite.position = Vector2(0, -117.5)
	character_sprite.scale = Vector2(WALKER_SCALE, WALKER_SCALE)
	character_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	walker.add_child(character_sprite)


func _build_snow() -> void:
	snow = GPUParticles2D.new()
	snow.name = "TravelSnow"
	snow.position = Vector2(VIEWPORT_SIZE.x * 0.5, -24)
	snow.amount = 170
	snow.lifetime = 6.0
	snow.preprocess = 6.0
	snow.visibility_rect = Rect2(-560, -60, 1120, 680)

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(535, 22, 1)
	material.direction = Vector3(-0.12, 1.0, 0)
	material.spread = 16.0
	material.gravity = Vector3(-4, 18, 0)
	material.initial_velocity_min = 12.0
	material.initial_velocity_max = 28.0
	material.scale_min = 1.0
	material.scale_max = 2.8
	material.color = Color(0.92, 0.95, 1.0, 0.62)
	snow.process_material = material
	root.add_child(snow)


func _build_audio() -> void:
	for voice_index in range(2):
		var footstep_player := AudioStreamPlayer.new()
		footstep_player.name = "TravelFootstep%d" % (voice_index + 1)
		footstep_player.volume_db = -5.5
		add_child(footstep_player)
		footstep_players.append(footstep_player)


func _play_footstep() -> void:
	var player := footstep_players[footstep_voice]
	footstep_voice = (footstep_voice + 1) % footstep_players.size()
	player.stream = FOOTSTEP_SNOW[
		footstep_random.randi_range(0, FOOTSTEP_SNOW.size() - 1)
	]
	player.pitch_scale = footstep_random.randf_range(0.98, 1.02)
	player.play()


func _create_walk_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"walk")
	frames.set_animation_speed(&"walk", 5.5)
	frames.set_animation_loop(&"walk", true)
	for frame_texture in ILLUSTRATED_WALK_FRAMES:
		frames.add_frame(&"walk", frame_texture)
	return frames
