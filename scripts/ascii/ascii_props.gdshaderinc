// Окружение: деревья, камни, руины, часовня, колокол, мостик, цветок и их материалы.
const int PROP_BOULDER = 8;
const int MAT_RUIN = 40;
const int MAT_BELL = 41;

const float PINE_TIER = 1.0;
// Высота одного ряда знаков на вертикальной стене и на горизонтальном настиле.
const float WALL_ROW = 0.1014;
const float DECK_ROW = 0.1126;

// Руины: те же числа в ascii_world.gd (RUIN_WALLS, RUIN_TOWERS).
const float RUIN_Z = 46.0;
const float RUIN_HEIGHT = 3.0;
const float RUIN_THICK = 0.42;
const vec2 RUIN_BOUND_CENTER = vec2(58.25, 46.0);
const vec2 RUIN_BOUND_HALF = vec2(14.6, 0.95);
const float RUIN_WEST_X = 49.1;
const float RUIN_WEST_HALF = 5.1;
const float RUIN_EAST_X = 67.25;
const float RUIN_EAST_HALF = 5.25;
const float RUIN_TOWER_WEST = 54.2;
const float RUIN_TOWER_EAST = 62.0;


// Ярусы идут с постоянным шагом по высоте: материал узнаёт ярус прямо из p.y.
float sd_pine(vec3 q, float height, float radius, inout int m_out) {
	float r = length(q.xz);
	float base_y = floor(q.y / PINE_TIER) * PINE_TIER;
	float tier = fract(q.y / PINE_TIER);
	float envelope = radius * (1.0 - clamp(base_y / height, 0.0, 1.0));
	float angle = atan(q.z, q.x);
	float rad = envelope * (1.0 - tier * 0.74);
	rad *= 1.0 + 0.10 * sin(angle * 6.0 + base_y * 2.1) + 0.03 * sin(angle * 11.0 - base_y * 3.7);
	float d = (r - rad - 0.03) * 0.5;
	d = max(d, q.y - height);
	d = max(d, height * 0.13 - q.y);
	float trunk = max(r - 0.12, q.y - height * 0.3);
	m_out = trunk < d ? MAT_TRUNK : MAT_PINE;
	return min(d, trunk);
}


// Скальная масса: шар, срезанный плоскостями, с неровной поверхностью.
float sd_boulder(vec3 q, float rad, float seed) {
	vec3 b = q - vec3(0.0, rad * 0.38, 0.0);
	float s = sin(seed * 6.28);
	float c = cos(seed * 6.28);
	b = vec3(c * b.x - s * b.z, b.y, s * b.x + c * b.z);
	float core = length(b * vec3(1.0, 1.18, 1.12)) - rad;
	float facets = max(max(dot(b, vec3(0.62, 0.66, 0.42)), dot(b, vec3(-0.71, 0.55, 0.44))), dot(b, vec3(0.12, 0.72, -0.68)));
	facets = max(facets, dot(b, vec3(-0.20, 0.42, 0.88)));
	float d = max(core, facets - rad * 0.68);
	d += sin(b.x * 2.3 + seed * 9.0) * sin(b.y * 2.9 + 1.0) * sin(b.z * 2.1 + seed * 4.0) * 0.17;
	d += sin(b.x * 6.1 + 2.0) * sin(b.y * 7.3) * sin(b.z * 5.9 + seed * 3.0) * 0.05;
	return d * 0.68;
}


// Секция стены: зубцы на целой части, ступенчатый обвал к внешнему концу.
float sd_ruin_section(vec3 q, float half_len, float outer, float seed, float arch_x) {
	float fall = smoothstep(half_len - 4.2, half_len - 0.2, q.x * outer);
	float broken = max(fall, smoothstep(0.60, 0.86, value_noise(vec2(q.x * 0.42 + seed, seed))) * 0.7);
	float top = floor((RUIN_HEIGHT - broken * 2.5) / 0.36) * 0.36;
	if (broken < 0.1 && abs(fract(q.x / 1.9) - 0.5) < 0.27) {
		top += 0.62;
	}
	// Пилястры дают вертикальные тёмные борозды.
	float thick = RUIN_THICK + (abs(fract(q.x / 3.8 + 0.25) - 0.5) < 0.09 ? 0.2 : 0.0);
	float d = max(max(abs(q.x) - half_len, abs(q.z) - thick), q.y - top);
	float arch = max(length(vec2(q.x - arch_x, max(q.y - 1.05, 0.0))) - 0.9, RUIN_THICK - 0.42 - q.z);
	return max(d, -arch);
}


float sd_ruin_tower(vec3 q, float height) {
	float top = height;
	if (abs(fract(q.x / 0.84) - 0.5) < 0.25) {
		top += 0.42;
	}
	return max(sd_box(vec3(q.x, 0.0, q.z), vec3(0.78, 1.0, 0.78)), q.y - top);
}


void sd_ruin(vec3 p, inout float d, inout int m) {
	float bound = length(max(abs(p.xz - RUIN_BOUND_CENTER) - RUIN_BOUND_HALF, vec2(0.0)));
	if (bound > 0.9) {
		d = min(d, max(bound, p.y - 4.3));
		return;
	}
	float z = p.z - RUIN_Z;
	float wall;
	float tower;
	if (p.x < RUIN_BOUND_CENTER.x) {
		wall = sd_ruin_section(vec3(p.x - RUIN_WEST_X, p.y, z), RUIN_WEST_HALF, -1.0, 3.3, -1.2);
		tower = sd_ruin_tower(vec3(p.x - RUIN_TOWER_WEST, p.y, z), 3.7);
	} else {
		wall = sd_ruin_section(vec3(p.x - RUIN_EAST_X, p.y, z), RUIN_EAST_HALF, 1.0, 8.1, -0.9);
		tower = sd_ruin_tower(vec3(p.x - RUIN_TOWER_EAST, p.y, z), 3.15);
	}
	take(d, m, min(wall, tower) * 0.7, MAT_RUIN);
}


float sd_props(vec3 p, inout int m) {
	if (p.y > 6.5) {
		return p.y - 6.0;
	}
	float d = 1.5;
	ivec2 grid = textureSize(prop_map, 0);
	ivec2 base = ivec2(floor(p.xz / PROP_CELL));
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			ivec2 c = base + ivec2(i, j);
			if (c.x < 0 || c.y < 0 || c.x >= grid.x || c.y >= grid.y) {
				continue;
			}
			vec4 e = texelFetch(prop_map, c, 0);
			int kind = int(e.r * 255.0 + 0.5);
			if (kind == 0) {
				continue;
			}
			vec2 center = (vec2(c) + vec2(0.5) + (e.gb - vec2(0.5)) * PROP_JITTER) * PROP_CELL;
			vec3 q = vec3(p.x - center.x, p.y, p.z - center.y);
			float r = length(q.xz);
			float nd = 1.5;
			int nm = MAT_STONE;
			if (kind == PROP_PINE) {
				if (r > 2.0) {
					nd = r - 1.75;
				} else {
					nd = sd_pine(q, 3.4 + e.a * 2.2, 1.0 + e.a * 0.45, nm);
				}
			} else if (kind == PROP_TREE) {
				if (r > 2.4) {
					nd = r - 2.0;
				} else {
					vec3 h = q - vec3(0.0, 2.3 + e.a * 0.6, 0.0);
					float crown = length(h * vec3(1.0, 1.12, 1.0)) - (1.15 + e.a * 0.4);
					crown += sin(q.x * 3.1 + e.g * 9.0) * sin(q.y * 2.7 + e.b * 5.0) * sin(q.z * 3.3) * 0.2;
					crown += sin(q.x * 7.3) * sin(q.y * 6.9) * sin(q.z * 7.7) * 0.09;
					float trunk = max(r - 0.13, q.y - 2.0);
					nd = min(crown * 0.6, trunk);
					nm = trunk < crown ? MAT_TRUNK : MAT_LEAF;
				}
			} else if (kind == PROP_BUSH) {
				float bush = length(q - vec3(0.0, 0.5, 0.0)) - (0.72 + e.a * 0.3);
				bush += sin(q.x * 4.3 + e.g * 7.0) * sin(q.y * 5.1) * sin(q.z * 4.7) * 0.17;
				nd = bush * 0.7;
				nm = MAT_LEAF;
			} else if (kind == PROP_LANTERN) {
				float post = max(r - 0.045, q.y - 1.75);
				float lamp = length(q - vec3(0.0, 1.83, 0.0)) - 0.1;
				nd = min(post, lamp);
				nm = lamp < post ? MAT_LAMP : MAT_IRON;
			} else if (kind == PROP_GRAVE) {
				nd = sd_box(q - vec3(0.0, 0.55, 0.0), vec3(0.26, 0.5, 0.07)) - 0.05;
				nd = smin(nd, sd_box(q - vec3(0.0, 0.5, 0.0), vec3(0.42, 0.06, 0.06)), 0.02);
			} else if (kind == PROP_ROCK) {
				if (r > 1.7) {
					nd = r - 1.2;
				} else {
					nd = sd_boulder(q, 0.5 + e.a * 0.4, e.g + e.b);
				}
			} else if (kind == PROP_BOULDER) {
				float rad = 1.1 + e.a * 1.7;
				if (r > rad + 1.0) {
					nd = max(r - rad - 0.35, q.y - rad * 1.25 - 0.3);
				} else {
					nd = sd_boulder(q, rad, e.g + e.b);
				}
			} else if (kind == PROP_STUMP) {
				nd = max(r - 0.32, q.y - 0.55);
				nm = MAT_WOOD;
			}
			take(d, m, nd, nm);
		}
	}
	sd_ruin(p, d, m);
	return d;
}


void sd_chapel(vec3 p, inout float d, inout int m) {
	vec3 q = (p - chapel_pos) / CHAPEL_SCALE;
	float r = length(q.xz);
	if (r > 9.0) {
		d = min(d, max((r - 7.5) * CHAPEL_SCALE, q.y * CHAPEL_SCALE - 6.2));
		return;
	}
	float local_d = 1000.0;
	int local_m = MAT_WALL;
	take(local_d, local_m, sd_box(q - vec3(0.0, 2.0, 0.0), vec3(2.6, 2.0, 3.6)), MAT_WALL);
	// Цоколь и угловые контрфорсы фасада.
	take(local_d, local_m, sd_box(q - vec3(0.0, 0.3, 0.0), vec3(2.78, 0.3, 3.78)), MAT_WALL);
	vec3 corner = vec3(abs(q.x) - 2.42, q.y, q.z - 3.72);
	take(local_d, local_m, max(sd_box(corner - vec3(0.0, 1.45, 0.0), vec3(0.3, 1.45, 0.28)), corner.z * 0.7 + corner.y * 0.7 - 2.1), MAT_WALL);
	float roof = max(abs(q.x) * 0.8 + (q.y - 4.0) * 0.6 - 2.35, abs(q.z) - 3.9);
	roof = max(roof, 4.0 - q.y);
	take(local_d, local_m, roof, MAT_ROOF);
	vec3 tower = q - vec3(0.0, 0.0, 3.2);
	take(local_d, local_m, sd_box(tower - vec3(0.0, 3.2, 0.0), vec3(0.95, 3.2, 0.95)), MAT_WALL);
	float spire = max(abs(tower.x) * 0.9 + abs(tower.z) * 0.9 + (tower.y - 6.4) * 0.45 - 0.95, 6.4 - tower.y);
	take(local_d, local_m, spire, MAT_ROOF);
	take(local_d, local_m, sd_box(tower - vec3(0.0, 9.0, 0.0), vec3(0.05, 0.5, 0.05)), MAT_IRON);
	take(local_d, local_m, sd_box(tower - vec3(0.0, 9.1, 0.0), vec3(0.22, 0.05, 0.05)), MAT_IRON);
	take(d, m, local_d * CHAPEL_SCALE, local_m);
}


void sd_bell(vec3 p, inout float d, inout int m) {
	vec3 q = (p - bell_pos) / BELL_SCALE;
	float r = length(q.xz);
	if (r > 3.2) {
		d = min(d, max(r - 2.0, q.y - 3.3) * BELL_SCALE);
		return;
	}
	float local_d = 1000.0;
	int local_m = MAT_WOOD;
	take(local_d, local_m, sd_box(q - vec3(0.0, 0.06, 0.0), vec3(1.5, 0.12, 0.7)) - 0.02, MAT_STONE);
	// Рама: ноги расходятся вперёд и назад, под балкой укосины.
	vec3 leg = vec3(abs(q.x), q.y, abs(q.z));
	take(local_d, local_m, sd_capsule(leg, vec3(1.42, 0.0, 0.5), vec3(1.3, 3.0, 0.0), 0.10), MAT_WOOD);
	take(local_d, local_m, sd_capsule(leg, vec3(1.35, 2.3, 0.0), vec3(0.85, 3.0, 0.0), 0.07), MAT_WOOD);
	take(local_d, local_m, sd_capsule(q, vec3(-1.6, 3.02, 0.0), vec3(1.6, 3.02, 0.0), 0.12), MAT_WOOD);
	// Колокол качается вокруг балки.
	vec3 b = q - vec3(0.0, 2.95, 0.0);
	float s = sin(bell_swing);
	float c = cos(bell_swing);
	b = vec3(b.x * c - b.y * s, b.x * s + b.y * c, b.z);
	// Профиль: плечи, узкая талия и расходящийся край.
	float t = clamp((-b.y - 0.2) / 1.5, 0.0, 1.0);
	float t2 = t * t;
	float bell = (length(b.xz) - (0.3 + 0.12 * t + 0.42 * t2 * t2)) * 0.62;
	bell = max(bell, max(-1.7 - b.y, b.y + 0.2));
	bell = smin(bell, length(b + vec3(0.0, 0.42, 0.0)) - 0.32, 0.08);
	take(local_d, local_m, bell, MAT_BELL);
	take(local_d, local_m, sd_box(b + vec3(0.0, 0.12, 0.0), vec3(0.2, 0.09, 0.1)), MAT_IRON);
	take(local_d, local_m, length(b + vec3(0.0, 1.82, 0.0)) - 0.11, MAT_IRON);
	take(d, m, local_d * BELL_SCALE, local_m);
}


void sd_pier(vec3 p, inout float d, inout int m) {
	vec2 half_size = (pier_rect.zw - pier_rect.xy) * 0.5;
	vec2 center = (pier_rect.zw + pier_rect.xy) * 0.5;
	vec3 q = p - vec3(center.x, pier_top - 0.07, center.y);
	take(d, m, sd_box(q, vec3(half_size.x, 0.07, half_size.y)), MAT_PIER);
	float post_z = q.z - clamp(round(q.z / 3.0) * 3.0, -half_size.y, half_size.y);
	float post_x = abs(q.x) - half_size.x;
	take(d, m, max(length(vec2(post_x, post_z)) - 0.1, q.y - 0.32), MAT_PIER);
}


void sd_flower(vec3 p, inout float d, inout int m) {
	vec3 q = p - flower_pos;
	float r = length(q.xz);
	if (r > 1.0) {
		d = min(d, max(r - 0.6, q.y - 1.15));
		return;
	}
	take(d, m, sd_capsule(q, vec3(0.0), vec3(0.03, 0.7, 0.0), 0.022), MAT_STEM);
	vec3 h = q - vec3(0.03, 0.78, 0.0);
	float angle = atan(h.z, h.x) + sin(time * 0.7) * 0.1;
	float petals = length(h * vec3(1.0, 1.7, 1.0)) - (0.2 + 0.09 * cos(angle * 5.0));
	take(d, m, petals * 0.7, MAT_FLOWER);
}


// Скала: неровный тон, трещины, провалы, резкий переход к тени и светлая верхняя кайма.
vec3 rock_albedo(vec3 p, vec3 n) {
	vec2 uv = p.xz * 1.35 + p.y * vec2(1.15, -0.85);
	float big = value_noise(uv);
	float crack = abs(value_noise(uv * 1.8 + vec2(3.1, 7.7)) - 0.5);
	float fine = value_noise(uv * 6.7 + vec2(1.3, 4.1));
	float lit = smoothstep(0.10, 0.34, dot(n, MOON_DIR));
	float seam = 0.42 + 0.58 * smoothstep(0.02, 0.06, crack);
	float pit = smoothstep(0.24, 0.44, big * 0.65 + fine * 0.35);
	// Тон тёплее серого: лунный свет синий, в сумме камень выходит холодно-серым.
	vec3 c = mix(vec3(0.60, 0.53, 0.42), vec3(1.38, 1.21, 0.97), big * 0.5 + fine * 0.5);
	c *= seam * (0.22 + 0.78 * pit) * (0.18 + 0.82 * lit);
	return mix(c, vec3(1.5, 1.34, 1.08), smoothstep(0.74, 0.94, n.y) * seam * 0.75);
}


// Кладка: ряды блоков со смещением и тёмными швами. Возвращает множитель тона.
float masonry(vec2 uv, vec2 block) {
	float row = floor(uv.y / block.y);
	float x = uv.x / block.x + mod(row, 2.0) * 0.5;
	vec2 id = vec2(floor(x), row);
	float fx = (fract(x) < 0.5 ? fract(x) : 1.0 - fract(x)) * block.x;
	float fy = uv.y - row * block.y;
	if (fy < block.y * 0.25 || fx < 0.03) {
		return 0.42;
	}
	return 0.62 + 0.55 * hash21(id + vec2(7.0, 3.0));
}


// Кладка на грани: ось шва зависит от того, куда смотрит грань.
vec3 wall_stone(vec3 p, vec3 n, vec2 block) {
	vec2 uv = n.y > 0.6 ? p.xz : vec2(abs(n.x) > abs(n.z) ? p.z : p.x, p.y);
	vec3 c = rock_albedo(p, n);
	// Фасад получает меньше луны, чем верх скалы: кладка светлее и холоднее.
	return c * masonry(uv, block) * vec3(1.2, 1.35, 1.65);
}


// Окно с полукруглым верхом и переплётом. dx, dy — от центра окна, половины ширины и высоты.
bool arched(float dx, float dy, float half_w, float half_h) {
	return abs(dx) < half_w && length(vec2(dx, max(dy - (half_h - half_w), 0.0))) < half_w && dy > -half_h;
}


void environment_surface(int mat, vec3 p, vec3 n, inout vec3 albedo, inout vec3 emissive, inout int ramp) {
	if (mat == MAT_PINE) {
		ramp = RAMP_PINE;
		float garden = world_at(p.xz).b;
		float tier = fract(p.y / PINE_TIER);
		vec2 uv = p.xz * 3.1 + p.y * vec2(2.3, -1.7);
		float clump = value_noise(uv);
		float fine = value_noise(uv * 2.6 + vec2(9.0, 2.0));
		// Верх яруса уходит в тень под верхними ветвями: так видны чёрные просветы.
		float open = 1.0 - smoothstep(0.42, 0.62, tier);
		float groups = 0.3 + 0.7 * smoothstep(0.34, 0.46, clump * 0.7 + fine * 0.3);
		vec3 body = garden > 0.5
			? mix(vec3(0.16, 0.50, 0.30), vec3(0.46, 0.95, 0.62), clump)
			: mix(vec3(0.20, 0.42, 0.38), vec3(0.50, 0.80, 0.70), clump);
		albedo = body * groups * (0.10 + 0.90 * open);
		if (garden <= 0.5) {
			float cap = smoothstep(0.42, 0.60, value_noise(uv * 0.55 + vec2(3.0, 1.0)) + (0.3 - tier) * 0.6);
			albedo = mix(albedo, vec3(0.86, 0.94, 1.05), cap * open * smoothstep(0.05, 0.35, n.y));
		}
	} else if (mat == MAT_TRUNK) {
		albedo = vec3(0.30, 0.20, 0.16) * (0.5 + 0.7 * value_noise(p.xz * 13.0 + p.y * 3.0));
	} else if (mat == MAT_LEAF) {
		ramp = RAMP_LEAF;
		vec2 uv = p.xz * 4.2 + p.y * vec2(2.9, -2.1);
		float clump = value_noise(uv);
		float fine = value_noise(uv * 2.7 + vec2(5.0, 1.0));
		float groups = 0.22 + 0.78 * smoothstep(0.32, 0.46, clump * 0.72 + fine * 0.28);
		// Низ кроны тёмный.
		float under = smoothstep(-0.35, 0.55, n.y);
		albedo = mix(vec3(0.20, 0.52, 0.30), vec3(0.52, 0.95, 0.58), clump) * groups * (0.12 + 0.88 * under);
	} else if (mat == MAT_WOOD) {
		albedo = vec3(0.86, 0.60, 0.40) * (0.55 + 0.7 * value_noise(vec2(p.x * 14.0, p.y * 2.5 + p.z * 14.0)));
	} else if (mat == MAT_STONE) {
		albedo = rock_albedo(p, n);
	} else if (mat == MAT_RUIN) {
		vec2 block = vec2(0.86, WALL_ROW * 4.0);
		albedo = wall_stone(p, n, block);
		float z = p.z - RUIN_Z;
		float west = p.x - RUIN_WEST_X + 1.2;
		float east = p.x - RUIN_EAST_X + 0.9;
		bool recess = z < RUIN_THICK - 0.1 && length(vec2(p.x < RUIN_BOUND_CENTER.x ? west : east, max(p.y - 1.05, 0.0))) < 0.92;
		if (recess) {
			albedo *= 0.05;
		} else {
			float garden = world_at(p.xz).b;
			if (garden > 0.5) {
				// В ложбине низ стены затягивает мох.
				float moss = smoothstep(0.45, 0.7, value_noise(p.xz * 1.3 + p.y * 1.1) + (1.2 - p.y) * 0.22);
				albedo = mix(albedo, albedo * vec3(0.42, 0.92, 0.50), moss);
			} else if (n.y > 0.6) {
				albedo = mix(albedo, vec3(0.80, 0.88, 1.0), 0.6);
			}
		}
	} else if (mat == MAT_BELL) {
		vec3 b = (p - bell_pos) / BELL_SCALE - vec3(0.0, 2.95, 0.0);
		float t = clamp((-b.y - 0.2) / 1.5, 0.0, 1.0);
		// Бронза: пояса у плеч и у края, тёмная талия, яркий нижний обод.
		float bands = 0.72 + 0.4 * smoothstep(0.05, 0.0, abs(t - 0.30)) + 0.65 * smoothstep(0.86, 0.96, t);
		bands *= 1.0 - 0.55 * smoothstep(0.04, 0.0, abs(t - 0.78));
		float patina = value_noise(p.xz * 5.0 + p.y * 3.0);
		albedo = mix(vec3(1.05, 0.72, 0.36), vec3(0.62, 0.70, 0.52), patina * patina) * bands;
	} else if (mat == MAT_IRON) {
		albedo = vec3(0.34, 0.40, 0.48);
		ramp = RAMP_BODY;
	} else if (mat == MAT_LAMP) {
		albedo = vec3(0.4);
		emissive = vec3(1.0, 0.70, 0.34);
		ramp = RAMP_GLOW;
	} else if (mat == MAT_WALL) {
		albedo = wall_stone(p, n, vec2(0.7, WALL_ROW * 3.0));
		vec3 q = (p - chapel_pos) / CHAPEL_SCALE;
		// Тёплые окна зала и башни: прямо в материале, без геометрии.
		bool side_window = abs(abs(q.x) - 2.6) < 0.09 && abs(q.y - 2.3) < 0.75
			&& abs(fract(q.z / 2.4 + 0.5) - 0.5) < 0.17;
		bool tower_window = abs(q.z - 4.15) < 0.09 && arched(q.x, q.y - 4.1, 0.3, 0.85);
		bool door = abs(q.z - 4.15) < 0.09 && arched(q.x, q.y - 0.9, 0.46, 0.92);
		bool front_window = abs(q.z - 3.6) < 0.09 && arched(abs(q.x) - 1.6, q.y - 2.4, 0.34, 0.85);
		if (side_window || tower_window || front_window) {
			float dx = tower_window ? q.x : abs(q.x) - 1.6;
			float bars = abs(dx) < 0.045 || abs(fract(q.y * 1.5) - 0.5) < 0.07 ? 0.25 : 1.0;
			emissive = vec3(1.0, 0.66, 0.26) * bars * (0.72 + 0.4 * value_noise(p.xy * 3.0));
			albedo = vec3(0.05);
			ramp = RAMP_GLOW;
		} else if (door) {
			// Доски двери и тёплая щель между створками.
			albedo = vec3(0.20, 0.13, 0.09) * (abs(fract(q.x * 3.2) - 0.5) < 0.12 ? 0.25 : 1.0);
			if (abs(q.x) < 0.035) {
				emissive = vec3(0.6, 0.36, 0.12);
				ramp = RAMP_GLOW;
			}
		}
	} else if (mat == MAT_ROOF) {
		vec3 q = (p - chapel_pos) / CHAPEL_SCALE;
		if (n.z > 0.7 && q.z < 4.0) {
			albedo = wall_stone(p, n, vec2(0.7, WALL_ROW * 3.0));
		} else {
			// Сланец: ряды черепицы, местами снег.
			float row = floor(p.y / (WALL_ROW * 2.0));
			float x = p.x * 2.6 + p.z * 2.6 + mod(row, 2.0) * 0.5;
			float slate = fract(p.y / (WALL_ROW * 2.0)) < 0.5 ? 0.22 : 0.65 + 0.5 * hash21(vec2(floor(x), row));
			albedo = vec3(0.34, 0.37, 0.46) * slate;
			if (world_at(p.xz).b <= 0.5 && value_noise(p.xz * 1.7 + p.y) > 0.58) {
				albedo = vec3(0.72, 0.80, 0.94);
				ramp = RAMP_PATH;
			}
		}
	} else if (mat == MAT_PIER) {
		// Шаг доски кратен строкам сетки: шов всегда ложится ровно на одну строку.
		float row = p.z / (DECK_ROW * 3.0);
		float plank = floor(row);
		albedo = vec3(0.56, 0.40, 0.26) * (0.62 + 0.6 * hash21(vec2(plank, 2.0)));
		ramp = RAMP_PLANK;
		if (fract(row) < 0.33) {
			albedo *= 0.14;
		}
	} else if (mat == MAT_FLOWER) {
		albedo = vec3(0.05, 0.03, 0.08);
		emissive = vec3(0.22, 0.09, 0.40) * (1.0 + 0.45 * sin(time * 1.6));
		ramp = RAMP_BODY;
	} else if (mat == MAT_STEM) {
		albedo = vec3(0.13, 0.22, 0.20);
	}
}
