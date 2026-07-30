class_name SoulcycleDialogueTheme
extends Resource

@export var theme_id: StringName
@export var font: Font
@export var panel_color: Color = Color("#120f19")
@export var panel_border_color: Color = Color("#823044")
@export var name_plate_color: Color = Color("#1c1320")
@export var name_color: Color = Color("#e16a7c")
@export var text_color: Color = Color("#f5ede3")
@export var indicator_color: Color = Color("#d8bac2")
@export var dimmer_color: Color = Color(0.015, 0.01, 0.025, 0.46)
@export_range(0, 12, 1) var border_width: int = 2
@export_range(0, 24, 1) var corner_radius: int = 7
@export_range(0, 32, 1) var shadow_size: int = 14
@export_range(12, 48, 1) var speaker_font_size: int = 27
@export_range(12, 48, 1) var text_font_size: int = 25
