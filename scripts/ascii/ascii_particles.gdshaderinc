// Частицы поверх мира: снег, пылинки и колечки над травой, пыль из-под ног.
// Столбцы рампы RAMP_FLAKE: 0–3 дальний снег, 4–7 ближний, 8 пылинка над водой,
// 9 пылинка над травой (её рисует второй проход), 10 и 11 колечки.
const int FLAKE_LEVEL_WATER = 8;
const int FLAKE_LEVEL_MOTE = 9;
const int FLAKE_LEVEL_RING = 10;
const int FLAKE_LEVEL_RING_SMALL = 11;


// Слой снега: чем больше layer, тем ближе, крупнее, реже и быстрее.
bool particle_at(vec2 wc, float layer, float fall, out float strength) {
	vec2 tile = vec2(6.0 + layer * 2.0, 4.0 + layer);
	float gust = sin(time * 0.4 + layer) * 2.0;
	vec2 v = wc + vec2(floor(time * (1.2 + layer) + gust), -floor(time * fall));
	vec2 id = floor(v / tile);
	vec2 pos = floor(vec2(hash21(id + layer), hash21(id + layer + 11.0)) * tile);
	strength = hash21(id + layer + 23.0);
	return mod(v, tile) == pos && strength > 0.2;
}


// Пылинка живёт в своей клетке и медленно бродит по ней, не перескакивая в соседнюю.
bool mote_at(vec2 wc, vec2 tile, float salt, float density, out vec2 offset, out float phase) {
	vec2 id = floor(wc / tile);
	float present = hash21(id + salt);
	// Густота плавает пятнами, чтобы поле не выглядело ровной сеткой.
	if (present > density * (0.55 + 0.65 * hash21(floor(id / 5.0) + salt))) {
		return false;
	}
	phase = hash21(id + salt + 4.0) * 6.28;
	vec2 room = tile - vec2(3.0, 1.0);
	vec2 home = vec2(hash21(id + salt + 8.0), hash21(id + salt + 13.0)) * room;
	home += vec2(sin(time * 0.31 + phase), cos(time * 0.23 + phase) * 0.6) * 0.5 + vec2(0.5, 0.3);
	offset = floor(mod(wc, tile)) - floor(clamp(home, vec2(0.0), room));
	return true;
}


void apply_particles(vec2 wc, vec3 ground, bool water, inout vec3 col, inout int ramp, inout int level) {
	// Снег не дырявит фигуру: силуэт важнее редкой снежинки на пальто.
	if (ramp == RAMP_FIGURE) {
		return;
	}
	vec4 w = world_at(ground.xz);
	bool in_garden = w.b >= 0.6;
	float strength = 0.0;

	if (!in_garden) {
		// Дальний снег мелкий и тусклый, ближний крупный и светится.
		for (int i = 4; i >= 0; i--) {
			float layer = float(i);
			if (particle_at(wc, layer, 4.0 + layer * 4.5, strength)) {
				float depth = layer / 4.0;
				col = vec3(0.78, 0.84, 0.90) * mix(0.2, 0.95, depth * depth) * (0.8 + strength * 0.2);
				ramp = RAMP_FLAKE;
				if (i == 4) {
					level = 7;
				} else if (i == 3) {
					level = strength > 0.6 ? 6 : 5;
				} else if (i == 2) {
					level = 4;
				} else {
					level = int(strength * 3.99);
				}
				break;
			}
		}
	} else {
		// Отдельные стебли заходят в воду: край не повторяет линию берега.
		if (water) {
			float reed = 1.0 + w.r / 0.22;
			if (reed > 0.0 && hash21(wc + vec2(31.0, 8.0)) < reed * (0.1 + 1.1 * value_noise(ground.xz * 2.3))) {
				col = mix(GRASS_DIM, GRASS_LIT, hash21(wc + vec2(3.0, 19.0))) * GRASS_STORE * 0.7;
				ramp = RAMP_GRASS;
				level = 3 + int(hash21(wc + vec2(7.0, 2.0)) * 2.0);
			}
		}
		vec2 offset = vec2(0.0);
		float phase = 0.0;
		if (ramp == RAMP_GRASS) {
			if (mote_at(wc, vec2(4.0, 4.0), 0.0, 0.95, offset, phase) && offset == vec2(0.0)) {
				float blink = 0.5 + 0.5 * sin(time * 1.3 + phase);
				col = vec3(0.92, 1.0, 0.93) * (0.72 + 0.28 * blink);
				ramp = RAMP_FLAKE;
				level = FLAKE_LEVEL_MOTE;
			} else if (mote_at(wc, vec2(9.0, 6.0), 50.0, 0.7, offset, phase)) {
				// Колечки иногда стоят парой, а между ними пылинка.
				bool twin = phase > 4.7;
				if (offset == vec2(0.0) || (twin && offset == vec2(2.0, 0.0))) {
					col = vec3(0.62, 0.80, 0.70) * (0.6 + 0.15 * sin(time * 0.9 + phase));
					ramp = RAMP_FLAKE;
					level = phase < 1.2 ? FLAKE_LEVEL_RING_SMALL : FLAKE_LEVEL_RING;
				} else if (twin && offset == vec2(1.0, 0.0)) {
					col = vec3(0.92, 1.0, 0.93) * 0.85;
					ramp = RAMP_FLAKE;
					level = FLAKE_LEVEL_MOTE;
				}
			}
		} else if (water && mote_at(wc, vec2(11.0, 7.0), 90.0, 0.35, offset, phase) && offset == vec2(0.0)) {
			// Над чёрной водой почти ничего: редкая еле заметная пылинка.
			col = vec3(0.34, 0.40, 0.42) * (0.3 + 0.2 * sin(time * 0.8 + phase));
			ramp = RAMP_FLAKE;
			level = FLAKE_LEVEL_WATER;
		}
	}
}
