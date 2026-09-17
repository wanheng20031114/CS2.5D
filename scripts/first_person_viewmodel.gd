extends Node3D
## Camera-local weapon art rendered in a separate world, so nearby walls cannot
## clip the hands and viewmodel geometry never casts shadows into the map.

const Catalog = preload("res://scripts/weapon_catalog.gd")

var viewport: SubViewport
var view_camera: Camera3D
var weapon: Node3D
var _main_camera: Camera3D
var _layer: CanvasLayer
var _surface: TextureRect
var _rig: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _sleeve_material: StandardMaterial3D
var _muzzle: Node3D
var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _weapon_id: String = ""
var _actor_id: int = 0
var _team: String = ""
var _active: bool = false
var _short_weapon: bool = false
var _melee: bool = false
var _can_flash: bool = false
var _sight_height: float = 0.18
var _ads: float = 0.0
var _phase: float = 0.0
var _motion: float = 0.0
var _sway: Vector2 = Vector2.ZERO
var _recoil: float = 0.0
var _recoil_strength: float = 0.6
var _flash_time: float = 0.0
var _equip: float = 0.0

func setup(main_camera: Camera3D) -> void:
	_main_camera = main_camera
	if is_instance_valid(viewport):
		return
	viewport = SubViewport.new()
	viewport.name = "FirstPersonViewport"
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	var stage := Node3D.new()
	stage.name = "ViewmodelStage"
	viewport.add_child(stage)
	view_camera = Camera3D.new()
	view_camera.name = "ViewmodelCamera"
	view_camera.near = 0.01
	view_camera.far = 8.0
	view_camera.fov = 65.0
	stage.add_child(view_camera)
	view_camera.make_current()
	var environment := WorldEnvironment.new()
	var lighting := Environment.new()
	lighting.background_mode = Environment.BG_COLOR
	lighting.background_color = Color(0.0, 0.0, 0.0, 0.0)
	lighting.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	lighting.ambient_light_color = Color(0.85, 0.9, 1.0)
	lighting.ambient_light_energy = 0.8
	environment.environment = lighting
	stage.add_child(environment)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	key_light.light_color = Color(1.0, 0.93, 0.82)
	key_light.light_energy = 1.05
	key_light.shadow_enabled = false
	stage.add_child(key_light)
	_rig = Node3D.new()
	_rig.name = "WeaponRig"
	stage.add_child(_rig)
	_sleeve_material = _material(Color(0.18, 0.25, 0.3))
	_right_arm = _build_arm("RightArm")
	_left_arm = _build_arm("LeftArm")
	_layer = CanvasLayer.new()
	_layer.name = "FirstPersonLayer"
	_layer.layer = 2
	add_child(_layer)
	_surface = TextureRect.new()
	_surface.name = "FirstPersonTexture"
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.texture = viewport.get_texture()
	_surface.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_surface.stretch_mode = TextureRect.STRETCH_SCALE
	_layer.add_child(_surface)
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.visible = false
	_sync_size()

func update_view(delta: float, actor: CharacterBody3D, settings: Dictionary, active: bool, look_delta: Vector2 = Vector2.ZERO) -> void:
	if not is_instance_valid(viewport):
		return
	var should_show: bool = active and is_instance_valid(actor) and bool(actor.get("alive"))
	if not should_show:
		if _active or _actor_id != 0:
			reset()
		return
	var actor_id: int = actor.get_instance_id()
	if _actor_id != actor_id:
		reset()
		_actor_id = actor_id
	if not _active:
		_active = true
		_layer.visible = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_equip = 1.0
	_sync_size()
	view_camera.fov = clampf(float(settings.get("fp_viewmodel_fov", 65.0)), 35.0, 120.0)
	var next_weapon: String = str(actor.call("current_weapon"))
	if next_weapon != _weapon_id or not is_instance_valid(weapon):
		_set_weapon(next_weapon)
	var next_team: String = str(actor.get("team"))
	if next_team != _team:
		_team = next_team
		_sleeve_material.albedo_color = Color(0.17, 0.25, 0.31) if _team == "CT" else Color(0.48, 0.38, 0.24)
	var dt: float = maxf(0.0, delta)
	var smoothing: float = 1.0 - exp(-14.0 * dt)
	var reloading: bool = float(actor.get("reload_timer")) > 0.0
	_ads = lerpf(_ads, 1.0 if bool(actor.get("aiming")) and not reloading else 0.0, smoothing)
	_motion = lerpf(_motion, clampf(float(actor.get("speed")) / 5.7, 0.0, 1.3), smoothing)
	_phase += dt * maxf(0.0, float(settings.get("fp_bob_speed", 10.0))) * _motion
	var motion_scale: float = _motion * lerpf(1.0, 0.2, _ads)
	var bob_amount: float = maxf(0.0, float(settings.get("fp_bob", 0.015))) * motion_scale
	var sway_strength: float = maxf(0.0, float(settings.get("fp_sway", 0.4)))
	# Mouse input is pixels accumulated during this frame. Convert to velocity
	# before smoothing so the visible lag stays consistent across frame rates.
	var sway_target: Vector2 = (look_delta / maxf(dt, 0.001) * 0.00010 * sway_strength).limit_length(0.075)
	_sway = _sway.lerp(sway_target, smoothing)
	_recoil_strength = maxf(0.0, float(settings.get("fp_recoil", 0.6)))
	_recoil *= exp(-maxf(0.1, float(settings.get("fp_recoil_recovery", 10.0))) * dt)
	_equip = move_toward(_equip, 0.0, dt * 3.2)
	var size_scale: float = clampf(float(settings.get("fp_weapon_scale", 1.0)), 0.4, 2.0)
	_rig.scale = Vector3.ONE * size_scale
	var hip: Vector3 = Vector3(float(settings.get("fp_weapon_x", 0.24)), float(settings.get("fp_weapon_y", -0.22)), float(settings.get("fp_weapon_z", -0.38)))
	# Align the top of the authored sights just below the reticle. The stock must
	# stay below eye level, otherwise its rear face obscures the sight picture.
	var aimed: Vector3 = Vector3(0.0, -(_sight_height + 0.015) * size_scale, hip.z - 0.09)
	var bob: Vector3 = Vector3(sin(_phase) * bob_amount, sin(_phase * 2.0) * bob_amount * 0.65, 0.0)
	_rig.position = hip.lerp(aimed, _ads) + bob + Vector3(-_sway.x, _sway.y, _recoil * 0.065)
	_rig.rotation = Vector3(_sway.y * 0.45 + _recoil * 0.10, _sway.x * 0.65, -sin(_phase) * bob_amount * 0.6)
	_rig.position.y -= _equip * 0.34
	_rig.rotation.x -= _equip * 0.40
	var reload_blend: float = 0.0
	var reload_cycle: float = 0.0
	if reloading:
		var duration: float = maxf(0.01, float(actor.get("reload_duration")))
		var progress: float = clampf(1.0 - float(actor.get("reload_timer")) / duration, 0.0, 1.0)
		reload_blend = sin(progress * PI)
		reload_cycle = sin(progress * TAU * 2.0) * reload_blend
		_rig.position += Vector3(-0.065, -0.13, 0.07) * reload_blend
		_rig.rotation += Vector3(-0.18, -0.18, -0.48) * reload_blend
	if _melee:
		_rig.rotation.z -= _recoil * 0.9
		_rig.position.x -= sin(_recoil * 2.0) * 0.16
	_pose_arms(reload_blend, reload_cycle)
	_flash_time = maxf(0.0, _flash_time - dt)
	if is_instance_valid(_flash):
		_flash.visible = _flash_time > 0.0
		_flash_light.light_energy = 1.7 if _flash_time > 0.0 else 0.0

func fire() -> void:
	if not _active:
		return
	_recoil = minf(1.8, _recoil + _recoil_strength)
	_flash_time = 0.045 if _can_flash else 0.0
	if is_instance_valid(_flash):
		_flash.visible = _can_flash
		_flash.rotation.y = randf() * TAU
		_flash_light.light_energy = 1.7 if _can_flash else 0.0

func reset() -> void:
	_active = false
	_actor_id = 0
	_ads = 0.0
	_phase = 0.0
	_motion = 0.0
	_sway = Vector2.ZERO
	_recoil = 0.0
	_flash_time = 0.0
	_equip = 0.0
	if is_instance_valid(_rig):
		_rig.transform = Transform3D.IDENTITY
	if is_instance_valid(_flash):
		_flash.visible = false
		_flash_light.light_energy = 0.0
	if is_instance_valid(_layer):
		_layer.visible = false
	if is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _sync_size() -> void:
	if not is_instance_valid(_main_camera):
		return
	var visible_size: Vector2 = _main_camera.get_viewport().get_visible_rect().size
	var target_size: Vector2i = Vector2i(maxi(1, int(visible_size.x)), maxi(1, int(visible_size.y)))
	if viewport.size != target_size:
		viewport.size = target_size

func _set_weapon(id: String) -> void:
	if is_instance_valid(weapon):
		_rig.remove_child(weapon)
		weapon.queue_free()
	_muzzle = null
	_flash = null
	_flash_light = null
	_weapon_id = id
	_recoil = 0.0
	_flash_time = 0.0
	_equip = 1.0
	var data: Dictionary = Catalog.data(id)
	var category: String = str(data.get("category", "rifle"))
	_short_weapon = category in ["pistol", "grenade", "gear", "melee"]
	_melee = category == "melee"
	_can_flash = category in ["pistol", "rifle", "smg", "sniper", "shotgun", "machinegun", "heavy"]
	var path: String = Catalog.model_path(id)
	if not ResourceLoader.exists(path):
		path = Catalog.model_path("ak47")
	weapon = (load(path) as PackedScene).instantiate() as Node3D
	_rig.add_child(weapon)
	_disable_shadows(weapon)
	_sight_height = 0.04
	for mesh_node: Node in weapon.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = mesh_node as MeshInstance3D
		if instance.mesh == null:
			continue
		var bounds: AABB = instance.mesh.get_aabb()
		for corner: int in range(8):
			var local_corner: Vector3 = bounds.get_endpoint(corner)
			_sight_height = maxf(_sight_height, weapon.to_local(instance.to_global(local_corner)).y)
	_muzzle = weapon.get_node_or_null("Muzzle") as Node3D
	if not is_instance_valid(_muzzle):
		return
	_flash = MeshInstance3D.new()
	_flash.name = "FirstPersonMuzzleFlash"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.008
	cone.bottom_radius = 0.055
	cone.height = 0.17
	cone.radial_segments = 5
	_flash.mesh = cone
	_flash.rotation.x = PI * 0.5
	_flash.position.z = -0.085
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := _material(Color(1.0, 0.83, 0.3))
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(1.0, 0.46, 0.08)
	material.emission_energy_multiplier = 2.0
	_flash.material_override = material
	_flash.visible = false
	_muzzle.add_child(_flash)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.62, 0.3)
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = 1.5
	_flash_light.shadow_enabled = false
	_muzzle.add_child(_flash_light)

func _build_arm(arm_name: String) -> Node3D:
	var arm := Node3D.new()
	arm.name = arm_name
	_rig.add_child(arm)
	var skin := _material(Color(0.69, 0.47, 0.31))
	var glove := _material(Color(0.075, 0.09, 0.095))
	for part: int in range(3):
		var segment := MeshInstance3D.new()
		segment.name = ["Sleeve", "Wrist", "Glove"][part]
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = [0.048, 0.038, 0.041][part]
		cylinder.bottom_radius = [0.068, 0.044, 0.044][part]
		cylinder.height = 1.0
		cylinder.radial_segments = 7
		cylinder.rings = 1
		segment.mesh = cylinder
		segment.material_override = [_sleeve_material, skin, glove][part]
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arm.add_child(segment)
	return arm

func _pose_arms(reload_blend: float, reload_cycle: float) -> void:
	var right_grip := Vector3(0.018, -0.057, 0.016)
	var left_grip := Vector3(-0.025, -0.025, -0.30)
	if _short_weapon:
		left_grip = Vector3(-0.05, -0.075, -0.045)
	if _melee:
		right_grip = Vector3(0.012, -0.016, 0.025)
		left_grip = Vector3(-0.37, -0.09, -0.12)
	left_grip += Vector3(-0.11 * reload_blend, -0.20 * reload_blend + 0.07 * reload_cycle, 0.20 * reload_blend)
	_pose_arm(_right_arm, Vector3(0.20, -0.32, 0.31), right_grip)
	_pose_arm(_left_arm, Vector3(-0.51, -0.35, 0.28), left_grip)

func _pose_arm(arm: Node3D, elbow: Vector3, grip: Vector3) -> void:
	var wrist: Vector3 = elbow.lerp(grip, 0.78)
	var cuff: Vector3 = elbow.lerp(grip, 0.67)
	var direction: Vector3 = (grip - elbow).normalized()
	_segment(arm.get_child(0) as Node3D, elbow, cuff)
	_segment(arm.get_child(1) as Node3D, cuff, wrist)
	_segment(arm.get_child(2) as Node3D, wrist, grip + direction * 0.045)

func _segment(part: Node3D, start: Vector3, end: Vector3) -> void:
	var direction: Vector3 = end - start
	var length: float = maxf(0.001, direction.length())
	part.position = (start + end) * 0.5
	part.quaternion = Quaternion(Vector3.UP, direction / length)
	part.scale = Vector3(1.0, length, 1.0)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.84
	return material

func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_disable_shadows(child)
