extends SceneTree

var game: Node3D
var checks: Array[Dictionary] = []
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(65)
	var map_id: int = game.world.get_instance_id()
	var world_children: int = game.world.get_child_count()
	_check("menu_has_map_preview_entry",_button(game.ui.menu,"地图预览",true) != null)
	game._flash.color.a = 0.8
	await _click(_button(game.ui.menu,"地图预览",true))
	await _frames(50)
	_check("real_menu_click_enters_model_viewer",game.map_viewer.active and game.ui.map_preview.visible)
	_check("viewer_hides_combat_ui",not game.ui.menu.visible and not game.ui.hud.visible and not game.running)
	_check("viewer_uses_original_world",game.world.get_instance_id() == map_id and game.world.get_child_count() == world_children)
	_check("whole_model_disables_visibility",float(game.visibility_material.get_shader_parameter("enabled")) == 0.0)
	_check("preview_clears_previous_flash_overlay",is_zero_approx(game._flash.color.a))
	var sun := game.get_node("MirageSun_Valve318_60") as DirectionalLight3D
	_check("preview_shadow_distance_covers_inspection_camera",sun.directional_shadow_max_distance > game.camera.global_position.distance_to(game.map_viewer.target)+50.0)
	_check("viewer_starts_orthographic",game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	_check("whole_map_framing",game.camera.size > 110.0)
	await _capture("map_preview_overview.png")
	var initial_yaw: float = game.map_viewer.yaw
	await _drag(MOUSE_BUTTON_LEFT,Vector2(870,420),Vector2(1050,480))
	_check("left_drag_orbits_model",absf(game.map_viewer.yaw-initial_yaw) > 0.5)
	await _test_toolbar_release()
	var initial_target: Vector3 = game.map_viewer.target
	await _drag(MOUSE_BUTTON_RIGHT,Vector2(870,420),Vector2(960,455))
	_check("right_drag_pans_model",game.map_viewer.target.distance_to(initial_target) > 2.0)
	initial_target = game.map_viewer.target
	await _drag(MOUSE_BUTTON_MIDDLE,Vector2(870,420),Vector2(830,390))
	_check("middle_drag_pans_model",game.map_viewer.target.distance_to(initial_target) > 1.0)
	var initial_span: float = game.map_viewer.span
	await _wheel(MOUSE_BUTTON_WHEEL_UP,5)
	_check("wheel_zoom_in",game.map_viewer.span < initial_span*0.6)
	await _click(_button(game.ui.map_preview,"重置视角"))
	await create_timer(0.9).timeout
	_check("reset_restores_overview",absf(game.map_viewer.span-game.map_viewer._overview_span) < 0.1 and game.map_viewer.target.distance_to(game.map_viewer._overview_center) < 0.1)
	for entry in [["A","A 包点"],["B","B 包点"],["MID","中路"],["CT","CT 出生点"],["T","T 出生点"]]:
		await _click(_button(game.ui.map_preview,entry[1]))
		await create_timer(0.9).timeout
		var expected := Vector3(10.0,0.0,-6.0)
		if entry[0] in ["A","B"]:
			expected = game.world.sites[entry[0]]
		elif entry[0] in ["CT","T"]:
			expected = game.world.spawns[entry[0]]
		_check("landmark_button_focuses_"+entry[0],Vector2(game.map_viewer.target.x,game.map_viewer.target.z).distance_to(Vector2(expected.x,expected.z)) < 0.2 and game.camera.size < 50.0)
		if entry[0] == "A":
			await _capture("map_preview_a_site.png")
	var before_projection_span: float = game.camera.size
	await _click(_button(game.ui.map_preview,"正交 /",true))
	_check("perspective_toggle",game.camera.projection == Camera3D.PROJECTION_PERSPECTIVE and _button(game.ui.map_preview,"透视 /",true) != null)
	_check("projection_toggle_preserves_target_scale",absf(game.map_viewer.span-before_projection_span) < 0.1)
	await _click(_button(game.ui.map_preview,"透视 /",true))
	_check("orthographic_toggle",game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	await _wheel(MOUSE_BUTTON_WHEEL_UP,80)
	_check("zoom_cannot_cross_model_or_go_negative",game.map_viewer._span_goal >= 4.0 and game.camera.near > 0.0)
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN,120)
	_check("zoom_out_is_bounded",game.map_viewer._span_goal <= 300.0)
	await _key(KEY_HOME)
	await create_timer(0.9).timeout
	_check("Home_resets_view",absf(game.map_viewer.span-game.map_viewer._overview_span) < 0.1)
	await _key(KEY_ESCAPE)
	_check("Escape_returns_to_menu",not game.map_viewer.active and game.ui.menu.visible and not game.ui.map_preview.visible)
	_check("camera_range_restored_on_exit",is_equal_approx(game.camera.far,240.0))
	_check("shadow_range_restored_on_exit",is_equal_approx(sun.directional_shadow_max_distance,110.0))
	await _click(_button(game.ui.menu,"地图预览",true))
	await _click(_button(game.ui.map_preview,"正交 /",true))
	await _click(_button(game.ui.map_preview,"返回主菜单",true))
	_check("toolbar_return_restores_menu",game.ui.menu.visible and not game.map_viewer.active)
	_check("perspective_exit_restores_original_projection",game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	await _click(_button(game.ui.menu,"自由练习"))
	await _click(_button(game.ui.menu,"部署进入战局",true))
	await _frames(45)
	_check("game_starts_normally_after_viewer",game.running and is_instance_valid(game.player) and game.ui.hud.visible and not game.ui.map_preview.visible)
	_check("combat_camera_and_visibility_restore",game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and game.camera.size < 40.0 and float(game.visibility_material.get_shader_parameter("enabled")) == 1.0)
	var result := {"passed":checks.size()-failures,"failed":failures,"checks":checks,"render_method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"viewport":[root.size.x,root.size.y],"native_input":true}
	FileAccess.open("res://tests/map_preview_results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("MAP_PREVIEW_TEST ",JSON.stringify(result))
	game.queue_free()
	await _frames(20)
	quit(0 if failures == 0 else 1)

func _check(id: String, passed: bool) -> void:
	checks.append({"id":id,"passed":passed})
	if not passed:
		failures += 1
		push_error("Map preview check failed: "+id)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _button(node: Node, text: String, prefix := false) -> Button:
	if node is Button and (node.text.begins_with(text) if prefix else node.text == text):
		return node
	for child in node.get_children():
		var match_button := _button(child,text,prefix)
		if match_button != null:
			return match_button
	return null

func _click(button: Button) -> void:
	if button == null:
		_check("requested_button_exists",false)
		return
	var position := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion,true)
	_mouse_button(MOUSE_BUTTON_LEFT,true,position)
	await process_frame
	_mouse_button(MOUSE_BUTTON_LEFT,false,position)
	await _frames(18)

func _mouse_button(button: int, pressed: bool, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = position
	event.global_position = position
	root.push_input(event,true)

func _drag(button: int, from: Vector2, to: Vector2) -> void:
	_mouse_button(button,true,from)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.global_position = to
	motion.relative = to-from
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else (MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_MIDDLE)
	root.push_input(motion,true)
	await process_frame
	_mouse_button(button,false,to)
	await _frames(45)

func _wheel(button: int, count: int) -> void:
	for i in count:
		_mouse_button(button,true,Vector2(900,420))
		_mouse_button(button,false,Vector2(900,420))
	await _frames(50)

func _test_toolbar_release() -> void:
	var start := Vector2(870,420)
	var end := _button(game.ui.map_preview,"正交 /",true).get_global_rect().get_center()
	_mouse_button(MOUSE_BUTTON_LEFT,true,start)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = end
	motion.global_position = end
	motion.relative = end-start
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion,true)
	_mouse_button(MOUSE_BUTTON_LEFT,false,end)
	await process_frame
	var yaw_goal: float = game.map_viewer._yaw_goal
	motion = InputEventMouseMotion.new()
	motion.position = start
	motion.global_position = start
	motion.relative = start-end
	motion.button_mask = 0
	root.push_input(motion,true)
	await _frames(8)
	_check("release_over_toolbar_does_not_leave_stuck_orbit",is_equal_approx(yaw_goal,game.map_viewer._yaw_goal))

func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	root.push_input(event,true)
	await process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	root.push_input(event,true)
	await _frames(20)

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/"+name)
