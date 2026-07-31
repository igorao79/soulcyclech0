extends Node2D

const PlayerScene := preload("res://scripts/player.gd")
const NpcScene := preload("res://scripts/npc.gd")
const DialogueScene := preload("res://scripts/dialogue_ui.gd")
const BattleSystemScene := preload("res://scripts/battle/battle_system.gd")
const WinterMapScene := preload("res://scripts/winter_map.gd")
const TravelTransitionScene := preload("res://scripts/transitions/travel_transition.gd")
const CHAPEL_TEXTURE := preload("res://assets/props/chapel.png")
const WINTER_THEME := preload("res://assets/music/snowbound_crossroads.ogg")

var current_location := &"crossroads"
var winter_map: SoulcycleWinterMap
var player: SoulcyclePlayer
var dialogue: SoulcycleDialogue
var battle: SoulcycleBattleSystem
var npc: SoulcycleNpc
var chapel: StaticBody2D
var travel_transition: SoulcycleTravelTransition
var music: AudioStreamPlayer
var is_traveling := false


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#0c1422"))
	_build_lighting()
	_build_music()
	_build_map()
	_spawn_player()
	_build_dialogue_system()
	_spawn_npc()
	_build_battle_system()
	_build_landmarks()
	_build_hud()
	_build_travel_transition()
	if "--dialogue-preview" in OS.get_cmdline_user_args():
		call_deferred("_open_dialogue_preview")
	elif "--battle-preview" in OS.get_cmdline_user_args():
		call_deferred("_open_battle_preview")
	elif "--travel-preview" in OS.get_cmdline_user_args():
		call_deferred("_open_travel_preview")


func _process(_delta: float) -> void:
	if player == null or dialogue == null or battle == null or is_traveling:
		return

	if Input.is_action_just_pressed("battle_preview") and not dialogue.is_open():
		if not battle.is_active():
			battle.start_battle(&"first_wraith")
		return

	if battle.is_active():
		return

	if dialogue.is_open():
		if Input.is_action_just_pressed("interact"):
			dialogue.advance()
		return

	var exit_id := winter_map.get_travel_exit(player.global_position)
	if exit_id != &"":
		_begin_travel(exit_id)
		return

	if npc == null:
		return

	var close_enough := player.global_position.distance_to(npc.global_position) <= 120.0
	npc.set_player_near(close_enough)
	if Input.is_action_just_pressed("interact") and close_enough:
		npc.request_dialogue()


func _build_map() -> void:
	winter_map = WinterMapScene.new()
	winter_map.name = "WinterMap_%s" % current_location
	winter_map.location_id = current_location
	add_child(winter_map)


func _spawn_player() -> void:
	player = PlayerScene.new()
	player.name = "Player"
	player.position = winter_map.get_spawn_position()
	player.set_footstep_surface_resolver(winter_map.get_footstep_surface)
	add_child(player)

	var camera := Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(SoulcycleWinterMap.WORLD_SIZE.x)
	camera.limit_bottom = int(SoulcycleWinterMap.WORLD_SIZE.y)
	camera.zoom = Vector2(1.1, 1.1)
	player.add_child(camera)


func _spawn_npc() -> void:
	if current_location != &"crossroads":
		npc = null
		return

	npc = NpcScene.new()
	npc.name = "Keeper"
	npc.position = winter_map.get_npc_position()
	npc.dialogue_requested.connect(_on_dialogue_requested)
	add_child(npc)


func _build_dialogue_system() -> void:
	dialogue = DialogueScene.new()
	dialogue.name = "DialogueUI"
	dialogue.dialogue_opened.connect(func() -> void: player.can_move = false)
	dialogue.dialogue_closed.connect(func() -> void: player.can_move = true)
	add_child(dialogue)


func _build_battle_system() -> void:
	battle = BattleSystemScene.new()
	battle.name = "BattleSystem"
	battle.battle_started.connect(func() -> void: player.can_move = false)
	battle.battle_ended.connect(func(_victory: bool) -> void: player.can_move = true)
	add_child(battle)
	_install_battle_input()


func _build_landmarks() -> void:
	if current_location == &"crossroads":
		chapel = _add_chapel(winter_map.get_chapel_position())
	else:
		chapel = null


func _add_chapel(position: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = position + Vector2(0, 24)
	body.collision_layer = 2
	body.z_index = int(body.position.y)

	var collision_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(122, 54)
	collision_shape.position = Vector2(0, -26)
	collision_shape.shape = rectangle
	body.add_child(collision_shape)

	var building := Sprite2D.new()
	building.texture = CHAPEL_TEXTURE
	building.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	building.offset = Vector2(0, -CHAPEL_TEXTURE.get_height() * 0.5)
	body.add_child(building)
	body.add_child(_create_warm_light(Vector2(0, -78), 0.95, 1.65))
	add_child(body)
	return body


func _build_travel_transition() -> void:
	travel_transition = TravelTransitionScene.new()
	travel_transition.name = "TravelTransition"
	add_child(travel_transition)


func _begin_travel(exit_id: StringName) -> void:
	var destination := &""
	var arrival_edge := &""
	var direction := 1
	if current_location == &"crossroads" and exit_id == &"north":
		destination = &"northern_grove"
		arrival_edge = &"south"
		direction = 1
	elif current_location == &"northern_grove" and exit_id == &"south":
		destination = &"crossroads"
		arrival_edge = &"north"
		direction = -1

	if destination == &"":
		return

	is_traveling = true
	player.can_move = false
	await travel_transition.play(direction)
	_replace_location(destination, arrival_edge)
	await travel_transition.reveal_world()
	player.can_move = true
	is_traveling = false


func _replace_location(destination: StringName, arrival_edge: StringName) -> void:
	if npc != null:
		npc.queue_free()
		npc = null
	if chapel != null:
		chapel.queue_free()
		chapel = null
	if winter_map != null:
		winter_map.queue_free()

	current_location = destination
	_build_map()
	player.set_footstep_surface_resolver(winter_map.get_footstep_surface)
	player.global_position = winter_map.get_arrival_position(arrival_edge)
	_spawn_npc()
	_build_landmarks()


func _build_hud() -> void:
	_build_snowfall()

	var canvas := CanvasLayer.new()
	canvas.layer = 20
	add_child(canvas)

	var cold_tint := ColorRect.new()
	cold_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cold_tint.color = Color(0.06, 0.11, 0.25, 0.08)
	cold_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(cold_tint)


func _build_lighting() -> void:
	var night_tint := CanvasModulate.new()
	night_tint.color = Color("#b8c6e4")
	add_child(night_tint)


func _build_music() -> void:
	var looped_theme := WINTER_THEME.duplicate() as AudioStreamOggVorbis
	looped_theme.loop = true

	music = AudioStreamPlayer.new()
	music.name = "WinterTheme"
	music.stream = looped_theme
	music.volume_db = -20.0
	add_child(music)
	music.play()


func _create_warm_light(position: Vector2, energy: float, texture_scale: float) -> PointLight2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.95))
	gradient.set_color(1, Color(1, 1, 1, 0))

	var light_texture := GradientTexture2D.new()
	light_texture.gradient = gradient
	light_texture.width = 192
	light_texture.height = 192
	light_texture.fill = GradientTexture2D.FILL_RADIAL
	light_texture.fill_from = Vector2(0.5, 0.5)
	light_texture.fill_to = Vector2(1.0, 0.5)

	var light := PointLight2D.new()
	light.position = position
	light.texture = light_texture
	light.color = Color("#ffc36b")
	light.energy = energy
	light.texture_scale = texture_scale
	return light


func _build_snowfall() -> void:
	var snow_canvas := CanvasLayer.new()
	snow_canvas.layer = 12
	add_child(snow_canvas)

	var snow := GPUParticles2D.new()
	snow.position = Vector2(480, -30)
	snow.amount = 140
	snow.lifetime = 7.0
	snow.preprocess = 7.0
	snow.visibility_rect = Rect2(-560, -60, 1120, 680)

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(540, 25, 1)
	material.direction = Vector3(0.1, 1.0, 0)
	material.spread = 18.0
	material.gravity = Vector3(7, 22, 0)
	material.initial_velocity_min = 10.0
	material.initial_velocity_max = 24.0
	material.scale_min = 1.0
	material.scale_max = 2.6
	material.color = Color(0.88, 0.93, 1.0, 0.55)
	snow.process_material = material
	snow_canvas.add_child(snow)


func _on_dialogue_requested(sequence_id: StringName) -> void:
	if not dialogue.is_open():
		dialogue.show_sequence(sequence_id)


func _open_dialogue_preview() -> void:
	dialogue.show_sequence(&"keeper_first_meeting")
	if "--portrait" in OS.get_cmdline_user_args():
		dialogue.advance()
		dialogue.advance()


func _open_battle_preview() -> void:
	battle.start_battle(&"first_wraith")


func _open_travel_preview() -> void:
	_begin_travel(&"north")


func _install_battle_input() -> void:
	if not InputMap.has_action("battle_preview"):
		InputMap.add_action("battle_preview")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_B
	InputMap.action_add_event("battle_preview", event)
