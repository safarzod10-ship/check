shader_type spatial;
// Zebra crossing decal: stripes across UV.x (metres), discards the gaps.
render_mode cull_back;
global uniform float wetness;
void fragment() {
	float s = step(0.5, fract(UV.x / 1.0));
	if (s < 0.5) { discard; }
	ALBEDO = vec3(0.88, 0.88, 0.85) * mix(1.0, 0.6, wetness);
	ROUGHNESS = mix(0.7, 0.2, wetness);
}
