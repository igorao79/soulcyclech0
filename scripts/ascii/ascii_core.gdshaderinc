// Сцена целиком: расстояния, трассировка, свет и материалы. Общая для мира и слоя героя.
float scene_static(vec3 p, bool reflected, inout int m) {
	float h = world_at(p.xz).r;
	float d = (p.y - h) * 0.75;
	m = MAT_TERRAIN;

	d = min(d, 1000.0);
	int prop_mat = MAT_STONE;
	take(d, m, sd_props(p, prop_mat), prop_mat);

	sd_chapel(p, d, m);
	sd_bell(p, d, m);
	sd_flower(p, d, m);
	if (p.y < 1.0 && p.z > pier_rect.y - 1.0) {
		sd_pier(p, d, m);
	}

	float to_keeper = length(p.xz - keeper_pos.xz);
	if (to_keeper > 1.1 || p.y > keeper_pos.y + 2.2) {
		d = min(d, max(to_keeper - 0.6, p.y - keeper_pos.y - 1.6));
	} else {
		float figure_d = 1000.0;
		int figure_m = m;
		sd_keeper(to_local(p, keeper_pos, keeper_yaw) / FIGURE_SCALE, figure_d, figure_m);
		take(d, m, figure_d * FIGURE_SCALE, figure_m);
	}

	if (reflected && wraith_on > 0.5) {
		float to_wraith = length(p.xz - wraith_pos.xz);
		if (to_wraith > 1.6) {
			d = min(d, to_wraith - 0.9);
		} else {
			float figure_d = 1000.0;
			int figure_m = m;
			sd_wraith(to_local(p, wraith_pos, 0.0) / FIGURE_SCALE, figure_d, figure_m);
			take(d, m, figure_d * FIGURE_SCALE, figure_m);
		}
	}
	return d;
}


// Герой считается отдельно: на экран его рисует свой слой, а в тени и отражениях он есть всегда.
void sd_player(vec3 p, inout float d, inout int m) {
	float to_player = length(p.xz - player_pos.xz);
	// Граница учитывает высоту, иначе лучи над фигурой дают ложную полутень.
	if (to_player > 1.1 || p.y > player_pos.y + 2.2) {
		d = min(d, max(to_player - 0.6, p.y - player_pos.y - 1.6));
	} else {
		vec3 q = to_local(p, player_pos, player_yaw) / FIGURE_SCALE;
		float figure_d = 1000.0;
		int figure_m = m;
		if (player_style == 0) {
			sd_nameless(q, player_phase, player_move, figure_d, figure_m);
		} else {
			sd_wanderer(q, player_phase, player_move, figure_d, figure_m);
		}
		take(d, m, figure_d * FIGURE_SCALE, figure_m);
	}
}


float scene_sdf(vec3 p, bool reflected, inout int m) {
	float d = scene_static(p, reflected, m);
	sd_player(p, d, m);
	return d;
}


// Мир без героя: так персонаж не может уйти под дерево или башню.
float trace_static(vec3 ro, vec3 rd, float tmax, int steps, bool reflected, inout int m) {
	float t = 0.0;
	for (int i = 0; i < steps; i++) {
		float d = scene_static(ro + rd * t, reflected, m);
		if (d < 0.012) {
			return t;
		}
		t += d * 0.92;
		if (t > tmax) {
			return -1.0;
		}
	}
	return t;
}


float trace(vec3 ro, vec3 rd, float tmax, int steps, bool reflected, inout int m) {
	float t = 0.0;
	for (int i = 0; i < steps; i++) {
		float d = scene_sdf(ro + rd * t, reflected, m);
		if (d < 0.012) {
			return t;
		}
		t += d * 0.92;
		if (t > tmax) {
			return -1.0;
		}
	}
	return t;
}


vec3 normal_at(vec3 p, bool reflected) {
	vec3 n = vec3(0.0);
	int unused = 0;
	for (int i = 0; i < 4; i++) {
		vec3 e = 0.5773 * (2.0 * vec3(float(((i + 3) >> 1) & 1), float((i >> 1) & 1), float(i & 1)) - 1.0);
		n += e * scene_sdf(p + 0.012 * e, reflected, unused);
	}
	return normalize(n);
}


float moon_shadow(vec3 p) {
	float result = 1.0;
	float t = 0.08;
	int unused = 0;
	for (int i = 0; i < 16; i++) {
		float d = scene_sdf(p + MOON_DIR * t, false, unused);
		result = min(result, 18.0 * d / t);
		t += clamp(d, 0.05, 1.2);
		if (result < 0.02 || t > 11.0) {
			break;
		}
	}
	return clamp(result, 0.0, 1.0);
}


vec3 light_at(vec3 p, vec3 n, vec3 rd, float shadow) {
	vec3 c = vec3(0.70, 0.76, 0.90) * max(dot(n, MOON_DIR), 0.0) * shadow * 0.85;
	c += vec3(0.13, 0.16, 0.23) * (0.55 + 0.45 * n.y);
	c += vec3(0.36, 0.42, 0.54) * pow(clamp(1.0 + dot(n, rd), 0.0, 1.0), 3.0);
	for (int i = 0; i < 10; i++) {
		if (lanterns[i].y < 0.0) {
			continue;
		}
		vec3 to_lamp = lanterns[i] - p;
		float dd = dot(to_lamp, to_lamp);
		if (dd > 64.0) {
			continue;
		}
		float flicker = 0.9 + 0.1 * sin(time * 7.0 + float(i) * 2.3) * sin(time * 3.1 + float(i));
		float wrap = max(dot(n, to_lamp / sqrt(dd)) * 0.75 + 0.25, 0.0);
		c += vec3(1.15, 0.68, 0.30) * wrap * flicker * 2.4 / (1.0 + dd * 0.85) * (1.0 - dd / 64.0);
	}
	vec3 to_keeper = keeper_pos + vec3(0.0, 1.0, 0.0) - p;
	float keeper_dd = dot(to_keeper, to_keeper);
	c += vec3(0.85, 0.16, 0.20) * max(dot(n, normalize(to_keeper)) * 0.6 + 0.4, 0.0) * 1.1 / (1.0 + keeper_dd * 0.55);
	vec3 to_player = player_pos + vec3(0.0, 1.3, 0.8) - p;
	float player_dd = dot(to_player, to_player);
	c += vec3(0.42, 0.48, 0.60) * max(dot(n, normalize(to_player)) * 0.6 + 0.4, 0.0) * 0.8 / (1.0 + player_dd * 0.16);
	return c;
}


void surface_of(int mat, vec3 p, vec3 n, float garden, out vec3 albedo, out vec3 emissive, out int ramp) {
	emissive = vec3(0.0);
	ramp = RAMP_SOLID;
	albedo = vec3(0.45);
	if (!figure_surface(mat, p, n, albedo, emissive, ramp)) {
		environment_surface(mat, p, n, albedo, emissive, ramp);
	}
	// На неживых поверхностях зимой лежит снег.
	if (garden < 0.5 && (mat == MAT_ROOF || mat == MAT_STONE || mat == MAT_WALL || mat == MAT_WOOD || mat == MAT_TRUNK)) {
		float snow = smoothstep(0.45, 0.85, n.y);
		albedo = mix(albedo, vec3(0.80, 0.88, 1.0), snow * 0.7);
		if (snow > 0.5) {
			ramp = RAMP_PATH;
		}
	}
}
