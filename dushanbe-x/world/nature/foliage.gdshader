shader_type spatial;
// Tree crowns / bushes: wind sway (more at the top), per-instance tint (INSTANCE_CUSTOM.r), leafy noise.
render_mode cull_back;
global uniform float wind_strength;
global uniform float wetness;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wp;
varying float tint;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tint = INSTANCE_CUSTOM.r;
	float ph = MODEL_MATRIX[3].x * 0.07 + MODEL_MATRIX[3].z * 0.05;
	float sway = sin(TIME * 1.3 + ph) * 0.6 + sin(TIME * 3.1 + ph * 2.3 + VERTEX.y) * 0.25;
	float k = max(VERTEX.y - 1.0, 0.0) * 0.018 * (0.25 + wind_strength * 1.2);
	VERTEX.x += sway * k;
	VERTEX.z += sway * k * 0.6;
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	c *= mix(vec3(0.85, 1.0, 0.8), vec3(1.15, 1.05, 0.75), tint);
	float n = texture(noise_tex, wp.xz * 0.35 + wp.y * 0.21).b;
	float n2 = texture(noise_tex, wp.xy * 0.9).a;
	c *= 0.7 + n * 0.45 + n2 * 0.15;
	ALBEDO = c * mix(1.0, 0.8, wetness);
	ROUGHNESS = mix(0.85, 0.45, wetness);
	SPECULAR = 0.25;
	BACKLIGHT = c * 0.35;
}
