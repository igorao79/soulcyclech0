// Персонажи: геометрия SDF и материалы фигур. Образ сверен с assets/portraits и assets/sprites.
// Ячейка сетки примерно 0.083 × 0.125 в локальных единицах фигуры: тоньше деталь не прочитается.
const int RAMP_FIGURE = 14;
// Опорная нога едет назад ровно со скоростью героя, поэтому ступня не скользит:
// STEP_LENGTH в ascii_demo.gd = GAIT_REACH * FIGURE_SCALE / GAIT_STANCE.
const float GAIT_STANCE = 0.55;
const float GAIT_REACH = 0.52;


// x — вынос стопы вперёд, y — подъём, z — наклон носка.
vec3 gait_foot(float phase) {
	float t = fract(phase / TAU);
	if (t < GAIT_STANCE) {
		float s = t / GAIT_STANCE;
		return vec3(GAIT_REACH * (1.0 - 2.0 * s), smoothstep(0.7, 1.0, s) * 0.05, smoothstep(0.6, 1.0, s) * -0.08);
	}
	float s = (t - GAIT_STANCE) / (1.0 - GAIT_STANCE);
	float e = s * s * (3.0 - 2.0 * s);
	return vec3(GAIT_REACH * (2.0 * e - 1.0), sin(s * PI) * 0.17, mix(-0.08, 0.05, e));
}


void sd_leg(vec3 q, float side, float phase, float amount, float bob, bool thighs, int trouser, int shoe, inout float d, inout int m) {
	vec3 pose = gait_foot(phase) * amount;
	vec3 hip = vec3(side * 0.11, 0.90 + bob, 0.0);
	vec3 foot = vec3(side * 0.12, 0.09 + pose.y, pose.x);
	// Колено сгибается только в переносе: опорная нога почти прямая.
	vec3 knee = mix(hip, foot, 0.5) + vec3(0.0, 0.0, 0.03 + pose.y * 0.7);
	if (thighs) {
		take(d, m, sd_capsule(q, hip, knee, 0.085), trouser);
	}
	take(d, m, sd_capsule(q, knee, foot, 0.072), trouser);
	take(d, m, sd_capsule(q, foot, foot + vec3(0.0, -0.02 + pose.z, 0.15), 0.072), shoe);
}


// Корпус наклоняется в движение и перекручивается навстречу шагу. Возвращает мах ног.
float apply_body_motion(inout vec3 q, float phase, float amount, out float bob) {
	float swing = cos(phase) * amount;
	bob = (0.5 - 0.5 * cos(phase * 2.0)) * 0.03 * amount;
	q.x -= player_lean.x * q.y;
	q.z -= player_lean.y * q.y;
	return swing;
}


void twist_upper_body(inout vec3 q, float phase, float amount, float bob) {
	q.y -= bob + sin(time * 1.7) * 0.012 * (1.0 - amount);
	// Таз переносится на опорную ногу, плечи идут навстречу шагу.
	q.x += sin(phase) * 0.035 * amount;
	float twist = -cos(phase) * amount * 0.2 * smoothstep(0.75, 1.3, q.y);
	float s = sin(twist);
	float c = cos(twist);
	q = vec3(c * q.x - s * q.z, q.y, s * q.x + c * q.z);
}


// Безымянный: спутанные чёрные волосы, бледное лицо с большими чёрными глазами,
// длинное угольное пальто с высоким воротом, распахнутое над светлой рубашкой.
void sd_nameless(vec3 q, float phase, float amount, inout float d, inout int m) {
	float bob;
	float swing = apply_body_motion(q, phase, amount, bob);
	sd_leg(q, -1.0, phase, amount, bob, false, MAT_COAT, MAT_HAIR_DARK, d, m);
	sd_leg(q, 1.0, phase + PI, amount, bob, false, MAT_COAT, MAT_HAIR_DARK, d, m);
	twist_upper_body(q, phase, amount, bob);

	// Полы отстают от героя и раскачиваются тем сильнее, чем ближе к подолу.
	float low = clamp(1.22 - q.y, 0.0, 1.0);
	low *= low;
	vec2 hem = coat_lag + vec2(sin(phase) * amount * 0.09 + sin(time * 1.1) * 0.03, 0.0);
	vec3 body = vec3(q.x - hem.x * low, q.y, (q.z - hem.y * low) * 1.22);
	float coat = max(sd_taper(body, 0.12, 0.38, 1.17, 0.20), 0.34 - q.y);
	// Разрез спереди идёт до подола и расходится книзу, как на портрете.
	float opening = max(max(abs(body.x) - (0.085 + low * 0.10), 0.03 - body.z), q.y - 1.27);
	float vent = max(abs(body.x) - max(0.72 - q.y, 0.0) * 0.12, -0.03 - body.z);
	coat = max(coat, -min(opening, vent));
	take(d, m, sd_taper(q, 0.42, 0.17, 1.26, 0.11), MAT_SHIRT);
	take(d, m, coat * 0.8, MAT_COAT);
	// Высокий ворот стоит за шеей и расходится вперёд.
	vec3 collar = vec3(abs(q.x), q.y, q.z);
	take(d, m, sd_capsule(collar, vec3(0.13, 1.26, 0.05), vec3(0.16, 1.44, -0.11), 0.07), MAT_COAT);

	// Широкие рукава: кисть бледная и заметная.
	vec3 hand_l = vec3(-0.31, 0.74 + abs(swing) * 0.04, -swing * 0.30);
	vec3 hand_r = vec3(0.31, 0.74 + abs(swing) * 0.04, swing * 0.30);
	take(d, m, sd_capsule(q, vec3(-0.235, 1.26, 0.0), hand_l + vec3(0.0, 0.08, 0.0), 0.095), MAT_COAT);
	take(d, m, sd_capsule(q, vec3(0.235, 1.26, 0.0), hand_r + vec3(0.0, 0.08, 0.0), 0.095), MAT_COAT);
	take(d, m, length(q - hand_l) - 0.062, MAT_SKIN);
	take(d, m, length(q - hand_r) - 0.062, MAT_SKIN);

	take(d, m, length((q - vec3(0.0, 1.56, 0.03)) * vec3(0.92, 1.0, 1.0)) - 0.2, MAT_SKIN);
	vec3 strands = q + vec3(coat_lag.x, 0.0, coat_lag.y) * -0.1;
	vec3 side_hair = vec3(abs(strands.x) - 0.19, strands.y - 1.50, strands.z + 0.10);
	float hair = length(strands - vec3(0.0, 1.68, -0.05)) - 0.225;
	hair = smin(hair, length(strands - vec3(0.0, 1.50, -0.12)) - 0.18, 0.07);
	hair = smin(hair, length(side_hair) - 0.085, 0.06);
	// Спутанные пряди рвут край силуэта.
	hair -= max(sin(q.x * 19.0 + 0.7) * sin(q.y * 17.0 + q.x * 5.0) * sin(q.z * 16.0 + 1.3), 0.0) * 0.15;
	// Чёлка падает до самых глаз, но лицо остаётся открытым.
	hair = max(hair, -(length(q - vec3(0.0, 1.46, 0.35)) - 0.34));
	take(d, m, hair * 0.6, MAT_HAIR_DARK);
	take(d, m, length(vec3(abs(q.x) - 0.09, (q.y - 1.545) * 0.85, q.z - 0.19)) - 0.043, MAT_EYE_DARK);
}


// Странник: светлые волнистые волосы, кремовая вязаная туника, кожаные наручи,
// кружка пива перед собой и вторая рука на поясе.
void sd_wanderer(vec3 q, float phase, float amount, inout float d, inout int m) {
	float bob;
	float swing = apply_body_motion(q, phase, amount, bob);
	sd_leg(q, -1.0, phase, amount, bob, true, MAT_BOOT, MAT_BOOT, d, m);
	sd_leg(q, 1.0, phase + PI, amount, bob, true, MAT_BOOT, MAT_BOOT, d, m);
	twist_upper_body(q, phase, amount, bob);

	float low = clamp(1.1 - q.y, 0.0, 1.0);
	vec3 body = vec3(q.x - coat_lag.x * low * 0.5, q.y, (q.z - coat_lag.y * low * 0.5) * 1.22);
	take(d, m, max(sd_taper(body, 0.62, 0.26, 1.24, 0.20), 0.56 - q.y), MAT_TUNIC);

	// Правая рука упёрта в бок: просвет у локтя виден в силуэте.
	vec3 hand_r = vec3(0.235, 0.86, 0.09 + swing * 0.10);
	vec3 elbow_r = vec3(0.43, 1.04, -0.02 + swing * 0.08);
	take(d, m, sd_capsule(q, vec3(0.235, 1.26, 0.0), elbow_r, 0.085), MAT_TUNIC);
	take(d, m, sd_capsule(q, elbow_r, hand_r, 0.07), MAT_TUNIC);
	// Кожаный наруч у запястья.
	take(d, m, length(q - mix(hand_r, elbow_r, 0.28)) - 0.085, MAT_BOOT);
	take(d, m, length(q - hand_r) - 0.058, MAT_SKIN);

	// Левая несёт кружку перед грудью, пена покачивается вместе с шагом.
	vec3 mug_at = vec3(-0.22, 1.02 + abs(swing) * 0.02, 0.27 - swing * 0.04);
	vec3 hand_l = mug_at + vec3(-0.12, -0.03, -0.02);
	vec3 elbow_l = vec3(-0.40, 0.96, 0.02 - swing * 0.06);
	take(d, m, sd_capsule(q, vec3(-0.235, 1.26, 0.0), elbow_l, 0.085), MAT_TUNIC);
	take(d, m, sd_capsule(q, elbow_l, hand_l, 0.07), MAT_TUNIC);
	take(d, m, length(q - mix(hand_l, elbow_l, 0.28)) - 0.085, MAT_BOOT);
	take(d, m, length(q - hand_l) - 0.058, MAT_SKIN);

	vec3 mug = q - mug_at;
	take(d, m, max(length(mug.xz) - 0.125, abs(mug.y) - 0.15), MAT_BEER);
	take(d, m, length((mug - vec3(0.0, 0.15, 0.0)) * vec3(1.0, 1.5, 1.0)) - 0.11, MAT_FOAM);

	take(d, m, length(q - vec3(0.0, 1.56, 0.03)) - 0.185, MAT_SKIN);
	// Волнистая шапка заметно шире головы и закрывает уши.
	float hair = length(q - vec3(0.0, 1.67, -0.05)) - 0.245;
	hair = smin(hair, length(vec3(abs(q.x) - 0.20, q.y - 1.49, q.z + 0.05)) - 0.115, 0.08);
	hair += sin(q.x * 19.0 + q.y * 6.0) * sin(q.y * 17.0 - q.z * 5.0) * sin(q.z * 17.0 + 0.8) * 0.06;
	hair = max(hair, -(length(q - vec3(0.0, 1.47, 0.32)) - 0.30));
	take(d, m, hair * 0.7, MAT_HAIR_BLOND);
	take(d, m, length(vec3(abs(q.x) - 0.085, (q.y - 1.55) * 0.85, q.z - 0.175)) - 0.042, MAT_EYE_DARK);
}


// Смотритель: острый капюшон, тёмный балахон, бледное лицо в тени, красные глаза и багровая кайма.
void sd_keeper(vec3 q, inout float d, inout int m) {
	q.y -= sin(time * 1.3) * 0.012;
	vec3 body = vec3(q.x, q.y, q.z * 1.12);
	float robe = sd_taper(body, 0.03, 0.43, 1.30, 0.16);
	take(d, m, robe, q.y < 0.19 + sin(q.x * 13.0) * 0.02 ? MAT_CRIMSON : MAT_ROBE);
	take(d, m, length(q - vec3(0.0, 1.50, 0.05)) - 0.175, MAT_SKIN);
	// Капюшон сужается к острию, откинутому назад.
	vec3 cowl = vec3(q.x, q.y, q.z + 0.06 + max(q.y - 1.55, 0.0) * 0.45);
	float rim = length(q - vec3(0.0, 1.42, 0.31)) - 0.29;
	take(d, m, max(sd_taper(cowl, 1.52, 0.275, 1.98, 0.04), -rim), rim < 0.05 ? MAT_CRIMSON : MAT_ROBE);
	take(d, m, length(vec3(abs(q.x) - 0.08, (q.y - 1.51) * 0.8, q.z - 0.19)) - 0.05, MAT_EYE);
	// Рукава считаются один раз: фигура симметрична.
	vec3 mirrored = vec3(abs(q.x), q.y, q.z);
	take(d, m, sd_capsule(mirrored, vec3(0.21, 1.24, 0.06), vec3(0.31, 0.84, 0.15), 0.088), q.y < 0.90 ? MAT_CRIMSON : MAT_ROBE);
}


// Эхо колокола: круглая голова, колокольное тело и прорези глаз.
void sd_wraith(vec3 q, inout float d, inout int m) {
	q.y -= 0.12 + sin(time * 1.1) * 0.05;
	float body = sd_taper(q, 0.0, 0.56, 1.45, 0.25);
	body += sin(q.y * 9.0 + time * 2.0 + atan(q.z, q.x) * 3.0) * 0.015;
	take(d, m, smin(body, length(q - vec3(0.0, 1.78, 0.0)) - 0.26, 0.08), MAT_WRAITH);
	take(d, m, sd_box(vec3(abs(q.x) - 0.11, q.y - 1.80, q.z - 0.24), vec3(0.075, 0.018, 0.04)), MAT_WRAITH_EYE);
}


// Возвращает true, если материал принадлежит фигуре.
bool figure_surface(int mat, vec3 p, vec3 n, inout vec3 albedo, inout vec3 emissive, inout int ramp) {
	ramp = RAMP_FIGURE;
	if (mat == MAT_COAT) {
		albedo = vec3(0.115, 0.115, 0.13);
		emissive = vec3(0.03, 0.03, 0.035);
	} else if (mat == MAT_SHIRT) {
		albedo = vec3(0.62, 0.60, 0.58);
		emissive = vec3(0.26, 0.25, 0.24);
	} else if (mat == MAT_SKIN) {
		albedo = vec3(0.66, 0.60, 0.56);
		emissive = vec3(0.36, 0.32, 0.30);
	} else if (mat == MAT_HAIR_DARK) {
		albedo = vec3(0.05, 0.05, 0.06);
		emissive = vec3(0.012, 0.012, 0.016);
	} else if (mat == MAT_HAIR_BLOND) {
		albedo = vec3(0.58, 0.48, 0.30);
		emissive = vec3(0.20, 0.165, 0.10);
	} else if (mat == MAT_TUNIC) {
		albedo = vec3(0.66, 0.62, 0.50);
		emissive = vec3(0.25, 0.235, 0.18);
	} else if (mat == MAT_BOOT) {
		albedo = vec3(0.19, 0.13, 0.10);
		emissive = vec3(0.045, 0.032, 0.025);
	} else if (mat == MAT_BEER) {
		albedo = vec3(0.40, 0.28, 0.08);
		emissive = vec3(0.56, 0.38, 0.12);
	} else if (mat == MAT_FOAM) {
		albedo = vec3(0.60, 0.58, 0.52);
		emissive = vec3(0.55, 0.53, 0.47);
	} else if (mat == MAT_ROBE) {
		albedo = vec3(0.16, 0.12, 0.24);
		emissive = vec3(0.04, 0.03, 0.07);
	} else if (mat == MAT_CRIMSON) {
		albedo = vec3(0.20, 0.03, 0.05);
		emissive = vec3(0.50, 0.055, 0.10);
		ramp = RAMP_GLOW;
	} else if (mat == MAT_EYE) {
		albedo = vec3(0.2);
		emissive = vec3(1.0, 0.13, 0.20);
		ramp = RAMP_GLOW;
	} else if (mat == MAT_WRAITH) {
		albedo = vec3(0.08, 0.12, 0.20);
		emissive = vec3(0.12, 0.20, 0.30);
		ramp = RAMP_BODY;
	} else if (mat == MAT_WRAITH_EYE) {
		albedo = vec3(0.2);
		emissive = mix(vec3(0.55, 0.85, 1.0), vec3(1.0, 0.3, 0.38), clamp(tolls / 3.0, 0.0, 1.0)) * 1.3;
		ramp = RAMP_GLOW;
	} else if (mat == MAT_EYE_DARK) {
		albedo = vec3(0.0);
	} else {
		ramp = RAMP_SOLID;
		return false;
	}
	return true;
}


// Знак выбирается по материалу, а не по яркости: фигура остаётся плотной массой с чистым рисунком.
// Номера знаков — ряд 14 в ascii_font_atlas.gd.
void figure_glyph(int mat, vec2 wc, inout vec3 col, inout int level) {
	float grain = hash21(wc);
	bool even_col = mod(wc.x, 2.0) < 1.0;
	level = 0;
	if (mat == MAT_COAT || mat == MAT_ROBE) {
		// Ткань: редкие вертикальные складки, как на портрете.
		level = grain > 0.84 ? 7 : (grain > 0.62 ? 1 : 0);
	} else if (mat == MAT_HAIR_DARK) {
		// Спутанные пряди.
		level = grain > 0.8 ? 5 : (grain > 0.5 ? 3 : 1);
	} else if (mat == MAT_SHIRT) {
		level = even_col ? 7 : 0;
	} else if (mat == MAT_TUNIC) {
		level = even_col ? 7 : 2;
	} else if (mat == MAT_HAIR_BLOND) {
		level = grain > 0.55 ? 10 + int(grain * 1.99) : 5;
	} else if (mat == MAT_BOOT || mat == MAT_FOAM) {
		level = 1;
	} else if (mat == MAT_EYE_DARK) {
		col = vec3(0.012);
	}
}
