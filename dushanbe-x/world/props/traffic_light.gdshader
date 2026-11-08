shader_type spatial;
// Traffic light lamps. COLOR.rgb = lamp colour, COLOR.a = slot (0 red, 0.5 yellow, 1 green), UV2.x = phase offset.
render_mode cull_back;
void fragment() {
	float cycle = mod(TIME + UV2.x * 40.0, 40.0);
	// 0-17 green, 17-20 yellow, 20-40 red (cross street gets the opposite via phase offset)
	float slot = COLOR.a;
	float on = 0.0;
	if (slot > 0.75) { on = step(cycle, 17.0); }
	else if (slot > 0.25) { on = step(17.0, cycle) * step(cycle, 20.0); }
	else { on = step(20.0, cycle); }
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = c * mix(0.08, 0.5, on);
	EMISSION = c * on * 5.0;
	ROUGHNESS = 0.3;
}
