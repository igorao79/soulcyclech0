class_name SoulcycleBattleSystem
extends CanvasLayer

signal battle_started
signal battle_ended(victory: bool)

enum BattleState {
	INACTIVE,
	PLAYER_TURN,
	ENEMY_TURN,
	FINISHED,
}

const BattleCatalog := preload("res://scripts/battle/battle_catalog.gd")
const BattleSilhouette := preload("res://scripts/battle/battle_silhouette.gd")
const BATTLE_FONT := preload("res://assets/fonts/CormorantGaramond.ttf")

var overlay: Control
var player_sprite: TextureRect
var enemy_silhouette: SoulcycleBattleSilhouette
var enemy_name_label: Label
var enemy_level_label: Label
var enemy_hp_bar: ProgressBar
var player_name_label: Label
var player_level_label: Label
var player_hp_label: Label
var player_hp_bar: ProgressBar
var message_label: RichTextLabel
var action_buttons: Array[Button] = []
var state := BattleState.INACTIVE
var player_actor: SoulcycleBattleActor
var enemy_actor: SoulcycleBattleActor
var player_hp := 0
var enemy_hp := 0
var player_guarding := false


func _ready() -> void:
	layer = 70
	_build_interface()
	overlay.visible = false


func is_active() -> bool:
	return state != BattleState.INACTIVE


func start_battle(encounter_id: StringName = &"first_wraith") -> void:
	if is_active():
		return

	var encounter := BattleCatalog.get_encounter(encounter_id)
	player_actor = BattleCatalog.get_actor(StringName(encounter.get("player", &"nameless")))
	enemy_actor = BattleCatalog.get_actor(StringName(encounter.get("enemy", &"bell_wraith")))
	player_hp = player_actor.max_hp
	enemy_hp = enemy_actor.max_hp
	player_guarding = false
	state = BattleState.PLAYER_TURN
	overlay.visible = true

	_apply_actor_visuals()
	_update_status()
	_set_message("%s преграждает путь." % enemy_actor.display_name)
	_set_actions_enabled(true)
	action_buttons[0].grab_focus()
	battle_started.emit()
	_animate_battle_in()


func end_battle(victory: bool) -> void:
	if not is_active():
		return
	state = BattleState.INACTIVE
	overlay.visible = false
	battle_ended.emit(victory)


func _on_action_selected(action_id: StringName) -> void:
	if state != BattleState.PLAYER_TURN:
		return

	_set_actions_enabled(false)
	match action_id:
		&"attack":
			var damage := _calculate_damage(player_actor.attack, enemy_actor.defense, 1.0)
			enemy_hp = maxi(0, enemy_hp - damage)
			_set_message("%s наносит %d урона." % [player_actor.display_name, damage])
		&"thrust":
			if randf() <= 0.78:
				var damage := _calculate_damage(player_actor.attack, enemy_actor.defense, 1.55)
				enemy_hp = maxi(0, enemy_hp - damage)
				_set_message("Точный выпад — %d урона." % damage)
			else:
				_set_message("Острие рапиры рассекает лишь холодный воздух.")
		&"guard":
			player_guarding = true
			_set_message("%s принимает защитную стойку." % player_actor.display_name)
		&"escape":
			if randf() <= 0.62:
				_set_message("Ты разрываешь дистанцию и уходишь в метель.")
				state = BattleState.FINISHED
				await get_tree().create_timer(0.75).timeout
				end_battle(false)
				return
			_set_message("Путь назад исчезает среди снега.")

	_update_status()
	if enemy_hp <= 0:
		state = BattleState.FINISHED
		_set_message("%s растворяется в колокольном звоне." % enemy_actor.display_name)
		await get_tree().create_timer(0.90).timeout
		end_battle(true)
		return

	state = BattleState.ENEMY_TURN
	await get_tree().create_timer(0.72).timeout
	_take_enemy_turn()


func _take_enemy_turn() -> void:
	if state != BattleState.ENEMY_TURN:
		return

	var damage := _calculate_damage(enemy_actor.attack, player_actor.defense, 1.0)
	if player_guarding:
		damage = maxi(1, ceili(damage * 0.42))
	player_guarding = false
	player_hp = maxi(0, player_hp - damage)
	_set_message("%s отвечает эхом: %d урона." % [enemy_actor.display_name, damage])
	_update_status()

	if player_hp <= 0:
		state = BattleState.FINISHED
		_set_message("Снег укрывает твоё имя. Цикл начинается снова.")
		await get_tree().create_timer(1.0).timeout
		end_battle(false)
		return

	await get_tree().create_timer(0.52).timeout
	state = BattleState.PLAYER_TURN
	_set_message("Твой ход.")
	_set_actions_enabled(true)
	action_buttons[0].grab_focus()


func _calculate_damage(attacker_attack: int, defender_defense: int, multiplier: float) -> int:
	var base := float(attacker_attack) * multiplier - float(defender_defense) * 0.55
	return maxi(1, roundi(base + randf_range(-1.5, 2.0)))


func _apply_actor_visuals() -> void:
	player_sprite.texture = player_actor.battle_sprite
	var horizontal_scale := -player_actor.sprite_scale if player_actor.sprite_flip_h else player_actor.sprite_scale
	player_sprite.scale = Vector2(horizontal_scale, player_actor.sprite_scale)
	player_sprite.modulate = Color.WHITE
	enemy_silhouette.accent_color = enemy_actor.accent_color

	enemy_name_label.text = enemy_actor.display_name
	enemy_level_label.text = "УР. %d" % enemy_actor.level
	player_name_label.text = player_actor.display_name
	player_level_label.text = "УР. %d" % player_actor.level


func _update_status() -> void:
	enemy_hp_bar.max_value = enemy_actor.max_hp
	enemy_hp_bar.value = enemy_hp
	player_hp_bar.max_value = player_actor.max_hp
	player_hp_bar.value = player_hp
	player_hp_label.text = "%d / %d" % [player_hp, player_actor.max_hp]


func _set_message(message: String) -> void:
	message_label.text = message


func _set_actions_enabled(enabled: bool) -> void:
	for button in action_buttons:
		button.disabled = not enabled


func _animate_battle_in() -> void:
	overlay.modulate.a = 0.0
	player_sprite.position.x -= 34.0
	enemy_silhouette.position.x += 34.0
	var player_target_x := player_sprite.position.x + 34.0
	var enemy_target_x := enemy_silhouette.position.x - 34.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(overlay, "modulate:a", 1.0, 0.22)
	tween.tween_property(player_sprite, "position:x", player_target_x, 0.34)
	tween.tween_property(enemy_silhouette, "position:x", enemy_target_x, 0.34)


func _build_interface() -> void:
	overlay = Control.new()
	overlay.name = "BattleOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = _create_battle_background()
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(background)

	_add_platform(Vector2(725, 190), Vector2(230, 55), Color(0.39, 0.57, 0.62, 0.48))
	_add_platform(Vector2(270, 360), Vector2(300, 72), Color(0.24, 0.34, 0.45, 0.58))

	player_sprite = TextureRect.new()
	player_sprite.anchor_left = 0.055
	player_sprite.anchor_top = 0.19
	player_sprite.anchor_right = 0.50
	player_sprite.anchor_bottom = 0.78
	player_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	player_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	player_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	player_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(player_sprite)

	enemy_silhouette = BattleSilhouette.new()
	enemy_silhouette.anchor_left = 0.63
	enemy_silhouette.anchor_top = 0.17
	enemy_silhouette.anchor_right = 0.88
	enemy_silhouette.anchor_bottom = 0.54
	overlay.add_child(enemy_silhouette)

	var enemy_card := _create_status_card()
	enemy_card.anchor_left = 0.04
	enemy_card.anchor_top = 0.055
	enemy_card.anchor_right = 0.42
	enemy_card.anchor_bottom = 0.21
	overlay.add_child(enemy_card)
	var enemy_contents := _create_status_contents(enemy_card)
	enemy_name_label = enemy_contents[0] as Label
	enemy_level_label = enemy_contents[1] as Label
	enemy_hp_bar = enemy_contents[2] as ProgressBar

	var player_card := _create_status_card()
	player_card.anchor_left = 0.59
	player_card.anchor_top = 0.49
	player_card.anchor_right = 0.96
	player_card.anchor_bottom = 0.655
	overlay.add_child(player_card)
	var player_contents := _create_status_contents(player_card, true)
	player_name_label = player_contents[0] as Label
	player_level_label = player_contents[1] as Label
	player_hp_bar = player_contents[2] as ProgressBar
	player_hp_label = player_contents[3] as Label

	var message_panel := _create_bottom_panel()
	message_panel.anchor_left = 0.025
	message_panel.anchor_top = 0.735
	message_panel.anchor_right = 0.575
	message_panel.anchor_bottom = 0.97
	overlay.add_child(message_panel)
	var message_margin := _create_margin(24, 20, 22, 18)
	message_panel.add_child(message_margin)
	message_label = RichTextLabel.new()
	message_label.bbcode_enabled = false
	message_label.scroll_active = false
	message_label.fit_content = false
	message_label.add_theme_font_override("normal_font", BATTLE_FONT)
	message_label.add_theme_font_size_override("normal_font_size", 25)
	message_label.add_theme_color_override("default_color", Color("#f3eee5"))
	message_label.add_theme_constant_override("line_separation", 6)
	message_margin.add_child(message_label)

	var actions_panel := _create_bottom_panel()
	actions_panel.anchor_left = 0.59
	actions_panel.anchor_top = 0.70
	actions_panel.anchor_right = 0.975
	actions_panel.anchor_bottom = 0.97
	overlay.add_child(actions_panel)
	var actions_margin := _create_margin(12, 12, 12, 12)
	actions_panel.add_child(actions_margin)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	actions_margin.add_child(grid)

	_add_action_button(grid, "АТАКА", &"attack")
	_add_action_button(grid, "ВЫПАД", &"thrust")
	_add_action_button(grid, "ЗАЩИТА", &"guard")
	_add_action_button(grid, "ОТСТУПИТЬ", &"escape")


func _create_battle_background() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color("#17263a"),
		Color("#31536a"),
		Color("#91aeb7"),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.56, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 960
	texture.height = 540
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	return texture


func _add_platform(center: Vector2, radii: Vector2, color: Color) -> void:
	var platform := Polygon2D.new()
	var points := PackedVector2Array()
	for point_index in range(40):
		var angle := TAU * float(point_index) / 40.0
		points.append(Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	platform.position = center
	platform.polygon = points
	platform.color = color
	overlay.add_child(platform)


func _create_status_card() -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.94, 0.87, 0.96)
	style.border_color = Color("#25354a")
	style.set_border_width_all(3)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 16
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 7
	card.add_theme_stylebox_override("panel", style)
	return card


func _create_status_contents(card: PanelContainer, include_hp_text: bool = false) -> Array:
	var margin := _create_margin(16, 9, 16, 8)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_override("font", BATTLE_FONT)
	name_label.add_theme_font_size_override("font_size", 23)
	name_label.add_theme_color_override("font_color", Color("#182233"))
	header.add_child(name_label)
	var level_label := Label.new()
	level_label.add_theme_font_override("font", BATTLE_FONT)
	level_label.add_theme_font_size_override("font_size", 18)
	level_label.add_theme_color_override("font_color", Color("#3c4656"))
	header.add_child(level_label)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	column.add_child(hp_row)
	var hp_caption := Label.new()
	hp_caption.text = "HP"
	hp_caption.add_theme_font_override("font", BATTLE_FONT)
	hp_caption.add_theme_font_size_override("font_size", 16)
	hp_caption.add_theme_color_override("font_color", Color("#8f4a3f"))
	hp_row.add_child(hp_caption)
	var hp_bar := ProgressBar.new()
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size.y = 12
	_style_hp_bar(hp_bar)
	hp_row.add_child(hp_bar)

	var result: Array = [name_label, level_label, hp_bar]
	if include_hp_text:
		var hp_value := Label.new()
		hp_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hp_value.add_theme_font_override("font", BATTLE_FONT)
		hp_value.add_theme_font_size_override("font_size", 16)
		hp_value.add_theme_color_override("font_color", Color("#243044"))
		column.add_child(hp_value)
		result.append(hp_value)
	return result


func _style_hp_bar(bar: ProgressBar) -> void:
	var background_style := StyleBoxFlat.new()
	background_style.bg_color = Color("#263548")
	background_style.corner_radius_top_left = 5
	background_style.corner_radius_top_right = 5
	background_style.corner_radius_bottom_left = 5
	background_style.corner_radius_bottom_right = 5
	bar.add_theme_stylebox_override("background", background_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color("#69b879")
	fill_style.corner_radius_top_left = 5
	fill_style.corner_radius_top_right = 5
	fill_style.corner_radius_bottom_left = 5
	fill_style.corner_radius_bottom_right = 5
	bar.add_theme_stylebox_override("fill", fill_style)


func _create_bottom_panel() -> PanelContainer:
	var panel_container := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.04, 0.075, 0.97)
	style.border_color = Color("#d0c5b5")
	style.set_border_width_all(3)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0, 0, 0, 0.52)
	style.shadow_size = 9
	panel_container.add_theme_stylebox_override("panel", style)
	return panel_container


func _create_margin(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_bottom", bottom)
	return margin


func _add_action_button(parent: GridContainer, title: String, action_id: StringName) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(0, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.add_theme_font_override("font", BATTLE_FONT)
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", Color("#f4eee5"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color("#26364d")
	normal_style.border_color = Color("#8396a8")
	normal_style.set_border_width_all(2)
	normal_style.corner_radius_top_left = 6
	normal_style.corner_radius_top_right = 6
	normal_style.corner_radius_bottom_left = 6
	normal_style.corner_radius_bottom_right = 6
	button.add_theme_stylebox_override("normal", normal_style)

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color("#7d3548")
	hover_style.border_color = Color("#e1a5af")
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("focus", hover_style)

	var pressed_style := normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color("#5c2637")
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.pressed.connect(_on_action_selected.bind(action_id))
	parent.add_child(button)
	action_buttons.append(button)
