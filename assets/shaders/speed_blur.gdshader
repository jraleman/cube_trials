shader_type canvas_item;
render_mode unshaded;

uniform vec2 blur_offset = vec2(0.0);
uniform vec2 focus_uv = vec2(0.5);
uniform vec2 focus_radius = vec2(0.1);

void fragment() {
	vec4 sharp = texture(TEXTURE, UV);
	vec2 distance_from_car = abs((UV - focus_uv) / max(focus_radius, vec2(0.001)));
	float scenery = smoothstep(1.0, 1.75, max(distance_from_car.x, distance_from_car.y));
	vec2 offset = blur_offset * scenery;
	vec2 edge = TEXTURE_PIXEL_SIZE * 0.5;
	vec4 blurred = sharp * 0.4;
	blurred += texture(TEXTURE, clamp(UV + offset * 0.5, edge, vec2(1.0) - edge)) * 0.24;
	blurred += texture(TEXTURE, clamp(UV - offset * 0.5, edge, vec2(1.0) - edge)) * 0.24;
	blurred += texture(TEXTURE, clamp(UV + offset, edge, vec2(1.0) - edge)) * 0.06;
	blurred += texture(TEXTURE, clamp(UV - offset, edge, vec2(1.0) - edge)) * 0.06;
	COLOR = blurred;
}
