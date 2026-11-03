// Комната храма от первого лица: первый проход, по точке на ячейку символьной сетки.
// Красные деревянные стены панелями между тёмными столбами, балки под потолком,
// световой проём в потолке — из него столб розового света. Кровать у левой стены, рядом
// тумбочка, на ней ваза с красно-белым цветком: его сердцевина — глаз, он всегда обращён к нам.
// Раздвижные двери ведут в коридор, там ждёт воин с копьём.
// RGB — цвет знака, A — код знака: (ряд в атласе * 16 + яркость) / 255,
// его разворачивает temple_glyph.gdshader.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

const int RAMP_SNOW = 0;
const int RAMP_PATH = 1;
const int RAMP_DENSE = 5;
const int RAMP_SOLID = 7;
const int RAMP_EDGE = 9;
const int RAMP_GLOW = 10;
const int RAMP_FLAKE = 11;
const int RAMP_PLANK = 12;

const int M_WALL = 1;
const int M_PILLAR = 2;
const int M_FLOOR = 3;
const int M_CEIL = 4;
const int M_BED = 5;
const int M_LINEN = 6;
const int M_BLANKET = 7;
const int M_STAND = 8;
const int M_VASE = 9;
const int M_STEM = 10;
const int M_DOOR = 12;
const int M_SKY = 13;
const int M_RUNNER = 14;
const int M_LANTERN = 15;
const int M_ARMOR = 16;
const int M_CLOTH = 17;
const int M_DARK = 18;
const int M_VISOR = 19;
const int M_PLUME = 20;
const int M_SHAFT = 21;

// Комната: полуширина, высота, ближняя и дальняя стена. Те же числа в temple_wake.gd.
const vec2 ROOM = vec2(2.6, 3.2);
const vec2 ROOM_Z = vec2(-1.5, 5.0);
const vec3 SKY_LIGHT = vec3(0.3, 3.2, 1.0);
const vec3 BED = vec3(-1.575, 0.0, 2.65);
const vec3 NIGHTSTAND = vec3(-0.35, 0.0, 2.9);
const vec3 FLOWER = vec3(-0.35, 1.3, 2.9);
const float FLOWER_SIZE = 0.3;
// Коридор за дверями: полуширина, высота, где кончается.
const vec3 CORRIDOR = vec3(1.2, 2.9, 22.0);
const float DOOR_HEIGHT = 2.3;

uniform vec2 grid_size = vec2(288.0, 101.0);
uniform vec2 cell_px = vec2(5.0, 8.0);
uniform vec3 cam_pos = vec3(0.0, 1.6, 3.0);
uniform float cam_yaw = 0.0;
uniform float cam_pitch = 0.0;
uniform float cam_roll = 0.0;
uniform float time = 0.0;
// 0 — двери сомкнуты, коридора ещё не считаем; 1 — разъехались.
uniform float door_open = 0.0;
uniform vec3 warrior_pos = vec3(0.0, 0.0, 6.4);
uniform float warrior_yaw = 0.0;
uniform float warrior_phase = 0.0;
uniform float warrior_walk = 0.0;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}


float sd_box(vec3 p, vec3 b) {
	vec3 q = abs(p) - b;
	return length(max(q, vec3(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}


float sd_capsule(vec3 p, vec3 a, vec3 b, float r) {
	vec3 pa = p - a;
	vec3 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}


float sd_ellipsoid(vec3 p, vec3 r) {
	return (length(p / r) - 1.0) * min(r.x, min(r.y, r.z));
}


void take(inout float d, inout int m, float nd, int nm) {
	if (nd < d) {
		d = nd;
		m = nm;
	}
}


// Кровать: рама на ножках, изголовье к дверям, матрас, подушка, одеяло в ногах.
void sd_bed(vec3 p, inout float d, inout int m) {
	vec3 q = p - BED;
	float bound = sd_box(q - vec3(0.0, 0.45, 0.0), vec3(0.95, 0.55, 1.4));
	if (bound > 0.2) {
		d = min(d, bound);
		return;
	}
	take(d, m, sd_box(q - vec3(0.0, 0.25, 0.0), vec3(0.825, 0.07, 1.25)) - 0.01, M_BED);
	vec3 legs = vec3(abs(q.x) - 0.76, q.y - 0.09, abs(q.z) - 1.18);
	take(d, m, sd_box(legs, vec3(0.05, 0.09, 0.05)), M_BED);
	take(d, m, sd_box(q - vec3(0.0, 0.5, 1.26), vec3(0.825, 0.42, 0.035)) - 0.01, M_BED);
	take(d, m, sd_box(q - vec3(0.0, 0.38, 0.0), vec3(0.77, 0.07, 1.2)) - 0.03, M_LINEN);
	take(d, m, sd_box(q - vec3(0.0, 0.5, 0.92), vec3(0.42, 0.04, 0.2)) - 0.05, M_LINEN);
	take(d, m, sd_box(q - vec3(0.0, 0.42, -0.5), vec3(0.8, 0.07, 0.72)) - 0.03, M_BLANKET);
}


// Тумбочка с ящиком, на ней ваза; стебель поднимается к цветку.
void sd_nightstand(vec3 p, inout float d, inout int m) {
	vec3 q = p - NIGHTSTAND;
	float bound = sd_box(q - vec3(0.0, 0.65, 0.0), vec3(0.4, 0.7, 0.4));
	if (bound > 0.2) {
		d = min(d, bound);
		return;
	}
	take(d, m, sd_box(q - vec3(0.0, 0.3, 0.0), vec3(0.28, 0.3, 0.28)) - 0.02, M_STAND);
	take(d, m, sd_box(q - vec3(0.0, 0.62, 0.0), vec3(0.31, 0.015, 0.31)) - 0.01, M_STAND);
	// Ваза: тело вращения, пузатая снизу, с узким горлом.
	float y = clamp((q.y - 0.64) / 0.34, 0.0, 1.0);
	float radius = 0.045 + 0.075 * sin(pow(y, 0.7) * PI);
	float vase = max(length(q.xz) - radius, abs(q.y - 0.81) - 0.17);
	take(d, m, vase * 0.8, M_VASE);
	float sway = sin(time * 0.5) * 0.008;
	take(d, m, sd_capsule(p, FLOWER + vec3(0.0, -0.36, 0.0), FLOWER + vec3(sway, -0.04, 0.0), 0.012), M_STEM);
}


// Мир в координатах воина: начало в ступнях, лицом к -z.
vec3 to_warrior(vec3 p) {
	vec3 v = p - warrior_pos;
	float c = cos(warrior_yaw);
	float s = sin(warrior_yaw);
	return vec3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c);
}


// Воин: серебристые латы, тёмные рукава, багровый шарф и табард с поясом,
// заострённый шлем с прорезью и красным плюмажем, длинное копьё в правой руке.
void sd_warrior(vec3 p, inout float d, inout int m) {
	vec3 q = to_warrior(p);
	float bound = sd_ellipsoid(q - vec3(0.1, 1.2, 0.0), vec3(0.75, 1.55, 0.75));
	if (bound > 0.25) {
		d = min(d, bound);
		return;
	}
	float swing = sin(warrior_phase) * warrior_walk;
	q.y -= abs(cos(warrior_phase)) * 0.025 * warrior_walk;
	// Ноги: бедро, колено с накладкой, поножи, острый сабатон.
	for (int i = 0; i < 2; i++) {
		float side = i == 0 ? 1.0 : -1.0;
		float stride = side * swing;
		vec3 hip = vec3(side * 0.11, 0.98, 0.0);
		vec3 knee = vec3(side * 0.12, 0.55 + max(-stride, 0.0) * 0.05, stride * -0.15 - 0.02);
		vec3 ankle = vec3(side * 0.12, 0.13 + max(stride, 0.0) * 0.06, stride * -0.28);
		take(d, m, sd_capsule(q, hip, knee, 0.075), M_DARK);
		take(d, m, sd_capsule(q, knee, ankle, 0.062), M_ARMOR);
		take(d, m, length(q - knee) - 0.082, M_ARMOR);
		take(d, m, sd_capsule(q, ankle + vec3(0.0, -0.05, 0.02), ankle + vec3(0.0, -0.1, -0.2), 0.042), M_ARMOR);
	}
	// Корпус: кираса и пояс.
	take(d, m, sd_box(q - vec3(0.0, 1.32, 0.0), vec3(0.17, 0.2, 0.09)) - 0.05, M_ARMOR);
	take(d, m, sd_box(q - vec3(0.0, 1.08, 0.0), vec3(0.13, 0.08, 0.08)) - 0.02, M_DARK);
	take(d, m, sd_box(q - vec3(0.0, 1.0, 0.0), vec3(0.18, 0.035, 0.115)) - 0.01, M_CLOTH);
	// Табард расходится книзу: спереди и сзади багровый, по бокам серебристые полы.
	float flare = mix(1.35, 0.8, clamp((q.y - 0.2) / 0.8, 0.0, 1.0));
	vec3 panel = vec3(abs(q.x) / flare, q.y - 0.6, abs(q.z) - 0.125);
	take(d, m, sd_box(panel, vec3(0.125, 0.39, 0.018)) * 0.8, M_CLOTH);
	vec3 flap = vec3(abs(q.x) - 0.2 / flare, q.y - 0.66, q.z);
	take(d, m, sd_box(flap, vec3(0.05, 0.32, 0.1)) * 0.8, M_ARMOR);
	// Шарф вокруг шеи и его конец на груди.
	take(d, m, sd_ellipsoid(q - vec3(0.0, 1.59, 0.01), vec3(0.17, 0.085, 0.15)), M_CLOTH);
	take(d, m, sd_box(q - vec3(0.0, 1.49, -0.13), vec3(0.09, 0.06, 0.02)) - 0.012, M_CLOTH);
	// Наплечники и руки: левая висит и качается, правая держит копьё.
	vec3 shoulders = vec3(abs(q.x) - 0.27, q.y - 1.5, q.z);
	take(d, m, sd_ellipsoid(shoulders, vec3(0.1, 0.075, 0.1)), M_ARMOR);
	vec3 elbow_l = vec3(-0.32, 1.2, swing * 0.1);
	vec3 hand_l = vec3(-0.3, 0.96, swing * 0.22 - 0.03);
	take(d, m, sd_capsule(q, vec3(-0.28, 1.46, 0.0), elbow_l, 0.052), M_DARK);
	take(d, m, sd_capsule(q, elbow_l, hand_l, 0.05), M_ARMOR);
	vec3 hand_r = vec3(0.36, 1.2, -0.16);
	vec3 elbow_r = vec3(0.37, 1.2, 0.0);
	take(d, m, sd_capsule(q, vec3(0.28, 1.46, 0.0), elbow_r, 0.052), M_DARK);
	take(d, m, sd_capsule(q, elbow_r, hand_r, 0.05), M_ARMOR);
	take(d, m, length(q - hand_r) - 0.055, M_ARMOR);
	// Копьё: тёмное древко, листовидное серебряное жало.
	take(d, m, sd_capsule(q, vec3(0.36, 0.02, -0.16), vec3(0.36, 2.28, -0.16), 0.024), M_SHAFT);
	float leaf = clamp(1.0 - abs(q.y - 2.4) / 0.15, 0.0, 1.0);
	take(d, m, sd_box(q - vec3(0.36, 2.4, -0.16), vec3(0.05 * leaf + 0.002, 0.15, 0.008)) * 0.7, M_ARMOR);
	// Шлем: заострён кверху, узкая тёмная прорезь Т-образной формы.
	take(d, m, sd_ellipsoid(q - vec3(0.0, 1.78, 0.0), vec3(0.122, 0.155, 0.135)), M_ARMOR);
	take(d, m, sd_capsule(q, vec3(0.0, 1.88, -0.03), vec3(0.0, 2.0, 0.01), 0.022), M_ARMOR);
	take(d, m, sd_box(q - vec3(0.0, 1.8, -0.122), vec3(0.078, 0.014, 0.02)), M_VISOR);
	take(d, m, sd_box(q - vec3(0.0, 1.75, -0.13), vec3(0.012, 0.05, 0.02)), M_VISOR);
	// Плюмаж стекает с гребня назад и колышется.
	float wave = sin(time * 1.4) * 0.02 + swing * 0.015;
	vec3 a = vec3(0.0, 1.97, 0.03);
	vec3 b = vec3(0.02, 2.0, 0.2 + wave);
	vec3 c = vec3(0.06, 1.85, 0.34 + wave * 2.0);
	vec3 e = vec3(0.1, 1.64, 0.38 + wave * 3.0);
	take(d, m, sd_capsule(q, a, b, 0.04), M_PLUME);
	take(d, m, sd_capsule(q, b, c, 0.034), M_PLUME);
	take(d, m, sd_capsule(q, c, e, 0.02), M_PLUME);
}


float scene(vec3 p, out int m) {
	m = M_WALL;
	// Пустота комнаты: расстояние до стен, пола и потолка. Открытые двери добавляют коридор.
	vec3 room_center = vec3(0.0, ROOM.y * 0.5, (ROOM_Z.x + ROOM_Z.y) * 0.5);
	float d = -sd_box(p - room_center, vec3(ROOM.x, ROOM.y * 0.5, (ROOM_Z.y - ROOM_Z.x) * 0.5));
	bool open = door_open > 0.001;
	if (open) {
		// Коридор заходит в комнату на метр: на стыке двух пустот поле не должно падать в ноль.
		float hall_start = ROOM_Z.y - 1.0;
		vec3 hall_center = vec3(0.0, CORRIDOR.y * 0.5, (hall_start + CORRIDOR.z) * 0.5);
		d = max(d, -sd_box(p - hall_center, vec3(CORRIDOR.x, CORRIDOR.y * 0.5, (CORRIDOR.z - hall_start) * 0.5)));
	}
	if (p.y < 0.02) {
		m = M_FLOOR;
	} else if (p.y > ROOM.y - 0.02 || (p.z > ROOM_Z.y && p.y > CORRIDOR.y - 0.02)) {
		m = M_CEIL;
	}
	// Столбы вдоль стен и балки под потолком.
	float pz = p.z - clamp(round(p.z / 1.25) * 1.25, ROOM_Z.x + 0.25, ROOM_Z.y);
	take(d, m, sd_box(vec3(abs(p.x) - ROOM.x, p.y - ROOM.y * 0.5, pz), vec3(0.14, ROOM.y * 0.5, 0.09)), M_PILLAR);
	take(d, m, sd_box(vec3(p.x, p.y - ROOM.y + 0.12, pz), vec3(ROOM.x, 0.1, 0.07)), M_PILLAR);
	sd_bed(p, d, m);
	sd_nightstand(p, d, m);
	// Створки разъезжаются в стороны и уходят вдоль стены; над ними притолока.
	vec3 leaf = vec3(abs(p.x) - 0.6 - door_open * 1.15, p.y - DOOR_HEIGHT * 0.5, p.z - ROOM_Z.y);
	take(d, m, sd_box(leaf, vec3(0.6, DOOR_HEIGHT * 0.5, 0.03)), M_DOOR);
	if (open) {
		take(d, m, sd_box(p - vec3(0.0, (DOOR_HEIGHT + CORRIDOR.y) * 0.5, ROOM_Z.y + 0.04), vec3(CORRIDOR.x + 0.1, (CORRIDOR.y - DOOR_HEIGHT) * 0.5, 0.05)), M_WALL);
		// Столбы коридора и фонари под потолком.
		float hall_z = p.z - clamp(round((p.z - 6.5) / 3.0) * 3.0 + 6.5, 6.5, CORRIDOR.z - 0.5);
		take(d, m, sd_box(vec3(abs(p.x) - CORRIDOR.x, p.y - CORRIDOR.y * 0.5, hall_z), vec3(0.1, CORRIDOR.y * 0.5, 0.1)), M_PILLAR);
		float lamp_z = p.z - clamp(round((p.z - 8.0) / 3.0) * 3.0 + 8.0, 8.0, CORRIDOR.z - 2.0);
		take(d, m, sd_box(vec3(p.x, p.y - 2.5, lamp_z), vec3(0.08, 0.12, 0.08)), M_LANTERN);
		take(d, m, sd_capsule(vec3(p.x, p.y, lamp_z), vec3(0.0, 2.6, 0.0), vec3(0.0, 2.9, 0.0), 0.012), M_PILLAR);
		sd_warrior(p, d, m);
	}
	return d;
}


vec3 normal_at(vec3 p) {
	int unused;
	vec2 e = vec2(0.004, 0.0);
	return normalize(vec3(
		scene(p + e.xyy, unused) - scene(p - e.xyy, unused),
		scene(p + e.yxy, unused) - scene(p - e.yxy, unused),
		scene(p + e.yyx, unused) - scene(p - e.yyx, unused)
	));
}


// Свет: столб из проёма (тёплый розовый), слабый красный отсвет стен, в коридоре — фонари.
vec3 lighting(vec3 p, vec3 n) {
	vec3 to_light = SKY_LIGHT - p;
	float dist = length(to_light);
	vec3 l = to_light / dist;
	vec3 c = vec3(0.30, 0.10, 0.11) * (0.6 + 0.4 * n.y);
	// Пятно света на полу под проёмом, к краям мягко гаснет.
	float pool = exp(-pow(length(p.xz - SKY_LIGHT.xz) / 1.1, 2.0));
	c += vec3(1.0, 0.55, 0.50) * max(dot(n, l), 0.0) * (0.35 + 1.6 * pool) * 4.5 / (1.0 + dist * dist * 0.35);
	// Отражённый от стен красный свет.
	c += vec3(0.35, 0.09, 0.08) * (1.0 - abs(n.y)) * 0.6;
	if (p.z > ROOM_Z.y - 1.0) {
		// Ближайший фонарь коридора и лёгкий холод от лат.
		vec3 lamp = vec3(0.0, 2.45, clamp(round((p.z - 8.0) / 3.0) * 3.0 + 8.0, 8.0, CORRIDOR.z - 2.0)) - p;
		float lamp_dist = length(lamp);
		c += vec3(1.0, 0.66, 0.42) * max(dot(n, lamp / lamp_dist), 0.0) * 3.2 / (1.0 + lamp_dist * lamp_dist * 0.7);
	}
	return c;
}


// Цветок — плоский силуэт, всегда обращённый к смотрящему: красная сердцевина с вертикальной
// щелью-зрачком, вокруг лучатся изогнутые щупальца, красные и поверх них белые.
// u — от центра в долях размера цветка, y вверх.
bool flower_at(vec2 u, out vec3 col, out int ramp, out int level) {
	col = vec3(0.0);
	ramp = RAMP_EDGE;
	level = 0;
	float r = length(u);
	if (r > 1.35) {
		return false;
	}
	float a = atan(u.y, u.x);
	// Белые лежат сверху и длиннее: сначала проверяем их, потом красные.
	for (int layer = 0; layer < 2; layer++) {
		float white = layer == 0 ? 1.0 : 0.0;
		float count = mix(30.0, 24.0, white);
		float curl = (0.7 * sin(r * 6.0 + time * 0.5 + white * 2.0) + 0.25 * sin(a * 3.0 - time * 0.3)) * r;
		float k = (a + curl + white * 0.4) * count / (2.0 * PI);
		float id = round(k);
		float seed = hash21(vec2(mod(id, count), 11.0 + white));
		float reach = mix(0.72 + seed * 0.32, 0.95 + seed * 0.4, white);
		float width = mix(0.075, 0.034, white) * (1.0 - r / reach) + 0.012;
		// Редкие белые пропускаем: сквозь них видно красное.
		if (r < reach && r > 0.2 && abs(k - id) * 2.0 * PI / count * r < width && (white < 0.5 || seed > 0.3)) {
			float g = atan(u.x, u.y) - curl * 0.6;
			level = int(floor(fract(g / PI + 0.125) * 4.0));
			col = mix(vec3(1.0, 0.13, 0.10) * (0.72 + 0.4 * (1.0 - r / reach)), vec3(0.98, 0.93, 0.92), white);
			return true;
		}
	}
	// Сердцевина и зрачок.
	vec2 core = u / vec2(0.3, 0.5);
	if (dot(core, core) < 1.0) {
		float along = u.y / 0.4;
		float breath = 0.062 + 0.018 * sin(time * 0.7);
		if (abs(along) < 1.0 && abs(u.x) < breath * (1.0 - along * along)) {
			col = vec3(0.34, 0.015, 0.05);
			ramp = RAMP_SOLID;
			level = 4;
			return true;
		}
		col = vec3(1.0, 0.11, 0.09) * (0.8 + 0.3 * value_noise(u * 9.0 + time * 0.2));
		ramp = RAMP_DENSE;
		level = 11 + int(value_noise(u * 12.0) * 4.0);
		return true;
	}
	return false;
}


void fragment() {
	vec2 cell = floor(UV * grid_size);
	// Луч из глаза: ячейки вытянуты по вертикали, поле зрения ~ 70° по высоте.
	vec2 ndc = (cell + 0.5 - grid_size * 0.5) * cell_px / (grid_size.y * cell_px.y);
	ndc.y = -ndc.y;
	float cr = cos(cam_roll);
	float sr = sin(cam_roll);
	ndc = vec2(cr * ndc.x - sr * ndc.y, sr * ndc.x + cr * ndc.y);
	vec3 forward = vec3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), -cos(cam_yaw) * cos(cam_pitch));
	vec3 right = normalize(vec3(cos(cam_yaw), 0.0, sin(cam_yaw)));
	vec3 up = cross(right, forward);
	vec3 rd = normalize(forward + (ndc.x * right + ndc.y * up) * 1.4);
	vec3 ro = cam_pos;

	float t = 0.02;
	int m = M_WALL;
	for (int i = 0; i < 90; i++) {
		float d = scene(ro + rd * t, m);
		if (d < 0.002 * t) {
			break;
		}
		t += d;
		if (t > 26.0) {
			break;
		}
	}
	vec3 p = ro + rd * t;
	vec3 n = normal_at(p);
	vec3 light = lighting(p, n);
	float grain = hash21(cell);

	vec3 albedo = vec3(0.5, 0.12, 0.10);
	int ramp = RAMP_DENSE;
	int level = 0;
	vec3 emissive = vec3(0.0);

	if (m == M_WALL) {
		// Панели: вертикальные доски с тёмными швами.
		float along = abs(n.x) > 0.5 ? p.z : p.x;
		float board = fract(along / 0.31);
		albedo = vec3(0.55, 0.16, 0.12) * (0.8 + 0.35 * value_noise(vec2(floor(along / 0.31), p.y * 3.0)));
		// Доски — мягкими редкими знаками, швы — вертикальной чертой: стена спокойная.
		ramp = board < 0.12 ? RAMP_EDGE : RAMP_PATH;
		if (board < 0.12) {
			albedo *= 0.45;
		}
		// Торец коридора: такие же двери, но закрытые.
		if (p.z > CORRIDOR.z - 0.05 && n.z < -0.5 && p.y < DOOR_HEIGHT) {
			m = M_DOOR;
		}
	} else if (m == M_PILLAR) {
		albedo = vec3(0.20, 0.05, 0.05);
		ramp = RAMP_EDGE;
	} else if (m == M_FLOOR) {
		// Доски пола поперёк, по середине — дорожка от дверей.
		float row = fract(p.z / 0.24);
		albedo = vec3(0.30, 0.08, 0.09) * (0.8 + 0.3 * hash21(vec2(floor(p.z / 0.24), floor(p.x / 1.3 + floor(p.z / 0.24) * 0.5))));
		ramp = RAMP_PLANK;
		if (row < 0.1) {
			albedo *= 0.4;
		}
		if (abs(p.x) < 0.55) {
			m = M_RUNNER;
			albedo = vec3(0.42, 0.12, 0.18) * (0.9 + 0.2 * value_noise(p.xz * 4.0));
			ramp = abs(abs(p.x) - 0.5) < 0.04 ? RAMP_EDGE : RAMP_SOLID;
		}
	} else if (m == M_CEIL) {
		albedo = vec3(0.22, 0.06, 0.06);
		ramp = RAMP_PLANK;
		// Световой проём в потолке.
		if (abs(p.x - SKY_LIGHT.x) < 0.55 && abs(p.z - SKY_LIGHT.z) < 0.7) {
			m = M_SKY;
			emissive = vec3(1.0, 0.78, 0.72) * 1.3;
			ramp = RAMP_GLOW;
		}
	} else if (m == M_BED) {
		albedo = vec3(0.42, 0.15, 0.11);
		emissive = vec3(0.06, 0.02, 0.015);
		ramp = abs(n.y) > 0.5 ? RAMP_PLANK : RAMP_DENSE;
	} else if (m == M_LINEN) {
		albedo = vec3(0.85, 0.70, 0.66);
		emissive = vec3(0.13, 0.10, 0.10);
		ramp = RAMP_SOLID;
	} else if (m == M_BLANKET) {
		// Складки одеяла поперёк кровати.
		albedo = vec3(0.56, 0.11, 0.15) * (0.82 + 0.3 * sin(p.z * 19.0 + sin(p.x * 5.0)));
		emissive = vec3(0.08, 0.012, 0.02);
		ramp = RAMP_SOLID;
	} else if (m == M_STAND) {
		albedo = vec3(0.52, 0.20, 0.13);
		emissive = vec3(0.09, 0.03, 0.02);
		ramp = abs(n.y) > 0.5 ? RAMP_PLANK : RAMP_DENSE;
		// Щель вокруг ящика и круглая ручка.
		vec2 front = vec2(p.x - NIGHTSTAND.x, p.y - 0.42);
		if (n.z > 0.5 || n.z < -0.5) {
			if (abs(abs(front.y) - 0.12) < 0.012 && abs(front.x) < 0.24) {
				albedo *= 0.3;
				ramp = RAMP_EDGE;
				level = 2;
			} else if (length(front) < 0.028) {
				albedo = vec3(0.8, 0.62, 0.45);
			}
		}
	} else if (m == M_VASE) {
		// Глазурь: светлая керамика, красная полоса и блик.
		albedo = abs(p.y - 0.84) < 0.03 ? vec3(0.62, 0.08, 0.10) : vec3(0.78, 0.76, 0.78);
		vec3 h = normalize(normalize(SKY_LIGHT - p) - rd);
		emissive = albedo * 0.3 + vec3(1.0, 0.85, 0.82) * pow(max(dot(n, h), 0.0), 20.0) * 0.6;
		ramp = RAMP_DENSE;
	} else if (m == M_STEM) {
		albedo = vec3(0.16, 0.34, 0.2);
		emissive = vec3(0.06, 0.15, 0.08);
		ramp = RAMP_EDGE;
	} else if (m == M_LANTERN) {
		emissive = vec3(1.0, 0.72, 0.42) * (1.05 + 0.1 * sin(time * 2.1 + p.z));
		ramp = RAMP_GLOW;
	} else if (m == M_ARMOR) {
		// Латы: серебро, в прорезях тень, по кромке холодный блик.
		// Красный свет комнаты на них почти не ложится: металл держит свой холодный цвет.
		albedo = vec3(0.22, 0.26, 0.34);
		vec3 h = normalize(vec3(0.0, 1.0, -0.2) - rd);
		float rim = pow(clamp(1.0 + dot(n, rd), 0.0, 1.0), 2.0);
		float facing_up = 0.5 + 0.5 * n.y;
		emissive = vec3(0.58, 0.62, 0.74) * (0.6 + 0.5 * facing_up) + vec3(0.70, 0.74, 0.86) * (rim * 0.55 + pow(max(dot(n, h), 0.0), 14.0) * 0.5);
		ramp = rim > 0.5 ? RAMP_EDGE : RAMP_DENSE;
	} else if (m == M_CLOTH) {
		// Багровый ярче красных стен: табард и шарф не должны в них растворяться.
		albedo = vec3(0.70, 0.05, 0.11);
		emissive = vec3(0.50, 0.03, 0.08);
		ramp = RAMP_DENSE;
		// Заклёпки на поясе.
		vec3 q = to_warrior(p);
		if (abs(q.y - 1.0) < 0.04 && fract(q.x / 0.07) < 0.3) {
			emissive = vec3(0.7, 0.72, 0.8);
		}
	} else if (m == M_DARK) {
		albedo = vec3(0.11, 0.10, 0.13);
		emissive = vec3(0.025, 0.025, 0.035);
		ramp = RAMP_DENSE;
	} else if (m == M_VISOR) {
		albedo = vec3(0.0);
		ramp = RAMP_SNOW;
		level = 0;
	} else if (m == M_PLUME) {
		albedo = vec3(0.86, 0.10, 0.11);
		emissive = vec3(0.72, 0.06, 0.08);
		ramp = RAMP_EDGE;
	} else if (m == M_SHAFT) {
		albedo = vec3(0.30, 0.18, 0.18);
		emissive = vec3(0.34, 0.24, 0.24);
		ramp = RAMP_EDGE;
	}
	if (m == M_DOOR) {
		// Створки: светлая бумага в тёмной решётке, рисунок едет вместе со створкой.
		float slide = p.z < ROOM_Z.y + 1.0 ? door_open * 1.15 * sign(p.x) : 0.0;
		vec2 g = vec2((p.x - slide) / 0.3, p.y / 0.38);
		bool lattice = fract(g.x) < 0.1 || fract(g.y) < 0.1 || abs(p.x - slide) < 0.03;
		albedo = lattice ? vec3(0.30, 0.10, 0.08) : vec3(0.85, 0.62, 0.55);
		ramp = lattice ? RAMP_EDGE : RAMP_PLANK;
		emissive = lattice ? vec3(0.0) : vec3(0.10, 0.05, 0.06);
	}

	vec3 col = albedo * light + emissive;
	// Столб света: интеграл свечения вдоль луча около оси под проёмом.
	vec2 axis = SKY_LIGHT.xz;
	vec2 o = ro.xz - axis;
	vec2 dv = rd.xz;
	float a = dot(dv, dv);
	float closest = clamp(-dot(o, dv) / max(a, 1e-4), 0.0, t);
	vec2 near = o + dv * closest;
	float h_at = ro.y + rd.y * closest;
	float beam = exp(-dot(near, near) / 0.28) * smoothstep(0.0, 0.6, h_at) * smoothstep(ROOM.y + 0.1, ROOM.y - 1.4, h_at * 0.6);
	float dust = 0.0;
	if (beam > 0.25) {
		// Пылинки в луче медленно плывут вниз.
		vec2 dc = cell + vec2(floor(sin(time * 0.4 + cell.y * 0.07) * 2.0), -floor(time * 2.0));
		vec2 id = floor(dc / vec2(7.0, 6.0));
		if (mod(dc, vec2(7.0, 6.0)) == floor(vec2(hash21(id), hash21(id + 3.0)) * vec2(7.0, 6.0)) && hash21(id + 5.0) > 0.55) {
			dust = 1.0;
		}
	}
	col += vec3(1.0, 0.60, 0.55) * beam * 0.55;

	float lum = dot(col, vec3(0.3, 0.55, 0.15));
	if (ramp == RAMP_EDGE) {
		level = int(floor(fract(atan(-n.y, n.x) / 3.14159 + 0.625) * 4.0));
		if (m == M_WALL || m == M_PILLAR || m == M_STEM || m == M_SHAFT) {
			level = 0;
		}
		if (m == M_STAND) {
			level = 2;
		}
	} else if (ramp == RAMP_GLOW) {
		level = 13;
	} else if (m != M_VISOR) {
		level = int(clamp(pow(lum, 0.75) * 15.0 + (grain - 0.5) * 1.6, 1.0, 15.0));
	}
	if (dust > 0.5) {
		ramp = RAMP_FLAKE;
		level = grain > 0.5 ? 5 : 0;
		col = vec3(1.0, 0.85, 0.80);
	}
	// Даль тонет в красном сумраке.
	col = mix(col, vec3(0.08, 0.02, 0.03), clamp((t - 4.0) / 10.0, 0.0, 0.6));

	// Цветок рисуется поверх всего, что за ним: плоскость через его центр лицом к нам.
	vec2 toward = normalize(FLOWER.xz - ro.xz);
	vec3 facing = vec3(toward.x, 0.0, toward.y);
	float along_ray = dot(rd, facing);
	if (along_ray > 0.01) {
		// Чуть ближе своего центра, чтобы стебель не лёг поверх лепестков.
		float ft = dot(FLOWER - facing * 0.04 - ro, facing) / along_ray;
		if (ft > 0.0 && ft < t) {
			vec3 hit = ro + rd * ft - FLOWER;
			vec2 u = vec2(dot(hit, vec3(-facing.z, 0.0, facing.x)), hit.y) / FLOWER_SIZE;
			vec3 petal;
			int petal_ramp;
			int petal_level;
			if (flower_at(u, petal, petal_ramp, petal_level)) {
				col = petal;
				ramp = petal_ramp;
				level = petal_level;
			}
		}
	}
	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), float(ramp * 16 + level) / 255.0);
}
