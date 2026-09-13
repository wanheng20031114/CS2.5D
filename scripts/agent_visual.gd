class_name AgentVisual
extends Node3D
## Rigid-joint animation of offline-authored, native faceted character sculptures.
## World scale: metres, feet at Y=0, aiming forward along local -Z.

const Catalog = preload("res://scripts/weapon_catalog.gd")
var team: String = "CT"
var weapon_id: String = "m4a1"
var model: Node3D
var weapon: Node3D
var _rig: Node3D
var _upper: Node3D
var _head: Node3D
var _socket: Node3D
var _legs: Array[Node3D] = []
var _shins: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _forearms: Array[Node3D] = []
var _muzzle: Node3D
var _flash: MeshInstance3D
var _light: OmniLight3D
var _phase: float = 0.0
var _clock: float = 0.0
var _motion: float = 0.0
var _recoil: float = 0.0
var _flash_time: float = 0.0
var _reload_phase: float = 0.0
var _was_reloading: bool = false
var _dead: bool = false
var _death_time: float = 0.0
var _short_weapon: bool = false
var _melee_weapon: bool = false

func build(which_team: String, which_weapon: String) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	team = which_team.to_upper()
	_dead = false
	_death_time = 0.0
	rotation = Vector3.ZERO
	model = (load("res://assets/characters/%s.tscn" % ("ct" if team == "CT" else "t")) as PackedScene).instantiate()
	add_child(model)
	_rig = model.get_node("Rig")
	_upper = model.get_node("Rig/Upper")
	_head = model.get_node("Rig/Upper/Head")
	_socket = model.get_node("Rig/Upper/WeaponSocket")
	_legs.clear()
	_shins.clear()
	_arms.clear()
	_forearms.clear()
	for side: String in ["Left", "Right"]:
		_legs.append(model.get_node("Rig/%sLeg" % side))
		_shins.append(model.get_node("Rig/%sLeg/%sShin" % [side, side]))
		_arms.append(model.get_node("Rig/Upper/%sArm" % side))
		_forearms.append(model.get_node("Rig/Upper/%sArm/%sForearm" % [side, side]))
	set_weapon(which_weapon)

func set_weapon(id: String) -> void:
	weapon_id = Catalog.canonical(id)
	_short_weapon = str(Catalog.data(weapon_id).category) in ["pistol", "grenade", "gear", "melee"]
	_melee_weapon = str(Catalog.data(weapon_id).category) == "melee"
	if not is_instance_valid(_socket):
		return
	for child: Node in _socket.get_children():
		_socket.remove_child(child)
		child.queue_free()
	var path: String = Catalog.model_path(weapon_id)
	if not ResourceLoader.exists(path):
		path = Catalog.model_path("ak47")
	weapon = (load(path) as PackedScene).instantiate()
	_socket.add_child(weapon)
	_muzzle = weapon.get_node("Muzzle")
	_flash = MeshInstance3D.new()
	_flash.name = "MuzzleFlash"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.013
	cone.bottom_radius = 0.075
	cone.height = 0.20
	cone.radial_segments = 5
	_flash.mesh = cone
	_flash.rotation.x = PI / 2.0
	_flash.position.z = -0.10
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.42, 0.10)
	mat.emission_energy_multiplier = 2.5
	_flash.material_override = mat
	_flash.visible = false
	_muzzle.add_child(_flash)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.59, 0.22)
	_light.light_energy = 0.0
	_light.omni_range = 2.7
	_light.shadow_enabled = false
	_muzzle.add_child(_light)
	_recoil = 0.0

func animate(delta: float, speed: float, aiming: bool, reloading: bool) -> void:
	if not is_instance_valid(model):
		return
	_clock += delta
	if _dead:
		_death_time = minf(1.0, _death_time + delta * 3.4)
		_rig.rotation.z = lerpf(0.0, 1.48, _death_time)
		_rig.position.y = -0.13 * _death_time
		if is_instance_valid(_flash):
			_flash.visible = false
			_light.light_energy = 0.0
		return
	_motion = move_toward(_motion, clampf(speed / 5.2, 0.0, 1.3), delta * 5.5)
	_phase += delta * (2.8 + speed * 2.7) * minf(1.0, _motion * 5.0)
	var stride: float = sin(_phase)
	var bob: float = absf(sin(_phase)) * 0.031 * _motion
	_rig.position.y = bob
	_upper.rotation.z = -stride * .025 * _motion
	_upper.rotation.x = -.028 * _motion
	_upper.position.y = .88 + sin(_clock * 2.15) * .005
	_head.rotation.y = sin(_clock * 1.1) * .015 * (0.2 if aiming else 1.0)
	for i: int in range(2):
		var phase: float = _phase + i * PI
		_legs[i].rotation.x = sin(phase) * .49 * _motion
		_shins[i].rotation.x = maxf(0.0, -sin(phase)) * .62 * _motion
		_arms[i].rotation.x = sin(phase) * .033 * _motion
		_arms[i].rotation.z = 0.0
		_forearms[i].rotation = Vector3.ZERO
		_forearms[i].scale.z = .51 if _short_weapon and i == 0 else 1.0
	_recoil = move_toward(_recoil, 0.0, delta * 6.7)
	_socket.position = Vector3(.11, .315, -.335 + _recoil * .074)
	_socket.rotation = Vector3(-_recoil * .095, 0.0, 0.0)
	if _melee_weapon:
		_socket.rotation.z = -_recoil * .9
		_socket.position.x += sin(_recoil * 2.2) * .20
	if reloading:
		if not _was_reloading:
			_reload_phase = 0.0
		_reload_phase += delta
		var reach: float = sin(minf(1.0, _reload_phase / .55) * PI * .5)
		_socket.rotation.z = -.34 * reach
		_socket.rotation.x = -.16 * reach
		_arms[0].rotation.x = -.38 * reach
		_arms[0].rotation.z = -.14 * reach
		_forearms[0].rotation.x = .58 * sin(_reload_phase * 4.7)
	elif aiming:
		_socket.position.z -= .029
		_arms[0].rotation.x -= .032
		_arms[1].rotation.x -= .032
	_was_reloading = reloading
	_flash_time = maxf(0.0, _flash_time - delta)
	if is_instance_valid(_flash):
		_flash.visible = _flash_time > 0.0
		_light.light_energy = 1.3 if _flash_time > 0.0 else 0.0

func fire() -> void:
	if _dead:
		return
	_recoil = minf(1.5, _recoil + 1.0)
	_flash_time = 0.0 if _melee_weapon else .045
	if is_instance_valid(_flash):
		_flash.rotation.y = randf() * TAU
		_flash.visible = not _melee_weapon

func die() -> void:
	_dead = true
	_death_time = 0.0

func get_muzzle_position() -> Vector3:
	if is_instance_valid(_muzzle) and _muzzle.is_inside_tree():
		return _muzzle.global_position
	return global_position + global_basis * Vector3(.11, 1.28, -.97)
