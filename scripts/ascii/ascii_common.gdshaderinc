// Общие константы, параметры камеры и мира, шум и примитивы SDF.
const int RAMP_SNOW = 0;
const int RAMP_PATH = 1;
const int RAMP_GRASS = 2;
const int RAMP_WATER = 3;
const int RAMP_MIRROR = 4;
const int RAMP_PINE = 5;
const int RAMP_LEAF = 6;
const int RAMP_SOLID = 7;
const int RAMP_BODY = 8;
const int RAMP_GLOW = 10;
const int RAMP_FLAKE = 11;
const int RAMP_PLANK = 12;

const int MAT_TERRAIN = 0;
const int MAT_PINE = 1;
const int MAT_TRUNK = 2;
const int MAT_LEAF = 3;
const int MAT_WOOD = 4;
const int MAT_STONE = 5;
const int MAT_IRON = 6;
const int MAT_LAMP = 7;
const int MAT_WALL = 8;
const int MAT_ROOF = 9;
const int MAT_PIER = 10;
const int MAT_COAT = 11;
const int MAT_SHIRT = 12;
const int MAT_SKIN = 13;
const int MAT_HAIR_DARK = 14;
const int MAT_HAIR_BLOND = 15;
const int MAT_TUNIC = 16;
const int MAT_BOOT = 17;
const int MAT_ROBE = 22;
const int MAT_CRIMSON = 23;
const int MAT_EYE = 24;
const int MAT_WRAITH = 25;
const int MAT_WRAITH_EYE = 26;
const int MAT_FLOWER = 27;
const int MAT_STEM = 28;
const int MAT_EYE_DARK = 29;
const int MAT_TROUSER = 30;
const int MAT_SHOE = 31;
const int MAT_STAFF = 32;
const int MAT_STOLE = 33;
const int MAT_BUCKLE = 34;
const int MAT_BOOK = 35;
// Материалы фигур: два диапазона, между ними цветок и стебель.
const int MAT_FIGURE_LAST = 35;

const int PROP_PINE = 1;
const int PROP_TREE = 2;
const int PROP_BUSH = 3;
const int PROP_LANTERN = 4;
const int PROP_GRAVE = 5;
const int PROP_ROCK = 6;
const int PROP_STUMP = 7;

const float PROP_CELL = 3.0;
const float PROP_JITTER = 0.7;
const float HEAD_ROOM = 14.0;
const float CHAPEL_SCALE = 0.62;
const float BELL_SCALE = 0.82;
const float FIGURE_SCALE = 0.72;
const vec3 MOON_DIR = vec3(-0.46, 0.74, 0.49);

uniform sampler2D world_map : filter_linear, repeat_disable;
uniform sampler2D prop_map : filter_nearest, repeat_disable;
uniform vec2 world_size = vec2(120.0, 90.0);
uniform vec2 grid_size = vec2(200.0, 60.0);
uniform vec2 cell_world = vec2(0.08, 0.15);
uniform vec2 cam_cell = vec2(0.0);
uniform float cam_sin = 0.8;
uniform float cam_cos = 0.6;
uniform float time = 0.0;

uniform vec3 player_pos = vec3(0.0);
uniform float player_yaw = 0.0;
uniform float player_phase = 0.0;
uniform float player_move = 0.0;
// 0 — стоит, 1 — сидит на земле, обхватив колени. Пока только у Безымянного.
uniform float player_sit = 0.0;
// 0 — стоит, 1 — сидит на стуле у стола, руки на столешнице. Только у Безымянного.
uniform float player_chair = 0.0;
// 1 — несёт книгу в правой руке.
uniform float player_book = 0.0;
// 1 — потягивается: руки над головой, корпус прогнут назад.
uniform float player_stretch = 0.0;
uniform vec2 player_lean = vec2(0.0);
uniform vec2 coat_lag = vec2(0.0);
uniform int player_style = 0;
uniform vec3 keeper_pos = vec3(0.0);
uniform float keeper_yaw = 0.0;
uniform vec3 wraith_pos = vec3(0.0);
uniform float wraith_on = 0.0;
uniform float tolls = 0.0;
// Вода — открытый океан: валы с пеной вместо ряби, у кромки нет стеблей.
uniform float sea_on = 0.0;
uniform vec3 bell_pos = vec3(0.0);
uniform float bell_swing = 0.0;
uniform vec3 chapel_pos = vec3(0.0);
// Руины на северном краю ложбины есть только на перекрёстке ASCII-ночи.
uniform float ruins_on = 1.0;
uniform vec3 flower_pos = vec3(0.0);
uniform vec4 pier_rect = vec4(0.0);
uniform float pier_top = 0.42;
uniform vec3 lanterns[10];
uniform vec3 ripples[8];
uniform vec3 footprints[32];


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}


vec4 world_at(vec2 xz) {
	return textureLod(world_map, xz / world_size, 0.0);
}


float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}


float sd_capsule(vec3 p, vec3 a, vec3 b, float r) {
	vec3 pa = p - a;
	vec3 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}


// Вертикальный конус со скруглёнными концами: плащи, туловища, колокол.
float sd_taper(vec3 p, float y0, float r0, float y1, float r1) {
	float h = clamp((p.y - y0) / (y1 - y0), 0.0, 1.0);
	return length(vec3(p.x, p.y - mix(y0, y1, h), p.z)) - mix(r0, r1, h);
}


float sd_box(vec3 p, vec3 b) {
	vec3 q = abs(p) - b;
	return length(max(q, vec3(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}


void take(inout float d, inout int m, float nd, int nm) {
	if (nd < d) {
		d = nd;
		m = nm;
	}
}


vec3 to_local(vec3 p, vec3 origin, float yaw) {
	vec3 q = p - origin;
	float s = sin(yaw);
	float c = cos(yaw);
	return vec3(c * q.x - s * q.z, q.y, s * q.x + c * q.z);
}
