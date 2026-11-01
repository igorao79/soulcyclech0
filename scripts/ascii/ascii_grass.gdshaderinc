// Трава: тонкие штрихи поверх символьной сетки, с точностью до пикселя.
// Корень каждой травинки стоит в ячейке с рампой RAMP_GRASS. Форма травинки считается из
// хэша мировой ячейки, а текстура читается, только если пиксель попал в её возможный контур.
// Столбец ячейки: бит 3 — травинка примята. Изгиб приходит из физики, текстура grass_bend.
// Цвет в ячейке притушен (GRASS_GAIN), чтобы подложка второго прохода оставалась чёрной.
const int BLADE_REACH = 2;
const int BLADES_PER_CELL = 2;
const float BLADE_BEND = 1.0;
const float GRASS_GAIN = 2.2;
// Совпадают с константами ascii_grass_field.gd.
const float BEND_RANGE = 1.6;
const float GRASS_FIELD_SIZE = 16.0;
// Рядом с героем травинка может согнуться сильнее, поэтому там проверяем больше соседей.
const int NEAR_SLOT_REACH = 5;
const float NEAR_BEND = 2.5;
const float HERO_ZONE_PX = 900.0;
const int FLAKE_NEAR = 7;
const int FLAKE_MOTE = 9;
const int FLAKE_RING = 10;
const int FLAKE_RING_SMALL = 11;


uint blade_hash(ivec2 id) {
	uint h = uint(id.x) * 1597334677u ^ uint(id.y) * 3812015801u;
	h *= 1597334677u;
	return h ^ (h >> 15u);
}


float hash_byte(uint h, uint shift) {
	return float((h >> shift) & 255u) / 255.0;
}


// Пылинка рисуется здесь же: ядро и мягкий ореол в пределах своей ячейки.
vec4 flake_glow(vec2 px, ivec2 c, ivec2 origin, vec3 tint, int level) {
	float scale = cell_px.x / 10.0;
	vec2 center = (vec2(c) + vec2(0.5)) * cell_px;
	float core = 0.0;
	float halo = 0.1;
	if (level == FLAKE_MOTE) {
		uint h = blade_hash(c + origin);
		center += vec2(hash_byte(h, 0u) - 0.5, hash_byte(h, 8u) - 0.5) * vec2(3.0, 6.0) * scale;
		float size = mix(1.2, 2.3, hash_byte(h, 16u)) * scale;
		core = 1.0 - smoothstep(size, size + 1.2 * scale, length(px - center));
		halo = 0.36;
	} else if (level == FLAKE_NEAR) {
		halo = 0.16;
	}
	vec2 to_edge = min(px - vec2(c) * cell_px, vec2(c + ivec2(1)) * cell_px - px);
	float window = smoothstep(0.0, 2.5 * scale, min(to_edge.x, to_edge.y));
	float d = length(px - center) / (2.1 * scale);
	float light = max(core, exp(-d * d) * halo * window);
	return vec4(tint, light);
}


// min_row >= 0: только травинки перед этой строкой, те что закрывают ноги героя.
vec4 grass_strokes(vec2 px, ivec2 c, ivec2 grid, int min_row) {
	vec3 color = vec3(0.0);
	float alpha = 0.0;
	float scale = cell_px.x / 10.0;
	bool near_hero = length(px - (screen_px * 0.5 + scroll_px)) < HERO_ZONE_PX;
	int slot_reach = near_hero ? NEAR_SLOT_REACH : 2;
	float lean_limit = near_hero ? NEAR_BEND : 1.0;
	float reach_x = lean_limit * BLADE_BEND * cell_px.x;
	float slot_px = cell_px.x / float(BLADES_PER_CELL);
	int slot = int(floor(px.x / slot_px));
	ivec2 origin = ivec2(cam_cell) - grid / 2;

	// От ближних корней к дальним: ближняя травинка перекрывает дальнюю и ноги героя.
	for (int dr = BLADE_REACH; dr >= 0 && alpha < 0.97; dr--) {
		int row = c.y + dr;
		if (row >= grid.y || row < min_row) {
			continue;
		}
		for (int ds = -slot_reach; ds <= slot_reach; ds++) {
			int blade_slot = slot + ds;
			ivec2 root = ivec2(blade_slot / BLADES_PER_CELL, row);
			if (blade_slot < 0 || root.x >= grid.x) {
				continue;
			}
			uint h = blade_hash(ivec2(blade_slot + origin.x * BLADES_PER_CELL, row + origin.y));
			float base_y = (float(row) + 0.35 + hash_byte(h, 8u) * 0.65) * cell_px.y;
			float blade = cell_px.y * (1.45 + hash_byte(h, 16u) * 1.55);
			float rise = base_y - px.y;
			if (rise <= 0.0 || rise >= blade) {
				continue;
			}
			float base_x = (float(blade_slot) + 0.1 + hash_byte(h, 0u) * 0.8) * slot_px;
			float dx = px.x - base_x;
			if (abs(dx) > reach_x * min(rise / blade * 1.6, 1.0) + 1.9 * scale) {
				continue;
			}
			vec4 s = texelFetch(scene_tex, root, 0);
			int code = int(s.a * 255.0 + 0.5);
			if ((code >> 4) != RAMP_GRASS) {
				continue;
			}
			if ((code & 8) != 0) {
				blade *= 0.58;
				if (rise >= blade) {
					continue;
				}
			}
			uint k = h * 2654435769u;
			vec2 id = vec2(float(blade_slot) * 0.5 + float(origin.x), float(row + origin.y));
			// Изгиб из физики. Отклонённая травинка ниже, а к камере наклоняется и короче.
			vec2 ground = (id + vec2(0.25, 0.5)) * vec2(cell_world.x, cell_world.y / cam_sin);
			vec2 bend = (textureLod(grass_bend, ground / GRASS_FIELD_SIZE, 0.0).rg * 2.0 - 1.0) * BEND_RANGE;
			bend *= 0.7 + 0.6 * hash_byte(k, 12u);
			blade *= clamp(1.0 - length(bend) * 0.26 - bend.y * 0.16, 0.42, 1.0);
			if (rise >= blade) {
				continue;
			}
			float t = rise / blade;
			// Свой наклон у каждой травинки, у пучка свой, общий ветер едва заметен.
			float tuft = hash21(floor(id / vec2(3.0, 2.0))) - 0.5;
			float phase = hash_byte(k, 0u) * 6.28;
			float sway = sin(time * (0.8 + hash_byte(k, 8u)) + phase) * 0.09;
			sway += sin(id.x * 0.05 + id.y * 0.09 + time * 0.7) * 0.16;
			float lean = (hash_byte(k, 16u) - 0.5) * 1.2 + tuft * 0.6 + sway + bend.x * 1.9;
			lean = clamp(lean, -lean_limit, lean_limit);
			float x = dx - lean * BLADE_BEND * cell_px.x * t * (0.55 + 0.45 * t);
			float width = mix(1.3, 0.6, t) * scale;
			float cover = 1.0 - smoothstep(width - 0.55, width + 0.55, abs(x));
			if (cover <= 0.0) {
				continue;
			}
			float pick = hash_byte(k, 24u);
			vec3 tone = s.rgb * GRASS_GAIN * (0.46 + 0.74 * pick);
			float tall = hash_byte(h, 24u);
			if (tall > 0.965) {
				tone = tone * 1.5 + vec3(0.12, 0.17, 0.13) * dot(s.rgb, vec3(2.2));
			}
			// Низ травинки уходит в чёрный.
			tone *= mix(0.05, 1.0, smoothstep(0.0, 0.42, t));
			color += tone * cover * (1.0 - alpha);
			alpha += cover * (1.0 - alpha);
		}
	}

	vec4 own = texelFetch(scene_tex, c, 0);
	int own_code = int(own.a * 255.0 + 0.5);
	if (min_row < 0 && (own_code >> 4) == RAMP_FLAKE) {
		int level = own_code & 15;
		if (level == FLAKE_NEAR || (level >= FLAKE_MOTE && level <= FLAKE_RING_SMALL)) {
			vec4 glow = flake_glow(px, c, origin, own.rgb, level);
			color = color * (1.0 - glow.a) + glow.rgb * glow.a;
			alpha += glow.a * (1.0 - alpha);
		}
	}
	return vec4(color / max(alpha, 0.001), alpha);
}
