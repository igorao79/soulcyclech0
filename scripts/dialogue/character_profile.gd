class_name SoulcycleCharacterProfile
extends Resource

enum PortraitAnchor {
	LEFT,
	CENTER,
	RIGHT,
}

@export var character_id: StringName
@export var display_name: String = "???"
@export var world_sprite_sheet: Texture2D
@export var dialogue_portrait: Texture2D
@export var dialogue_theme_id: StringName = &"crimson"
@export var portrait_anchor: PortraitAnchor = PortraitAnchor.CENTER
@export var portrait_scale: float = 1.0
@export var portrait_offset: Vector2 = Vector2.ZERO
@export var portrait_tint: Color = Color.WHITE
