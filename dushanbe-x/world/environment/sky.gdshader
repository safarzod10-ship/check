shader_type sky;
// Dynamic sky: day/night gradient, sun & moon discs, stars, two layers of procedural clouds.
render_mode use_half_res_pass;

uniform vec3 zenith_day : source_color = vec3(0.22, 0.45, 0.85);
uniform vec3 horizon_day : source_color = vec3(0.68, 0.80, 0.93);
uniform vec3 zenith_night : source_color = vec3(0.01, 0.02, 0.06);
uniform vec3 horizon_night : source_color = vec3(0.05, 0.07, 0.14);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.45, 0.18);
uniform float day_amount = 1.0;      // 0 night .. 1 day
uniform float sunset_amount = 0.0;   // 0..1 near sunrise/sunset
uniform float cloudiness = 0.2;
uniform float overcast_dark = 0.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float time_offset = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, -1.0, 1.0);
	float hz = pow(1.0 - max(up, 0.0), 3.0);
	vec3 day_col = mix(zenith_day, horizon_day, hz);
	vec3 night_col = mix(zenith_night, horizon_night, hz);
	vec3 col = mix(night_col, day_col, day_amount);
	// sunset glow around the sun azimuth
	vec3 sd = normalize(sun_dir);
	float sun_az = max(dot(normalize(vec3(d.x, 0.0, d.z)), normalize(vec3(sd.x, 0.0, sd.z))), 0.0);
	col = mix(col, sunset_color, sunset_amount * hz * (0.35 + 0.65 * pow(sun_az, 3.0)));
	// overcast greys everything
	vec3 grey = mix(vec3(0.05, 0.055, 0.07), vec3(0.55, 0.58, 0.62), day_amount);
	col = mix(col, grey * (1.0 - overcast_dark * 0.4), clamp(cloudiness * 1.1 - 0.25, 0.0, 0.9));

	// sun disc + halo
	float sdot = dot(d, sd);
	float sun = smoothstep(0.9993, 0.9997, sdot) * (1.0 - cloudiness * 0.8);
	float halo = pow(max(sdot, 0.0), 180.0) * 0.6 + pow(max(sdot, 0.0), 12.0) * 0.12;
	col += vec3(1.0, 0.9, 0.7) * (sun * 18.0 + halo * (1.0 - cloudiness * 0.6)) * step(-0.02, sd.y);
	// moon
	float mdot = dot(d, normalize(moon_dir));
	col += vec3(0.85, 0.9, 1.0) * smoothstep(0.9995, 0.99975, mdot) * 2.5 * (1.0 - day_amount) * (1.0 - cloudiness);
	// stars
	if (day_amount < 0.6 && up > 0.0) {
		vec3 sp = floor(d * 380.0);
		float st = step(0.9975, hash(sp));
		col += vec3(st) * (0.6 - day_amount) * 1.6 * (1.0 - cloudiness) * smoothstep(0.0, 0.25, up);
	}
	// clouds: project onto a plane, two noise octaves drifting with time
	if (up > 0.0) {
		vec2 cuv = d.xz / (up + 0.08) * 0.35;
		float t = TIME * 0.004 + time_offset;
		float n1 = texture(cloud_noise, cuv * 0.6 + vec2(t, t * 0.4)).r;
		float n2 = texture(cloud_noise, cuv * 1.7 - vec2(t * 1.3, t * 0.2)).g;
		float c = n1 * 0.7 + n2 * 0.45;
		float cover = mix(0.92, 0.38, cloudiness);
		float cl = smoothstep(cover, cover + 0.22, c) * smoothstep(0.0, 0.15, up);
		vec3 lit = mix(vec3(0.08, 0.09, 0.12), vec3(1.0, 0.98, 0.95), day_amount);
		lit = mix(lit, sunset_color * 1.2 + vec3(0.2), sunset_amount * 0.6);
		vec3 shade = lit * mix(0.75, 0.45, overcast_dark) ;
		vec3 ccol = mix(lit, shade, smoothstep(0.2, 0.9, c - cover));
		ccol += vec3(1.0, 0.85, 0.6) * pow(max(sdot, 0.0), 8.0) * 0.5 * day_amount;
		col = mix(col, ccol, cl * 0.95);
	}
	// below horizon: ground haze colour
	if (up < 0.0) {
		col = mix(col, mix(night_col, horizon_day * 0.7, day_amount), clamp(-up * 4.0, 0.0, 1.0));
	}
	COLOR = col;
}
