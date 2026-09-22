shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.82, 0.48, 1.0);
uniform vec2 bay_size = vec2(6.0, 4.2);
uniform float pulse : hint_range(0.0, 1.0) = 1.0;
uniform float halo_strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 edges = min(UV, vec2(1.0) - UV) * bay_size;
	float distance_to_edge = min(edges.x, edges.y);
	float line = 1.0 - smoothstep(0.025, 0.09, distance_to_edge);
	// A feathered halo stays visible in Compatibility without screen-space bloom.
	float halo = (1.0 - smoothstep(0.04, 0.36, distance_to_edge)) * 0.45;
	ALBEDO = tint.rgb;
	ALPHA = max(line, halo * halo_strength) * tint.a * pulse;
}
