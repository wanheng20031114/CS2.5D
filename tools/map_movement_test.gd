extends SceneTree
var map: MirageMap
var walkers: Array = []
var graph_routes: Array = []
var route_results: Array = []
var frames := 0
var started := false
var failed := false
var patrol_only := false
var controller_sha256 := ""

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	patrol_only = OS.get_cmdline_user_args().has("--patrol-only")
	controller_sha256 = FileAccess.get_sha256("res://scripts/combatant.gd")
	map = MirageMap.new()
	root.add_child(map)
	await physics_frame
	await physics_frame
	for team in map.spawn_points:
		var points: Array = map.spawn_points[team]
		for i in points.size():
			for site in map.sites:
				var target: Vector3 = map.sites[site]
				var path: Array[Vector3] = map.find_path(points[i], target)
				var route_name: String = "%s[%d]->%s" % [team, i, site]
				graph_routes.append({"name": route_name, "nonempty": not path.is_empty(), "points": path.size()})
				if path.is_empty():
					failed = true
					print("FAIL EMPTY GRAPH PATH ", route_name)
				if i >= 5 or patrol_only:
					continue
				# Use the actual gameplay capsule, layers and step controller.
				var body := load("res://scripts/combatant.gd").new() as CharacterBody3D
				body.call("setup", team, false, "ak47" if team == "T" else "m4a1")
				root.add_child(body)
				body.position = points[i]
				walkers.append({"body": body, "path": path, "name": route_name, "target": target, "index": 0, "last": body.position, "stuck": 0, "done": false})
	# Defenders continue patrolling after reaching the first objective. These
	# reverse-direction routes exercise stair approaches absent from spawn paths.
	for from_site in ["A", "B"]:
		var to_site := "B" if from_site == "A" else "A"
		var start_position: Vector3 = map.sites[from_site]
		var target: Vector3 = map.sites[to_site]
		var body := load("res://scripts/combatant.gd").new() as CharacterBody3D
		body.call("setup", "CT", false, "m4a1")
		root.add_child(body)
		body.position = start_position
		walkers.append({"body": body, "path": map.find_path(start_position, target), "name": "patrol " + from_site + "->" + to_site, "target": target, "index": 0, "last": body.position, "stuck": 0, "done": false})
	started = true

func _finish_route(w: Dictionary, passed: bool, reason: String) -> void:
	var body: CharacterBody3D = w.body
	w.done = true
	failed = failed or not passed
	var target: Vector3 = w.target
	var result := {"name": w.name, "passed": passed, "reason": reason, "path_nonempty": not w.path.is_empty(), "path_points": w.path.size(), "waypoint_index": w.index, "frames": frames, "position": [body.position.x, body.position.y, body.position.z], "target": [target.x, target.y, target.z], "distance_to_target": body.position.distance_to(target)}
	route_results.append(result)
	print("PASS " if passed else "FAIL ", w.name, " frames=", frames, " position=", body.position, " distance=", result.distance_to_target, " reason=", reason)
	if not passed:
		for k in body.get_slide_collision_count():
			var hit := body.get_slide_collision(k)
			print(" HIT ", hit.get_collider().name, " normal=", hit.get_normal(), " point=", hit.get_position())

func _physics_process(delta: float) -> bool:
	if not started:
		return false
	frames += 1
	var done := 0
	for w in walkers:
		if w.done:
			done += 1
			continue
		var body: CharacterBody3D = w.body
		var path: Array = w.path
		if path.is_empty():
			_finish_route(w, false, "empty_path")
			continue
		if w.index >= path.size():
			var arrived: bool = body.position.distance_to(w.target) < 0.5
			_finish_route(w, arrived, "arrived" if arrived else "waypoints_finished_away_from_target")
			continue
		var goal: Vector3 = path[w.index]
		var direction := Vector3(goal.x-body.position.x,0,goal.z-body.position.z)
		if direction.length() < 0.18:
			w.index += 1
			continue
		direction = direction.normalized()
		body.call("move_direction", direction, delta)
		if body.position.distance_to(w.last) < .003:w.stuck += 1
		else:w.stuck=0
		w.last = body.position
		if w.stuck > 180 or body.position.y < -12 or frames>9000:
			_finish_route(w, false, "stuck" if w.stuck > 180 else ("fell" if body.position.y < -12 else "timeout"))
	if done == walkers.size():
		DirAccess.make_dir_recursive_absolute("res://artifacts")
		var output_path := "res://artifacts/map_patrol_routes.json" if patrol_only else "res://artifacts/map_routes.json"
		var output := FileAccess.open(output_path, FileAccess.WRITE)
		var report := {"passed": not failed, "physics_engine": ProjectSettings.get_setting("physics/3d/physics_engine"), "controller": "res://scripts/combatant.gd", "controller_sha256": controller_sha256, "fixed_fps": 60, "waypoint_tolerance_m": 0.18, "arrival_tolerance_m": 0.5, "graph_routes": graph_routes, "physical_routes": route_results}
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
		if not patrol_only:
			# Keep the focused patrol artifact current after a full regression.
			report["physical_routes"] = route_results.filter(func(r: Dictionary) -> bool: return r.name.begins_with("patrol "))
			var patrol_output := FileAccess.open("res://artifacts/map_patrol_routes.json", FileAccess.WRITE)
			patrol_output.store_string(JSON.stringify(report, "\t"))
			patrol_output.close()
		print("ROUTES COMPLETE physical=", route_results.size(), " graph=", graph_routes.size(), " passed=", not failed)
		quit(1 if failed else 0)
	return false
