extends Node2D

const PlayerScene := preload("res://scripts/player.gd")
const NpcScene := preload("res://scripts/npc.gd")
const DialogueScene := preload("res://scripts/dialogue_ui.gd")
const BattleSystemScene := preload("res://scripts/battle/battle_system.gd")
const WinterMapScene := preload("res://scripts/winter_map.gd")
const CHAPEL_TEXTURE := preload("res://assets/props/chapel.png")
const WINTER_THEME := preload("res://assets/music/snowbound_crossroads.ogg")

var winter_map: SoulcycleWinterMap
var player: SoulcyclePlayer
var dialogue: SoulcycleDialogue
var battle: SoulcycleBattleSystem
var npc: SoulcycleNpc
var music: AudioStreamPlayer


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#0c1422"))
	_build_lighting()
	_build_music()
	_build_map()
	_spawn_player()
	_spawn_npc()
	_build_battle_system()
	_build_landmarks()
	_build_hud()
	if "--dialogue-preview" in OS.get_cmdline_user_args():
		call_deferred("_open_dialogue_preview")
	elif "--battle-preview" in OS.get_cmdline_user_args():
		call_deferred("_open_battle_preview")


func _process(_delta: float) -> void:
	if player == null or npc == null or dialogue == null or battle == null:
		return

	if Input.is_action_just_pressed("battle_preview") and not dialogue.is_open():
		if not battle.is_active():
			battle.start_battle(&"first_wraith")
		return

	if battle.is_active():
		return

	var close_enough := player.global_position.distance_to(npc.global_position) <= 120.0
	npc.set_player_near(close_enough and not dialogue.is_open())

	if not Input.is_action_just_pressed("interact"):
		return

	if dialogue.is_open():
		dialogue.advance()
	elif close_enough:
		npc.request_dialogue()


func _build_map() -> void:
	winter_map = WinterMapScene.new()
	winter_map.name = "WinterMap"
	add_child(winter_map)


func _spawn_player() -> void:
	player = PlayerScene.new()
	player.name = "Player"
	player.position = winter_map.get_spawn_position()
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
	npc = NpcScene.new()
	npc.name = "Keeper"
	npc.position = winter_map.get_npc_position()
	npc.dialogue_requested.connect(_on_dialogue_requested)
	add_child(npc)

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
	_add_chapel(winter_map.get_chapel_position())


func _add_chapel(position: Vector2) -> void:
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
	music.volume_db = -14.0
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


func _install_battle_input() -> void:
	if not InputMap.has_action("battle_preview"):
		InputMap.add_action("battle_preview")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_B
	InputMap.action_add_event("battle_preview", event)
