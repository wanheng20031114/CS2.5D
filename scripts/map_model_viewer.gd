class_name MapModelViewer
extends RefCounted

# A camera controller over the existing map. Game state, visibility effects and
# the camera's update ownership are deliberately managed by the main scene.
var active := false
var camera: Camera3D
var world: Node3D
var target := Vector3.ZERO
var yaw := deg_to_rad(28.0)
var pitch := deg_to_rad(58.0)
var span := 140.0
var _target_goal := Vector3.ZERO
var _yaw_goal := yaw
var _pitch_goal := pitch
var _span_goal := span
var _saved_camera: Dictionary = {}
var _bounds := Rect2(-54.0,-48.0,112.0,97.0)
var _overview_center := Vector3.ZERO
var _overview_span := 140.0
var _drag_button := MOUSE_BUTTON_NONE

func enter(view_camera: Camera3D, map_world: Node3D) -> void:
	if active:
		return
	camera = view_camera
	world = map_world
	_saved_camera = {"transform":camera.global_transform,"projection":camera.projection,
		"size":camera.size,"fov":camera.fov,"near":camera.near,"far":camera.far}
	_bounds = world.bounds
	_fit_overview()
	active = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.fov = 48.0
	camera.near = 0.08
	camera.far = 900.0
	reset_view()
	_snap_to_goal()

func exit() -> void:
	if not active:
		return
	active = false
	_drag_button = MOUSE_BUTTON_NONE
	if is_instance_valid(camera):
		camera.global_transform = _saved_camera.transform
		camera.projection = _saved_camera.projection
		camera.size = _saved_camera.size
		camera.fov = _saved_camera.fov
		camera.near = _saved_camera.near
		camera.far = _saved_camera.far
	_saved_camera.clear()

func reset_view() -> void:
	_target_goal = _overview_center
	_yaw_goal = deg_to_rad(28.0)
	_pitch_goal = deg_to_rad(58.0)
	_span_goal = _overview_span
	_drag_button = MOUSE_BUTTON_NONE

func focus_landmark(id: String) -> void:
	# The complete model retains its roofs and outer walls. A steeper inspection
	# angle keeps a chosen courtyard visible without removing that geometry.
	_pitch_goal = deg_to_rad(75.0)
	match id:
		"A", "B":
			_target_goal = world.sites.get(id,_overview_center) + Vector3.UP*2.0
			_span_goal = 39.0
		"CT", "T":
			_target_goal = world.spawns.get(id,_overview_center) + Vector3.UP*2.0
			_span_goal = 37.0
		"MID":
			_target_goal = Vector3(10.0,2.0,-6.0)
			if world.has_method("ground_height"):
				_target_goal.y = world.ground_height(_target_goal)+2.0
			_span_goal = 48.0
		_:
			reset_view()
	_drag_button = MOUSE_BUTTON_NONE

func _fit_overview() -> void:
	var boxes: Array[AABB] = []
	_collect_bounds(world,boxes)
	var bounds := AABB(Vector3(_bounds.position.x,0.0,_bounds.position.y),Vector3(_bounds.size.x,20.0,_bounds.size.y))
	for box in boxes:
		bounds = bounds.merge(box)
	_overview_center = bounds.get_center()
	var rotation_basis := Basis.looking_at(-Vector3(sin(deg_to_rad(28.0))*cos(deg_to_rad(58.0)),sin(deg_to_rad(58.0)),cos(deg_to_rad(28.0))*cos(deg_to_rad(58.0))),Vector3.UP)
	var view_min := Vector2(INF,INF)
	var view_max := Vector2(-INF,-INF)
	for i in 8:
		var corner := bounds.get_endpoint(i)-_overview_center
		var point := Vector2(corner.dot(rotation_basis.x),corner.dot(rotation_basis.y))
		view_min = view_min.min(point)
		view_max = view_max.max(point)
	var size := camera.get_viewport().get_visible_rect().size
	var aspect := maxf(size.x,1.0)/maxf(size.y,1.0)
	var view_size := view_max-view_min
	_overview_span = maxf(view_size.y,view_size.x/aspect)*1.25

func _collect_bounds(node: Node, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D and node.is_visible_in_tree() and node.mesh != null:
		boxes.append(node.global_transform*node.get_aabb())
	for child in node.get_children():
		_collect_bounds(child,boxes)

func toggle_projection() -> String:
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	else:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	return "正交" if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else "透视"

func handle_input(event: InputEvent) -> bool:
	if not active:
		return false
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				_drag_button = event.button_index
			elif _drag_button == event.button_index:
				_drag_button = MOUSE_BUTTON_NONE
			return true
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := -0.14 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.14
			_span_goal = clampf(_span_goal*exp(factor*maxf(event.factor,1.0)),4.0,300.0)
			return true
	if event is InputEventMouseMotion and _drag_button != MOUSE_BUTTON_NONE:
		# A release over a toolbar button may not reach _unhandled_input.
		var mask := MOUSE_BUTTON_MASK_LEFT
		if _drag_button == MOUSE_BUTTON_RIGHT:
			mask = MOUSE_BUTTON_MASK_RIGHT
		elif _drag_button == MOUSE_BUTTON_MIDDLE:
			mask = MOUSE_BUTTON_MASK_MIDDLE
		if (event.button_mask & mask) == 0:
			_drag_button = MOUSE_BUTTON_NONE
			return false
		if _drag_button == MOUSE_BUTTON_LEFT:
			_yaw_goal -= event.relative.x*0.007
			_pitch_goal = clampf(_pitch_goal+event.relative.y*0.006,deg_to_rad(5.0),deg_to_rad(88.0))
		else:
			var viewport_size := camera.get_viewport().get_visible_rect().size
			var meters_per_pixel := span/maxf(viewport_size.y,1.0)
			_target_goal += (-camera.global_basis.x*event.relative.x+camera.global_basis.y*event.relative.y)*meters_per_pixel
			_target_goal.x = clampf(_target_goal.x,_bounds.position.x-100.0,_bounds.end.x+100.0)
			_target_goal.y = clampf(_target_goal.y,-8.0,75.0)
			_target_goal.z = clampf(_target_goal.z,_bounds.position.y-100.0,_bounds.end.y+100.0)
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_HOME:
			reset_view()
			return true
	return false

func update(delta: float) -> void:
	if not active or not is_instance_valid(camera):
		return
	var blend := 1.0-exp(-15.0*delta)
	target = target.lerp(_target_goal,blend)
	yaw = lerpf(yaw,_yaw_goal,blend)
	pitch = lerpf(pitch,_pitch_goal,blend)
	span = lerpf(span,_span_goal,blend)
	_apply_camera()

func _snap_to_goal() -> void:
	target = _target_goal
	yaw = _yaw_goal
	pitch = _pitch_goal
	span = _span_goal
	_apply_camera()

func _apply_camera() -> void:
	# Equal apparent scale on the target plane when changing projection.
	var distance := span/(2.0*tan(deg_to_rad(camera.fov)*0.5))
	var orbit := Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))
	camera.global_position = target+orbit*distance
	camera.size = span
	camera.look_at(target,Vector3.UP)
