shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
global uniform vec3 view_player;
global uniform vec3 view_camera_direction;
global uniform vec2 view_facing;
global uniform float view_radius;
global uniform float view_cone_cos;
global uniform float view_cutaway;
uniform float roughness_value = 0.86;
uniform float metallic_value = 0.0;
uniform float cutaway_height = 1.35;
varying vec3 world_position;
bool in_view_sector(vec2 at) {
	vec2 relative = at-view_player.xz;
	float distance_to_player = length(relative);
	// Only the small footprint of the character is opened behind the player.
	// The rest of the opening follows the entire forward field of view.
	if (distance_to_player < 1.25) { return true; }
	return distance_to_player < view_radius && dot(relative/distance_to_player,view_facing) >= view_cone_cos;
}
void vertex() {
	world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	if (view_cutaway > 0.5 && world_position.y > view_player.y + cutaway_height) {
		// Orthographic camera rays are parallel. Extend this fragment's camera
		// ray onto the player's ground plane: foreground geometry outside the
		// world-space fan can still hide a part of that fan on screen.
		float down = min(view_camera_direction.y,-0.001);
		float to_ground = (view_player.y+0.05-world_position.y)/down;
		vec2 covered_ground = world_position.xz+view_camera_direction.xz*to_ground;
		if (in_view_sector(world_position.xz) || in_view_sector(covered_ground)) {
			discard;
		}
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
}
