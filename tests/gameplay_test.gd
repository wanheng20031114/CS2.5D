extends SceneTree
## Actual main-scene integration tests. Main auto-processing is stopped; test
## steps drive the same public/internal actions deterministically. Native physics
## frames synchronize CharacterBody3D/StaticBody3D collision queries.
## Godot --headless --path . --script res://tests/gameplay_test.gd

const MainScene = preload("res://scenes/main.tscn")
const Catalog = preload("res://scripts/weapon_catalog.gd")
const ARENA := Vector3(1000, 0.06, 1000)
var game: Node3D
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var observations: Dictionary = {}
var arena_floor: StaticBody3D
var barrier: StaticBody3D
var started_ms: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	started_ms = Time.get_ticks_msec()
	game = MainScene.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.paused = true
	await _sync()
	await _session_reset()
	await _shop()
	await _ammunition_and_drop()
	await _physics_shooting_visibility()
	await _round_rules()
	await _practice_respawn()
	var report: Dictionary = {
		"godot": Engine.get_version_info().string,
		"date": Time.get_datetime_string_from_system(true),
		"duration_ms": Time.get_ticks_msec() - started_ms,
		"scene": "res://scenes/main.tscn",
		"files_sha256": {
			"main": FileAccess.get_sha256("res://scripts/main.gd"),
			"combatant": FileAccess.get_sha256("res://scripts/combatant.gd"),
			"catalog": FileAccess.get_sha256("res://assets/weapons/catalog.json")
		},
		"checks": checks,
		"failures": failures,
		"observations": observations,
		"limitations": [
			"Headless gameplay/physics integration; no rendered pixels or subjective input-feel assessment.",
			"Isolated collision arena is added outside the map to distinguish gameplay ray logic from map authoring.",
			"Player input is not synthesized; movement/combat/shop/bomb actions call actual scene methods.",
			"Equipment price expectations track the retained Valve snapshot, not live network data."
		]
	}
	var output := FileAccess.open("res://tests/gameplay_results.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("GAMEPLAY_INTEGRATION_RESULT checks=%d failures=%d report=res://tests/gameplay_results.json" % [checks.size(), failures.size()])
	for failure: String in failures:
		printerr("GAMEPLAY_FAILURE ", failure)
	# Tests deliberately advance game timers faster than audio playback. Stop
	# short-lived sound voices and let the audio thread retire WAV playbacks.
	_stop_audio(game)
	game.queue_free()
	await _sync()
	await create_timer(.15).timeout
	quit(0 if failures.is_empty() else 1)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null
	for child: Node in node.get_children():
		_stop_audio(child)

func _check(condition: bool, name: String, detail: Variant = null) -> void:
	checks.append({"name": name, "passed": condition, "detail": detail})
	if not condition:
		failures.append(name + (" :: " + str(detail) if detail != null else ""))

func _sync() -> void:
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame

func _start(team: String, mode: String) -> void:
	# Independent fixture: cross-session preservation is tested separately.
	if is_instance_valid(game.player):
		game.player.alive = false
	game.start_game(team, mode, 0)
	game.set_physics_process(false)
	game.paused = true
	game.ui.close_panels()
	await _sync()

func _enemy() -> CharacterBody3D:
	for actor: CharacterBody3D in game.actors:
		if actor.team != game.side and actor.alive:
			return actor
	return null

func _bot(team: String) -> CharacterBody3D:
	for actor: CharacterBody3D in game.actors:
		if actor.team == team and not actor.is_player and actor.alive:
			return actor
	return null

func _session_reset() -> void:
	await _start("CT", "practice")
	_check(game.money == 16000 and game.player.armor == 100, "practice_has_training_funds_and_armor")
	game.start_game("T", "bomb", 0)
	game.paused = true
	await _sync()
	var state: Dictionary = {"money":game.money, "armor":game.player.armor, "helmet":game.player.helmet, "kit":game.player.kit, "loadout":game.player.loadout.duplicate(), "supplies":game.player.supplies.duplicate()}
	_check(game.money == 800 and game.player.armor == 0 and not game.player.helmet and not game.player.kit and game.player.loadout[0] == "" and game.player.loadout[1] == "glock" and game.player.supplies.is_empty(), "new_match_does_not_inherit_other_team_practice_equipment", state)

func _shop() -> void:
	await _start("CT", "bomb")
	_check(game.actors.size() == 10 and game._alive_count("CT") == 5 and game._alive_count("T") == 5, "bomb_starts_5v5")
	_check(game._buy_allowed(), "spawn_buy_window_allows_purchases")
	game.buy_item("armor")
	_check(game.money == 150 and game.player.armor == 100, "armor_costs_650", {"money":game.money,"armor":game.player.armor})
	game.buy_item("armor")
	_check(game.money == 150, "duplicate_full_armor_does_not_charge")
	game.buy_item("helmet")
	_check(game.money == 150 and not game.player.helmet, "insufficient_funds_rejects_helmet_upgrade")
	game.money = 1000
	game.buy_item("helmet")
	_check(game.money == 650 and game.player.helmet and game.player.armor == 100, "full_armor_helmet_upgrade_costs_350", game.money)
	game.buy_item("helmet")
	_check(game.money == 650, "duplicate_full_armor_helmet_does_not_charge")
	game.money = 16000
	game.buy_item("ak47")
	_check(game.money == 16000 and game.player.loadout[0] != "ak47", "CT_cannot_buy_T_AK")
	game.buy_item("m4a1")
	_check(game.money == 13100 and game.player.current_weapon() == "m4a1", "M4A4_price_and_equipping", {"money":game.money,"weapon":game.player.current_weapon()})
	game.buy_item("m4a1")
	_check(game.money == 13100, "duplicate_equipped_weapon_does_not_charge")
	var before: Array = game.player.loadout.duplicate()
	game.buy_item("knife")
	_check(game.money == 13100 and game.player.loadout == before, "knife_is_not_a_free_primary_shop_purchase", game.player.loadout.duplicate())
	game.buy_item("kit")
	_check(game.money == 12700 and game.player.kit, "CT_defuse_kit_costs_400")
	game.buy_item("kit")
	_check(game.money == 12700, "duplicate_defuse_kit_does_not_charge")
	game.player.supplies.clear()
	game.money = 16000
	game.buy_item("flashbang")
	game.buy_item("flashbang")
	game.buy_item("flashbang")
	_check(game.money == 15600 and game.player.supplies.get("flashbang",0) == 2, "flashbang_limit_two")
	game.buy_item("hegrenade")
	game.buy_item("hegrenade")
	_check(game.money == 15300 and game.player.supplies.get("hegrenade",0) == 1, "same_grenade_limit_one")
	game.buy_item("smokegrenade")
	game.buy_item("decoy")
	_check(game.money == 15000 and not game.player.supplies.has("decoy"), "grenade_total_capacity_four", game.player.supplies.duplicate())
	game.buy_item("molotov")
	_check(game.money == 15000 and not game.player.supplies.has("molotov"), "CT_cannot_buy_T_molotov")
	game.player.position += Vector3(100,0,0)
	game.buy_item("deagle")
	_check(game.money == 15000 and game.player.loadout[1] != "deagle", "purchase_requires_spawn_area")
	game.player.position = game.world.spawns.CT
	game.buy_time = 0
	game.buy_item("deagle")
	_check(game.money == 15000 and game.player.loadout[1] != "deagle", "purchase_requires_live_buy_timer")

func _ammunition_and_drop() -> void:
	await _start("T", "practice")
	var actor: CharacterBody3D = game.player
	actor.ammunition["ak47"] = {"mag":7,"reserve":50}
	_check(actor.start_reload(), "partial_magazine_starts_reload")
	var before: Dictionary = actor.ammunition["ak47"].duplicate()
	game._shoot(actor, Vector3.FORWARD)
	_check(actor.ammunition["ak47"] == before, "cannot_fire_during_reload")
	actor.tick(3.0)
	_check(actor.ammunition["ak47"].mag == 30 and actor.ammunition["ak47"].reserve == 27, "reload_preserves_total_ammunition", actor.ammunition["ak47"].duplicate())
	_check(not actor.start_reload(), "cannot_reload_full_magazine")
	actor.ammunition["ak47"] = {"mag":7,"reserve":4}
	actor.start_reload()
	actor.tick(3.0)
	_check(actor.ammunition["ak47"].mag == 11 and actor.ammunition["ak47"].reserve == 0, "limited_reserve_transfers_only_remaining_ammo", actor.ammunition["ak47"].duplicate())
	_check(not actor.start_reload(), "cannot_reload_without_reserve")
	actor.ammunition["ak47"] = {"mag":7,"reserve":50}
	actor.start_reload()
	actor.equip(1)
	actor.tick(3.0)
	_check(actor.reload_timer == 0 and actor.ammunition["ak47"].mag == 7 and actor.ammunition["ak47"].reserve == 50, "switching_weapon_cancels_reload_without_ammo_transfer")
	actor.ammunition["glock"] = {"mag":3,"reserve":11}
	var primary: String = actor.loadout[0]
	game._drop_weapon()
	_check(game.drops.size() == 1 and game.drops[0].id == "glock" and actor.loadout[0] == primary and actor.loadout[1] == "", "dropping_secondary_keeps_primary_and_drops_actual_secondary", {"drops":game.drops.size(),"drop_id":game.drops[0].id if not game.drops.is_empty() else "none","loadout":actor.loadout.duplicate()})
	game._pickup()
	_check(actor.loadout[1] == "glock" and actor.ammunition["glock"].mag == 3 and actor.ammunition["glock"].reserve == 11 and game.drops.is_empty(), "pickup_preserves_secondary_ammunition", actor.ammunition["glock"].duplicate())

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

func _physics_shooting_visibility() -> void:
	await _start("CT", "practice")
	arena_floor = _body_at(Vector3(1000,-.5,1000), Vector3(60,1,60))
	var actor: CharacterBody3D = game.player
	var enemy: CharacterBody3D = _enemy()
	actor.position = ARENA
	actor.rotation = Vector3.ZERO
	actor.add_weapon("ak47")
	actor.aiming = true
	actor.bloom = 0
	actor.speed = 0
	enemy.position = ARENA + Vector3(0,0,-8)
	enemy.armor = 0
	enemy.health = 100
	game.aim_direction = Vector3.FORWARD
	await _sync()
	_check(game._line_of_sight(actor.position,enemy.position), "native_physics_clear_line_of_sight")
	actor.shot_timer = 0
	game.rng.seed = 78119
	game._shoot(actor,Vector3.FORWARD)
	_check(enemy.health < 100 and enemy.health > 0, "clear_shot_damages_enemy", enemy.health)
	_check(actor.ammunition["ak47"].mag == 29, "one_shot_consumes_one_round", actor.ammunition["ak47"].duplicate())
	game._update_visibility()
	_check(enemy.visible, "front_clear_enemy_visible")
	barrier = _body_at(ARENA+Vector3(0,1.4,-4), Vector3(8,3,.5))
	await _sync()
	_check(not game._line_of_sight(actor.position,enemy.position), "native_wall_blocks_line_of_sight")
	enemy.health = 100
	actor.shot_timer = 0
	actor.bloom = 0
	game._shoot(actor,Vector3.FORWARD)
	_check(enemy.health == 100 and actor.ammunition["ak47"].mag == 28, "wall_blocks_bullet_but_round_is_consumed", {"health":enemy.health,"ammo":actor.ammunition["ak47"].mag})
	game._update_visibility()
	_check(not enemy.visible, "wall_occluded_enemy_hidden")
	barrier.queue_free()
	await _sync()
	enemy.position = ARENA+Vector3(0,0,8)
	await _sync()
	game._update_visibility()
	_check(not enemy.visible, "enemy_behind_player_hidden")
	enemy.position = ARENA+Vector3(0,0,-8)
	var smoke := Node3D.new()
	game.add_child(smoke)
	smoke.position = ARENA+Vector3(0,0,-4)
	game.smokes.append({"node":smoke,"position":smoke.position,"time":3.0})
	game._update_visibility()
	_check(not enemy.visible and not game._line_of_sight(actor.position,enemy.position), "smoke_blocks_enemy_visibility")
	game.smokes[0].position = ARENA
	smoke.position = ARENA
	game._update_visibility()
	var east_range: float = game.visibility_image.get_pixel(0,0).r
	_check(not enemy.visible and east_range < .08, "inside_smoke_visibility_ranges_are_blocked", {"visible":enemy.visible,"east_range_normalized":east_range})
	game.smokes.clear()
	smoke.queue_free()
	# Real movement against a native floor. Drive actual acceleration and ADS.
	actor.position = ARENA
	actor.velocity = Vector3.ZERO
	actor.aiming = false
	for i: int in 25:
		actor.move_direction(Vector3.RIGHT,1.0/60.0)
		await physics_frame
	var normal_speed: float = actor.speed
	actor.aiming = true
	for i: int in 25:
		actor.move_direction(Vector3.RIGHT,1.0/60.0)
		await physics_frame
	var ads_speed: float = actor.speed
	for i: int in 12:
		actor.move_direction(Vector3.ZERO,1.0/60.0)
		await physics_frame
	_check(normal_speed > 5.0 and ads_speed < normal_speed*.5 and actor.speed < .01, "native_movement_ADS_slows_and_release_stops", {"normal":normal_speed,"aimed":ads_speed,"stopped":actor.speed})
	observations["physics_arena"] = {"position":str(ARENA),"collision_layer":1,"actor_layer":2,"normal_speed":normal_speed,"ads_speed":ads_speed}
	arena_floor.queue_free()
	await _sync()

func _round_rules() -> void:
	await _start("CT", "bomb")
	game.phase = "live"
	for actor: CharacterBody3D in game.actors:
		if actor.team == "T":
			game._damage(actor,10000,game.player)
	_check(game.phase == "result" and game.score_ct == 1, "eliminating_T_before_plant_awards_CT")
	await _start("CT", "bomb")
	game.phase = "live"
	game.planted = true
	game.bomb_position = game.world.sites.A
	for actor: CharacterBody3D in game.actors:
		if actor.team == "T":
			game._damage(actor,10000,game.player)
	_check(game.phase == "live" and game.score_ct == 0, "eliminating_T_after_plant_does_not_end_round")
	var victim: CharacterBody3D = game.player
	victim.tick(.1)
	var dead_enemy: CharacterBody3D = null
	for actor: CharacterBody3D in game.actors:
		if actor.team == "T": dead_enemy = actor; break
	dead_enemy.tick(.1)
	_check(dead_enemy.visual.model.get_node("Rig").rotation.z > 0, "dead_combatant_tick_advances_collapse_animation")
	for actor: CharacterBody3D in game.actors:
		if actor.team == "CT": actor.take_damage(10000)
	game._check_elimination()
	_check(game.phase == "result" and game.score_t == 1, "eliminating_CT_awards_T_even_after_plant")
	await _start("CT", "bomb")
	game.phase = "live"
	var planter: CharacterBody3D = _bot("T")
	planter.position = game.world.sites.A
	planter.bomb_carrier = true
	planter.speed = 0
	game._update_bomb(2.0,false)
	planter.speed = 1
	game._update_bomb(.1,false)
	_check(not game.planted and game.bomb_progress == 0, "moving_interrupts_plant")
	planter.speed = 0
	game._update_bomb(3.21,false)
	_check(game.planted and not planter.bomb_carrier and game.bomb_time == 40, "stationary_carrier_plants_at_A_site", {"planted":game.planted,"timer":game.bomb_time})
	var defuser: CharacterBody3D = _bot("CT")
	defuser.position = game.bomb_position
	defuser.kit = true
	defuser.speed = 0
	game._update_bomb(4.9,false)
	_check(game.phase != "result", "kit_defuse_requires_full_five_seconds")
	game._update_bomb(.11,false)
	_check(game.phase == "result" and game.score_ct == 1, "kit_defuses_after_five_seconds")
	await _start("CT", "bomb")
	game.phase = "live"
	game.planted = true
	game.bomb_position = game.world.sites.A
	game.bomb_time = 40
	defuser = _bot("CT")
	defuser.position = game.bomb_position
	defuser.kit = false
	defuser.speed = 0
	game._update_bomb(9.9,false)
	_check(game.phase != "result", "no_kit_defuse_requires_full_ten_seconds")
	game._update_bomb(.11,false)
	_check(game.phase == "result" and game.score_ct == 1, "no_kit_defuses_after_ten_seconds")
	await _start("CT", "bomb")
	game.phase = "live"
	game.planted = true
	game.bomb_position = game.world.sites.A
	game.bomb_time = .1
	game._update_bomb(.2,false)
	_check(game.phase == "result" and game.score_t == 1, "bomb_expiration_awards_T")
	await _start("CT", "bomb")
	game.phase = "live"
	game.round_time = .1
	game.paused = false
	game._physics_process(.2)
	game.paused = true
	_check(game.phase == "result" and game.score_ct == 1, "round_timeout_without_plant_awards_CT")

func _practice_respawn() -> void:
	await _start("CT", "practice")
	var target: CharacterBody3D = _enemy()
	game._damage(target,10000,game.player)
	_check(game.phase != "result" and game.respawns.size() == 1, "practice_death_queues_respawn_without_round_end")
	game._update_respawns(3.1)
	await _sync()
	_check(game.respawns.is_empty() and game._alive_count("T") == 3 and game.actors.size() == 4, "practice_enemy_respawns_without_accumulating_actors", {"actors":game.actors.size(),"alive_T":game._alive_count("T")})
