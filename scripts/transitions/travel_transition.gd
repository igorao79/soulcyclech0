class_name SoulcycleTravelTransition
extends CanvasLayer

const TRAVEL_BACKGROUND := preload("res://assets/transitions/winter_forest_travel.png")
const WALK_FRAMES_PATH := "res://assets/transitions/nameless_walk_v3/frame_%02d.png"
const FOOTSTEP_SNOW := [
	preload("res://assets/audio/footsteps/snow_01.wav"),
	preload("res://assets/audio/footsteps/snow_02.wav"),
	preload("res://assets/audio/footsteps/snow_03.wav"),
]
const VIEWPORT_SIZE := Vector2(960, 540)
const WALKER_START_X := -100.0
const WALKER_END_X := 1060.0
const WALKER_BASELINE_Y := 462.0
const WALKER_SCALE := 0.5
const MOONLIGHT_TINT := Color(0.76, 0.81, 0.98)

# Цикл ходьбы nameless_walk_v3 вырезан из сгенерированного видео: камера
# следовала за персонажем, поэтому кадры идут «на месте» (400×570, подошва
# на y=548). 26 кадров видео дополнены промежуточными по оптическому потоку
# до 52, чтобы при спокойном темпе анимация шла с частотой 30 кадров в секунду.
# Опорная стопа уходит назад с постоянной скоростью — WALK_ADVANCE пикселей
# кадра за кадр. Тело сдвигается ровно на столько же
# при каждой смене кадра, так что стопа стоит на снегу неподвижно.
# HEEL_STRIKES — кадры касания пятки и центр передней подошвы (след, звук).
const FRAME_SIZE := Vector2(400, 570)
const FRAME_SOLE_Y := 548.0
const WALK_FRAME_COUNT := 52
const WALK_FPS := 30.0
const WALK_ADVANCE := 9.275
const HEEL_STRIKES := {
	0: 318.0,
	26: 326.0,
}

signal walk_finished

var root: Control
var background: TextureRect
var cold_veil: ColorRect
var black_cover: ColorRect
var footprints: Node2D
var walker: Node2D
var character_sprite: AnimatedSprite2D
var walker_shadow: Polygon2D
var snow: GPUParticles2D
var footstep_players: Array[AudioStreamPlayer] = []
var footstep_random := RandomNumberGenerator.new()
var footstep_voice := 0
var walking := false
var walk_direction := 1
var walk_start_x := 0.0
var walk_end_x := 0.0
var frame_index := 0
var frame_time_left := 0.0


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

	frame_time_left -= delta
	while frame_time_left <= 0.0 and walking:
		# Тело проходит ровно тот путь, который опорная стопа прошла назад
		# за кадр, поэтому стопа остаётся на том же месте снега.
		walker.position.x += walk_direction * WALK_ADVANCE * WALKER_SCALE
		frame_index = (frame_index + 1) % WALK_FRAME_COUNT
		_show_frame(frame_index)
		frame_time_left += 1.0 / WALK_FPS

		var reached_end := walker.position.x >= walk_end_x if walk_direction > 0 else walker.position.x <= walk_end_x
		if reached_end:
			walking = false
			walk_finished.emit()


func play(direction: int = 1) -> void:
	visible = true
	background.visible = true
	cold_veil.visible = true
	walker.visible = true
	snow.visible = true
	snow.emitting = true
	root.modulate = Color(1, 1, 1, 0)
	black_cover.color = Color(0.015, 0.02, 0.04, 0)
	background.scale = Vector2(1.04, 1.04)
	for print_node in footprints.get_children():
		print_node.queue_free()

	walk_direction = 1 if direction >= 0 else -1
	if character_sprite.sprite_frames == null:
		character_sprite.sprite_frames = _create_walk_frames()
	character_sprite.animation = &"walk"
	character_sprite.flip_h = walk_direction < 0
	walk_start_x = WALKER_START_X if walk_direction > 0 else WALKER_END_X
	walk_end_x = WALKER_END_X if walk_direction > 0 else WALKER_START_X
	walker.position = Vector2(walk_start_x, WALKER_BASELINE_Y)
	frame_index = 0
	_show_frame(frame_index)
	frame_time_left = 1.0 / WALK_FPS
	walking = true

	var speed := WALK_ADVANCE * WALKER_SCALE * WALK_FPS
	var travel_duration := absf(walk_end_x - walk_start_x) / speed

	var intro := create_tween().set_parallel(true)
	intro.tween_property(root, "modulate:a", 1.0, 0.35)
	# Лёгкий наезд камеры с центром на линии земли, чтобы снег под ногами
	# не уплывал по вертикали.
	intro.tween_property(background, "scale", Vector2.ONE, travel_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await walk_finished

	var cover := create_tween()
	cover.tween_property(black_cover, "color:a", 1.0, 0.42)
	await cover.finished


func _show_frame(index: int) -> void:
	character_sprite.frame = index
	# Тень шире в момент касания, когда ноги расставлены, и уже при переносе.
	var phase := float(index) / float(WALK_FRAME_COUNT)
	var spread := 0.5 + 0.5 * cos(phase * TAU * 2.0)
	walker_shadow.scale = Vector2(0.82 + spread * 0.28, 1.0)
	if HEEL_STRIKES.has(index):
		_on_heel_strike(float(HEEL_STRIKES[index]))


func _on_heel_strike(frame_sole_x: float) -> void:
	_play_footstep()
	var print_x := walker.position.x + walk_direction * (frame_sole_x - FRAME_SIZE.x * 0.5) * WALKER_SCALE
	var footprint := Polygon2D.new()
	var points := PackedVector2Array()
	for point_index in range(16):
		var angle := TAU * float(point_index) / 16.0
		points.append(Vector2(cos(angle) * 13.0, sin(angle) * 3.2))
	footprint.polygon = points
	footprint.color = Color(0.03, 0.05, 0.14, 0.38)
	footprint.position = Vector2(print_x, WALKER_BASELINE_Y + 1.0)
	footprints.add_child(footprint)
	var fade := footprint.create_tween()
	fade.tween_interval(2.2)
	fade.tween_property(footprint, "modulate:a", 0.0, 2.5)
	fade.tween_callback(footprint.queue_free)


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
	background.pivot_offset = Vector2(VIEWPORT_SIZE.x * 0.5, WALKER_BASELINE_Y)
	root.add_child(background)

	cold_veil = ColorRect.new()
	cold_veil.color = Color(0.07, 0.11, 0.24, 0.12)
	cold_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cold_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(cold_veil)

	footprints = Node2D.new()
	footprints.name = "Footprints"
	root.add_child(footprints)

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
	walker_shadow.color = Color(0.015, 0.025, 0.07, 0.34)
	walker.add_child(walker_shadow)

	character_sprite = AnimatedSprite2D.new()
	character_sprite.name = "AnimatedWalker"
	character_sprite.position = Vector2(0, -(FRAME_SOLE_Y - FRAME_SIZE.y * 0.5) * WALKER_SCALE)
	character_sprite.modulate = MOONLIGHT_TINT
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
	frames.set_animation_loop(&"walk", true)
	for frame_number in range(1, WALK_FRAME_COUNT + 1):
		frames.add_frame(&"walk", load(WALK_FRAMES_PATH % frame_number) as Texture2D)
	return frames
