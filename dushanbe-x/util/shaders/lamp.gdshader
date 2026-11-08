shader_type spatial;
// Emissive lamp glass: lights up at night (global night_factor), colour from vertex colour.
render_mode cull_back;
uniform bool always_on = false;
uniform float strength = 6.0;
global uniform float night_factor;

void fragment() {
	float on = always_on ? 1.0 : smoothstep(0.15, 0.6, night_factor);
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = mix(c * 0.6, c, on);
	EMISSION = c * strength * on;
	ROUGHNESS = 0.3;
}
