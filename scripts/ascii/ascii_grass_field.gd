class_name SoulcycleAsciiGrassField
extends RefCounted

# Физика травы: участок земли 0.25 × 0.25 м — груз на пружине с трением.
# Сетка замкнута, как тор, и привязана к миру: считаются только те участки, что ещё качаются.

const CELLS := 64
const CELL_SIZE := 0.25
# Совпадает с BEND_RANGE в ascii_grass.gdshaderinc.
const BEND_RANGE := 1.6
const STIFFNESS := 60.0
const DAMPING := 2.6
const CONTACT_RADIUS := 0.8
const PUSH_FORCE := 170.0
const DRAG_FORCE := 22.0
const REST_EPSILON := 0.004

var texture: ImageTexture

var _image: Image
var _bytes := PackedByteArray()
var _bend := PackedVector2Array()
var _velocity := PackedVector2Array()
var _active := {}
var _dirty := false


func _init() -> void:
	_bend.resize(CELLS * CELLS)
	_velocity.resize(CELLS * CELLS)
	_bytes.resize(CELLS * CELLS * 2)
	_bytes.fill(128)
	_image = Image.create_from_data(CELLS, CELLS, false, Image.FORMAT_RG8, _bytes)
	texture = ImageTexture.create_from_image(_image)


# Шаг героя: трава вокруг ступни вздрагивает и расходится кругом.
func kick(point: Vector2, strength: float, radius: float) -> void:
	var reach := ceili(radius / CELL_SIZE)
	var base := Vector2i(floori(point.x / CELL_SIZE), floori(point.y / CELL_SIZE))
	for z in range(base.y - reach, base.y + reach + 1):
		for x in range(base.x - reach, base.x + reach + 1):
			var offset := (Vector2(x, z) + Vector2(0.5, 0.5)) * CELL_SIZE - point
			var distance := offset.length()
			if distance >= radius:
				continue
			var index := _index(x, z)
			_velocity[index] += offset / maxf(distance, 0.05) * strength * (1.0 - distance / radius)
			_active[index] = true


func step(delta: float, hero: Vector2, hero_velocity: Vector2, touching: bool) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	if touching:
		_apply_contact(dt, hero, hero_velocity)

	for index: int in _active.keys():
		var bend := _bend[index]
		var velocity := _velocity[index]
		velocity += (-bend * STIFFNESS - velocity * DAMPING) * dt
		bend += velocity * dt
		# На пределе изгиба травинка не копит скорость наружу: иначе она залипает и потом хлещет.
		if bend.length() > BEND_RANGE:
			var outward := bend.normalized()
			bend = outward * BEND_RANGE
			var radial := velocity.dot(outward)
			if radial > 0.0:
				velocity -= outward * radial
		if bend.length() < REST_EPSILON and velocity.length() < REST_EPSILON * 8.0:
			bend = Vector2.ZERO
			velocity = Vector2.ZERO
			_active.erase(index)
		_bend[index] = bend
		_velocity[index] = velocity
		_bytes[index * 2] = _encode(bend.x)
		_bytes[index * 2 + 1] = _encode(bend.y)
		_dirty = true

	if _dirty:
		_image.set_data(CELLS, CELLS, false, Image.FORMAT_RG8, _bytes)
		texture.update(_image)
		_dirty = false


func bend_at(point: Vector2) -> Vector2:
	return _bend[_index(floori(point.x / CELL_SIZE), floori(point.y / CELL_SIZE))]


# Тело расталкивает траву наружу и тащит её за собой по ходу движения.
func _apply_contact(dt: float, hero: Vector2, hero_velocity: Vector2) -> void:
	var reach := ceili(CONTACT_RADIUS / CELL_SIZE)
	var base := Vector2i(floori(hero.x / CELL_SIZE), floori(hero.y / CELL_SIZE))
	for z in range(base.y - reach, base.y + reach + 1):
		for x in range(base.x - reach, base.x + reach + 1):
			var offset := (Vector2(x, z) + Vector2(0.5, 0.5)) * CELL_SIZE - hero
			var distance := offset.length()
			if distance >= CONTACT_RADIUS:
				continue
			var depth := 1.0 - distance / CONTACT_RADIUS
			var index := _index(x, z)
			var force := offset / maxf(distance, 0.05) * PUSH_FORCE + hero_velocity * DRAG_FORCE
			_velocity[index] += force * depth * dt
			_active[index] = true


func _index(x: int, z: int) -> int:
	return posmod(z, CELLS) * CELLS + posmod(x, CELLS)


func _encode(value: float) -> int:
	return clampi(roundi((value / BEND_RANGE * 0.5 + 0.5) * 255.0), 0, 255)
