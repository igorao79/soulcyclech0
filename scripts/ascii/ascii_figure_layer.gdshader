// Слой героя: сетка жёстко привязана к экрану, поэтому фигура не дрожит, пока под ней едет мир.
// Формат тот же, что у прохода мира. Ряд 15 значит, что героя заслоняет постройка: он просвечивает.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://scripts/ascii/ascii_common.gdshaderinc"
#include "res://scripts/ascii/ascii_figures.gdshaderinc"
#include "res://scripts/ascii/ascii_props.gdshaderinc"
#include "res://scripts/ascii/ascii_core.gdshaderinc"

const int RAMP_GHOST = 15;

uniform vec2 layer_size = vec2(56.0, 44.0);


float figure_only(vec3 p, inout int m) {
	float d = 1000.0;
	sd_player(p, d, m);
	return d;
}


vec3 figure_normal(vec3 p) {
	vec3 n = vec3(0.0);
	int unused = 0;
	for (int i = 0; i < 4; i++) {
		vec3 e = 0.5773 * (2.0 * vec3(float(((i + 3) >> 1) & 1), float((i >> 1) & 1), float(i & 1)) - 1.0);
		n += e * figure_only(p + 0.012 * e, unused);
	}
	return normalize(n);
}


void fragment() {
	vec2 cell = floor(UV * layer_size);
	vec2 offset = cell + vec2(0.5) - layer_size * 0.5;
	vec3 rd = vec3(0.0, -cam_sin, -cam_cos);
	vec3 ground = vec3(
		player_pos.x + offset.x * cell_world.x,
		0.0,
		// Слой центрирован там же, где камера: на точке, куда проецируются ступни героя.
		player_pos.z - player_pos.y * cam_cos / cam_sin + offset.y * cell_world.y / cam_sin
	);
	float t_ground = HEAD_ROOM / cam_sin;
	vec3 ro = ground - rd * t_ground;

	float t = t_ground - 5.0 / cam_sin;
	float t_end = t_ground + 3.0 / cam_sin;
	int mat = MAT_TERRAIN;
	bool hit = false;
	for (int i = 0; i < 48 && t < t_end; i++) {
		float d = figure_only(ro + rd * t, mat);
		if (d < 0.008) {
			hit = true;
			break;
		}
		t += d * 0.9;
	}
	vec3 p = ro + rd * t;
	// То, что ниже глади, скрыто водой: герой стоит в ней по щиколотку.
	if (!hit || p.y < 0.0) {
		COLOR = vec4(0.0);
	} else {
		vec3 n = figure_normal(p);
		vec3 albedo = vec3(0.45);
		vec3 emissive = vec3(0.0);
		int ramp = RAMP_FIGURE;
		figure_surface(mat, p, n, albedo, emissive, ramp);
		vec3 lighting = light_at(p, n, rd, moon_shadow(p + n * 0.03));
		vec3 col = albedo * lighting * 1.25 + emissive;
		int level = 0;
		if (ramp == RAMP_FIGURE) {
			figure_glyph(mat, p, cell, dot(lighting, vec3(0.3, 0.55, 0.15)), col, level);
		} else {
			float lum = dot(col, vec3(0.3, 0.55, 0.15));
			level = int(clamp(pow(lum, 0.8) * 15.0, 1.0, 15.0));
		}
		int blocker = MAT_TERRAIN;
		float t_block = trace_static(ro, rd, t - 0.05, 48, false, blocker);
		if (t_block >= 0.0 && t_block < t - 0.05 && blocker != MAT_TERRAIN) {
			ramp = RAMP_GHOST;
		}
		COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), float(ramp * 16 + level) / 255.0);
	}
}
