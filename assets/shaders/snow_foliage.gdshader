shader_type spatial;
render_mode cull_disabled;

varying float snow_cover;

void vertex() {
	vec3 world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	snow_cover = smoothstep(0.05, 0.65, world_normal.y);
}

void fragment() {
	ALBEDO = mix(vec3(0.12, 0.23, 0.22), vec3(0.87, 0.94, 0.98), snow_cover);
	ROUGHNESS = 0.95;
}
