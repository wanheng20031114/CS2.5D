extends Node3D
class_name MirageMap

# The rendered environment and collision are baked native resources. These compact
# measurements serve gameplay queries and a height-aware navigation graph.
var spawns: Dictionary = {}
var sites: Dictionary = {}
var site_regions: Dictionary = {}
var spawn_points: Dictionary = {}
var bounds: Rect2 = Rect2(-54.0, -48.0, 112.0, 97.0)
var nav_points: Array[Vector3] = []
var _data: Dictionary = {}
var _grid: Dictionary = {}
var _astar := AStar3D.new()
var _built := false
var _rows: Array = []
var _cell_nodes: Dictionary = {}
var _locations: Array = []

func _ready() -> void:
	build()

func build() -> void:
	if _built:
		return
	_built = true
	_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map/map_data.json"))
	_grid = _data["grid"]
	_rows = _grid["rows"]
	_locations = _data["locations"]
	for team in _data["spawns"]:
		spawns[team] = _vec(_data["spawns"][team])
	for team in _data.get("spawn_points", {}):
		spawn_points[team] = []
		for point in _data["spawn_points"][team]:
			spawn_points[team].append(_vec(point))
	for site in _data.get("site_regions", {}):
		var region: Dictionary = _data["site_regions"][site]
		var minimum := _vec(region["min"])
		var maximum := _vec(region["max"])
		var polygon := PackedVector2Array()
		for point in region.get("polygon_xz", []):
			polygon.append(Vector2(float(point[0]),float(point[1])))
		site_regions[site] = {"min":minimum,"max":maximum,"rect":Rect2(minimum.x, minimum.z, maximum.x-minimum.x, maximum.z-minimum.z),"polygon":polygon}
	for site in _data["sites"]:
		sites[site] = _vec(_data["sites"][site])
	var packed := load("res://assets/map/mirage_baked.tscn") as PackedScene
	if packed:
		var geometry := packed.instantiate()
		add_child(geometry)
		_apply_architecture_cutaway(geometry)
	for entry in _data["labels"]:
		var label := Label3D.new()
		label.text = entry["text"]
		label.font_size = 144
		label.pixel_size = 0.022
		label.position = _vec(entry["position"])
		label.rotation_degrees.x = -90.0
		label.modulate = Color(0.69, 0.21, 0.10)
		label.outline_size = 0
		label.no_depth_test = false
		add_child(label)
	var navigation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map/navigation.json"))
	var nodes: Array = navigation["nodes"]
	_astar.reserve_space(nodes.size())
	for index in nodes.size():
		var p := _vec(nodes[index])
		_astar.add_point(index, p)
		var key := _cell(p)
		if not _cell_nodes.has(key):
			_cell_nodes[key] = []
		_cell_nodes[key].append(index)
	for edge in navigation["edges"]:
		_astar.connect_points(int(edge[0]), int(edge[1]), true)
	for entry in _locations:
		var point: Array = entry["point"]
		var p := Vector3(float(point[0]), 0.0, float(point[1]))
		p.y = ground_height(p)
		nav_points.append(p)

func _vec(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _cell(p: Vector3) -> Vector2i:
	var origin: Array = _grid.get("origin", [-54.0, -48.0])
	var size: float = float(_grid.get("cell", 0.5))
	return Vector2i(floori((p.x - float(origin[0])) / size), floori((p.z - float(origin[1])) / size))

func _cell_open(cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= _rows.size():
		return false
	var row: String = _rows[cell.y]
	return cell.x >= 0 and cell.x < row.length() and row.unicode_at(cell.x) == 49

func is_walkable(p: Vector3, radius: float = 0.4) -> bool:
	if not _built:
		build()
	if not _cell_open(_cell(p)):
		return false
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		if not _cell_open(_cell(p + direction * maxf(radius - 0.18, 0.0))):
			return false
	return true

# Inputs are feet positions. Tests a chest-height segment against the actual
# baked colliders, so a low passage and its upper floor do not share visibility.
func segment_blocked(a: Vector3, b: Vector3) -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(a + Vector3.UP * 1.05, b + Vector3.UP * 1.05, 1)
	query.hit_from_inside = true
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _nearest_id(p: Vector3) -> int:
	var center := _cell(p)
	var best := -1
	var distance := INF
	for radius in [1, 3, 8]:
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				for id in _cell_nodes.get(center + Vector2i(dx, dz), []):
					var candidate := _astar.get_point_position(id)
					var d := p.distance_squared_to(candidate)
					if d < distance:
						distance = d
						best = id
		if best >= 0:
			return best
	return _astar.get_closest_point(p)

func ground_height(p: Vector3) -> float:
	if _astar.get_point_count() == 0:
		return 0.0
	var id := _nearest_id(p)
	return _astar.get_point_position(id).y if id >= 0 else 0.0

func find_path(a: Vector3, b: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if _astar.get_point_count() == 0:
		return result
	var start := _nearest_id(a)
	var finish := _nearest_id(b)
	if start < 0 or finish < 0:
		return result
	var points := _astar.get_point_path(start, finish)
	if points.is_empty():
		return result
	# Keep changes in direction and slope; avoid hundreds of redundant half-meter
	# waypoints while keeping the original ramps and underpass layer intact.
	result.append(points[0])
	for i in range(1, points.size() - 1):
		var before := (points[i] - points[i - 1]).normalized()
		var after := (points[i + 1] - points[i]).normalized()
		if before.dot(after) < 0.995 or result[-1].distance_to(points[i]) > 3.0:
			result.append(points[i])
	result.append(points[-1])
	return result

func location_name(p: Vector3) -> String:
	var best := "荒漠迷城"
	var nearest := INF
	for entry in _locations:
		var point: Array = entry["point"]
		var d := Vector2(p.x, p.z).distance_squared_to(Vector2(float(point[0]), float(point[1])))
		if d < nearest:
			nearest = d
			best = entry["name"]
	return best


func _apply_architecture_cutaway(node: Node) -> void:
	if node is MeshInstance3D and (node.name.begins_with("Architecture") or node.name.begins_with("Canopy") or node.name.begins_with("Foliage") or node.name.begins_with("Props")):
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/architecture.gdshader")
		var source_material := node.mesh.surface_get_material(0) as StandardMaterial3D
		if source_material:
			material.set_shader_parameter("roughness_value",source_material.roughness)
			material.set_shader_parameter("metallic_value",source_material.metallic)
		if node.name.begins_with("Canopy") or node.name.begins_with("Foliage"):
			material.set_shader_parameter("cutaway_height", 2.2)
		node.material_override = material
	for child in node.get_children():
		_apply_architecture_cutaway(child)
