// Земля: снег, тропа и поле травы (сами штрихи травы рисует ascii_grass).
// Яркость ячейки травы хранится притушенной: второй проход умножает её на GRASS_GAIN.
const float GRASS_STORE = 0.4545;
const vec3 GRASS_DIM = vec3(0.10, 0.34, 0.24);
const vec3 GRASS_LIT = vec3(0.28, 0.63, 0.41);


vec3 ground_normal(vec2 xz) {
	float e = 0.35;
	float dx = world_at(xz + vec2(e, 0.0)).r - world_at(xz - vec2(e, 0.0)).r;
	float dz = world_at(xz + vec2(0.0, e)).r - world_at(xz - vec2(0.0, e)).r;
	return normalize(vec3(-dx, 2.0 * e, -dz));
}


// Сжимает свет: луна не красит землю в синий, у фонарей остаётся тёплый оттенок.
vec3 night_light(vec3 light) {
	float lum = dot(light, vec3(0.3, 0.55, 0.15));
	float shade = 1.35 * (1.0 - exp(-max(lum - 0.1, 0.0) * 2.2));
	vec3 hue = light / max(lum, 0.01) / vec3(0.81, 0.98, 1.46);
	return shade * mix(vec3(1.0), clamp(hue, vec3(0.4), vec3(1.6)), 0.55);
}


// Символ и цвет для земли: снег, тропа или живая трава в ложбине.
void shade_ground(vec3 p, vec3 rd, vec2 wc, float shadow, out vec3 col, out int ramp, out int level) {
	vec4 w = world_at(p.xz);
	vec3 n = ground_normal(p.xz);
	vec3 light = night_light(light_at(p, n, rd, shadow));
	float cell_hash = hash21(wc);
	float cell_hash2 = hash21(wc + vec2(41.0, 17.0));

	float print_mark = 0.0;
	for (int i = 0; i < 32; i++) {
		if (footprints[i].z >= 0.0) {
			float dist = length(p.xz - footprints[i].xy);
			if (dist < 0.15) {
				print_mark = max(print_mark, 1.0 - footprints[i].z / 45.0);
			}
		}
	}

	float fine = value_noise(p.xz * 2.7);
	float edge = (fine - 0.5) * 0.34 + (cell_hash - 0.5) * 0.3;
	bool is_garden = w.b + (value_noise(p.xz * 0.9) - 0.5) * 0.35 + (cell_hash - 0.5) * 0.28 > 0.5;
	bool on_path = w.g + edge > 0.55;
	if (is_garden && !on_path) {
		// У самой воды трава редеет: голая тёмная земля с отдельными травинками.
		if (w.r + (fine - 0.5) * 0.09 + (cell_hash2 - 0.5) * 0.1 < 0.03) {
			ramp = RAMP_PATH;
			col = vec3(0.13, 0.14, 0.12) * light;
			level = int(cell_hash * 4.0);
			return;
		}
		ramp = RAMP_GRASS;
		float clump = value_noise(p.xz * 0.55);
		vec3 tone = mix(GRASS_DIM, GRASS_LIT, smoothstep(0.22, 0.78, clump * 0.7 + fine * 0.3));
		// Тёмные просветы между куртинами.
		tone *= mix(0.42, 1.0, smoothstep(0.16, 0.42, fine * 0.65 + clump * 0.35));
		col = tone * (light * 0.85 + vec3(0.25)) * GRASS_STORE;

		// След приминает траву. Как она гнётся и качается, считает ascii_grass_field.gd.
		bool pressed = print_mark > 0.0;
		if (pressed) {
			col *= 0.8;
		}
		level = pressed ? 8 : 0;
		return;
	}

	// Дюны вытянуты поперёк ветра, тёмной стороной отвёрнуты от луны.
	float bend = sin(p.x * 0.31 + sin(p.z * 0.23) * 1.7) * 1.1;
	vec2 dune_uv = p.xz * vec2(0.22, 0.6) + vec2(0.0, bend);
	float dune = value_noise(dune_uv);
	float slope = dune - value_noise(dune_uv + vec2(0.12, -0.36));
	float relief = clamp(0.5 + slope * 3.6 + (dune - 0.5) * 0.9, 0.0, 1.0);
	float lit = dot(light, vec3(0.3, 0.55, 0.15));
	// Плотность знаков повторяет рельеф: на гребне густо, в провале пусто.
	float density = smoothstep(0.2, 0.8, relief) * smoothstep(0.05, 0.5, lit + 0.1);

	if (on_path) {
		ramp = RAMP_PATH;
		vec3 ground_tone = is_garden ? vec3(0.30, 0.28, 0.23) * mix(0.6, 1.0, fine) : vec3(0.46, 0.50, 0.54) * mix(0.5, 1.1, relief);
		col = ground_tone * (light * 0.8 + vec3(0.2));
		if (print_mark > 0.0) {
			col *= mix(1.0, 0.45, print_mark);
			level = 5 + int(cell_hash * 3.0);
			return;
		}
		if (is_garden) {
			float lum = dot(col, vec3(0.3, 0.55, 0.15));
			level = int(clamp(lum * 7.0 + fine * 7.0 + cell_hash * 5.0 - 4.5, 0.0, 15.0));
		} else {
			level = cell_hash2 < density * 0.85 ? 2 + int(clamp(relief * 9.0 + cell_hash * 2.0 - 1.0, 0.0, 9.99)) : 0;
		}
		return;
	}

	ramp = RAMP_SNOW;
	col = mix(vec3(0.30, 0.34, 0.40), vec3(0.92, 0.97, 1.0), relief) * (light * 1.0 + vec3(0.42));

	if (print_mark > 0.0) {
		col *= mix(1.0, 0.45, print_mark);
		ramp = RAMP_PATH;
		level = 5 + int(cell_hash * 3.0);
		return;
	}

	// Поземка ползёт длинными полосами и только по освещённым склонам.
	float streak = value_noise(vec2(p.x * 0.55 - time * 0.45, p.z * 7.0 + bend));
	if (streak > 0.57 && relief > 0.3 && relief < 0.86 && cell_hash2 > 0.3) {
		level = 8 + int(clamp((streak - 0.57) * 11.0, 0.0, 3.99));
	} else if (relief > 0.86 && cell_hash2 > 0.95) {
		// Гребень: редкие плотные знаки.
		level = 12 + int(cell_hash * 3.99);
	} else if (cell_hash2 < density * 0.68) {
		level = 1 + int(clamp(relief * 5.2 + (cell_hash - 0.5) * 2.0, 0.0, 6.99));
	} else {
		level = cell_hash2 > 0.97 ? 1 : 0;
	}
}
