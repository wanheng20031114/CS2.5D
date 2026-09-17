extends SceneTree
## Native main-scene integration, with automatic gameplay processing disabled.
## Godot --headless --path . --audio-driver Dummy --script res://tests/first_person_test.gd

const MainScene = preload("res://scenes/main.tscn")
const FPSettings = preload("res://scripts/first_person_settings.gd")
const ARENA := Vector3(1000, 0.06, 1000)
const SETTINGS_PATH := "user://settings.cfg"
var game: Node3D
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var observations: Dictionary = {}
var skipped: Array[Dictionary] = []
var saved_settings := PackedByteArray()
var had_settings := false
var initial_mouse_mode: int
var finished := false
var started_ms: int

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	started_ms = Time.get_ticks_msec()
	had_settings = FileAccess.file_exists(SETTINGS_PATH)
	if had_settings:
		saved_settings = FileAccess.get_file_as_bytes(SETTINGS_PATH)
	initial_mouse_mode = Input.mouse_mode
	create_timer(120.0).timeout.connect(_timeout)
	game = MainScene.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.settings.merge(FPSettings.DEFAULTS, true)
	game.settings.fullscreen = false
	await _sync()
	_parameters()
	await _mode_and_look()
	await _shooting_and_visibility()
	await _movement_and_modals()
	await _inactive_guards()
	await _lifecycle()
	await _finish()

func _check(condition: bool, name: String, detail: Variant = null) -> void:
	checks.append({"name":name, "passed":condition, "detail":detail})
	if not condition:
		failures.append(name + (" :: " + str(detail) if detail != null else ""))
		printerr("FIRST_PERSON_FAILURE ", failures.back())

func _sync() -> void:
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame

func _start() -> void:
	if is_instance_valid(game.player): game.player.alive = false
	game.start_game("CT", "practice", 0)
	game.set_physics_process(false)
	game.paused = false
	game.ui.close_panels()
	game.settings.merge(FPSettings.DEFAULTS, true)
	game.set_view_mode("first_person")
	game.player.position = ARENA
	game.player.rotation = Vector3.ZERO
	game.player.velocity = Vector3.ZERO
	game._reset_first_person()
	game._update_camera(1.0)
	await _sync()

func _parameters() -> void:
	var old_config := {"sensitivity":1.2, "volume":0.4, "zoom":28.0}
	var migrated: Dictionary = FPSettings.sanitize(old_config)
	_check(migrated.view_mode == "top_down" and migrated.fp_fov == 75.0 and migrated.volume == 0.4 and not old_config.has("fp_fov"), "legacy_settings_migrate_without_mutating_input")
	for key: String in FPSettings.RANGES:
		var limits: Array = FPSettings.RANGES[key]
		var low: Dictionary = FPSettings.sanitize({key:-1000000.0})
		var high: Dictionary = FPSettings.sanitize({key:1000000.0})
		var invalid: Dictionary = FPSettings.sanitize({key:NAN})
		_check(float(low[key]) >= float(limits[0]) and float(high[key]) <= float(limits[1]) and is_finite(float(invalid[key])), "bounded_finite_parameter_"+key)
	var invalid: Dictionary = FPSettings.sanitize({"view_mode":"invalid", "fp_invert_y":"false", "fp_sensitivity":"bad", "fp_near":INF, "fp_fov":50.0, "fp_ads_fov":90.0})
	_check(invalid.view_mode == "top_down" and invalid.fp_invert_y == false and invalid.fp_sensitivity == FPSettings.DEFAULTS.fp_sensitivity and is_finite(invalid.fp_near), "invalid_types_and_mode_restore_safe_defaults")
	_check(invalid.fp_ads_fov <= invalid.fp_fov, "ADS_FOV_never_widens_normal_FOV")
	observations["parameter_defaults"] = FPSettings.DEFAULTS
	observations["parameter_ranges"] = FPSettings.RANGES

func _mode_and_look() -> void:
	await _start()
	_check(game.is_first_person() and game.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "first_person_uses_perspective")
	_check(game.camera.position.distance_to(game.player.position + Vector3.UP*float(game.settings.fp_eye_height)) < 0.005, "camera_at_configured_eye_height", str(game.camera.position))
	_check(is_equal_approx(game.camera.fov,75.0) and is_equal_approx(game.camera.near,0.03) and is_equal_approx(game.camera.far,240.0), "camera_applies_FOV_and_clipping")
	game._update_visibility()
	_check(not game.player.visible and float(game.visibility_material.get_shader_parameter("enabled")) == 0.0, "first_person_hides_local_body_and_disables_fan_mask")
	var persisted := ConfigFile.new()
	_check(persisted.load(SETTINGS_PATH) == OK and persisted.get_value("game","view_mode","") == "first_person", "view_mode_persists_to_configuration")
	game.settings.fp_smoothing = 0.0
	game._apply_first_person_look(Vector2(100,-50))
	game._update_camera(1.0)
	_check(is_equal_approx(game._fp_yaw,deg_to_rad(-12.0)) and is_equal_approx(game._fp_pitch,deg_to_rad(6.0)), "relative_mouse_uses_degrees_per_pixel_and_pitch", {"yaw":game._fp_yaw,"pitch":game._fp_pitch})
	game._apply_first_person_look(Vector2(0,-100000))
	game._update_camera(1.0)
	_check(is_equal_approx(game._fp_pitch,deg_to_rad(89.0)), "up_pitch_is_clamped")
	game._apply_first_person_look(Vector2(0,100000))
	game._update_camera(1.0)
	_check(is_equal_approx(game._fp_pitch,deg_to_rad(-89.0)), "down_pitch_is_clamped")
	game.player.rotation = Vector3.ZERO
	game._reset_first_person()
	game.settings.fp_invert_y = true
	game._apply_first_person_look(Vector2(0,-50))
	game._update_camera(1.0)
	_check(game._fp_pitch < 0.0, "invert_Y_reverses_pitch")
	game.settings.fp_invert_y = false
	game.player.rotation = Vector3.ZERO
	game._reset_first_person()
	game.player.aiming = true
	game._apply_first_person_look(Vector2(100,0))
	game._update_camera(1.0)
	_check(is_equal_approx(game._fp_yaw,deg_to_rad(-12.0*0.65)) and is_equal_approx(game.camera.fov,55.0), "ADS_applies_sensitivity_multiplier_and_FOV", {"yaw":game._fp_yaw,"fov":game.camera.fov})
	game.player.aiming = false
	game._update_camera(1.0)
	_check(is_equal_approx(game.camera.fov,75.0), "releasing_ADS_restores_normal_FOV")
	game.player.rotation = Vector3.ZERO
	game._reset_first_person()
	game.settings.fp_smoothing = 10.0
	game._apply_first_person_look(Vector2(100,0))
	game._step_first_person_look(1.0/60.0)
	_check(game._fp_yaw < 0.0 and game._fp_yaw > game._fp_target_yaw, "smoothing_moves_toward_target_without_jumping")
	game._step_first_person_look(1.0)
	_check(absf(game._fp_yaw-game._fp_target_yaw) < 0.0001, "smoothing_converges_to_mouse_target")
	game.settings.fp_smoothing = 0.0
	var viewmodel: Node3D = game.first_person_viewmodel
	game.settings.fp_viewmodel_fov = 85.0
	game._update_camera(1.0)
	_check(viewmodel.viewport.own_world_3d and is_equal_approx(viewmodel.view_camera.fov,85.0) and is_equal_approx(game.camera.fov,75.0), "viewmodel_has_independent_world_and_FOV")
	game.player.equip(1)
	game._update_camera(1.0)
	_check(viewmodel._weapon_id == game.player.current_weapon() and is_instance_valid(viewmodel.weapon), "viewmodel_tracks_equipped_pistol")
	game.player.equip(2)
	game._update_camera(1.0)
	_check(viewmodel._weapon_id == "knife" and is_instance_valid(viewmodel.weapon), "viewmodel_tracks_knife")
	game.set_view_mode("top_down")
	game._update_camera(1.0)
	game._update_visibility()
	_check(not game.is_first_person() and game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and game.player.visible and float(game.visibility_material.get_shader_parameter("enabled")) == 1.0, "switching_back_restores_top_down_camera_body_and_fan")
	_check(not viewmodel._active and viewmodel.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "top_down_disables_viewmodel_rendering")
	game.set_view_mode("first_person")
	game._update_camera(1.0)
	_check(game.is_first_person() and absf(game._fp_pitch) < 0.001, "switching_to_first_person_resets_pitch")

func _body_at(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	game.add_child(body)
	body.position = position
	return body

func _enemy() -> CharacterBody3D:
	for actor: CharacterBody3D in game.actors:
		if actor.team != game.side and actor.alive: return actor
	return null

func _look_at(target: Vector3) -> Vector3:
	var direction: Vector3 = (target-game.player.position-Vector3.UP*float(game.settings.fp_eye_height)).normalized()
	game._fp_yaw = atan2(-direction.x,-direction.z)
	game._fp_pitch = asin(direction.y)
	game._fp_target_yaw = game._fp_yaw
	game._fp_target_pitch = game._fp_pitch
	game.player.rotation.y = game._fp_yaw
	game.camera_shake = 0.0
	game._update_camera(1.0)
	return direction

func _shoot_once(enemy: CharacterBody3D) -> void:
	enemy.health = 100.0
	enemy.armor = 0.0
	game.player.shot_timer = 0.0
	game.player.bloom = 0.0
	game.player.speed = 0.0
	game.player.velocity = Vector3.ZERO
	game.rng.seed = 78119
	game._shoot(game.player,-game.camera.global_basis.z)

func _shooting_and_visibility() -> void:
	await _start()
	game.settings.fp_recoil = 0.0
	game.player.add_weapon("ak47")
	var enemy: CharacterBody3D = _enemy()
	for height: float in [4.0,-4.0]:
		enemy.position = ARENA+Vector3(0,height,-8)
		await _sync()
		var target: Vector3 = enemy.position+Vector3.UP*1.05
		var expected: Vector3 = _look_at(target)
		game._player_input(0.0,false)
		var center := root.get_visible_rect().size*0.5
		var camera_ray: Vector3 = game.camera.project_ray_normal(center)
		_check(camera_ray.dot(expected) > 0.99999 and game.shot_direction.dot(camera_ray) > 0.99999, "crosshair_and_shot_align_at_height_"+str(height))
		_shoot_once(enemy)
		_check(enemy.health < 100.0 and enemy.health > 0.0, "3D_shot_hits_enemy_at_height_"+str(height),enemy.health)
		game._update_visibility()
		_check(enemy.visible, "visible_enemy_at_height_"+str(height))
	enemy.position = ARENA+Vector3(0,0,-8)
	await _sync()
	_look_at(enemy.position+Vector3.UP*1.35)
	var low_wall := _body_at(ARENA+Vector3(0,0.64,-4),Vector3(4,1.28,0.3))
	await _sync()
	_shoot_once(enemy)
	game._update_visibility()
	_check(enemy.health < 100.0 and enemy.visible, "eye_ray_shoots_and_sees_over_low_cover",enemy.health)
	low_wall.queue_free()
	var full_wall := _body_at(ARENA+Vector3(0,2,-4),Vector3(4,4,0.3))
	await _sync()
	var rounds_before: int = game.player.ammunition.ak47.mag
	_shoot_once(enemy)
	game._update_visibility()
	_check(enemy.health == 100.0 and game.player.ammunition.ak47.mag == rounds_before-1, "wall_blocks_first_person_bullet_but_consumes_ammo")
	_check(not enemy.visible, "wall_blocks_first_person_enemy_visibility")
	full_wall.queue_free()
	enemy.position = ARENA+Vector3(0,0,8)
	await _sync()
	game._update_visibility()
	_check(not enemy.visible, "enemy_behind_camera_is_hidden")
	enemy.position = ARENA+Vector3(12,0,-4)
	await _sync()
	game._update_visibility()
	_check(not enemy.visible, "enemy_outside_camera_frustum_is_hidden")
	_look_at(ARENA+Vector3(0,5,-10))
	game.player.supplies.hegrenade = 1
	game._throw_grenade("hegrenade")
	var upward_velocity: Vector3 = game.grenades.back().velocity
	_look_at(ARENA+Vector3(0,-4,-10))
	game.player.supplies.hegrenade = 1
	game._throw_grenade("hegrenade")
	var downward_velocity: Vector3 = game.grenades.back().velocity
	_check(upward_velocity.y > downward_velocity.y+5.0 and upward_velocity.z < 0.0 and downward_velocity.z < 0.0, "grenade_throw_follows_vertical_view_direction",{"up":str(upward_velocity),"down":str(downward_velocity)})

func _key_state(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _right_mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	Input.parse_input_event(event)

func _movement_and_modals() -> void:
	await _start()
	if DisplayServer.get_name() == "headless":
		skipped.append({"name":"native_mouse_capture_WASD_ADS_and_modal_reacquisition","reason":"The headless DisplayServer cannot capture the pointer; repeat without --headless to exercise native input."})
		return
	var floor_body := _body_at(ARENA+Vector3(0,-0.56,0),Vector3(60,1,60))
	await _sync()
	_look_at(ARENA+Vector3(-10,3,-10))
	var camera_right: Vector3 = game.camera.global_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	_key_state(KEY_D,true)
	await process_frame
	for i: int in 20:
		game._player_input(1.0/60.0,false)
		await physics_frame
	var normal_speed: float = game.player.speed
	var horizontal_velocity := Vector3(game.player.velocity.x,0.0,game.player.velocity.z)
	_check(normal_speed > 5.0 and horizontal_velocity.normalized().dot(camera_right) > 0.999, "D_strafes_right_relative_to_first_person_yaw")
	_right_mouse(true)
	await process_frame
	for i: int in 20:
		game._player_input(1.0/60.0,false)
		game._update_camera(1.0/60.0)
		await physics_frame
	_check(game.player.aiming and game.player.speed < normal_speed*0.5 and game.camera.fov < 60.0, "right_mouse_ADS_slows_strafing_and_narrows_FOV", {"speed":game.player.speed,"normal_speed":normal_speed,"fov":game.camera.fov})
	_key_state(KEY_D,false)
	_key_state(KEY_A,true)
	_right_mouse(false)
	await process_frame
	for i: int in 25:
		game._player_input(1.0/60.0,false)
		await physics_frame
	horizontal_velocity = Vector3(game.player.velocity.x,0.0,game.player.velocity.z)
	_check(horizontal_velocity.normalized().dot(-camera_right) > 0.999, "A_strafes_left_relative_to_first_person_yaw")
	_key_state(KEY_A,false)
	game._sync_mouse_mode()
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "active_first_person_captures_mouse")
	game.ui.toggle_inventory(game._state())
	game._sync_mouse_mode()
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "inventory_releases_mouse")
	var pitch_before: float = game._fp_pitch
	var yaw_before: float = game._fp_yaw
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(75,-100)
	motion.screen_relative = motion.relative
	Input.parse_input_event(motion)
	await process_frame
	game._step_first_person_look(0.1)
	_check(is_equal_approx(game._fp_pitch,pitch_before) and is_equal_approx(game._fp_yaw,yaw_before), "modal_mouse_motion_cannot_rotate_player")
	game.ui.close_panels()
	game._sync_mouse_mode()
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "closing_inventory_recaptures_mouse")
	game.paused = true
	game.ui.show_pause()
	game._sync_mouse_mode()
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "pause_releases_mouse")
	game._action("resume")
	game._sync_mouse_mode()
	_check(not game.paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "resume_recaptures_mouse")
	_key_state(KEY_V,true)
	await process_frame
	_key_state(KEY_V,false)
	await process_frame
	_check(game.settings.view_mode == "top_down" and game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "V_key_switches_to_top_down")
	_key_state(KEY_V,true)
	await process_frame
	_key_state(KEY_V,false)
	await process_frame
	_check(game.settings.view_mode == "first_person" and game.camera.projection == Camera3D.PROJECTION_PERSPECTIVE and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "V_key_switches_back_and_recaptures_mouse")
	floor_body.queue_free()
	await _sync()

func _tap_key(code: Key) -> void:
	_key_state(code,true)
	await process_frame
	_key_state(code,false)
	await process_frame

func _inactive_guards() -> void:
	await _start()
	var viewmodel: Node3D = game.first_person_viewmodel
	await _tap_key(KEY_ESCAPE)
	game._update_camera(1.0)
	_check(game.paused and game.ui._modal_kind == "pause" and not viewmodel._active and viewmodel.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "pause_disables_viewmodel_and_camera_update_cannot_reenable_it")
	game.player.supplies.hegrenade = 2
	var active_slot: int = game.player.active_slot
	game._action("grenade:hegrenade")
	game._equip(1)
	_check(game.player.supplies.hegrenade == 2 and game.grenades.is_empty() and game.player.active_slot == active_slot, "pause_blocks_HUD_grenade_and_equipment_actions")
	game._action("resume")
	game._update_camera(1.0)
	_check(viewmodel._active and viewmodel.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "resume_reenables_viewmodel")
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game._update_camera(1.0)
	_check(not game._window_focused and not viewmodel._active and viewmodel.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "focus_loss_disables_viewmodel_and_camera_update_cannot_reenable_it")
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	game._update_camera(1.0)
	_check(game._window_focused and game.paused and not viewmodel._active, "focus_return_preserves_pause_until_player_resumes")
	game._action("resume")
	game._update_camera(1.0)
	_check(not game.paused and viewmodel._active and viewmodel.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "resume_after_focus_return_reenables_viewmodel")
	game._finish_round("CT","First-person integration fixture")
	game._physics_process(0.0)
	game._update_camera(1.0)
	_check(game.phase == "result" and not viewmodel._active and viewmodel.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "round_result_disables_viewmodel_and_camera_update_cannot_reenable_it")
	await _tap_key(KEY_4)
	_check(game.player.supplies.hegrenade == 2 and game.grenades.is_empty(), "round_result_4_key_cannot_consume_grenades")
	game._action("grenade:hegrenade")
	_check(game.player.supplies.hegrenade == 2 and game.grenades.is_empty(), "round_result_HUD_action_cannot_consume_grenades")
	await _tap_key(KEY_2)
	game.ui.equip_requested.emit(1)
	_check(game.player.active_slot == active_slot, "round_result_keyboard_and_HUD_cannot_change_equipment")
	game._new_round()
	await _sync()
	_check(game.phase != "result" and viewmodel._active and viewmodel.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "new_round_after_result_reenables_viewmodel")

func _lifecycle() -> void:
	await _start()
	var attacker: CharacterBody3D = _enemy()
	game._damage(game.player,10000.0,attacker)
	game._update_camera(1.0)
	game._sync_mouse_mode()
	_check(not game.is_first_person() and game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "death_restores_observer_camera_and_releases_capture")
	game._update_respawns(3.1)
	await _sync()
	game._update_camera(1.0)
	game._sync_mouse_mode()
	_check(game.player.alive and game.is_first_person() and game.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "practice_respawn_restores_first_person")
	if DisplayServer.get_name() != "headless":
		_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,"practice_respawn_recaptures_mouse")
	game._apply_first_person_look(Vector2(25,-100))
	game._new_round()
	await _sync()
	_check(game.is_first_person() and absf(game._fp_pitch) < 0.001, "new_round_resets_pitch_and_preserves_selected_mode")
	game._action("menu")
	game._menu_camera(0.0)
	game._sync_mouse_mode()
	_check(not game.is_first_person() and game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and game.player.visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "menu_restores_orthographic_camera_body_and_pointer")
	game._open_map_preview()
	_check(game.map_viewer.active and game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "map_preview_starts_orthographic_after_first_person")
	game._action("map_preview_projection")
	game._close_map_preview()
	_check(game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and not game.map_viewer.active, "perspective_preview_exit_restores_menu_projection")
	game.start_game("T","practice",0)
	game.set_physics_process(false)
	await _sync()
	_check(game.is_first_person() and game.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "starting_after_preview_restores_saved_first_person_mode")

func _restore_settings() -> void:
	if had_settings:
		var file := FileAccess.open(SETTINGS_PATH,FileAccess.WRITE)
		file.store_buffer(saved_settings)
		file.close()
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	Input.mouse_mode = initial_mouse_mode

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null
	for child: Node in node.get_children(): _stop_audio(child)

func _finish() -> void:
	if finished: return
	finished = true
	_key_state(KEY_A,false)
	_key_state(KEY_D,false)
	_right_mouse(false)
	_restore_settings()
	var report := {"godot":Engine.get_version_info().string,"display_server":DisplayServer.get_name(),"duration_ms":Time.get_ticks_msec()-started_ms,"checks":checks,"failures":failures,"skipped":skipped,"observations":observations,"files_sha256":{"main":FileAccess.get_sha256("res://scripts/main.gd"),"settings":FileAccess.get_sha256("res://scripts/first_person_settings.gd")},"limitations":["Native physics integration; rendered pixels and subjective mouse feel require visual review. Native input is exercised only with a window display server.","The fixture uses an isolated arena outside Mirage, and pauses automatic match logic.","The user's settings file is restored byte for byte on completion and watchdog timeout."]}
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var output := FileAccess.open("res://artifacts/first_person_results.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	print("FIRST_PERSON_RESULT checks=%d failures=%d report=res://artifacts/first_person_results.json" % [checks.size(),failures.size()])
	_stop_audio(game)
	game.queue_free()
	await _sync()
	quit(0 if failures.is_empty() else 1)

func _timeout() -> void:
	if finished: return
	_check(false,"test_watchdog_timeout")
	_restore_settings()
	quit(2)
