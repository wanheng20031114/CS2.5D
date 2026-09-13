extends CharacterBody3D

const Visual = preload("res://scripts/agent_visual.gd")
const Catalog = preload("res://scripts/weapon_catalog.gd")
var team: String = "CT"
var is_player: bool = false
var health: float = 100.0
var armor: float = 0.0
var helmet: bool = false
var alive: bool = true
var aiming: bool = false
var speed: float = 0.0
var bloom: float = 0.0
var shot_timer: float = 0.0
var reload_timer: float = 0.0
var reload_duration: float = 0.0
var active_slot: int = 1
var loadout: Array[String] = ["", "usp_silencer", "knife", ""]
var ammunition: Dictionary = {}
var supplies: Dictionary = {}
var visual: Node3D
var path: Array[Vector3] = []
var think_timer: float = 0.0
var react_timer: float = 0.0
var blind_timer: float = 0.0
var burst_timer: float = 0.0
var target: Node3D
var goal: Vector3
var bomb_carrier: bool = false
var kit: bool = false
var step_clock: float = 0.0
var display_name: String = ""

func setup(side: String, human: bool, weapon: String) -> void:
	team = side
	is_player = human
	collision_layer = 2
	collision_mask = 5
	floor_snap_length = 0.4
	floor_stop_on_slope = false
	floor_constant_speed = true
	floor_max_angle = deg_to_rad(52)
	safe_margin = 0.002
	max_slides = 10
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.65
	shape.shape = capsule
	shape.position.y = 0.83
	add_child(shape)
	loadout[1] = "glock" if side == "T" else "usp_silencer"
	visual = Visual.new()
	add_child(visual)
	visual.build(side, weapon)
	if weapon != loadout[1]:
		loadout[0] = weapon
		active_slot = 0
	for id in loadout:
		if not id.is_empty():
			fill_ammo(id)
	visual.set_weapon(current_weapon())

func current_weapon() -> String:
	return loadout[active_slot]

func weapon_data() -> Dictionary:
	return Catalog.data(current_weapon())

func fill_ammo(id: String) -> void:
	var d: Dictionary = Catalog.data(id)
	ammunition[id] = {"mag": int(d.get("magazine", 1)), "reserve": int(d.get("reserve", 0))}

func equip(slot: int) -> void:
	if slot < 0 or slot >= loadout.size() or loadout[slot].is_empty():
		return
	if current_weapon() != loadout[slot]:
		reload_timer = 0.0
		bloom *= 0.35
		shot_timer = maxf(shot_timer, 0.22)
	active_slot = slot
	visual.set_weapon(current_weapon())

func add_weapon(id: String) -> void:
	var d: Dictionary = Catalog.data(id)
	var slot: int = 1 if d.get("category", "") == "pistol" else 0
	loadout[slot] = id
	fill_ammo(id)
	equip(slot)

func start_reload() -> bool:
	var id := current_weapon()
	var d := weapon_data()
	if not ammunition.has(id) or reload_timer > 0.0 or id == "knife":
		return false
	if ammunition[id].mag >= d.get("magazine", 0) or ammunition[id].reserve <= 0:
		return false
	reload_duration = float(d.get("reload", 2.4))
	reload_timer = reload_duration
	return true

func tick(delta: float) -> void:
	blind_timer = maxf(0.0,blind_timer-delta)
	shot_timer = maxf(0.0, shot_timer - delta)
	bloom = move_toward(bloom, 0.0, delta * (0.075 if speed < 0.3 else 0.035))
	if reload_timer > 0.0:
		reload_timer = maxf(0.0, reload_timer - delta)
		if reload_timer == 0.0:
			var id := current_weapon()
			var needed: int = int(weapon_data().get("magazine", 30)) - int(ammunition[id].mag)
			var taken := mini(needed, int(ammunition[id].reserve))
			ammunition[id].mag += taken
			ammunition[id].reserve -= taken
	visual.animate(delta, speed if alive else 0.0, aiming, reload_timer > 0.0)

func spread_angle() -> float:
	var d := weapon_data()
	var steady := float(d.get("spread", 0.005))
	var moving := float(d.get("move_spread", 0.1)) * clampf(speed / 5.5, 0.0, 1.0)
	var airborne := 0.085 if absf(velocity.y)>1.0 and not is_on_floor() else 0.0
	return steady * (0.42 if aiming else 1.0) + moving * (0.38 if aiming else 1.0) + bloom * (0.62 if aiming else 1.0) + airborne

func move_direction(direction: Vector3, delta: float, slow: bool = false) -> void:
	var movement_speed := 5.7
	if current_weapon() == "knife":
		movement_speed = 6.4
	elif weapon_data().get("category", "") == "sniper":
		movement_speed = 4.8
	if aiming:
		movement_speed *= 0.43
	if slow:
		movement_speed *= 0.6
	if reload_timer > 0.0:
		movement_speed *= 0.83
	var desired := direction * movement_speed
	var acceleration := 44.0 if direction.length_squared() > 0.01 else 70.0
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
	velocity.y -= 22.0 * delta
	if is_on_floor():
		velocity.y = -0.5
	var horizontal := Vector3(velocity.x,0,velocity.z)*delta
	var before := position
	var was_grounded := is_on_floor()
	move_and_slide()
	var traveled := Vector2(position.x-before.x,position.z-before.z).length()
	if was_grounded and horizontal.length_squared()>0.00001 and traveled<horizontal.length()*0.7:
		if _try_step(horizontal.normalized(),horizontal.length()):
			velocity.x = horizontal.x/delta
			velocity.z = horizontal.z/delta
			velocity.y = 0.0
			move_and_slide()
	speed = Vector2(velocity.x, velocity.z).length()

func _try_step(direction: Vector3, distance: float) -> bool:
	# Probe beyond the capsule's rounded toe. Source collision meshes describe
	# individual stair faces; a one-frame probe can hit the same riser forever.
	var space := get_world_3d().direct_space_state
	var capsule_node: CollisionShape3D
	for child in get_children():
		if child is CollisionShape3D:
			capsule_node = child
			break
	if capsule_node == null: return false
	for ahead in [0.37+distance,0.22+distance]:
		var sample := position+direction*float(ahead)
		var ray := PhysicsRayQueryParameters3D.create(sample+Vector3.UP*0.47,sample-Vector3.UP*0.14,5,[get_rid()])
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y<0.65: continue
		var rise: float = hit.position.y-position.y+0.022
		if rise<0.014 or rise>0.48: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule_node.shape
		query.transform = capsule_node.global_transform.translated(Vector3.UP*rise)
		query.collision_mask = 5
		query.exclude = [get_rid()]
		query.margin = 0.001
		if not space.intersect_shape(query,1).is_empty(): continue
		if test_move(global_transform.translated(Vector3.UP*rise),direction*distance): continue
		position.y += rise
		return true
	# Some original Mirage stair edges are convex lips: the center ray sees
	# the lower slope behind the lip, so its measured rise misses the obstacle.
	# Require reachable support, then sweep the whole capsule through one legal
	# step. A full step also prevents floor snapping back onto the old slope.
	var supported := false
	for ahead in [0.37+distance,0.55+distance]:
		var sample := position+direction*float(ahead)
		var support_ray := PhysicsRayQueryParameters3D.create(sample+Vector3.UP*0.48,sample-Vector3.UP*0.15,5,[get_rid()])
		support_ray.hit_from_inside = true
		var support := space.intersect_ray(support_ray)
		if not support.is_empty() and support.normal.y >= 0.65 and support.position.y-position.y <= 0.48:
			supported = true
	if not supported: return false
	var step_up := Vector3.UP*0.46
	if test_move(global_transform,step_up): return false
	var raised_query := PhysicsShapeQueryParameters3D.new()
	raised_query.shape = capsule_node.shape
	raised_query.transform = capsule_node.global_transform.translated(step_up)
	raised_query.collision_mask = 5
	raised_query.exclude = [get_rid()]
	raised_query.margin = 0.001
	if not space.intersect_shape(raised_query,1).is_empty(): return false
	if test_move(global_transform.translated(step_up),direction*distance): return false
	position.y += step_up.y
	return true

func take_damage(amount: float) -> bool:
	if not alive:
		return false
	var absorbed := minf(armor, amount * 0.3)
	armor -= absorbed
	health = maxf(0.0, health - amount + absorbed)
	if health <= 0.0:
		alive = false
		collision_layer = 0
		velocity = Vector3.ZERO
		visual.die()
		return true
	return false
