// Комната храма от первого лица: первый проход, по точке на ячейку символьной сетки.
// Красные деревянные стены панелями между тёмными столбами, балки под потолком,
// световой проём в потолке — из него столб розового света падает на помост, где на
// лакированной подставке лежит изогнутый тёмный меч с красным камнем у гарды.
// Сзади — постель на полу и раздвижные двери. RGB — цвет знака, A — код знака:
// (ряд в атласе * 16 + яркость) / 255, его разворачивает temple_glyph.gdshader.
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
const int M_DAIS = 5;
const int M_STAND = 6;
const int M_BLADE = 7;
const int M_GUARD = 8;
const int M_GEM = 9;
const int M_GRIP = 10;
const int M_FUTON = 11;
const int M_DOOR = 12;
const int M_SKY = 13;
const int M_RUNNER = 14;

// Комната: полуширина, полудлина, высота. Те же числа в temple_wake.gd.
const vec3 ROOM = vec3(2.6, 3.2, 5.0);
const vec3 DAIS = vec3(0.0, 0.0, -2.6);
const vec3 SKY_LIGHT = vec3(0.0, 3.2, -2.6);

uniform vec2 grid_size = vec2(288.0, 101.0);
uniform vec2 cell_px = vec2(5.0, 8.0);
uniform vec3 cam_pos = vec3(0.0, 1.6, 3.0);
uniform float cam_yaw = 0.0;
uniform float cam_pitch = 0.0;
uniform float cam_roll = 0.0;
uniform float time = 0.0;


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


void take(inout float d, inout int m, float nd, int nm) {
	if (nd < d) {
		d = nd;
		m = nm;
	}
}


// Подставка и меч на помосте. q — от центра верха помоста.
void sd_sword_stand(vec3 q, inout float d, inout int m) {
	if (length(q) > 1.4) {
		d = min(d, length(q) - 1.2);
		return;
	}
	take(d, m, sd_box(q - vec3(0.0, 0.04, 0.0), vec3(0.62, 0.04, 0.16)) - 0.01, M_STAND);
	take(d, m, sd_box(q - vec3(0.0, 0.09, 0.0), vec3(0.5, 0.012, 0.11)), M_STAND);
	vec3 sym = vec3(abs(q.x), q.y, q.z);
	// Стойки, их подкосы и рогульки, на которых лежит клинок.
	take(d, m, sd_capsule(sym, vec3(0.36, 0.08, 0.0), vec3(0.36, 0.56, 0.0), 0.035), M_STAND);
	take(d, m, sd_box(sym - vec3(0.36, 0.42, 0.0), vec3(0.07, 0.018, 0.05)), M_STAND);
	take(d, m, sd_capsule(sym, vec3(0.44, 0.09, 0.0), vec3(0.37, 0.24, 0.0), 0.03), M_STAND);
	take(d, m, length(sym - vec3(0.36, 0.58, 0.0)) - 0.042, M_STAND);
	// Клинок: изогнутый, тёмный, остриём влево; хвостовик вправо.
	float x = q.x;
	float bend = 0.035 * (1.0 - pow(clamp((x + 0.15) / 0.75, -1.0, 1.0), 2.0));
	vec3 b = q - vec3(0.0, 0.47 + bend, 0.0);
	float tip = smoothstep(-0.55, -0.72, x);
	float blade = sd_box(b - vec3(-0.09, 0.0, 0.0), vec3(0.62, 0.03 * (1.0 - tip) + 0.004, 0.008));
	take(d, m, blade, M_BLADE);
	take(d, m, sd_box(q - vec3(0.56, 0.47, 0.0), vec3(0.018, 0.06, 0.05)), M_GUARD);
	take(d, m, length(q - vec3(0.56, 0.47, 0.055)) - 0.018, M_GEM);
	take(d, m, sd_capsule(q, vec3(0.58, 0.47, 0.0), vec3(0.8, 0.475, 0.0), 0.017), M_GRIP);
}


float scene(vec3 p, out int m) {
	m = M_WALL;
	// Внутренность комнаты: расстояние до стен, пола и потолка.
	float d = -sd_box(p - vec3(0.0, ROOM.y * 0.5, 0.0), vec3(ROOM.x, ROOM.y * 0.5, ROOM.z));
	if (p.y < 0.02) {
		m = M_FLOOR;
	} else if (p.y > ROOM.y - 0.02) {
		m = M_CEIL;
	}
	// Столбы вдоль стен и балки под потолком.
	float pz = p.z - clamp(round(p.z / 1.25) * 1.25, -ROOM.z, ROOM.z);
	take(d, m, sd_box(vec3(abs(p.x) - ROOM.x, p.y - ROOM.y * 0.5, pz), vec3(0.14, ROOM.y * 0.5, 0.09)), M_PILLAR);
	take(d, m, sd_box(vec3(p.x, p.y - ROOM.y + 0.12, pz), vec3(ROOM.x, 0.1, 0.07)), M_PILLAR);
	// Помост под световым проёмом.
	vec3 dq = p - DAIS;
	take(d, m, sd_box(dq - vec3(0.0, 0.25, 0.4), vec3(0.85, 0.25, 1.35)) - 0.01, M_DAIS);
	// Подставка крупнее человеческого роста в долю: меч должен читаться издалека.
	vec3 sq = (dq - vec3(0.0, 0.5, -0.3)) / 1.35;
	float sd = 1000.0;
	int sm = m;
	sd_sword_stand(sq, sd, sm);
	take(d, m, sd * 1.35, sm);
	// Постель на полу у дверей.
	take(d, m, sd_box(p - vec3(0.0, 0.06, 3.4), vec3(0.55, 0.06, 1.05)) - 0.03, M_FUTON);
	take(d, m, sd_box(p - vec3(0.0, 0.13, 4.25), vec3(0.32, 0.06, 0.16)) - 0.04, M_FUTON);
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


// Свет: столб из проёма (тёплый розовый), слабый красный отсвет стен, тень от меча — нет.
vec3 lighting(vec3 p, vec3 n) {
	vec3 to_light = SKY_LIGHT - p;
	float dist = length(to_light);
	vec3 l = to_light / dist;
	vec3 c = vec3(0.30, 0.10, 0.11) * (0.6 + 0.4 * n.y);
	// Пятно света на полу и помосте под проёмом, к краям мягко гаснет.
	float pool = exp(-pow(length(p.xz - SKY_LIGHT.xz) / 1.1, 2.0));
	c += vec3(1.0, 0.55, 0.50) * max(dot(n, l), 0.0) * (0.35 + 1.6 * pool) * 4.5 / (1.0 + dist * dist * 0.35);
	// Отражённый от стен красный свет.
	c += vec3(0.35, 0.09, 0.08) * (1.0 - abs(n.y)) * 0.6;
	return c;
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
		if (t > 14.0) {
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
		// Раздвижные двери в стене за постелью: светлые рамки с решёткой.
		if (n.z < -0.5 && abs(p.x) < 1.2 && p.y < 2.3) {
			m = M_DOOR;
			vec2 g = vec2(p.x / 0.3, p.y / 0.38);
			bool lattice = fract(g.x) < 0.1 || fract(g.y) < 0.1 || abs(p.x) < 0.03;
			albedo = lattice ? vec3(0.30, 0.10, 0.08) : vec3(0.85, 0.62, 0.55);
			ramp = lattice ? RAMP_EDGE : RAMP_PLANK;
			emissive = lattice ? vec3(0.0) : vec3(0.10, 0.05, 0.06);
		}
	} else if (m == M_PILLAR) {
		albedo = vec3(0.20, 0.05, 0.05);
		ramp = RAMP_EDGE;
	} else if (m == M_FLOOR) {
		// Доски пола поперёк, по середине — дорожка к помосту.
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
		// Световой проём над помостом.
		if (abs(p.x - SKY_LIGHT.x) < 0.55 && abs(p.z - SKY_LIGHT.z) < 0.7) {
			m = M_SKY;
			emissive = vec3(1.0, 0.78, 0.72) * 1.3;
			ramp = RAMP_GLOW;
		}
	} else if (m == M_DAIS) {
		albedo = vec3(0.28, 0.06, 0.12);
		ramp = abs(n.y) > 0.5 ? RAMP_SOLID : RAMP_DENSE;
	} else if (m == M_STAND) {
		// Красный лак с бликом.
		albedo = vec3(0.70, 0.10, 0.12);
		vec3 h = normalize(normalize(SKY_LIGHT - p) - rd);
		emissive = vec3(1.0, 0.6, 0.6) * pow(max(dot(n, h), 0.0), 24.0) * 0.8;
		ramp = RAMP_DENSE;
	} else if (m == M_BLADE) {
		// Почти чёрная сталь, по долу бежит красноватый отблеск света.
		albedo = vec3(0.06, 0.03, 0.04);
		float sheen = smoothstep(0.6, 1.0, sin(p.x * 9.0 - time * 0.6) * 0.5 + 0.5);
		emissive = vec3(0.55, 0.10, 0.14) * (0.25 + 0.75 * sheen) + vec3(0.9, 0.7, 0.7) * step(0.97, fract(p.x * 3.1 + 0.2)) * 0.6;
		ramp = RAMP_EDGE;
	} else if (m == M_GUARD) {
		albedo = vec3(0.6, 0.08, 0.10);
		ramp = RAMP_DENSE;
	} else if (m == M_GEM) {
		emissive = vec3(1.0, 0.45, 0.55) * (0.9 + 0.3 * sin(time * 1.7));
		ramp = RAMP_GLOW;
	} else if (m == M_GRIP) {
		// Витая рукоять.
		albedo = vec3(0.25, 0.06, 0.06) * (fract(p.x * 30.0 + p.y * 10.0) < 0.5 ? 0.5 : 1.0);
		ramp = RAMP_EDGE;
	} else if (m == M_FUTON) {
		albedo = vec3(0.72, 0.55, 0.52);
		ramp = RAMP_SOLID;
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
		if (m == M_WALL || m == M_PILLAR) {
			level = 0;
		}
		if (m == M_BLADE || m == M_GRIP) {
			level = 2;
		}
	} else if (ramp == RAMP_GLOW) {
		level = 13;
	} else {
		level = int(clamp(pow(lum, 0.75) * 15.0 + (grain - 0.5) * 1.6, 1.0, 15.0));
	}
	if (dust > 0.5) {
		ramp = RAMP_FLAKE;
		level = grain > 0.5 ? 5 : 0;
		col = vec3(1.0, 0.85, 0.80);
	}
	// Даль тонет в красном сумраке.
	col = mix(col, vec3(0.08, 0.02, 0.03), clamp((t - 4.0) / 10.0, 0.0, 0.6));
	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), float(ramp * 16 + level) / 255.0);
}
