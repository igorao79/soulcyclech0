class_name SoulcycleDialogue
extends CanvasLayer

signal dialogue_opened
signal dialogue_closed

const CharacterCatalog := preload("res://scripts/dialogue/character_catalog.gd")
const DialogueCatalog := preload("res://scripts/dialogue/dialogue_catalog.gd")

var overlay: Control
var dimmer: ColorRect
var portrait_stage: Control
var portrait_rect: TextureRect
var panel: PanelContainer
var name_plate: PanelContainer
var speaker_label: Label
var text_label: RichTextLabel
var indicator_label: Label
var lines: Array = []
var line_index := 0
var typing := false
var typed_characters := 0.0
var indicator_time := 0.0
var active_character_id: StringName = &""


func _ready() -> void:
	layer = 50
	_build_interface()
	hide_dialogue()


func _process(delta: float) -> void:
	if not is_open():
		return

	if typing:
		typed_characters += delta * 46.0
		text_label.visible_characters = int(typed_characters)
		if text_label.visible_characters >= text_label.get_total_character_count():
			_finish_typing()
		return

	indicator_time += delta
	indicator_label.modulate.a = 0.62 + sin(indicator_time * 4.2) * 0.30
	indicator_label.position.y = sin(indicator_time * 3.2) * 2.0


func advance() -> void:
	if not is_open():
		return
	if typing:
		text_label.visible_characters = -1
		_finish_typing()
	elif line_index + 1 < lines.size():
		line_index += 1
		_show_current_line()
	else:
		hide_dialogue()


func is_open() -> bool:
	return overlay != null and overlay.visible


func show_sequence(sequence_id: StringName) -> void:
	show_dialogue(DialogueCatalog.get_sequence(sequence_id))


func show_dialogue(new_lines: Array) -> void:
	if new_lines.is_empty():
		return
	lines = new_lines
	line_index = 0
	overlay.visible = true
	dialogue_opened.emit()
	_show_current_line()
	_animate_panel_in()


func hide_dialogue() -> void:
	if overlay == null:
		return
	var was_visible := overlay.visible
	overlay.visible = false
	typing = false
	active_character_id = &""
	if was_visible:
		dialogue_closed.emit()


func _show_current_line() -> void:
	var line: Dictionary = lines[line_index] as Dictionary
	var character_id: StringName = StringName(line.get("character", &"nameless"))
	var profile := CharacterCatalog.get_profile(character_id)
	var theme_id: StringName = StringName(line.get("theme", profile.dialogue_theme_id))
	var dialogue_theme := DialogueCatalog.get_theme(theme_id)

	_apply_theme(dialogue_theme)
	_apply_character(profile)

	speaker_label.text = str(line.get("speaker", profile.display_name))
	text_label.text = str(line.get("text", ""))
	text_label.visible_characters = 0
	typed_characters = 0.0
	typing = true
	indicator_label.visible = false


func _finish_typing() -> void:
	typing = false
	text_label.visible_characters = -1
	indicator_time = 0.0
	indicator_label.position = Vector2.ZERO
	indicator_label.modulate.a = 1.0
	indicator_label.visible = true


func _apply_character(profile: SoulcycleCharacterProfile) -> void:
	portrait_rect.texture = profile.dialogue_portrait
	portrait_rect.modulate = profile.portrait_tint
	portrait_stage.visible = profile.dialogue_portrait != null
	_set_portrait_anchor(profile.portrait_anchor)

	portrait_stage.scale = Vector2(profile.portrait_scale, profile.portrait_scale)
	portrait_stage.pivot_offset = portrait_stage.size * 0.5
	portrait_stage.offset_left += profile.portrait_offset.x
	portrait_stage.offset_right += profile.portrait_offset.x
	portrait_stage.offset_top += profile.portrait_offset.y
	portrait_stage.offset_bottom += profile.portrait_offset.y

	if active_character_id != profile.character_id and portrait_stage.visible:
		_animate_portrait_in()
	active_character_id = profile.character_id


func _set_portrait_anchor(anchor: int) -> void:
	match anchor:
		SoulcycleCharacterProfile.PortraitAnchor.LEFT:
			portrait_stage.anchor_left = 0.02
			portrait_stage.anchor_right = 0.56
		SoulcycleCharacterProfile.PortraitAnchor.RIGHT:
			portrait_stage.anchor_left = 0.44
			portrait_stage.anchor_right = 0.98
		_:
			portrait_stage.anchor_left = 0.23
			portrait_stage.anchor_right = 0.77

	portrait_stage.anchor_top = 0.015
	portrait_stage.anchor_bottom = 0.79
	portrait_stage.offset_left = 0.0
	portrait_stage.offset_top = 0.0
	portrait_stage.offset_right = 0.0
	portrait_stage.offset_bottom = 0.0


func _apply_theme(dialogue_theme: SoulcycleDialogueTheme) -> void:
	dimmer.color = dialogue_theme.dimmer_color

	var panel_style := _create_panel_style(
		dialogue_theme.panel_color,
		dialogue_theme.panel_border_color,
		dialogue_theme.border_width,
		dialogue_theme.corner_radius,
		dialogue_theme.shadow_size
	)
	panel.add_theme_stylebox_override("panel", panel_style)

	var name_style := _create_panel_style(
		dialogue_theme.name_plate_color,
		dialogue_theme.panel_border_color,
		dialogue_theme.border_width,
		dialogue_theme.corner_radius,
		8
	)
	name_plate.add_theme_stylebox_override("panel", name_style)

	speaker_label.add_theme_font_override("font", dialogue_theme.font)
	speaker_label.add_theme_font_size_override("font_size", dialogue_theme.speaker_font_size)
	speaker_label.add_theme_color_override("font_color", dialogue_theme.name_color)
	text_label.add_theme_font_override("normal_font", dialogue_theme.font)
	text_label.add_theme_font_size_override("normal_font_size", dialogue_theme.text_font_size)
	text_label.add_theme_color_override("default_color", dialogue_theme.text_color)
	indicator_label.add_theme_font_override("font", dialogue_theme.font)
	indicator_label.add_theme_font_size_override("font_size", 24)
	indicator_label.add_theme_color_override("font_color", dialogue_theme.indicator_color)


func _create_panel_style(
	background: Color,
	border: Color,
	border_width: int,
	radius: int,
	shadow_size: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.shadow_color = Color(0, 0, 0, 0.72)
	style.shadow_size = shadow_size
	return style


func _animate_panel_in() -> void:
	panel.modulate.a = 0.0
	name_plate.modulate.a = 0.0
	var panel_target_y := panel.position.y
	var name_target_y := name_plate.position.y
	panel.position.y += 20.0
	name_plate.position.y += 20.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, 0.20)
	tween.tween_property(panel, "position:y", panel_target_y, 0.24)
	tween.tween_property(name_plate, "modulate:a", 1.0, 0.20)
	tween.tween_property(name_plate, "position:y", name_target_y, 0.24)


func _animate_portrait_in() -> void:
	portrait_stage.modulate.a = 0.0
	var target_y := portrait_stage.position.y
	portrait_stage.position.y += 16.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(portrait_stage, "modulate:a", 1.0, 0.24)
	tween.tween_property(portrait_stage, "position:y", target_y, 0.30)


func _build_interface() -> void:
	overlay = Control.new()
	overlay.name = "DialogueOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	dimmer = ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dimmer)

	portrait_stage = Control.new()
	portrait_stage.name = "PortraitStage"
	portrait_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(portrait_stage)
	_set_portrait_anchor(SoulcycleCharacterProfile.PortraitAnchor.CENTER)

	portrait_rect = TextureRect.new()
	portrait_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_stage.add_child(portrait_rect)

	panel = PanelContainer.new()
	panel.name = "DialoguePanel"
	panel.anchor_left = 0.055
	panel.anchor_top = 0.675
	panel.anchor_right = 0.945
	panel.anchor_bottom = 0.955
	overlay.add_child(panel)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 30)
	panel_margin.add_theme_constant_override("margin_top", 25)
	panel_margin.add_theme_constant_override("margin_right", 26)
	panel_margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(panel_margin)

	var text_column := VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 4)
	panel_margin.add_child(text_column)

	text_label = RichTextLabel.new()
	text_label.bbcode_enabled = false
	text_label.fit_content = false
	text_label.scroll_active = false
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.add_theme_constant_override("line_separation", 7)
	text_column.add_child(text_label)

	var indicator_row := HBoxContainer.new()
	indicator_row.alignment = BoxContainer.ALIGNMENT_END
	indicator_row.custom_minimum_size.y = 22
	text_column.add_child(indicator_row)

	indicator_label = Label.new()
	indicator_label.text = "◆"
	indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	indicator_row.add_child(indicator_label)

	name_plate = PanelContainer.new()
	name_plate.name = "SpeakerPlate"
	name_plate.anchor_left = 0.085
	name_plate.anchor_top = 0.615
	name_plate.anchor_right = 0.37
	name_plate.anchor_bottom = 0.705
	overlay.add_child(name_plate)

	var name_margin := MarginContainer.new()
	name_margin.add_theme_constant_override("margin_left", 20)
	name_margin.add_theme_constant_override("margin_top", 4)
	name_margin.add_theme_constant_override("margin_right", 20)
	name_margin.add_theme_constant_override("margin_bottom", 4)
	name_plate.add_child(name_margin)

	speaker_label = Label.new()
	speaker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speaker_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_margin.add_child(speaker_label)
