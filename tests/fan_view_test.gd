extends SceneTree
## Native GPU integration checks for the actual main scene and cutaway material.
## Godot --path . --audio-driver Dummy --script res://tests/fan_view_test.gd
## Controlled colored geometry makes visibility assertions independent of the
## shader's implementation. A/B screenshots and LOS use the original map.

var game: Node3D
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var observations: Dictionary = {}
var probe_group: Node3D
var started_ms: int

func _initialize() -> void:
	root.size = Vector2i(1440, 810)
	_run.call_deferred()

func _run() -> void:
	started_ms = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute("res://artifacts/fan_view")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.start_game("CT", "bomb", 1)
	game.paused = true
	game.settings.shake = 0.0
	game.settings.zoom = 34.0
	_hide_canvas(game)
	await _frames(8)
	_check(RenderingServer.get_current_rendering_method() != "gl_compatibility" or DisplayServer.get_name() != "headless", "native_rendering_available")
	for site: String in ["A", "B"]:
		await _site_probes(site)
		await _source_visibility(site)
	await _material_categories()
	await _spectator_probe()
	var report := {
		"date_utc": Time.get_datetime_string_from_system(true),
		"engine": Engine.get_version_info().string,
		"gpu": RenderingServer.get_video_adapter_name(),
		"render_method": RenderingServer.get_current_rendering_method(),
		"duration_ms": Time.get_ticks_msec() - started_ms,
		"sha256": {
			"shader": FileAccess.get_sha256("res://shaders/architecture.gdshader"),
			"main": FileAccess.get_sha256("res://scripts/main.gd"),
			"map": FileAccess.get_sha256("res://scripts/mirage_map.gd")},
		"checks": checks, "failures": failures, "observations": observations,
		"limitations": [
			"Colored GPU probes temporarily hide map visuals to isolate clipping; original map physics remain loaded.",
			"A/B LOS checks and gameplay screenshots restore the actual map geometry.",
			"Tests drive actual main methods deterministically, without synthesizing mouse input."
		]
	}
	var file := FileAccess.open("res://tests/fan_view_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("FAN_VIEW_RESULT checks=%d failures=%d" % [checks.size(), failures.size()])
	for failure: String in failures:
		printerr("FAN_VIEW_FAILURE ", failure)
	_stop_audio(game)
	game.queue_free()
	await _frames(3)
	await create_timer(0.15).timeout
	quit(0 if failures.is_empty() else 1)

func _site_probes(site: String) -> void:
	game.player.alive = true
	game.world.visible = false
	for actor: Node3D in game.actors:
		actor.visible = false
	var origin := _site_origin(site)
	game.player.position = origin
	game.visibility_material.set_shader_parameter("enabled", 0.0)
	for heading: Vector3 in [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]:
		var tag := site + "_" + str(int(rad_to_deg(atan2(heading.x, heading.z))))
		_sync_view(heading, origin)
		game.camera.size = 55.0
		_create_probe_floor(origin)
		var front := _box("ArchitectureFront", origin + heading * 18.0 + Vector3.UP * 5.0, Vector3(1.4, 0.2, 1.4))
		var rear := _box("ArchitectureRear", origin - heading * 18.0 + Vector3.UP * 5.0, Vector3(1.4, 0.2, 1.4))
		var low := _box("ArchitectureLowCover", origin + heading * 9.0 + Vector3.UP * 0.6, Vector3(1.4, 0.5, 1.4))
		var left_edge := _box("ArchitectureWideLeft", origin + heading.rotated(Vector3.UP, deg_to_rad(75.0)) * 18.0 + Vector3.UP * 5.0, Vector3(1.0, 0.2, 1.0))
		var right_edge := _box("ArchitectureWideRight", origin + heading.rotated(Vector3.UP, deg_to_rad(-75.0)) * 18.0 + Vector3.UP * 5.0, Vector3(1.0, 0.2, 1.0))
		game.world._apply_architecture_cutaway(probe_group)
		RenderingServer.global_shader_parameter_set("view_cutaway", 0.0)
		var baseline := await _image()
		var front_pixel := _pixel(baseline, front.global_position)
		var rear_pixel := _pixel(baseline, rear.global_position)
		var low_pixel := _pixel(baseline, low.global_position)
		_check(_red(front_pixel) and _red(rear_pixel) and _red(low_pixel), tag + "_unclipped_probes_visible", [str(front_pixel), str(rear_pixel), str(low_pixel)])
		RenderingServer.global_shader_parameter_set("view_cutaway", 1.0)
		var clipped := await _image()
		_check(_green(_pixel(clipped, front.global_position)), tag + "_whole_fan_clears_roof_18m_away", str(_pixel(clipped, front.global_position)))
		_check(_red(_pixel(clipped, rear.global_position)), tag + "_outside_fan_roof_retained", str(_pixel(clipped, rear.global_position)))
		_check(_red(_pixel(clipped, low.global_position)), tag + "_low_cover_retained", str(_pixel(clipped, low.global_position)))
		_check(_green(_pixel(clipped, left_edge.global_position)), tag + "_wide_left_fan_cleared", str(_pixel(clipped, left_edge.global_position)))
		_check(_green(_pixel(clipped, right_edge.global_position)), tag + "_wide_right_fan_cleared", str(_pixel(clipped, right_edge.global_position)))
		_sync_view(-heading, origin)
		game.camera.size = 55.0
		var turned := await _image()
		_check(_red(_pixel(turned, front.global_position)), tag + "_turn_restores_previous_front_roof", str(_pixel(turned, front.global_position)))
		_check(_green(_pixel(turned, rear.global_position)), tag + "_turn_clears_new_front_roof", str(_pixel(turned, rear.global_position)))
		if heading == Vector3.FORWARD:
			baseline.save_png("res://artifacts/fan_view/" + site.to_lower() + "_probe_unclipped.png")
			clipped.save_png("res://artifacts/fan_view/" + site.to_lower() + "_probe_clipped.png")
		probe_group.queue_free()
		await _frames(2)
	# The roof itself lies behind the player. Orthographic projection places it
	# over distant forward ground; clearing only world-space fan membership fails.
	var camera_ground := Vector3(10, 0, 17).normalized()
	_sync_view(-camera_ground, origin)
	game.camera.size = 55.0
	_create_probe_floor(origin)
	var projected := _box("ArchitectureForeground", origin + camera_ground * 2.0 + Vector3.UP * 26.0, Vector3(1.4, 0.2, 1.4))
	game.world._apply_architecture_cutaway(probe_group)
	var screen_point: Vector2 = game.camera.unproject_position(projected.global_position)
	var floor_plane := Plane(Vector3.UP, origin.y)
	var projected_floor: Vector3 = floor_plane.intersects_ray(game.camera.project_ray_origin(screen_point), game.camera.project_ray_normal(screen_point))
	_check((projected_floor - origin).dot(-camera_ground) > 12.0, site + "_foreground_probe_projects_over_distant_front_ground", {"roof":str(projected.position), "projected_floor":str(projected_floor)})
	RenderingServer.global_shader_parameter_set("view_cutaway", 0.0)
	var before := await _image()
	RenderingServer.global_shader_parameter_set("view_cutaway", 1.0)
	var after := await _image()
	_check(_red(_pixel(before, projected.global_position)), site + "_foreground_probe_blocks_ground_without_cutaway")
	_check(_green(_pixel(after, projected.global_position)), site + "_projected_camera_obstruction_removed", str(_pixel(after, projected.global_position)))
	before.save_png("res://artifacts/fan_view/" + site.to_lower() + "_projection_before.png")
	after.save_png("res://artifacts/fan_view/" + site.to_lower() + "_projection_after.png")
	probe_group.queue_free()
	await _frames(2)

func _source_visibility(site: String) -> void:
	game.world.visible = true
	game.visibility_material.set_shader_parameter("enabled", 1.0)
	var origin := _site_origin(site)
	game.player.position = origin
	var opponent: Node3D
	for actor: Node3D in game.actors:
		actor.visible = false
		if actor.team != game.side:
			opponent = actor
	game.player.visible = true
	var nodes: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map/navigation.json")).nodes
	var clear := Vector3.INF
	var blocked := Vector3.INF
	for entry: Array in nodes:
		var candidate := Vector3(float(entry[0]), float(entry[1]), float(entry[2]))
		var distance := origin.distance_to(candidate)
		if distance < 5.0 or distance > 17.0 or absf(candidate.y - origin.y) > 0.7:
			continue
		if game._line_of_sight(origin, candidate):
			if clear == Vector3.INF: clear = candidate
		else:
			if blocked == Vector3.INF: blocked = candidate
		if clear != Vector3.INF and blocked != Vector3.INF:
			break
	_check(clear != Vector3.INF and blocked != Vector3.INF, site + "_real_source_map_has_clear_and_obstructed_actor_positions", {"observer":str(origin),"clear":str(clear),"blocked":str(blocked)})
	if clear != Vector3.INF:
		opponent.position = clear
		_sync_view((clear - origin).normalized(), origin)
		await _frames(2)
		game._update_visibility()
		_check(opponent.visible, site + "_unobstructed_forward_enemy_visible")
		_sync_view((origin - clear).normalized(), origin)
		game._update_visibility()
		_check(not opponent.visible, site + "_enemy_behind_facing_hidden")
	if blocked != Vector3.INF:
		opponent.position = blocked
		_sync_view((blocked - origin).normalized(), origin)
		await _frames(2)
		game._update_visibility()
		_check(not opponent.visible, site + "_source_wall_still_hides_enemy_with_cutaway_enabled")
		_check(game.world.segment_blocked(origin, blocked), site + "_source_wall_collision_remains_after_cutaway")
	for heading: Vector3 in [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]:
		_sync_view(heading, origin)
		game.player.visible = true
		game.camera.size = 34.0
		var shot := await _image()
		shot.save_png("res://artifacts/fan_view/" + site.to_lower() + "_source_" + str(int(rad_to_deg(atan2(heading.x,heading.z)))) + ".png")
	observations[site + "_source_positions"] = {"observer":str(origin),"clear_enemy":str(clear),"blocked_enemy":str(blocked)}

func _material_categories() -> void:
	game.world.visible = false
	game.visibility_material.set_shader_parameter("enabled", 0.0)
	var origin := _site_origin("A")
	game.player.position = origin
	_sync_view(Vector3.FORWARD, origin)
	game.camera.size = 55.0
	for category: String in ["Architecture", "Props", "PropsMetal", "Canopy", "Foliage", "Ground"]:
		_create_probe_floor(origin)
		var panel := _box(category + "CategoryProbe", origin + Vector3.FORWARD * 18.0 + Vector3.UP * 5.0, Vector3(1.4, 0.2, 1.4))
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		panel.material_override = material
		game.world._apply_architecture_cutaway(probe_group)
		RenderingServer.global_shader_parameter_set("view_cutaway", 0.0)
		var baseline := await _image()
		_check(_red(_pixel(baseline, panel.global_position)), category + "_category_probe_visible_before_cutaway")
		RenderingServer.global_shader_parameter_set("view_cutaway", 1.0)
		var clipped := await _image()
		var expected := _red(_pixel(clipped, panel.global_position)) if category == "Ground" else _green(_pixel(clipped, panel.global_position))
		_check(expected, category + ("_ground_not_clipped" if category == "Ground" else "_material_participates_in_fan_cutaway"), str(_pixel(clipped, panel.global_position)))
		probe_group.queue_free()
		await _frames(2)

func _spectator_probe() -> void:
	game.world.visible = false
	game.visibility_material.set_shader_parameter("enabled", 0.0)
	var ally: Node3D
	for actor: Node3D in game.actors:
		actor.visible = false
		if actor != game.player and actor.team == game.side and ally == null:
			ally = actor
		actor.alive = false
	ally.alive = true
	ally.position = _site_origin("B")
	ally.rotation.y = PI * 0.5
	game.player.position = _site_origin("A")
	game.player.rotation.y = -PI * 0.5
	game.camera_target = ally.position
	game._update_camera(1.0)
	game._update_visibility()
	game.camera.size = 55.0
	_check(game._observer() == ally, "spectator_uses_alive_teammate")
	_create_probe_floor(ally.position)
	var heading: Vector3 = -ally.global_basis.z
	var forward := _box("ArchitectureSpectatorFront", ally.position + heading * 18.0 + Vector3.UP * 5.0, Vector3(1.4, 0.2, 1.4))
	var rear := _box("ArchitectureSpectatorRear", ally.position - heading * 18.0 + Vector3.UP * 5.0, Vector3(1.4, 0.2, 1.4))
	game.world._apply_architecture_cutaway(probe_group)
	var capture := await _image()
	_check(_green(_pixel(capture, forward.global_position)), "spectator_fan_tracks_teammate_position_and_facing", str(_pixel(capture, forward.global_position)))
	_check(_red(_pixel(capture, rear.global_position)), "spectator_preserves_outside_teammate_fan", str(_pixel(capture, rear.global_position)))
	capture.save_png("res://artifacts/fan_view/spectator_probe.png")
	probe_group.queue_free()

func _sync_view(heading: Vector3, origin: Vector3) -> void:
	var planar := Vector3(heading.x, 0, heading.z).normalized()
	game.player.rotation.y = atan2(-planar.x, -planar.z)
	game.aim_direction = planar
	game.camera_target = origin
	game._update_camera(1.0)
	game._update_visibility()
	for actor: Node3D in game.actors:
		actor.visible = false

func _site_origin(site: String) -> Vector3:
	var point: Vector3 = game.world.sites[site]
	var path: Array[Vector3] = game.world.find_path(point, point)
	return (path[0] if not path.is_empty() else point) + Vector3.UP * 0.03

func _create_probe_floor(origin: Vector3) -> void:
	probe_group = Node3D.new()
	game.add_child(probe_group)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(150, 150)
	floor_mesh.mesh = plane
	floor_mesh.position = origin - Vector3.UP * 0.02
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.03, 1.0, 0.03)
	floor_mesh.material_override = material
	probe_group.add_child(floor_mesh)

func _box(label: String, position: Vector3, size: Vector3) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.surface_get_arrays(0)
	var colors := PackedColorArray()
	colors.resize(arrays[Mesh.ARRAY_VERTEX].size())
	colors.fill(Color(1.0, 0.02, 0.02))
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.position = position
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	probe_group.add_child(node)
	return node

func _image() -> Image:
	await _frames(5)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _pixel(image: Image, world_position: Vector3) -> Color:
	var screen: Vector2 = game.camera.unproject_position(world_position)
	var pixel := screen * Vector2(image.get_size()) / root.get_visible_rect().size
	if pixel.x < 2 or pixel.y < 2 or pixel.x > image.get_width() - 3 or pixel.y > image.get_height() - 3:
		return Color.MAGENTA
	var result := Color(0, 0, 0, 0)
	for y in range(-1, 2):
		for x in range(-1, 2):
			result += image.get_pixel(int(pixel.x) + x, int(pixel.y) + y)
	return result / 9.0

func _red(value: Color) -> bool:
	return value.r > value.g * 1.7 and value.r > value.b * 1.7

func _green(value: Color) -> bool:
	return value.g > value.r * 1.7 and value.g > value.b * 1.7

func _check(passed: bool, name: String, detail: Variant = null) -> void:
	checks.append({"name":name,"passed":passed,"detail":detail})
	if not passed: failures.append(name)

func _frames(count: int) -> void:
	for index in count:
		await process_frame
		await physics_frame

func _hide_canvas(node: Node) -> void:
	if node is CanvasLayer: node.visible = false
	for child: Node in node.get_children(): _hide_canvas(child)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null
	for child: Node in node.get_children(): _stop_audio(child)
