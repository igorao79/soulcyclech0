// Персонажи: геометрия SDF и материалы фигур. Образ сверен с assets/portraits и assets/sprites.
// Ячейка сетки примерно 0.083 × 0.125 в локальных единицах фигуры: тоньше деталь не прочитается,
// поэтому мелочь (шнуровка, швы карманов, щетина) рисуется знаками, а не геометрией.
const int RAMP_FIGURE = 14;
// Опорная нога едет назад ровно со скоростью героя, поэтому ступня не скользит:
// STEP_LENGTH в ascii_demo.gd = GAIT_REACH * FIGURE_SCALE / GAIT_STANCE.
const float GAIT_STANCE = 0.55;
const float GAIT_REACH = 0.52;
// Сидя таз опускается с 0.90 до этой высоты; на столько же опускается весь корпус.
const float SIT_DROP_HIP = 0.24;
const float SIT_DROP = 0.66;

// Номера знаков в ряду 14 атласа: " .:'-~=|+*os%#@8".
const int FG_NONE = 0;
const int FG_DOT = 1;
const int FG_COLON = 2;
const int FG_TICK = 3;
const int FG_DASH = 4;
const int FG_TILDE = 5;
const int FG_EQUAL = 6;
const int FG_BAR = 7;
const int FG_PLUS = 8;
const int FG_STAR = 9;
const int FG_RING = 10;
const int FG_CURL = 11;
const int FG_HASH = 13;


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


void sd_leg(vec3 q, float side, float phase, float amount, float bob, float sit, int trouser, int shin, int shoe, inout float d, inout int m) {
	vec3 pose = gait_foot(phase) * amount;
	vec3 hip = vec3(side * 0.11, 0.90 + bob, 0.0);
	vec3 foot = vec3(side * 0.12, 0.09 + pose.y, pose.x);
	// Колено сгибается только в переносе: опорная нога почти прямая.
	vec3 knee = mix(hip, foot, 0.5) + vec3(0.0, 0.0, 0.03 + pose.y * 0.7);
	// Сидя: таз на земле, колени подтянуты к груди, стопы впереди.
	hip = mix(hip, vec3(side * 0.12, SIT_DROP_HIP, -0.06), sit);
	knee = mix(knee, vec3(side * 0.14, 0.60, 0.40), sit);
	foot = mix(foot, vec3(side * 0.13, 0.09, 0.62), sit);
	take(d, m, sd_capsule(q, hip, knee, 0.085), trouser);
	take(d, m, sd_capsule(q, knee, foot, 0.072), shin);
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
	// Дыхание: на месте грудь чуть поднимается, плечи опускаются на выдохе.
	q.y -= bob + sin(time * 1.7) * 0.012 * (1.0 - amount);
	// Таз переносится на опорную ногу, плечи идут навстречу шагу.
	q.x += sin(phase) * 0.035 * amount;
	float twist = -cos(phase) * amount * 0.2 * smoothstep(0.75, 1.3, q.y);
	float s = sin(twist);
	float c = cos(twist);
	q = vec3(c * q.x - s * q.z, q.y, s * q.x + c * q.z);
}


// Ночной ветер дует вдоль мира слева направо; здесь он переведён в координаты героя.
vec2 local_wind() {
	float gust = 0.55 + 0.45 * sin(time * 0.43) * sin(time * 0.17 + 2.0);
	return vec2(cos(player_yaw), sin(player_yaw)) * gust * 0.05;
}


// На месте герой медленно оглядывается; на ходу смотрит прямо.
vec3 turn_head(vec3 q, float amount, float seed) {
	float look = sin(time * 0.37 + seed) * sin(time * 0.13 + seed * 2.0) * 0.55 * (1.0 - amount);
	float s = sin(look);
	float c = cos(look);
	return vec3(c * q.x - s * q.z, q.y, s * q.x + c * q.z);
}


// Моргание: глаза пропадают на долю секунды раз в несколько секунд.
bool eyes_open(float seed) {
	return fract(time * 0.23 + seed) > 0.03;
}


// Безымянный: спутанные чёрные волосы, бледное лицо с большими чёрными глазами,
// длинное угольное пальто с высоким воротом и лацканами, распахнутое над светлой рубашкой
// с тёмной лентой у горла; серые брюки и тёмные туфли видны в разрезе.
void sd_nameless(vec3 q, float phase, float amount, inout float d, inout int m) {
	float bob;
	float swing = apply_body_motion(q, phase, amount, bob);
	float sit = player_sit;
	sd_leg(q, -1.0, phase, amount, bob, sit, MAT_TROUSER, MAT_TROUSER, MAT_SHOE, d, m);
	sd_leg(q, 1.0, phase + PI, amount, bob, sit, MAT_TROUSER, MAT_TROUSER, MAT_SHOE, d, m);
	// Сидя корпус опускается к земле и клонится вперёд, к коленям.
	q.y += SIT_DROP * sit;
	q.z -= sit * 0.22 * max(q.y - 0.9, 0.0);
	twist_upper_body(q, phase, amount, bob);
	vec2 wind = local_wind();

	// Полы отстают от героя и раскачиваются тем сильнее, чем ближе к подолу.
	float low = clamp(1.22 - q.y, 0.0, 1.0);
	low *= low;
	vec2 hem = coat_lag + wind + vec2(sin(phase) * amount * 0.09 + sin(time * 1.1) * 0.03, 0.0);
	// По подолу бежит мелкая волна ветра.
	hem.x += sin(time * 3.1 + q.z * 6.0 + q.y * 4.0) * 0.02 * low;
	vec3 body = vec3(q.x - hem.x * low, q.y, (q.z - hem.y * low) * 1.22);
	float coat = max(sd_taper(body, 0.12, 0.38, 1.17, 0.20), 0.34 - q.y);
	// Разрез спереди идёт до подола и расходится книзу, как на портрете.
	float opening = max(max(abs(body.x) - (0.085 + low * 0.10), 0.03 - body.z), q.y - 1.27);
	float vent = max(abs(body.x) - max(0.72 - q.y, 0.0) * 0.12, -0.03 - body.z);
	coat = max(coat, -min(opening, vent));
	// Рубашка заправлена в серые брюки.
	take(d, m, sd_taper(q, 0.78, 0.15, 0.92, 0.165), MAT_TROUSER);
	take(d, m, sd_taper(q, 0.88, 0.17, 1.26, 0.11), MAT_SHIRT);
	take(d, m, coat * 0.8, MAT_COAT);
	vec3 mirrored = vec3(abs(q.x), q.y, q.z);
	// Высокий ворот стоит за шеей и расходится вперёд, ниже — отложенные лацканы.
	take(d, m, sd_capsule(mirrored, vec3(0.13, 1.26, 0.05), vec3(0.16, 1.44, -0.11), 0.07), MAT_COAT);
	take(d, m, sd_capsule(mirrored, vec3(0.10, 1.28, 0.13), vec3(0.15, 0.98, 0.17), 0.045), MAT_COAT);

	// Широкие рукава с отворотом: кисть бледная и заметная.
	vec3 hand_l = vec3(-0.31, 0.74 + abs(swing) * 0.04, -swing * 0.30);
	vec3 hand_r = vec3(0.31, 0.74 + abs(swing) * 0.04, swing * 0.30);
	// Сидя руки лежат на коленях.
	hand_l = mix(hand_l, vec3(-0.19, 1.22, 0.44), sit);
	hand_r = mix(hand_r, vec3(0.19, 1.22, 0.44), sit);
	take(d, m, sd_capsule(q, vec3(-0.235, 1.26, 0.0), hand_l + vec3(0.0, 0.08, 0.0), 0.095), MAT_COAT);
	take(d, m, sd_capsule(q, vec3(0.235, 1.26, 0.0), hand_r + vec3(0.0, 0.08, 0.0), 0.095), MAT_COAT);
	take(d, m, sd_capsule(q, hand_l + vec3(0.0, 0.09, 0.0), hand_l + vec3(0.0, 0.15, 0.0), 0.112), MAT_COAT);
	take(d, m, sd_capsule(q, hand_r + vec3(0.0, 0.09, 0.0), hand_r + vec3(0.0, 0.15, 0.0), 0.112), MAT_COAT);
	take(d, m, length(q - hand_l) - 0.062, MAT_SKIN);
	take(d, m, length(q - hand_r) - 0.062, MAT_SKIN);

	vec3 head = turn_head(q, amount, 0.0);
	take(d, m, length((head - vec3(0.0, 1.56, 0.03)) * vec3(0.92, 1.0, 1.0)) - 0.2, MAT_SKIN);
	// Пряди сносит ветром и шагом: концы двигаются сильнее макушки.
	float sway = smoothstep(1.78, 1.36, head.y);
	vec3 strands = head - vec3(wind.x * 1.6 + coat_lag.x * 0.1, 0.0, wind.y * 1.6 + coat_lag.y * 0.1) * sway;
	vec3 side_hair = vec3(abs(strands.x) - 0.19, strands.y - 1.50, strands.z + 0.10);
	float hair = length(strands - vec3(0.0, 1.68, -0.05)) - 0.225;
	hair = smin(hair, length(strands - vec3(0.0, 1.50, -0.12)) - 0.18, 0.07);
	hair = smin(hair, length(side_hair) - 0.085, 0.06);
	// Спутанные пряди рвут край силуэта.
	hair -= max(sin(head.x * 19.0 + 0.7) * sin(head.y * 17.0 + head.x * 5.0) * sin(head.z * 16.0 + 1.3), 0.0) * 0.15;
	// Чёлка падает до самых глаз, но лицо остаётся открытым.
	hair = max(hair, -(length(head - vec3(0.0, 1.46, 0.35)) - 0.34));
	take(d, m, hair * 0.6, MAT_HAIR_DARK);
	if (eyes_open(0.0)) {
		take(d, m, length(vec3(abs(head.x) - 0.09, (head.y - 1.545) * 0.85, head.z - 0.19)) - 0.043, MAT_EYE_DARK);
	}
}


// Странник: светлые волнистые волосы, щетина, кремовая вязаная туника с вырезом на шнуровке,
// кожаный пояс и наручи, высокие сапоги. Правая рука упёрта в бок, левая свободна.
void sd_wanderer(vec3 q, float phase, float amount, inout float d, inout int m) {
	float bob;
	float swing = apply_body_motion(q, phase, amount, bob);
	sd_leg(q, -1.0, phase, amount, bob, 0.0, MAT_TROUSER, MAT_BOOT, MAT_BOOT, d, m);
	sd_leg(q, 1.0, phase + PI, amount, bob, 0.0, MAT_TROUSER, MAT_BOOT, MAT_BOOT, d, m);
	twist_upper_body(q, phase, amount, bob);
	vec2 wind = local_wind();

	float low = clamp(1.1 - q.y, 0.0, 1.0);
	vec2 lag = coat_lag * 0.5 + wind * 0.6;
	vec3 body = vec3(q.x - lag.x * low, q.y, (q.z - lag.y * low) * 1.22);
	float tunic = max(sd_taper(body, 0.62, 0.26, 1.24, 0.20), 0.56 - q.y);
	// V-образный вырез: под ним грудь, по ней знаками идёт шнуровка.
	float neckline = max(max(abs(q.x) - (q.y - 1.0) * 0.4, 1.0 - q.y), 0.02 - q.z);
	tunic = max(tunic, -neckline);
	take(d, m, sd_taper(vec3(q.x, q.y, q.z * 1.22), 0.98, 0.19, 1.30, 0.13), MAT_SKIN);
	take(d, m, sd_capsule(q, vec3(0.0, 1.28, 0.0), vec3(0.0, 1.44, 0.02), 0.075), MAT_SKIN);
	take(d, m, tunic, MAT_TUNIC);
	// Широкий отложной воротник лежит по краям выреза.
	vec3 mirrored = vec3(abs(q.x), q.y, q.z);
	take(d, m, sd_capsule(mirrored, vec3(0.05, 1.04, 0.17), vec3(0.17, 1.33, 0.10), 0.045), MAT_TUNIC);
	// Пояс с пряжкой чуть выступает над вязкой.
	take(d, m, max(length(body.xz) - 0.262, abs(q.y - 0.78) - 0.035), MAT_BOOT);
	take(d, m, sd_box(vec3(q.x - lag.x * 0.1, q.y - 0.78, q.z - 0.215), vec3(0.045, 0.04, 0.02)), MAT_BUCKLE);

	// Правая рука упёрта в бок: просвет у локтя виден в силуэте.
	vec3 hand_r = vec3(0.235, 0.86, 0.09 + swing * 0.10);
	vec3 elbow_r = vec3(0.43, 1.04, -0.02 + swing * 0.08);
	take(d, m, sd_capsule(q, vec3(0.235, 1.26, 0.0), elbow_r, 0.085), MAT_TUNIC);
	take(d, m, sd_capsule(q, elbow_r, hand_r, 0.07), MAT_TUNIC);
	// Кожаный наруч у запястья.
	take(d, m, length(q - mix(hand_r, elbow_r, 0.28)) - 0.085, MAT_BOOT);
	take(d, m, length(q - hand_r) - 0.058, MAT_SKIN);

	// Левая рука свободна и ходит в такт шагу, на месте висит вдоль тела.
	vec3 elbow_l = vec3(-0.30, 0.98, -swing * 0.14);
	vec3 hand_l = vec3(-0.31, 0.72 + abs(swing) * 0.03, -swing * 0.32);
	take(d, m, sd_capsule(q, vec3(-0.235, 1.26, 0.0), elbow_l, 0.085), MAT_TUNIC);
	take(d, m, sd_capsule(q, elbow_l, hand_l + vec3(0.0, 0.05, 0.0), 0.07), MAT_TUNIC);
	take(d, m, length(q - mix(hand_l, elbow_l, 0.28)) - 0.085, MAT_BOOT);
	take(d, m, length(q - hand_l) - 0.058, MAT_SKIN);

	vec3 head = turn_head(q, amount, 1.7);
	take(d, m, length(head - vec3(0.0, 1.56, 0.03)) - 0.185, MAT_SKIN);
	// Волнистая шапка заметно шире головы и закрывает уши; кудри треплет ветер.
	float sway = smoothstep(1.80, 1.40, head.y);
	vec3 curls = head - vec3(wind.x * 1.4 + coat_lag.x * 0.08, 0.0, wind.y * 1.4 + coat_lag.y * 0.08) * sway;
	float hair = length(curls - vec3(0.0, 1.67, -0.05)) - 0.245;
	hair = smin(hair, length(vec3(abs(curls.x) - 0.20, curls.y - 1.49, curls.z + 0.05)) - 0.115, 0.08);
	hair += sin(curls.x * 19.0 + curls.y * 6.0) * sin(curls.y * 17.0 - curls.z * 5.0) * sin(curls.z * 17.0 + 0.8) * 0.06;
	hair = max(hair, -(length(head - vec3(0.0, 1.47, 0.32)) - 0.30));
	take(d, m, hair * 0.7, MAT_HAIR_BLOND);
	if (eyes_open(0.41)) {
		take(d, m, length(vec3(abs(head.x) - 0.085, (head.y - 1.55) * 0.85, head.z - 0.175)) - 0.042, MAT_EYE_DARK);
	}
}


// Смотритель: острый капюшон, тёмный балахон с рваным подолом и багровой столой,
// бледное лицо в тени, красные глаза. В правой руке посох с тлеющим фонарём.
void sd_keeper(vec3 q, inout float d, inout int m) {
	q.y -= sin(time * 1.3) * 0.012;
	vec3 body = vec3(q.x, q.y, q.z * 1.12);
	float around = atan(q.x, q.z);
	// Подол рваный: язычки ткани разной длины.
	float tatter = max(sin(around * 9.0 + 1.3) * sin(around * 4.0 + 0.4), 0.0) * 0.08;
	float robe = max(sd_taper(body, 0.03, 0.43, 1.30, 0.16), 0.02 + tatter - q.y);
	bool stole = abs(abs(q.x) - 0.09) < 0.035 && q.z > 0.0 && q.y > 0.26;
	int robe_mat = q.y < 0.19 + tatter + sin(q.x * 13.0) * 0.02 ? MAT_CRIMSON : (stole ? MAT_STOLE : MAT_ROBE);
	take(d, m, robe * 0.9, robe_mat);
	take(d, m, length(q - vec3(0.0, 1.50, 0.05)) - 0.175, MAT_SKIN);
	// Капюшон сужается к острию, откинутому назад.
	vec3 cowl = vec3(q.x, q.y, q.z + 0.06 + max(q.y - 1.55, 0.0) * 0.45);
	float rim = length(q - vec3(0.0, 1.42, 0.31)) - 0.29;
	take(d, m, max(sd_taper(cowl, 1.52, 0.275, 1.98, 0.04), -rim), rim < 0.05 ? MAT_CRIMSON : MAT_ROBE);
	// Красные глаза гаснут на миг, как у живого.
	if (fract(time * 0.19 + 0.6) > 0.025) {
		take(d, m, length(vec3(abs(q.x) - 0.08, (q.y - 1.51) * 0.8, q.z - 0.19)) - 0.05, MAT_EYE);
	}
	// Левый рукав опущен, правый поднят к посоху.
	take(d, m, sd_capsule(q, vec3(-0.21, 1.24, 0.06), vec3(-0.31, 0.84, 0.15), 0.088), q.y < 0.90 ? MAT_CRIMSON : MAT_ROBE);
	take(d, m, sd_capsule(q, vec3(0.21, 1.24, 0.06), vec3(0.33, 1.03, 0.17), 0.088), q.y < 1.08 ? MAT_CRIMSON : MAT_ROBE);
	take(d, m, length(q - vec3(0.37, 0.99, 0.19)) - 0.055, MAT_SKIN);
	// Посох с крюком наверху, на крюке качается фонарь.
	take(d, m, sd_capsule(q, vec3(0.39, 0.0, 0.19), vec3(0.39, 2.02, 0.19), 0.04), MAT_STAFF);
	take(d, m, sd_capsule(q, vec3(0.39, 2.02, 0.19), vec3(0.24, 2.10, 0.19), 0.035), MAT_STAFF);
	vec3 lamp = q - vec3(0.24 + sin(time * 1.6) * 0.025, 1.93, 0.19);
	take(d, m, length(lamp * vec3(1.0, 0.8, 1.0)) - 0.075, MAT_EYE);
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
	} else if (mat == MAT_TROUSER) {
		// Серые брюки Безымянного, у Странника — потёртая коричневая шерсть.
		albedo = player_style == 0 ? vec3(0.40, 0.40, 0.42) : vec3(0.27, 0.22, 0.17);
		emissive = player_style == 0 ? vec3(0.11, 0.11, 0.12) : vec3(0.06, 0.05, 0.035);
	} else if (mat == MAT_SHOE) {
		albedo = vec3(0.075, 0.068, 0.07);
		emissive = vec3(0.018, 0.016, 0.018);
	} else if (mat == MAT_BOOT) {
		albedo = vec3(0.19, 0.13, 0.10);
		emissive = vec3(0.045, 0.032, 0.025);
	} else if (mat == MAT_BUCKLE) {
		albedo = vec3(0.55, 0.50, 0.40);
		emissive = vec3(0.25, 0.22, 0.15);
	} else if (mat == MAT_ROBE) {
		albedo = vec3(0.16, 0.12, 0.24);
		emissive = vec3(0.04, 0.03, 0.07);
	} else if (mat == MAT_STOLE) {
		albedo = vec3(0.30, 0.05, 0.08);
		emissive = vec3(0.17, 0.025, 0.045);
	} else if (mat == MAT_STAFF) {
		albedo = vec3(0.17, 0.13, 0.10);
		emissive = vec3(0.035, 0.026, 0.02);
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


// Точка поверхности в координатах своей фигуры: швы и складки едут вместе с телом.
vec3 figure_local(vec3 p, out bool is_player) {
	is_player = length(p.xz - player_pos.xz) < length(p.xz - keeper_pos.xz);
	if (is_player) {
		return to_local(p, player_pos, player_yaw) / FIGURE_SCALE;
	}
	return to_local(p, keeper_pos, keeper_yaw) / FIGURE_SCALE;
}


// Знак выбирается по материалу и свету: фигура остаётся плотной массой с чистым рисунком,
// освещённая сторона гуще, теневая реже. light — яркость освещения без цвета материала.
void figure_glyph(int mat, vec3 p, vec2 wc, float light, inout vec3 col, inout int level) {
	float grain = hash21(wc);
	bool even_col = mod(wc.x, 2.0) < 1.0;
	bool is_player = true;
	vec3 lp = figure_local(p, is_player);
	float around = atan(lp.x, lp.z);
	bool front = lp.z > 0.06;
	level = FG_NONE;
	if (mat == MAT_COAT || mat == MAT_ROBE) {
		// Ткань: вертикальные складки, слегка уходящие в сторону к подолу.
		float fold = sin(around * 7.0 + lp.y * 1.3 + sin(lp.y * 3.0) * 0.6);
		bool hem = is_player ? lp.y < 0.42 : lp.y < 0.30;
		bool pocket = is_player && front && abs(abs(lp.x) - 0.21) < 0.085 && abs(lp.y - 0.72) < 0.045;
		if (pocket) {
			level = FG_DASH;
		} else if (hem && grain > 0.25) {
			level = FG_TILDE;
		} else if (fold > 0.55) {
			level = light > 0.45 ? FG_BAR : FG_COLON;
		} else if (light > 0.9) {
			level = grain > 0.5 ? FG_TICK : FG_DOT;
		} else {
			level = grain > 0.85 ? FG_DOT : FG_NONE;
		}
	} else if (mat == MAT_HAIR_DARK) {
		// Спутанные пряди: на свету завитки, в тени редкие точки.
		if (light > 0.7) {
			level = grain > 0.75 ? FG_TILDE : (grain > 0.45 ? FG_TICK : FG_COLON);
		} else {
			level = grain > 0.8 ? FG_TILDE : (grain > 0.5 ? FG_TICK : FG_DOT);
		}
	} else if (mat == MAT_SHIRT) {
		// Тёмная лента у горла идёт ровно по середине груди.
		if (abs(lp.x) < 0.045 && lp.y > 1.08 && front) {
			col = vec3(0.30, 0.05, 0.08);
			level = FG_BAR;
		} else {
			level = even_col ? FG_BAR : FG_NONE;
		}
	} else if (mat == MAT_TUNIC) {
		// Крупная вязка косами; по планке ниже выреза — пуговицы.
		float rib = sin(around * 14.0);
		if (front && abs(lp.x) < 0.04 && lp.y > 0.58 && lp.y < 0.98 && mod(lp.y, 0.14) < 0.07) {
			col *= 0.55;
			level = FG_RING;
		} else {
			level = rib > 0.2 ? FG_BAR : (light > 0.8 ? FG_COLON : FG_NONE);
		}
	} else if (mat == MAT_TROUSER) {
		// Стрелки на брюках спереди.
		level = front && abs(abs(lp.x) - 0.11) < 0.035 ? FG_BAR : (light > 0.8 ? FG_COLON : FG_NONE);
	} else if (mat == MAT_SKIN && is_player && player_style == 1 && front) {
		if (lp.y > 0.98 && lp.y < 1.28 && abs(lp.x) < 0.11) {
			// Шнуровка крест-накрест в вырезе туники.
			col = vec3(0.30, 0.20, 0.12);
			level = mod(wc.y, 2.0) < 1.0 ? FG_PLUS : FG_STAR;
		} else if (lp.y > 1.37 && lp.y < 1.50) {
			// Щетина по линии челюсти.
			col *= 0.72;
			level = grain > 0.4 ? FG_COLON : FG_DOT;
		}
	} else if (mat == MAT_HAIR_BLOND) {
		level = grain > 0.55 ? FG_RING + int(grain * 1.99) : (light > 0.6 ? FG_TILDE : FG_TICK);
	} else if (mat == MAT_BOOT) {
		// Ремешки сапог и наручей.
		level = mod(lp.y, 0.16) < 0.05 ? FG_EQUAL : FG_DOT;
	} else if (mat == MAT_SHOE) {
		level = light > 0.8 ? FG_DOT : FG_NONE;
	} else if (mat == MAT_BUCKLE) {
		level = FG_HASH;
	} else if (mat == MAT_STOLE || mat == MAT_STAFF) {
		level = FG_BAR;
	} else if (mat == MAT_EYE_DARK) {
		col = vec3(0.012);
	}
}
