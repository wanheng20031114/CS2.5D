extends Node3D

const MapScript = preload("res://scripts/mirage_map.gd")
const ActorScript = preload("res://scripts/combatant.gd")
const Catalog = preload("res://scripts/weapon_catalog.gd")
const UIScript = preload("res://scripts/game_ui.gd")
const SoundScript = preload("res://scripts/sound.gd")
const SIGHT_RADIUS: float = 42.0
const RAY_COUNT: int = 192
var world: Node3D
var camera: Camera3D
var ui: CanvasLayer
var sound: Node
var actors: Array = []
var effects: Array[Dictionary] = []
var smokes: Array[Dictionary] = []
var fires: Array[Dictionary] = []
var grenades: Array[Dictionary] = []
var drops: Array[Dictionary] = []
var player: CharacterBody3D
var running: bool = false
var paused: bool = false
var side: String = "CT"
var mode: String = "bomb"
var difficulty: int = 1
var money: int = 800
var score_ct: int = 0
var score_t: int = 0
var round_number: int = 0
var phase: String = "menu"
var round_time: float = 115.0
var buy_time: float = 0.0
var result_time: float = 0.0
var kills: int = 0
var feed: Array[String] = []
var target_site: String = "A"
var planted: bool = false
var bomb_time: float = 40.0
var bomb_position: Vector3 = Vector3.ZERO
var bomb_node: Node3D
var bomb_progress: float = 0.0
var bomb_actor: Node3D
var bomb_tick: float = 0.0
var bomb_dropped: bool = false
var aim_position: Vector3
var aim_direction := Vector3.FORWARD
var shot_direction := Vector3.FORWARD
var camera_target: Vector3
var camera_shake: float = 0.0
var hit_time: float = 0.0
var fog_time: float = 0.0
var hud_time: float = 0.0
var elapsed: float = 0.0
var trigger_pressed: bool = false
var visibility_material: ShaderMaterial
var visibility_image: Image
var visibility_texture: ImageTexture
var settings: Dictionary = {"sensitivity":1.0,"volume":0.65,"shake":0.55,"zoom":24.0,"fullscreen":false}
var rng := RandomNumberGenerator.new()
var respawns: Array[Dictionary] = []
var _empty_clock: float = 0.0
var _foot_clock: float = 0.0
var _flash: ColorRect
var map_viewer: RefCounted
var _preview_hidden: Array[Dictionary] = []
var _preview_sun: DirectionalLight3D
var _preview_shadow_distance := 110.0

func _ready() -> void:
	rng.randomize()
	_load_settings()
	world = MapScript.new()
	add_child(world)
	world.build()
	RenderingServer.global_shader_parameter_set("view_cutaway",0.0)
	_setup_environment()
	sound = SoundScript.new()
	add_child(sound)
	ui = UIScript.new()
	add_child(ui)
	ui.set_settings(settings)
	ui.start_requested.connect(start_game)
	ui.buy_requested.connect(buy_item)
	ui.equip_requested.connect(_equip)
	ui.action_requested.connect(_action)
	ui.settings_changed.connect(_settings_changed)
	var combat_layer := CanvasLayer.new()
	combat_layer.layer = 3
	add_child(combat_layer)
	var combat_overlay := preload("res://scripts/combat_overlay.gd").new()
	combat_overlay.game = self
	combat_layer.add_child(combat_overlay)
	_setup_visibility()
	var flash_layer := CanvasLayer.new()
	flash_layer.layer = 6
	add_child(flash_layer)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1,0.97,0.87,0)
	flash_layer.add_child(_flash)
	ui.show_menu()
	_menu_camera(0)
	if "--quick-start" in OS.get_cmdline_user_args():
		start_game("T", "practice", 0)

func _setup_environment() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("a4bec7")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# The source sky is blue; warm sandstone bounce neutralizes most of that
	# tint. This blended fill approximates it without Source 2 baked lightmaps.
	env.ambient_light_color = Color8(198,211,213)
	env.ambient_light_energy = 0.48
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.7
	env.ssao_light_affect = 0.6
	env.ssao_detail = 0.7
	environment.environment = env
	add_child(environment)
	# Mirage's Source 2 skybox is not part of the exported playable world.
	# A visual-only sand base keeps the overhead view from exposing blue void
	# outside that world; it does not add collision or change any map object.
	var backdrop := MeshInstance3D.new()
	backdrop.name = "DesertBackdrop"
	var base := PlaneMesh.new()
	base.size = Vector2(700,700)
	backdrop.mesh = base
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color("a79b7c")
	sand.roughness = 1.0
	backdrop.material_override = sand
	backdrop.position.y = -8.0
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(backdrop)
	var sunlight := DirectionalLight3D.new()
	sunlight.name = "MirageSun_Valve318_60"
	sunlight.light_color = Color8(255,223,179)
	sunlight.light_energy = 1.35
	sunlight.rotation_degrees = Vector3(-60.0,-132.0,0)
	sunlight.shadow_enabled = true
	sunlight.directional_shadow_max_distance = 110.0
	sunlight.shadow_bias = 0.03
	sunlight.shadow_normal_bias = 1.3
	sunlight.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sunlight.light_angular_distance = 0.65
	add_child(sunlight)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(settings.zoom)
	camera.far = 240.0
	camera.near = 0.1
	add_child(camera)
	camera.current = true

func _setup_visibility() -> void:
	visibility_image = Image.create(RAY_COUNT,1,false,Image.FORMAT_RF)
	visibility_image.fill(Color.WHITE)
	visibility_texture = ImageTexture.create_from_image(visibility_image)
	visibility_material = ShaderMaterial.new()
	visibility_material.shader = preload("res://shaders/visibility.gdshader")
	visibility_material.set_shader_parameter("sight_ranges",visibility_texture)
	visibility_material.set_shader_parameter("sight_radius",SIGHT_RADIUS)
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2,2)
	mesh.mesh = quad
	mesh.material_override = visibility_material
	mesh.extra_cull_margin = 16384
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(mesh)
	mesh.position.z = -1.0

func _menu_camera(t: float) -> void:
	var center: Vector3 = world.sites.get("A", Vector3.ZERO)
	camera.size = 34.0
	camera.position = center + Vector3(15.0+sin(t*0.055)*2.0,43,17)
	camera.look_at(center + Vector3(-4,0,0))

func start_game(chosen_side: String, chosen_mode: String, chosen_difficulty: int) -> void:
	if is_instance_valid(map_viewer) and map_viewer.active:
		_close_map_preview()
	side = chosen_side
	mode = chosen_mode
	difficulty = chosen_difficulty
	running = true
	paused = false
	score_ct = 0
	score_t = 0
	kills = 0
	round_number = 0
	money = 16000 if mode == "practice" else 800
	feed.clear()
	ui.show_hud()
	_new_round(false)
	ui.toast("WASD 移动 · 鼠标瞄准 · 右键稳枪 · B 购买 · Tab 背包")

func _new_round(preserve_gear: bool = true) -> void:
	var kept: Dictionary = {}
	if preserve_gear and is_instance_valid(player) and player.alive:
		kept = {"loadout":player.loadout.duplicate(),"ammunition":player.ammunition.duplicate(true),"armor":player.armor,"helmet":player.helmet,"kit":player.kit,"supplies":player.supplies.duplicate()}
	for actor in actors:
		actor.queue_free()
	actors.clear()
	for drop in drops:
		if is_instance_valid(drop.node): drop.node.queue_free()
	drops.clear()
	for g in grenades:
		if is_instance_valid(g.node): g.node.queue_free()
	grenades.clear()
	for s in smokes:
		if is_instance_valid(s.node): s.node.queue_free()
	smokes.clear()
	for f in fires:
		if is_instance_valid(f.node): f.node.queue_free()
	fires.clear()
	if is_instance_valid(bomb_node): bomb_node.queue_free()
	bomb_node = null
	bomb_dropped = false
	planted = false
	bomb_progress = 0
	bomb_time = 40
	bomb_actor = null
	respawns.clear()
	round_number += 1
	phase = "home" if mode == "practice" else "buy"
	buy_time = 9999 if mode == "practice" else 20
	round_time = 115
	result_time = 0
	target_site = "A" if round_number % 2 == 1 else "B"
	var starting_gun: String = ("ak47" if side == "T" else "m4a1_silencer") if mode == "practice" else ("glock" if side == "T" else "usp_silencer")
	player = _spawn_actor(side, true, starting_gun, 0)
	if not kept.is_empty():
		player.loadout = kept.loadout
		player.ammunition = kept.ammunition
		player.armor = kept.armor
		player.helmet = kept.helmet
		player.kit = kept.kit
		player.supplies = kept.supplies
		player.equip(0 if not player.loadout[0].is_empty() else 1)
	elif mode == "practice":
		player.armor = 100
		player.helmet = true
		player.kit = side == "CT"
		player.supplies = {"hegrenade":1,"smokegrenade":1,"flashbang":2}
	player.bomb_carrier = side == "T"
	var count := 5 if mode == "bomb" else 3
	for i in range(1, count):
		if mode == "bomb": _spawn_actor(side, false, ("ak47" if side == "T" else "m4a1") if round_number > 1 else ("glock" if side == "T" else "hkp2000"), i)
	var enemy_side := "T" if side == "CT" else "CT"
	for i in range(count):
		var bot: CharacterBody3D = _spawn_actor(enemy_side, false, ("ak47" if enemy_side == "T" else "m4a1") if (round_number > 1 or mode == "practice") else ("glock" if enemy_side == "T" else "hkp2000"), i)
		if enemy_side == "T" and i == 0: bot.bomb_carrier = true
	camera_target = player.position
	_update_camera(1.0)
	visibility_material.set_shader_parameter("enabled",1.0)
	RenderingServer.global_shader_parameter_set("view_cutaway",1.0)
	ui.close_panels()
	_update_hud()

func _spawn_actor(team: String, human: bool, gun: String, index: int) -> CharacterBody3D:
	var actor = ActorScript.new()
	actor.display_name = "你" if human else ("SABLE" if team == "T" else "GHOST") + " " + str(index+1)
	add_child(actor)
	actor.setup(team,human,gun)
	if human:
		var ring := MeshInstance3D.new()
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.34
		ring_mesh.outer_radius = 0.38
		ring_mesh.rings = 24
		ring_mesh.ring_segments = 6
		ring.mesh = ring_mesh
		var ring_material := StandardMaterial3D.new()
		ring_material.albedo_color = Color("dcc897")
		ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = ring_material
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		actor.add_child(ring)
		ring.position.y = 0.035
	var spawn: Vector3 = world.spawns[team]
	var spawn_list: Array = world.spawn_points.get(team,[])
	if not spawn_list.is_empty(): spawn = spawn_list[index % spawn_list.size()]
	actor.position = spawn + Vector3.UP*0.12
	actor.rotation.y = 0 if team == "CT" else PI
	actor.goal = world.sites[target_site] if team == "T" else world.sites["A" if index % 2 == 0 else "B"]
	var formation := Vector3(cos(float(index)*TAU/5.0),0,sin(float(index)*TAU/5.0))
	actor.set_meta("formation",formation)
	actor.goal += formation
	actor.think_timer = index*0.11
	if not human and round_number > 1: actor.armor = 100
	actors.append(actor)
	return actor

func _physics_process(delta: float) -> void:
	elapsed += delta
	if is_instance_valid(map_viewer) and map_viewer.active:
		map_viewer.update(delta)
		if is_instance_valid(_preview_sun):
			_preview_sun.directional_shadow_max_distance = camera.global_position.distance_to(map_viewer.target)+110.0
		return
	if not running:
		_menu_camera(elapsed)
		return
	if paused:
		return
	if not is_instance_valid(player): return
	hit_time = maxf(0,hit_time-delta)
	_empty_clock = maxf(0,_empty_clock-delta)
	_flash.color.a = maxf(0.0,_flash.color.a-delta*0.46)
	if phase == "result":
		result_time -= delta
		if result_time <= 0.0:
			if maxi(score_ct,score_t) >= 6:
				_action("menu")
			else:
				_new_round()
		_update_effects(delta)
		_update_hud()
		return
	buy_time = maxf(0,buy_time-delta)
	if phase == "buy" and buy_time <= 0:
		phase = "live"
		ui.toast("回合开始 · " + ("保护 A / B 炸弹点" if side == "CT" else "携带 C4 前往 A / B 点"))
	if phase == "live":
		round_time -= delta
		if round_time <= 0 and not planted: _finish_round("CT","时间结束")
	var modal: bool = ui.is_modal_open()
	if player.alive:
		_player_input(delta,modal)
	for actor in actors:
		actor.tick(delta)
		if actor.alive and not actor.is_player:
			_bot_tick(actor,delta)
	_update_bomb(delta,modal)
	_update_grenades(delta)
	_update_effects(delta)
	_update_respawns(delta)
	_update_camera(delta)
	fog_time -= delta
	if fog_time <= 0:
		fog_time = 0.055
		_update_visibility()
	hud_time -= delta
	if hud_time <= 0:
		hud_time = 0.07
		_update_hud()

func _player_input(delta: float, modal: bool) -> void:
	var input_axis := Vector2.ZERO
	if not modal:
		input_axis.x = float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
		input_axis.y = float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W))
	var right := camera.global_basis.x
	right.y = 0
	var forward := -camera.global_basis.z
	forward.y = 0
	var direction := (right.normalized()*input_axis.x-forward.normalized()*input_axis.y).normalized()
	player.aiming = not modal and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	player.move_direction(direction,delta,Input.is_physical_key_pressed(KEY_SHIFT))
	if not modal:
		var mouse := get_viewport().get_mouse_position()
		var origin := camera.project_ray_origin(mouse)
		var normal := camera.project_ray_normal(mouse)
		var plane := Plane(Vector3.UP,player.position.y+1.1)
		var hit: Variant = plane.intersects_ray(origin,normal)
		if hit != null:
			aim_position = hit
			aim_direction = aim_position-player.position-Vector3.UP*1.1
			aim_direction.y = 0
			if aim_direction.length_squared() > 0.08:
				aim_direction = aim_direction.normalized()
				player.rotation.y = lerp_angle(player.rotation.y,atan2(-aim_direction.x,-aim_direction.z),1.0-exp(-delta*35.0*float(settings.sensitivity)))
		shot_direction = aim_direction
		var target_query := PhysicsRayQueryParameters3D.create(origin,origin+normal*200,2,[player.get_rid()])
		var target_hit := get_world_3d().direct_space_state.intersect_ray(target_query)
		if not target_hit.is_empty() and target_hit.collider in actors and target_hit.collider.visible:
			shot_direction = (target_hit.collider.position-player.position).normalized()
		var pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if pressed and (not trigger_pressed or player.weapon_data().get("automatic",true)):
			_shoot(player,shot_direction)
		trigger_pressed = pressed
	else:
		trigger_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if player.speed > 1.0:
		_foot_clock -= delta
		if _foot_clock <= 0:
			_foot_clock = 0.34 if player.speed > 4 else 0.47
			sound.play("step",0.20 if player.aiming else 0.38,rng.randf_range(0.85,1.2))

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(map_viewer) and map_viewer.active:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			_close_map_preview()
			get_viewport().set_input_as_handled()
		elif map_viewer.handle_input(event):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if running:
				if ui.is_modal_open():
					ui.close_panels()
					paused = false
				else:
					paused = true
					if ui.has_method("show_pause"): ui.show_pause()
					else: ui.show_menu()
			return
		if not running or not is_instance_valid(player) or not player.alive: return
		match event.physical_keycode:
			KEY_B: ui.toggle_shop(Catalog.all(),_state())
			KEY_TAB: ui.toggle_inventory(_state())
			KEY_R:
				if not ui.is_modal_open() and player.start_reload(): sound.play("reload",0.75)
			KEY_SPACE:
				if not ui.is_modal_open() and player.is_on_floor(): player.velocity.y = 7.8
			KEY_1: _equip(0)
			KEY_2: _equip(1)
			KEY_3: _equip(2)
			KEY_4: _throw_grenade("hegrenade")
			KEY_5: _throw_grenade("smokegrenade")
			KEY_6: _throw_grenade("flashbang")
			KEY_7: _throw_grenade("molotov" if side == "T" else "incgrenade")
			KEY_8: _throw_grenade("decoy")
			KEY_G: _drop_weapon()
			KEY_F: _pickup()
			KEY_F5:
				if mode == "practice": _new_round()
	if event is InputEventMouseButton and event.pressed and running and not ui.is_modal_open():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: settings.zoom = clampf(float(settings.zoom)-1,16,34)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: settings.zoom = clampf(float(settings.zoom)+1,16,34)

func _equip(slot: int) -> void:
	if is_instance_valid(player) and player.alive and slot < 3:
		player.equip(slot)

func _bot_tick(bot: CharacterBody3D, delta: float) -> void:
	if bot.blind_timer > 0:
		bot.target = null
		bot.move_direction(Vector3.ZERO,delta)
		return
	if phase == "buy":
		bot.move_direction(Vector3.ZERO,delta)
		return
	bot.think_timer -= delta
	if bot.think_timer <= 0:
		bot.think_timer = rng.randf_range(0.24,0.42)
		var nearest: Node3D = null
		var closest: float = 32.0 + difficulty*4.0
		for other in actors:
			if not other.alive or other.team == bot.team: continue
			var dist: float = bot.position.distance_to(other.position)
			if dist < closest and _line_of_sight(bot.position,other.position):
				var facing := -bot.global_basis.z
				var to_enemy: Vector3 = (other.position-bot.position).normalized()
				if facing.dot(to_enemy) > -0.12 or dist < 5.0 or other == bot.target:
					closest = dist
					nearest = other
		if nearest != bot.target:
			bot.react_timer = [0.7,0.42,0.23][difficulty]
		bot.target = nearest
		if nearest == null:
			var previous_goal: Vector3 = bot.goal
			if planted:
				bot.goal = bomb_position if bot.team == "CT" else bomb_position+Vector3(5,0,4)+bot.get_meta("formation",Vector3.ZERO)
			elif bomb_dropped and bot.team == "T":
				bot.goal = bomb_position
			elif bot.goal.distance_to(bot.position) < 2.2:
				if mode == "practice":
					bot.goal = world.sites["B" if bot.goal.distance_to(world.sites["A"]) < 15 else "A"]
			# Replanning an unchanged route every few frames can select a point
			# behind a character on stairs and make it walk back indefinitely.
			if bot.path.is_empty() or previous_goal.distance_to(bot.goal) > 0.5:
				bot.path = world.find_path(bot.position,bot.goal)
	var direction := Vector3.ZERO
	if is_instance_valid(bot.target) and bot.target.alive and _line_of_sight(bot.position,bot.target.position):
		var aim: Vector3 = bot.target.position-bot.position
		aim.y = 0
		aim = aim.normalized()
		bot.rotation.y = lerp_angle(bot.rotation.y,atan2(-aim.x,-aim.z),1.0-exp(-delta*12.0))
		bot.react_timer -= delta
		bot.aiming = true
		bot.burst_timer -= delta
		if bot.react_timer <= 0 and bot.burst_timer <= 0:
			var error: float = [0.09,0.05,0.02][difficulty]
			var shot_aim: Vector3 = (bot.target.position-bot.position).normalized()
			_shoot(bot,shot_aim.rotated(Vector3.UP,rng.randf_range(-error,error)))
			if rng.randf() < 0.26: bot.burst_timer = rng.randf_range(0.25,0.6)
		if bot.ammunition.get(bot.current_weapon(),{}).get("mag",0) <= 0: bot.start_reload()
	else:
		bot.aiming = false
		while not bot.path.is_empty() and Vector2(bot.position.x-bot.path[0].x,bot.position.z-bot.path[0].z).length() < 0.18:
			bot.path.pop_front()
		if not bot.path.is_empty():
			direction = bot.path[0]-bot.position
			direction.y = 0
			direction = direction.normalized()
			bot.rotation.y = lerp_angle(bot.rotation.y,atan2(-direction.x,-direction.z),1.0-exp(-delta*8))
	# Small separation keeps squadmates from stacking in doorways.
	var separation := Vector3.ZERO
	for other in actors:
		if other == bot or not other.alive: continue
		var away: Vector3 = bot.position-other.position
		away.y = 0
		if away.length() < 0.7 and away.length() > 0.01: separation += away.normalized()*0.18
	# A stopped unit must be able to plant/defuse without squad separation
	# continually restarting its movement. Do not steer a walker into a wall.
	var steering := (direction+separation).limit_length(1.0) if not direction.is_zero_approx() else Vector3.ZERO
	if not separation.is_zero_approx() and bot.test_move(bot.global_transform,steering*0.1): steering = direction
	bot.move_direction(steering,delta)
	if bot.position.y < -20: bot.position = world.spawns[bot.team]+Vector3.UP

func _line_of_sight(a: Vector3,b: Vector3) -> bool:
	if _smoke_blocks(a,b): return false
	var query := PhysicsRayQueryParameters3D.create(a+Vector3.UP*1.1,b+Vector3.UP*1.1,1)
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _smoke_blocks(a: Vector3,b: Vector3) -> bool:
	for smoke in smokes:
		var near: Vector3 = Geometry3D.get_closest_point_to_segment(smoke.position,a,b)
		if near.distance_to(smoke.position) < 3.5: return true
	return false

func _shoot(actor: CharacterBody3D, direction: Vector3) -> void:
	if not actor.alive or actor.shot_timer > 0 or actor.reload_timer > 0 or phase == "result": return
	var data: Dictionary = actor.weapon_data()
	var id: String = actor.current_weapon()
	if id == "knife":
		actor.shot_timer = 0.5
		actor.visual.fire()
		for victim in actors:
			if victim.alive and victim.team != actor.team and actor.position.distance_to(victim.position) < 1.8 and direction.dot((victim.position-actor.position).normalized()) > 0.5 and _line_of_sight(actor.position,victim.position):
				_damage(victim,45,actor)
		return
	if not actor.ammunition.has(id): return
	if actor.ammunition[id].mag <= 0:
		if actor.is_player and _empty_clock <= 0:
			sound.play("empty",0.8)
			_empty_clock = 0.3
		actor.start_reload()
		return
	actor.ammunition[id].mag -= 1
	actor.shot_timer = 1.0/maxf(0.5,float(data.get("fire_rate",10)))
	var spread: float = actor.spread_angle()
	var origin: Vector3 = actor.position+Vector3.UP*1.08
	for pellet in range(int(data.get("pellets",1))):
		var deviated := direction.rotated(Vector3.UP,rng.randf_range(-spread,spread))
		var end := origin+deviated*float(data.get("range",75))
		var query := PhysicsRayQueryParameters3D.create(origin,end,3,[actor.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			end = hit.position
			if hit.collider in actors:
				var victim = hit.collider
				if victim.team != actor.team:
					var falloff := lerpf(1.0,0.72,clampf(origin.distance_to(end)/85.0,0,1))
					_damage(victim,float(data.get("damage",30))*falloff,actor)
			else:
				_spark(end,Color("d7b883"),0.06)
		if actor.is_player or actor.visible:
			_tracer(actor.visual.get_muzzle_position(),end,Color("ffda84"))
	actor.bloom = minf(0.14,actor.bloom+float(data.get("recoil",0.012)))
	actor.visual.fire()
	if actor.is_player:
		camera_shake = minf(0.18,camera_shake+0.085)
	var sound_kind := "rifle"
	if id in ["usp_silencer","m4a1_silencer","mp5sd"]: sound_kind = "silenced"
	elif data.get("category","") == "sniper": sound_kind = "sniper"
	elif data.get("category","") == "pistol": sound_kind = "pistol"
	var distance: float = actor.position.distance_to(player.position)
	if distance < 48: sound.play(sound_kind,1.0 if actor.is_player else clampf(1.0-distance/50.0,0.07,0.7),rng.randf_range(0.95,1.05))

func _damage(victim: CharacterBody3D, amount: float, attacker: CharacterBody3D) -> void:
	if mode == "practice" and victim.is_player: amount *= 0.45
	var died: bool = victim.take_damage(amount)
	if attacker == player:
		hit_time = 0.13
		sound.play("hit",0.5,0.8 if died else 1.2)
	if victim == player:
		camera_shake = 0.2
	if not died: return
	feed.push_front(attacker.display_name+"  ·  "+str(attacker.weapon_data().get("name",""))+"  ·  "+victim.display_name)
	if feed.size() > 4: feed.pop_back()
	if attacker == player and victim.team != attacker.team:
		kills += 1
		money = mini(16000,money+int(attacker.weapon_data().get("kill_reward",300)))
	elif attacker == player and victim != player:
		money = maxi(0,money-300)
	_drop_from_actor(victim)
	if victim.bomb_carrier and not planted:
		victim.bomb_carrier = false
		bomb_dropped = true
		bomb_position = victim.position
		_make_bomb()
	if mode == "practice":
		respawns.append({"actor":victim,"timer":3.0})
		if victim == player: ui.toast("训练中倒地 · 3 秒后重返出生点")
	else:
		_check_elimination()
		if victim == player and phase != "result": ui.toast("你已阵亡 · 观战队友，等待本回合结束")

func _check_elimination() -> void:
	if phase == "result": return
	if _alive_count("CT") == 0: _finish_round("T","反恐精英已被消灭")
	elif _alive_count("T") == 0 and not planted: _finish_round("CT","恐怖分子已被消灭")

func _alive_count(team: String) -> int:
	var count := 0
	for a in actors:
		if a.team == team and a.alive: count += 1
	return count

func _update_bomb(delta: float, modal: bool) -> void:
	if mode != "bomb" or phase == "result" or phase == "buy": return
	if bomb_dropped:
		for actor in actors:
			if actor.alive and actor.team == "T" and actor.position.distance_to(bomb_position) < 1.6:
				actor.bomb_carrier = true
				bomb_dropped = false
				if is_instance_valid(bomb_node): bomb_node.queue_free()
				bomb_node = null
				break
	if planted:
		bomb_time -= delta
		bomb_tick -= delta
		if bomb_tick <= 0:
			bomb_tick = lerpf(0.12,0.85,clampf(bomb_time/40.0,0,1))
			if player.position.distance_to(bomb_position) < 40: sound.play("bomb",0.6)
		if bomb_time <= 0:
			_spark(bomb_position+Vector3.UP,Color("ffb04b"),5.0,0.7)
			sound.play("explode",1)
			_finish_round("T","C4 已引爆")
			return
	var working: CharacterBody3D = null
	for actor in actors:
		if not actor.alive: continue
		var wants: bool = not actor.is_player or (not modal and Input.is_physical_key_pressed(KEY_E))
		if not wants or actor.speed > 0.4: continue
		if planted and actor.team == "CT" and actor.position.distance_to(bomb_position) < 2.0:
			working = actor
			break
		if not planted and actor.team == "T" and actor.bomb_carrier:
			for site_id in world.sites:
				if _inside_bombsite(actor.position,site_id):
					working = actor
					break
	if working == null:
		bomb_progress = 0
		bomb_actor = null
		return
	if bomb_actor != working:
		bomb_progress = 0
		bomb_actor = working
	bomb_progress += delta
	var duration := (5.0 if working.kit else 10.0) if planted else 3.2
	if bomb_progress >= duration:
		bomb_progress = 0
		if planted:
			_finish_round("CT","C4 已拆除")
		else:
			planted = true
			working.bomb_carrier = false
			bomb_position = working.position
			bomb_time = 40
			_make_bomb()
			if working == player: money = mini(16000,money+300)
			ui.toast("C4 已安放 · 40 秒")

func _make_bomb() -> void:
	if is_instance_valid(bomb_node): bomb_node.queue_free()
	bomb_node = _box_visual(Vector3(0.42,0.16,0.3),Color("605449"))
	add_child(bomb_node)
	bomb_node.position = bomb_position+Vector3.UP*0.15
	var light := OmniLight3D.new()
	light.light_color = Color("ff4738")
	light.light_energy = 1.7
	light.omni_range = 1.5
	bomb_node.add_child(light)
	light.position.y = 0.3

func _inside_bombsite(at: Vector3, site_id: String) -> bool:
	if world.site_regions.has(site_id):
		var region: Dictionary = world.site_regions[site_id]
		return Geometry2D.is_point_in_polygon(Vector2(at.x,at.z),region.polygon) and at.y >= region.min.y-0.25 and at.y <= region.max.y+0.2
	var site: Vector3 = world.sites[site_id]
	return Vector2(at.x-site.x,at.z-site.z).length() < 4.0

func _finish_round(winner: String, reason: String) -> void:
	if phase == "result": return
	phase = "result"
	result_time = 6
	if winner == "CT": score_ct += 1
	else: score_t += 1
	money = mini(16000,money+(3250 if winner == side else 1900))
	ui.close_panels()
	ui.show_round_result(("反恐精英" if winner == "CT" else "恐怖分子")+"获胜",reason+" · "+("比赛结束" if maxi(score_ct,score_t)>=6 else "下一回合即将开始"))

func _update_camera(delta: float) -> void:
	var observer = _observer()
	if not is_instance_valid(observer): return
	var lookahead := aim_direction * (2.0 if player.aiming else 1.0) if observer == player else Vector3.ZERO
	var desired: Vector3 = observer.position+lookahead
	var edge_margin := float(settings.zoom)*0.5
	desired.x = clampf(desired.x,world.bounds.position.x+edge_margin,world.bounds.end.x-edge_margin)
	desired.z = clampf(desired.z,world.bounds.position.y+edge_margin,world.bounds.end.y-edge_margin)
	camera_target = camera_target.lerp(desired,1.0-exp(-delta*8.0))
	camera.size = lerpf(camera.size,float(settings.zoom)*(0.91 if observer.aiming else 1.0),1.0-exp(-delta*7.0))
	camera_shake = move_toward(camera_shake,0,delta*1.5)
	var shake := Vector3(rng.randf_range(-1,1),0,rng.randf_range(-1,1))*camera_shake*float(settings.shake)
	camera.position = camera_target+Vector3(10,32,17)+shake
	camera.look_at(camera_target+shake)
	RenderingServer.global_shader_parameter_set("view_player",observer.position)
	RenderingServer.global_shader_parameter_set("view_camera",camera.position)
	RenderingServer.global_shader_parameter_set("view_camera_direction",-camera.global_basis.z)
	var facing: Vector3 = -observer.global_basis.z
	RenderingServer.global_shader_parameter_set("view_facing",Vector2(facing.x,facing.z).normalized())
	RenderingServer.global_shader_parameter_set("view_radius",SIGHT_RADIUS)
	# Rotate the screen-space visibility edge with the same pose as the cutaway;
	# obstacle range rays may update at a lower frequency.
	visibility_material.set_shader_parameter("observer",observer.position)
	visibility_material.set_shader_parameter("facing",Vector2(facing.x,facing.z).normalized())

func _observer() -> CharacterBody3D:
	if player.alive: return player
	for a in actors:
		if a.alive and a.team == side: return a
	return player

func _update_visibility() -> void:
	var observer = _observer()
	var center: Vector3 = observer.position
	var direction: Vector3 = -observer.global_basis.z
	visibility_material.set_shader_parameter("observer",center)
	visibility_material.set_shader_parameter("facing",Vector2(direction.x,direction.z))
	for i in range(RAY_COUNT):
		var angle := TAU*float(i)/RAY_COUNT
		var dir := Vector3(cos(angle),0,sin(angle))
		var start := center+Vector3.UP*1.1
		var query := PhysicsRayQueryParameters3D.create(start,start+dir*SIGHT_RADIUS,1)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		var distance := SIGHT_RADIUS
		if not hit.is_empty(): distance = start.distance_to(hit.position)
		for smoke in smokes:
			var rel: Vector3 = smoke.position-center
			rel.y = 0
			if rel.length_squared() < 12.25:
				distance = 0.0
				continue
			var projection := rel.dot(dir)
			var perp := rel.length_squared()-projection*projection
			if projection > 0 and perp < 12.25: distance = minf(distance,maxf(0,projection-sqrt(12.25-perp)))
		visibility_image.set_pixel(i,0,Color(distance/SIGHT_RADIUS,0,0))
	visibility_texture.update(visibility_image)
	for actor in actors:
		if actor == observer or actor == player:
			actor.visible = true
		else:
			var diff: Vector3 = actor.position-center
			var front: bool = direction.dot(diff.normalized()) > 0.2
			actor.visible = front and diff.length() < SIGHT_RADIUS and _line_of_sight(center,actor.position)
	for drop in drops:
		var diff: Vector3 = drop.position-center
		drop.node.visible = direction.dot(diff.normalized()) > 0.2 and diff.length() < SIGHT_RADIUS and _line_of_sight(center,drop.position)

func _buy_allowed() -> bool:
	return is_instance_valid(player) and player.alive and phase != "result" and buy_time > 0 and player.position.distance_to(world.spawns[side]) < 9.0

func buy_item(id: String) -> void:
	if not _buy_allowed():
		ui.toast("只能在购买时间内、己方出生区域购买")
		return
	var d: Dictionary = Catalog.data(id)
	if d.is_empty(): return
	if d.get("team","ANY") not in ["ANY",side]:
		ui.toast("该装备不属于当前阵营")
		return
	var price := int(d.get("price",0))
	if id in ["vesthelm","helmet"] and player.armor >= 100 and not player.helmet: price = 350
	if money < price:
		ui.toast("资金不足")
		return
	var category: String = d.get("category", "")
	if category == "melee":
		ui.toast("匕首已随身携带")
		return
	if category == "grenade":
		var total := 0
		for number in player.supplies.values(): total += int(number)
		if total >= 4 or int(player.supplies.get(id,0)) >= (2 if id == "flashbang" else 1):
			ui.toast("最多携带 4 枚投掷物，同类 1 枚，闪光弹 2 枚")
			return
		player.supplies[id] = int(player.supplies.get(id,0))+1
	elif id in ["vest","kevlar","armor"]:
		if player.armor >= 100:
			ui.toast("防弹衣完好")
			return
		player.armor = 100
	elif id in ["vesthelm","helmet"]:
		if player.armor >= 100 and player.helmet:
			ui.toast("防弹衣与头盔已装备")
			return
		player.armor = 100
		player.helmet = true
	elif id in ["defuser","kit"]:
		if player.kit: return
		player.kit = true
	elif category == "gear":
		ui.toast("该装备暂不支持")
		return
	else:
		var slot := 1 if category == "pistol" else 0
		if player.loadout[slot] == id:
			ui.toast("已装备这把武器")
			return
		player.add_weapon(id)
	money -= price
	sound.play("buy",0.65)
	ui.toast("已购买 "+str(d.get("name",id)))
	_update_hud()

func _state() -> Dictionary:
	if not is_instance_valid(player): return {}
	var id: String = player.current_weapon()
	var d: Dictionary = player.weapon_data()
	var ammo: Dictionary = player.ammunition.get(id,{"mag":0,"reserve":0})
	var inventory: Array = []
	for i in range(player.loadout.size()):
		var item: String = player.loadout[i]
		var info: Dictionary = Catalog.data(item) if not item.is_empty() else {}
		inventory.append({"id":item,"name":info.get("name","空槽位"),"count":1 if not item.is_empty() else 0,"equipped":i==player.active_slot,"slot":i,"category":info.get("category","")})
	for grenade in player.supplies:
		inventory.append({"id":grenade,"name":Catalog.data(grenade).get("name",grenade),"count":player.supplies[grenade],"equipped":false,"category":"grenade"})
	if player.kit: inventory.append({"id":"defuser","name":"拆弹器","count":1,"equipped":true,"category":"gear"})
	if player.bomb_carrier: inventory.append({"id":"c4","name":"C4 炸药","count":1,"equipped":true,"category":"gear"})
	var objective := "训练 · B 补给 / F5 重置" if mode == "practice" else ("守住 A / B 炸弹点" if side == "CT" else "护送 C4 至 A / B 点 · 按住 E 安放")
	if planted: objective = "C4 已安放 · 靠近按住 E 拆除" if side == "CT" else "守护 C4 · 阻止拆弹"
	if bomb_actor == player and bomb_progress > 0: objective = ("正在拆弹 " if planted else "正在安放 ")+"%.1f s" % bomb_progress
	return {"mode":mode,"moving":player.speed>0.3,"settings":settings,"map_data":_minimap_state(),"health":int(ceil(player.health)),"armor":int(ceil(player.armor)),"helmet":player.helmet,"money":money,"ammo":ammo.mag,"reserve":ammo.reserve,"weapon":id,"name":d.get("name",id),"round":round_number,"time":round_time,"score_ct":score_ct,"score_t":score_t,"kills":kills,"alive_ct":_alive_count("CT"),"alive_t":_alive_count("T"),"location":world.location_name(player.position),"aiming":player.aiming,"reloading":player.reload_timer>0,"reload_progress":1.0-player.reload_timer/maxf(0.001,player.reload_duration),"buy_allowed":_buy_allowed(),"buy_time":buy_time,"team":side,"phase":phase,"inventory":inventory,"active_slot":player.active_slot,"capacity":12,"used_slots":inventory.size(),"objective":objective,"crosshair_spread":player.spread_angle(),"hit_confirm":hit_time>0,"feed":feed,"bomb_planted":planted,"bomb_time":bomb_time}

func _update_hud() -> void:
	ui.update_state(_state())

func _minimap_state() -> Dictionary:
	var allies: Array[Vector3] = []
	var enemies: Array[Vector3] = []
	for actor in actors:
		if actor == player or not actor.alive: continue
		if actor.team == side: allies.append(actor.position)
		elif actor.visible: enemies.append(actor.position)
	return {"bounds":world.bounds,"player":player.position,"heading":-player.global_basis.z,"allies":allies,"enemies":enemies,"sites":world.sites}

func _action(action: String) -> void:
	if action.begins_with("map_preview_focus:"):
		if is_instance_valid(map_viewer) and map_viewer.active:
			map_viewer.focus_landmark(action.trim_prefix("map_preview_focus:"))
		return
	if action.begins_with("grenade:"):
		_throw_grenade(action.trim_prefix("grenade:"))
		return
	match action:
		"map_preview": _open_map_preview()
		"map_preview_exit": _close_map_preview()
		"map_preview_reset":
			if is_instance_valid(map_viewer) and map_viewer.active: map_viewer.reset_view()
		"map_preview_projection":
			if is_instance_valid(map_viewer) and map_viewer.active:
				ui.set_map_preview_projection(map_viewer.toggle_projection())
		"quit": get_tree().quit()
		"resume":
			paused = false
			ui.close_panels()
			ui.show_hud()
		"restart":
			paused = false
			_new_round()
		"menu":
			running = false
			paused = false
			phase = "menu"
			_flash.color.a = 0.0
			visibility_material.set_shader_parameter("enabled",0.0)
			RenderingServer.global_shader_parameter_set("view_cutaway",0.0)
			for actor in actors: actor.visible = true
			ui.show_menu()

func _open_map_preview() -> void:
	if running: return
	if is_instance_valid(map_viewer) and map_viewer.active: return
	if not is_instance_valid(map_viewer):
		map_viewer = load("res://scripts/map_model_viewer.gd").new()
	_preview_hidden.clear()
	for actor in actors: _hide_for_map_preview(actor)
	for collection in [effects,smokes,fires,grenades,drops]:
		for item in collection:
			if item.has("node"): _hide_for_map_preview(item.node)
	_hide_for_map_preview(bomb_node)
	_flash.color.a = 0.0
	visibility_material.set_shader_parameter("enabled",0.0)
	RenderingServer.global_shader_parameter_set("view_cutaway",0.0)
	map_viewer.enter(camera,world)
	_preview_sun = get_node_or_null("MirageSun_Valve318_60") as DirectionalLight3D
	if is_instance_valid(_preview_sun):
		_preview_shadow_distance = _preview_sun.directional_shadow_max_distance
		_preview_sun.directional_shadow_max_distance = camera.global_position.distance_to(map_viewer.target)+110.0
	ui.show_map_preview()
	ui.set_map_preview_projection("正交")

func _hide_for_map_preview(node: Node) -> void:
	if is_instance_valid(node) and node is Node3D:
		_preview_hidden.append({"node":node,"visible":node.visible})
		node.visible = false

func _close_map_preview() -> void:
	if not is_instance_valid(map_viewer) or not map_viewer.active: return
	map_viewer.exit()
	if is_instance_valid(_preview_sun):
		_preview_sun.directional_shadow_max_distance = _preview_shadow_distance
	for item in _preview_hidden:
		if is_instance_valid(item.node): item.node.visible = item.visible
	_preview_hidden.clear()
	RenderingServer.global_shader_parameter_set("view_cutaway",0.0)
	visibility_material.set_shader_parameter("enabled",0.0)
	ui.show_menu()
	_menu_camera(elapsed)

func _settings_changed(values: Dictionary) -> void:
	settings.merge(values,true)
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(0.001,float(settings.volume))))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	var config := ConfigFile.new()
	for key in settings: config.set_value("game",key,settings[key])
	config.save("user://settings.cfg")

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		for key in settings: settings[key] = config.get_value("game",key,settings[key])
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(0.001,float(settings.volume))))

func _box_visual(size: Vector3,color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	node.material_override = material
	return node

func _tracer(from: Vector3,to: Vector3,color: Color) -> void:
	if from.distance_to(to) < 0.02: return
	var node := _box_visual(Vector3(0.018,0.018,from.distance_to(to)),color)
	var material: StandardMaterial3D = node.material_override
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = color
	add_child(node)
	node.position = (from+to)*0.5
	node.look_at(to)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effects.append({"node":node,"time":0.055,"duration":0.055})

func _spark(at: Vector3,color: Color,size: float = 0.1,duration: float = 0.16) -> void:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size*2
	mesh.radial_segments = 8
	mesh.rings = 4
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.position = at
	effects.append({"node":node,"time":duration,"duration":duration,"shrink":true})

func _update_effects(delta: float) -> void:
	for i in range(effects.size()-1,-1,-1):
		var e: Dictionary = effects[i]
		e.time -= delta
		if e.time <= 0:
			if is_instance_valid(e.node): e.node.queue_free()
			effects.remove_at(i)
		elif e.get("shrink",false): e.node.scale = Vector3.ONE*maxf(0.01,e.time/e.duration)

func _drop_from_actor(actor: CharacterBody3D, specific_id: String = "") -> void:
	var id: String = specific_id if not specific_id.is_empty() else (actor.loadout[0] if not actor.loadout[0].is_empty() else actor.loadout[1])
	if id.is_empty(): return
	var visual := (load(Catalog.model_path(id)) as PackedScene).instantiate() as Node3D
	add_child(visual)
	visual.position = actor.position+Vector3(0.6,0.13,0)
	visual.rotation.y = actor.rotation.y+1
	visual.rotation.z = PI/2
	drops.append({"node":visual,"id":id,"ammo":actor.ammunition.get(id,{}).duplicate(),"position":visual.position})

func _drop_weapon() -> void:
	if player.active_slot >= 2 or ui.is_modal_open(): return
	_drop_from_actor(player,player.current_weapon())
	player.loadout[player.active_slot] = ""
	player.equip(1 if not player.loadout[1].is_empty() else 2)

func _pickup() -> void:
	if ui.is_modal_open(): return
	for i in range(drops.size()):
		var drop: Dictionary = drops[i]
		if player.position.distance_to(drop.position) < 2:
			player.add_weapon(drop.id)
			if not drop.ammo.is_empty(): player.ammunition[drop.id] = drop.ammo
			drop.node.queue_free()
			drops.remove_at(i)
			ui.toast("拾取 "+str(Catalog.data(drop.id).get("name",drop.id)))
			return
	ui.toast("靠近地上的武器后按 F 拾取")

func _throw_grenade(id: String) -> void:
	if ui.is_modal_open() or int(player.supplies.get(id,0)) <= 0:
		ui.toast("未携带该投掷物 · B 购买")
		return
	player.supplies[id] -= 1
	if player.supplies[id] <= 0: player.supplies.erase(id)
	var start: Vector3 = player.position+Vector3.UP*1.25
	var target: Vector3 = aim_position
	var distance := minf(20,(target-start).length())
	var flight_time := 0.8
	var velocity := aim_direction*distance/flight_time+Vector3.UP*4.8
	var node := _box_visual(Vector3(0.17,0.23,0.17),Color("586451"))
	add_child(node)
	node.position = start
	grenades.append({"node":node,"velocity":velocity,"time":1.5,"id":id,"owner":player})
	player.shot_timer = maxf(0.6,player.shot_timer)

func _update_grenades(delta: float) -> void:
	for i in range(grenades.size()-1,-1,-1):
		var g: Dictionary = grenades[i]
		g.time -= delta
		g.velocity.y -= 12.0*delta
		var old: Vector3 = g.node.position
		var next: Vector3 = old+g.velocity*delta
		var q := PhysicsRayQueryParameters3D.create(old,next,9)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			g.node.position = hit.position+hit.normal*0.1
			g.velocity = g.velocity.bounce(hit.normal)*0.4
		else: g.node.position = next
		g.node.rotate_x(delta*8)
		if g.time <= 0:
			_detonate(g)
			g.node.queue_free()
			grenades.remove_at(i)
	for i in range(smokes.size()-1,-1,-1):
		var smoke: Dictionary = smokes[i]
		smoke.time -= delta
		if smoke.time <= 0:
			smoke.node.queue_free()
			smokes.remove_at(i)
	for i in range(fires.size()-1,-1,-1):
		var fire: Dictionary = fires[i]
		fire.time -= delta
		fire.tick -= delta
		if fire.tick <= 0:
			fire.tick = 0.4
			for actor in actors:
				if actor.alive and actor.position.distance_to(fire.position) < 3.2: _damage(actor,12,fire.owner)
		if fire.time <= 0:
			fire.node.queue_free()
			fires.remove_at(i)

func _detonate(g: Dictionary) -> void:
	var at: Vector3 = g.node.position
	match g.id:
		"decoy":
			_spark(at,Color("b5b9aa"),0.4,0.3)
			sound.play("rifle",0.5)
			for actor in actors:
				if not actor.is_player and actor.alive and actor.position.distance_to(at) < 30:
					actor.goal = at
					actor.path = world.find_path(actor.position,at)
		"smokegrenade":
			var cloud := Node3D.new()
			add_child(cloud)
			cloud.position = at
			for i in range(12):
				var puff := MeshInstance3D.new()
				var mesh := SphereMesh.new()
				mesh.radius = rng.randf_range(1.1,1.7)
				mesh.height = mesh.radius*1.6
				mesh.radial_segments = 10
				mesh.rings = 5
				puff.mesh = mesh
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(0.57,0.59,0.56,0.75)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.roughness = 1
				puff.material_override = mat
				cloud.add_child(puff)
				puff.position = Vector3(rng.randf_range(-2,2),rng.randf_range(0.5,1.5),rng.randf_range(-2,2))
			smokes.append({"position":at,"node":cloud,"time":18.0})
		"flashbang":
			_spark(at,Color.WHITE,1.5,0.12)
			for actor in actors:
				if actor.alive and actor.position.distance_to(at)<18 and _line_of_sight(actor.position,at):
					var facing: float = (-actor.global_basis.z).dot((at-actor.position).normalized())
					if actor.is_player: _flash.color.a = 0.95 if facing > 0 else 0.3
					else: actor.blind_timer = 3.0 if facing > 0 else 0.8
		"molotov","incgrenade":
			var patch := _box_visual(Vector3(5.5,0.04,5.5),Color("d07a2a"))
			add_child(patch)
			patch.position = at+Vector3.UP*0.06
			fires.append({"position":at,"node":patch,"time":7.0,"tick":0.0,"owner":g.owner})
		_:
			_spark(at+Vector3.UP*0.3,Color("ffb15e"),2.2,0.28)
			for actor in actors:
				var distance: float = actor.position.distance_to(at)
				if actor.alive and distance < 7.0 and _line_of_sight(at,actor.position): _damage(actor,105.0*(1.0-distance/7.0),g.owner)
	sound.play("explode",0.7 if g.id == "hegrenade" else 0.3,1.2)

func _update_respawns(delta: float) -> void:
	for i in range(respawns.size()-1,-1,-1):
		respawns[i].timer -= delta
		if respawns[i].timer <= 0:
			var old = respawns[i].actor
			var fresh = _spawn_actor(old.team,old.is_player,"ak47" if old.team == "T" else "m4a1_silencer",i)
			if old == player:
				player = fresh
				player.armor = 100
				money = 16000
			actors.erase(old)
			old.queue_free()
			respawns.remove_at(i)
