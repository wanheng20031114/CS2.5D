extends SceneTree
## Bake the author's faceted, vertex-colored meshes into native Godot resources.
## Geometry is serialized offline; game-time character construction only loads scenes.

var checks: int = 0
var triangle_count: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--icons" in OS.get_cmdline_user_args():
		await _icons()
		return
	if "--validate" in OS.get_cmdline_user_args():
		_validate()
		return
	if "--preview" in OS.get_cmdline_user_args():
		await _preview()
		return
	for category: String in ["characters", "weapons"]:
		var folder: String = "res://assets/%s/source/" % category
		for filename: String in DirAccess.get_files_at(folder):
			if not filename.ends_with(".json") or filename == "verified_values.json":
				continue
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder + filename))
			if parsed is Dictionary and parsed.has("surfaces"):
				_bake(parsed, category)
	print("ACTOR_BAKE_SUCCESS scenes=%d triangles=%d" % [checks, triangle_count])
	quit(0)

func _validate() -> void:
	var catalog_script: Script = load("res://scripts/weapon_catalog.gd")
	var visual_script: Script = load("res://scripts/agent_visual.gd")
	var character_script: Script = load("res://scripts/combatant.gd")
	var actor: CharacterBody3D = character_script.new()
	root.add_child(actor)
	actor.setup("CT", true, "m4a1")
	var weapon_count: int = 0
	for row: Dictionary in catalog_script.all():
		assert(ResourceLoader.exists(catalog_script.model_path(str(row.id))))
		assert(row.category == "melee" or int(row.price) > 0)
		actor.visual.set_weapon(str(row.id))
		actor.visual.animate(.016, 4.0, true, false)
		actor.visual.fire()
		actor.visual.animate(.016, 0.0, true, false)
		assert(actor.visual.get_muzzle_position().is_finite())
		weapon_count += 1
	assert(weapon_count == 45)
	actor.add_weapon("ak47")
	actor.speed = 0.0
	actor.aiming = false
	var steady: float = actor.spread_angle()
	assert(is_equal_approx(steady, .0018))
	actor.speed = 5.7
	var moving: float = actor.spread_angle()
	actor.aiming = true
	actor.speed = 5.7 * .43
	var aimed_moving: float = actor.spread_angle()
	actor.speed = 0.0
	var aimed_steady: float = actor.spread_angle()
	assert(aimed_steady < steady and steady < aimed_moving and aimed_moving < moving)
	actor.ammunition["ak47"] = {"mag":5, "reserve":8}
	assert(actor.start_reload())
	actor.tick(4.0)
	assert(actor.ammunition["ak47"].mag == 13 and actor.ammunition["ak47"].reserve == 0)
	actor.ammunition["ak47"] = {"mag":5, "reserve":30}
	assert(actor.start_reload())
	actor.equip(1)
	assert(actor.reload_timer == 0.0)
	assert(actor.ammunition["ak47"].mag == 5 and actor.ammunition["ak47"].reserve == 30)
	actor.visual.die()
	actor.visual.animate(.1, 0.0, false, false)
	assert(actor.visual.model.get_node("Rig").rotation.z > 0.0)
	actor.free()
	print("ACTOR_API_SUCCESS models=%d AKspread=%f moving=%f ADSmoving=%f ADSsteady=%f reload=partial_and_cancel" % [weapon_count, steady, moving, aimed_moving, aimed_steady])
	quit(0)

func _icons() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/weapons/icons")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512,256)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0,0,0,0)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("dce7ec")
	env.environment.ambient_light_energy = .85
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 145, 0)
	sun.light_color = Color("fff0df")
	sun.light_energy = .65
	world.add_child(sun)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.make_current()
	var catalog_script: Script = load("res://scripts/weapon_catalog.gd")
	var count: int = 0
	for row: Dictionary in catalog_script.all():
		var object: Node3D = (load(catalog_script.model_path(str(row.id))) as PackedScene).instantiate()
		world.add_child(object)
		var bounds: AABB = (object.get_node("Model/Sculpture") as MeshInstance3D).mesh.get_aabb()
		var center: Vector3 = bounds.get_center()
		if str(row.category) in ["gear", "grenade"]:
			camera.position = center + Vector3(-2,.55,-.9)
			camera.size = maxf(.40, bounds.size.y * 1.20)
		else:
			camera.position = center + Vector3(-3,.42,.11)
			camera.size = maxf(bounds.size.y * 1.26, bounds.size.z * .63)
		camera.look_at(center, Vector3.UP)
		for i: int in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var screenshot: Image = viewport.get_texture().get_image()
		assert(screenshot.save_png("res://assets/weapons/icons/%s.png" % row.id) == OK)
		object.free()
		count += 1
	print("WEAPON_ICONS_SUCCESS count=%d" % count)
	quit(0)

func _bake(spec: Dictionary, category: String) -> void:
	var root := Node3D.new()
	root.name = str(spec.name)
	var nodes: Dictionary = {".": root}
	for info: Dictionary in spec.nodes:
		var node := Node3D.new()
		node.name = str(info.name)
		node.position = Vector3(info.position[0], info.position[1], info.position[2])
		var parent: Node3D = nodes[str(info.parent)]
		parent.add_child(node)
		node.owner = root
		var path: String = str(info.name) if str(info.parent) == "." else str(info.parent) + "/" + str(info.name)
		nodes[path] = node
	var meshes: Dictionary = {}
	for surface: Dictionary in spec.surfaces:
		var path: String = str(surface.part)
		if not meshes.has(path):
			meshes[path] = ArrayMesh.new()
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		for i: int in range(0, surface.vertices.size(), 3):
			vertices.append(Vector3(surface.vertices[i], surface.vertices[i+1], surface.vertices[i+2]))
			normals.append(Vector3(surface.normals[i], surface.normals[i+1], surface.normals[i+2]))
		for i: int in range(0, surface.colors.size(), 4):
			colors.append(Color(surface.colors[i], surface.colors[i+1], surface.colors[i+2], 1.0))
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		# Trimesh is counter-clockwise; Godot's front face uses clockwise winding.
		var indices := PackedInt32Array()
		for i: int in range(0, vertices.size(), 3):
			indices.append(i)
			indices.append(i+2)
			indices.append(i+1)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh: ArrayMesh = meshes[path]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		material.roughness = 0.62 if str(surface.material) == "metal" else 0.9
		material.metallic = 0.18 if str(surface.material) == "metal" else 0.0
		material.resource_name = "Faceted metal" if str(surface.material) == "metal" else "Painted matte"
		mesh.surface_set_material(mesh.get_surface_count()-1, material)
	for path: String in meshes:
		var mesh: ArrayMesh = meshes[path]
		var resource_path: String = "res://assets/%s/%s_%s.res" % [category, spec.name, path.replace("/", "_")]
		assert(ResourceSaver.save(mesh, resource_path, ResourceSaver.FLAG_COMPRESS) == OK)
		mesh = load(resource_path)
		var mi := MeshInstance3D.new()
		mi.name = "Sculpture"
		mi.mesh = mesh
		(nodes[path] as Node3D).add_child(mi)
		mi.owner = root
	for key: String in spec.metadata:
		root.set_meta(key, spec.metadata[key])
	var packed := PackedScene.new()
	assert(packed.pack(root) == OK)
	var scene_path: String = "res://assets/%s/%s.tscn" % [category, spec.name]
	assert(ResourceSaver.save(packed, scene_path) == OK)
	var verify: Node3D = (load(scene_path) as PackedScene).instantiate()
	assert(verify.get_child_count() > 0)
	verify.free()
	root.free()
	checks += 1
	triangle_count += int(spec.triangles)

func _preview() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("b7ac92")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("d5deed")
	env.environment.ambient_light_energy = .65
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color("fff0d2")
	sun.light_energy = .72
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(50,.1,50)
	floor_mi.mesh = floor_mesh
	floor_mi.position.y = -.05
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("b7ac92")
	floor_mat.roughness = 1.0
	floor_mi.material_override = floor_mat
	world.add_child(floor_mi)
	var visual_script: Script = load("res://scripts/agent_visual.gd")
	for i: int in range(2):
		var actor: Node3D = visual_script.new()
		world.add_child(actor)
		actor.position.x = -1.0 if i==0 else 1.0
		actor.rotation.y = -.18
		actor.build("CT" if i==0 else "T", "m4a1" if i==0 else "ak47")
		actor.animate(.016, 0.0, true, false)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(3.5,3.0,-6.5)
	camera.look_at(Vector3(0,.85,0), Vector3.UP)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.6
	camera.make_current()
	root.size = Vector2i(1280,900)
	for i: int in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	assert(screenshot.save_png("res://assets/characters/gallery.png") == OK)
	print("ACTOR_RENDER_SUCCESS assets/characters/gallery.png")
	quit(0)
