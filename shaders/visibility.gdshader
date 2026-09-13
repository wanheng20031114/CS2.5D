shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D sight_ranges : filter_linear, repeat_enable;
uniform vec3 observer;
uniform vec2 facing = vec2(0.0,-1.0);
uniform float sight_radius = 42.0;
uniform float enabled = 0.0;
uniform float darkness = 0.69;
varying mat4 inv_view;
varying mat4 inv_proj;
void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
	inv_view = INV_VIEW_MATRIX;
	inv_proj = INV_PROJECTION_MATRIX;
}
void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ndc = vec3(SCREEN_UV, depth)*2.0-1.0;
	#else
		ndc = vec3(SCREEN_UV*2.0-1.0, depth);
	#endif
	vec4 view = inv_proj*vec4(ndc,1.0);
	view /= view.w;
	vec3 world = (inv_view*view).xyz;
	vec2 delta = world.xz-observer.xz;
	float distance_to_player = length(delta);
	vec2 dir = delta/max(distance_to_player,0.001);
	float theta = atan(dir.y,dir.x)/6.28318530718;
	float permitted = texture(sight_ranges, vec2(fract(theta+1.0),0.5)).r*sight_radius;
	float cone = smoothstep(0.12,0.28,dot(dir,facing));
	float occlusion = 1.0-smoothstep(permitted-0.35,permitted+0.4,distance_to_player);
	float edge = 1.0-smoothstep(sight_radius-4.0,sight_radius,distance_to_player);
	float near_player = 1.0-smoothstep(0.65,1.3,distance_to_player);
	float lit = max(near_player,cone)*occlusion*edge;
	vec3 original = texture(screen_texture,SCREEN_UV).rgb;
	float grey = dot(original,vec3(0.299,0.587,0.114));
	vec3 shaded = mix(original,vec3(grey)*vec3(0.72,0.84,1.03),0.34)*(1.0-darkness);
	ALBEDO = mix(original,mix(shaded,original,lit),enabled);
}
