extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var map := MirageMap.new()
	world.add_child(map)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.66, 0.75, 0.77)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color8(198, 211, 213)
	env.environment.ambient_light_energy = 0.48
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.tonemap_exposure = 0.95
	env.environment.ssao_enabled = true
	env.environment.ssao_radius = 1.5
	env.environment.ssao_intensity = 1.7
	env.environment.ssao_light_affect = 0.6
	env.environment.ssao_detail = 0.7
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color8(255, 223, 179)
	sun.light_energy = 1.35
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.3
	sun.directional_shadow_max_distance = 150.0
	sun.rotation_degrees = Vector3(-60, -132, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(65, 85, 95)
	camera.look_at(Vector3(1, 2, 0))
	camera.size = 133
	camera.current = true
	root.size = Vector2i(1440, 1080)
	await process_frame
	await process_frame
	for team in map.spawns:
		for site in map.sites:
			print("PATH ", team, " -> ", site, " ", map.find_path(map.spawns[team], map.sites[site]).size())
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://assets/map/overview.png")
	camera.position = Vector3(5,2,33) + Vector3(3,40,4)
	camera.look_at(Vector3(5,2,33))
	camera.size = 31
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://assets/map/a_site.png")
	camera.position = Vector3(-35,2.5,-29) + Vector3(3,42,4)
	camera.look_at(Vector3(-35,2.5,-29))
	camera.size = 31
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://assets/map/b_site.png")
	# Confirm the original B canopy reveals a player below it during gameplay.
	var player := load("res://scripts/combatant.gd").new() as CharacterBody3D
	player.call("setup", "CT", true, "m4a1")
	world.add_child(player)
	player.position = map.sites["B"]
	RenderingServer.global_shader_parameter_set("view_player", player.position)
	RenderingServer.global_shader_parameter_set("view_camera", camera.position)
	RenderingServer.global_shader_parameter_set("view_camera_direction", -camera.global_basis.z)
	var forward := -player.global_basis.z
	RenderingServer.global_shader_parameter_set("view_facing", Vector2(forward.x,forward.z).normalized())
	RenderingServer.global_shader_parameter_set("view_radius", 42.0)
	RenderingServer.global_shader_parameter_set("view_cone_cos", 0.12)
	RenderingServer.global_shader_parameter_set("view_cutaway", 1.0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://assets/map/b_site_cutaway.png")
	quit()
