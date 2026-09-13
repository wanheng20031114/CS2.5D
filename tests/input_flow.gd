extends SceneTree

const TARGET_FRAMES := 600
const CatalogData := preload("res://scripts/weapon_catalog.gd")
var game: Node3D
var checks: Array[Dictionary] = []
var failures := 0
var report: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	report = {"started_utc":Time.get_datetime_string_from_system(true),"engine":Engine.get_version_info().get("string",""),"os":OS.get_name(),"cpu":OS.get_processor_name(),"gpu":RenderingServer.get_video_adapter_name(),"render_method":RenderingServer.get_current_rendering_method(),"map_assets":{}}
	for path in ["res://assets/map/mirage_baked.tscn","res://assets/map/source_environment.glb","res://assets/map/navigation.json"]:
		report.map_assets[path] = {"modified_unix":FileAccess.get_modified_time(path),"bytes":FileAccess.open(path,FileAccess.READ).get_length()}
	var scene := load("res://scenes/main.tscn") as PackedScene
	game = scene.instantiate()
	root.add_child(game)
	await _frames(75)
	report["window_pixels"] = [root.size.x,root.size.y]
	report["viewport_pixels"] = [root.get_visible_rect().size.x,root.get_visible_rect().size.y]
	report["vsync_mode"] = DisplayServer.window_get_vsync_mode()
	_check("menu_visible_on_boot",game.ui.menu.visible and not game.running)
	await _capture("runtime_menu_source.png")
	await _click(_find_button(game.ui.menu,"自由练习"))
	_check("practice_button_changes_mode",game.ui.mode == "practice")
	await _click(_find_button(game.ui.menu,"CT   反恐精英"))
	await _click(_find_button(game.ui.menu,"部署进入战局",true))
	await _frames(45)
	_check("CT_practice_starts_from_real_menu_button",game.running and game.side == "CT" and game.mode == "practice" and game.player.team == "CT")
	_check("CT_practice_has_three_enemy_bots",game.actors.size() == 4)
	await _capture("runtime_ct_source.png")
	await _key(KEY_B)
	_check("B_opens_shop",game.ui._modal_kind == "shop")
	await _frames(20)
	var ct_money := int(game.money)
	var ct_buy := _shop_button("deagle")
	_check("available_pistol_button_enabled",is_instance_valid(ct_buy) and not ct_buy.disabled)
	await _click(ct_buy)
	_check("purchase_deducts_exact_catalog_price",game.money == ct_money-int(CatalogData.data("deagle").price))
	_check("purchase_equips_pistol",game.player.current_weapon() == "deagle")
	_check("wrong_team_weapon_disabled",_shop_button("glock").disabled)
	await _capture("runtime_shop_source.png")
	await _click(_find_button(game.ui.modal,"装备"))
	var saved_money := int(game.money)
	game.player.armor = 100
	game.player.helmet = false
	game.money = 349
	game._update_hud()
	await _frames(8)
	_check("helmet_upgrade_349_dollars_disabled",_shop_button("helmet").disabled)
	for balance in [350,799,999]:
		game.player.helmet = false
		game.money = balance
		game._update_hud()
		await _frames(8)
		var helmet_button := _shop_button("helmet")
		_check("helmet_upgrade_%d_dollars_enabled" % balance,not helmet_button.disabled)
		for row in game.ui._shop_buttons:
			if row.item.id == "helmet":
				_check("helmet_upgrade_%d_displays_350_price" % balance,row.price.text == "$ 350")
		if balance == 799:
			await _capture("runtime_helmet_discount.png")
		await _click(helmet_button)
		_check("helmet_upgrade_%d_native_click_deducts_350" % balance,game.money == balance-350 and game.player.helmet)
	game.money = saved_money
	game._update_hud()
	await _key(KEY_B)
	_check("B_closes_shop",not game.ui.is_modal_open())
	await _key(KEY_TAB)
	_check("Tab_opens_inventory",game.ui._modal_kind == "inventory")
	await _frames(20)
	var inventory_buttons: Array = game.ui._inventory_grid.get_children()
	await _click(inventory_buttons[0])
	_check("inventory_primary_button_equips_slot0",game.player.active_slot == 0)
	inventory_buttons = game.ui._inventory_grid.get_children()
	_check("grenade_inventory_not_invalid_equip_button",inventory_buttons[3].disabled)
	await _capture("runtime_inventory_source.png")
	await _key(KEY_ESCAPE)
	_check("Escape_closes_inventory_without_pausing",not game.ui.is_modal_open() and not game.paused)
	await _key(KEY_ESCAPE)
	_check("Escape_opens_pause",game.paused and game.ui._modal_kind == "pause")
	await _click(_find_button(game.ui.modal,"继续行动"))
	_check("continue_button_resumes",not game.paused and not game.ui.is_modal_open())
	await _key(KEY_ESCAPE)
	await _click(_find_button(game.ui.modal,"设置与操作"))
	_check("settings_open_from_pause",game.paused and game.ui._modal_kind == "settings")
	await _click(_find_button(game.ui.modal,"完成"))
	_check("settings_done_resumes_paused_game",not game.paused and not game.ui.is_modal_open())
	await _key(KEY_ESCAPE)
	await _click(_find_button(game.ui.modal,"返回主界面"))
	_check("return_menu_button",game.ui.menu.visible and not game.running)
	await _click(_find_button(game.ui.menu,"T   恐怖分子"))
	await _click(_find_button(game.ui.menu,"部署进入战局",true))
	await _frames(45)
	_check("T_practice_starts_from_real_menu_button",game.running and game.side == "T" and game.player.team == "T")
	await _key(KEY_B)
	await _click(_find_button(game.ui.modal,"步枪"))
	await _frames(12)
	var t_money := int(game.money)
	await _click(_shop_button("galilar"))
	_check("T_shop_buy_rifle_uses_price_and_loadout",game.money == t_money-int(CatalogData.data("galilar").price) and game.player.current_weapon() == "galilar")
	await _click(_find_button(game.ui.modal,"×"))
	_check("shop_close_button_returns_gameplay",not game.ui.is_modal_open() and not game.paused)
	await _frames(120)
	await _capture("runtime_t_source.png")
	var quick := "--quick" in OS.get_cmdline_user_args()
	if not quick:
		# Monitors refresh periodically: leave screenshot readback out of samples.
		await create_timer(4.0).timeout
		await _measure()
		report["native_rate_sample"] = report.performance.duplicate(true)
		var previous_cap := Engine.max_fps
		Engine.max_fps = 60
		await create_timer(2.0).timeout
		await _measure()
		report.performance["configured_frame_limit"] = 60
		Engine.max_fps = previous_cap
	await _capture("runtime_t_after_stability.png")
	report["checks"] = checks
	report["failed"] = failures
	report["finished_utc"] = Time.get_datetime_string_from_system(true)
	var file := FileAccess.open("res://artifacts/runtime_validation_quick.json" if quick else "res://artifacts/runtime_validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("INPUT_FLOW_RESULT ",JSON.stringify({"checks":checks.size(),"failed":failures,"performance":report.get("performance",{})}))
	quit(0 if failures == 0 else 1)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _check(name: String, passed: bool) -> void:
	checks.append({"name":name,"passed":passed})
	if not passed:
		failures += 1
	print("INPUT_CHECK ",name," ","PASS" if passed else "FAIL")

func _find_button(node: Node, text: String, prefix: bool = false) -> Button:
	if node is Button and (node.text.begins_with(text) if prefix else node.text == text):
		return node
	for child in node.get_children():
		var found := _find_button(child,text,prefix)
		if found != null:
			return found
	return null

func _shop_button(id: String) -> Button:
	for row in game.ui._shop_buttons:
		if row.item.id == id:
			return row.button
	return null

func _click(button: Button) -> void:
	if not is_instance_valid(button):
		_check("requested_button_exists",false)
		return
	var scroll := button.get_parent().get_parent()
	if scroll is ScrollContainer:
		scroll.ensure_control_visible(button)
		await _frames(3)
	var p := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = p
	motion.global_position = p
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = p
	event.global_position = p
	root.push_input(event,true)
	await process_frame
	var released := event.duplicate() as InputEventMouseButton
	released.pressed = false
	root.push_input(released,true)
	await _frames(18)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	root.push_input(event,true)
	await process_frame
	var released := event.duplicate() as InputEventKey
	released.pressed = false
	root.push_input(released,true)
	await _frames(12)

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/"+name)

func _measure() -> void:
	var process_ms: Array[float] = []
	var physics_ms: Array[float] = []
	var frame_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var primitives: Array[float] = []
	var begin := Time.get_ticks_usec()
	var engine_frames_begin := Engine.get_process_frames()
	var physics_frames_begin := Engine.get_physics_frames()
	var last := begin
	for i in TARGET_FRAMES:
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now-last)/1000.0)
		last = now
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var elapsed_seconds := float(Time.get_ticks_usec()-begin)/1000000.0
	report["performance"] = {"frames":TARGET_FRAMES,"engine_process_frames":Engine.get_process_frames()-engine_frames_begin,"physics_frames":Engine.get_physics_frames()-physics_frames_begin,"wall_seconds":elapsed_seconds,"effective_fps":float(TARGET_FRAMES)/elapsed_seconds,"frame_ms":_stats(frame_ms),"engine_process_cpu_ms":_stats(process_ms),"physics_cpu_ms":_stats(physics_ms),"draw_calls":_stats(draw_calls),"rendered_primitives":_stats(primitives),"static_memory_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,"video_memory_mb":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0,"actors":game.actors.size(),"mode":game.mode,"alive_player":game.player.alive,"camera_size":game.camera.size}

func _stats(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var sum := 0.0
	for value in values:
		sum += value
	return {"mean":sum/values.size(),"p50":sorted[sorted.size()/2],"p95":sorted[mini(sorted.size()-1,int(sorted.size()*0.95))],"max":sorted.back()}
