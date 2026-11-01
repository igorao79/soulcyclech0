// Первый проход: каждая точка SubViewport — одна ячейка символьной сетки.
// Сцена целиком описана SDF-функциями и трассируется из ортографической камеры.
// RGB — цвет символа, A — код символа: (ряд в атласе * 16 + столбец) / 255.
// Для травы столбец хранит наклон штриха, его рисует второй проход. Героя здесь нет, у него свой слой.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://scripts/ascii/ascii_common.gdshaderinc"
#include "res://scripts/ascii/ascii_figures.gdshaderinc"
#include "res://scripts/ascii/ascii_props.gdshaderinc"


#include "res://scripts/ascii/ascii_core.gdshaderinc"
#include "res://scripts/ascii/ascii_ground.gdshaderinc"
#include "res://scripts/ascii/ascii_water.gdshaderinc"
#include "res://scripts/ascii/ascii_particles.gdshaderinc"


void fragment() {
	vec2 cell = floor(UV * grid_size);
	vec2 wc = cell - floor(grid_size * 0.5) + cam_cell;
	vec3 rd = vec3(0.0, -cam_sin, -cam_cos);
	vec3 ground = vec3((wc.x + 0.5) * cell_world.x, 0.0, (wc.y + 0.5) * cell_world.y / cam_sin);
	float t_ground = HEAD_ROOM / cam_sin;
	vec3 ro = ground - rd * t_ground;

	vec3 col = vec3(0.0);
	int ramp = RAMP_SOLID;
	int level = 0;

	int mat = MAT_TERRAIN;
	float t = trace_static(ro, rd, t_ground + 2.0 / cam_sin, 60, false, mat);
	bool water = t < 0.0 || t > t_ground;
	vec3 p = water ? ground : ro + rd * t;

	if (water) {
		shade_water(p, rd, wc, col, ramp, level);
	} else {
		float garden = world_at(p.xz).b;
		bool in_grass = garden > 0.5 && mat != MAT_TERRAIN && mat != MAT_PIER && p.y - world_at(p.xz).r < 0.10
			&& hash21(wc + vec2(5.0, 1.0)) < 0.8 && world_at(p.xz).r > 0.04;
		if (mat == MAT_TERRAIN || in_grass) {
			float shadow = moon_shadow(p + vec3(0.0, 0.05, 0.0));
			shade_ground(p, rd, wc, shadow, col, ramp, level);
		} else {
			vec3 n = normal_at(p, false);
			vec3 albedo;
			vec3 emissive;
			surface_of(mat, p, n, garden, albedo, emissive, ramp);
			float shadow = moon_shadow(p + n * 0.03);
			col = albedo * light_at(p, n, rd, shadow) * 1.25 + emissive;
			if (ramp == RAMP_FIGURE) {
				figure_glyph(mat, wc, col, level);
			} else {
				if (ramp == RAMP_BODY) {
					col = pow(col + albedo * 0.12, vec3(0.85));
					col = max(col, vec3(0.17, 0.17, 0.22));
				}
				float lum = dot(col, vec3(0.3, 0.55, 0.15));
				level = int(clamp(pow(lum, 0.8) * 15.0 + (hash21(wc) - 0.5) * 1.8, 1.0, 15.0));
			}
		}
	}
	apply_particles(wc, ground, water, col, ramp, level);

	// Края кадра тонут в ночи.
	vec2 v = (cell / grid_size - vec2(0.5)) * vec2(1.45, 1.55);
	float vignette = smoothstep(1.1, 0.3, length(v));
	col *= mix(0.28, 1.0, vignette);

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), float(ramp * 16 + level) / 255.0);
}
