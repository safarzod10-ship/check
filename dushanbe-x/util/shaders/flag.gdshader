shader_type spatial;
// Waving cloth. UV.x = 0 at the pole, grows along the flag (metres). Colour from vertex colour.
render_mode cull_disabled;
global uniform float wind_strength;
uniform float flag_length = 30.0;

void vertex() {
	float t = UV.x / flag_length;
	float w = 0.6 + wind_strength * 1.6;
	float wave = sin(UV.x * 0.35 - TIME * 3.2) * 0.9 + sin(UV.x * 0.9 - TIME * 5.0 + UV.y * 0.2) * 0.3;
	VERTEX.z += wave * t * w * 1.4;
	VERTEX.y -= t * t * (1.6 - wind_strength) * 1.5;
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 0.85;
	BACKLIGHT = pow(COLOR.rgb, vec3(2.2)) * 0.4;
}
