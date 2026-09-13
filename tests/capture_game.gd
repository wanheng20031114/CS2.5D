extends SceneTree
var game: Node3D
var frames := 0
var requested := false
var configured := false

func _initialize() -> void:
	root.size = Vector2i(1440,810)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child.call_deferred(game)

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 40:
		_configure.call_deferred()
	if frames > 100 and configured and not requested:
		requested = true
		capture.call_deferred()
	return false

func _configure() -> void:
		var args := OS.get_cmdline_user_args()
		if "--source" in args:
			for child in game.world.get_children():
				game.world.remove_child(child)
				child.queue_free()
			game.world.add_child(load("res://assets/map/source_environment.glb").instantiate())
		if "--play" in args or "--shop" in args or "--inventory" in args:
			game.start_game("T","practice",0)
			game.player.position = game.world.sites["B" if "--b" in args else "A"]+Vector3(0,0.15,0)
			for tick in range(20): await physics_frame
			game.player.rotation.y = 0.6
			game.aim_direction = Vector3(-0.7,0,-0.7)
			game.camera_target = game.player.position
			game._update_camera(1)
			game._update_visibility()
			if "--nofog" in args: game.visibility_material.set_shader_parameter("enabled",0.0)
			game.paused = true
			game._update_hud()
			if "--top" in args:
				var focus: Vector3 = game.world.sites["B" if "--b" in args else "A"]
				game.camera.size = 34.0
				game.camera.position = focus+Vector3(0,44,3)
				game.camera.look_at(focus)
			if "--clean" in args: game.ui.visible = false
			if "--shop" in args:
				game.player.position = game.world.spawns.T
				game.ui.toggle_shop(game.Catalog.all(),game._state())
			if "--inventory" in args: game.ui.toggle_inventory(game._state())
		configured = true

func capture() -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var suffix := "menu"
	for arg in OS.get_cmdline_user_args():
		if arg in ["--play","--shop","--inventory"]: suffix = arg.replace("--","")
	if "--nofog" in OS.get_cmdline_user_args(): suffix += "_nofog"
	if "--source" in OS.get_cmdline_user_args(): suffix += "_source"
	for tag in ["--top","--b","--clean"]:
		if tag in OS.get_cmdline_user_args(): suffix += tag.replace("--","_")
	root.get_texture().get_image().save_png("res://artifacts/game_"+suffix+".png")
	print("CAPTURE_OK ",suffix," fps=",Engine.get_frames_per_second())
	quit()
