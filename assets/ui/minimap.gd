extends Control

# Live actor positions are supplied by gameplay after its visibility checks.
# This control never discovers combatants or retains old enemy positions.
var map_state: Dictionary = {}
var _terrain: ImageTexture
var _bounds := Rect2(-54.0,-48.0,112.0,97.0)
var _terrain_bounds := Rect2(-54.0,-48.0,112.0,97.0)
var _sites: Dictionary = {}
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_load_terrain()

func set_state(value: Dictionary) -> void:
	map_state = value.duplicate()
	if value.get("bounds") is Rect2:
		_bounds = value.bounds
	if value.get("sites") is Dictionary:
		_sites = value.sites
	queue_redraw()

func _load_terrain() -> void:
	var path := "res://assets/map/map_data.json"
	if not FileAccess.file_exists(path):
		return
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not source is Dictionary:
		return
	var data: Dictionary = source
	var box: Array = data.get("bounds",[-54,-48,112,97])
	_terrain_bounds = Rect2(float(box[0]),float(box[1]),float(box[2]),float(box[3]))
	_bounds = _terrain_bounds
	_sites = data.get("sites",{})
	var grid: Dictionary = data.get("grid",{})
	var rows: Array = grid.get("rows",[])
	if rows.is_empty():
		return
	var width := int(grid.get("width",str(rows[0]).length()))
	var height := rows.size()
	var image := Image.create(width,height,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in height:
		var row: String = rows[y]
		for x in mini(width,row.length()):
			if row.unicode_at(x) != 49:
				continue
			var edge := x == 0 or y == 0 or x == width-1 or y == height-1
			if not edge:
				edge = row.unicode_at(x-1) != 49 or row.unicode_at(x+1) != 49 or str(rows[y-1]).unicode_at(x) != 49 or str(rows[y+1]).unicode_at(x) != 49
			image.set_pixel(x,y,Color("788073") if edge else Color("434e49"))
	_terrain = ImageTexture.create_from_image(image)
	queue_redraw()

func _map_rect() -> Rect2:
	var available := Vector2(size.x-24.0,size.y-42.0)
	var scale_factor := minf(available.x/_bounds.size.x,available.y/_bounds.size.y)
	var rect_size := _bounds.size*scale_factor
	return Rect2(Vector2((size.x-rect_size.x)*0.5,31.0+(available.y-rect_size.y)*0.5),rect_size)

func _point(value: Variant) -> Vector2:
	if value is Vector3:
		return Vector2(value.x,value.z)
	if value is Vector2:
		return value
	if value is Array and value.size() >= 3:
		return Vector2(float(value[0]),float(value[2]))
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]),float(value[1]))
	return _bounds.get_center()

func _project(value: Variant) -> Vector2:
	var rect := _map_rect()
	return rect.position+(_point(value)-_bounds.position)/_bounds.size*rect.size

func _draw() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.045,0.072,0.078,0.91)
	background.border_color = Color(1,1,1,0.12)
	background.set_border_width_all(1)
	background.set_corner_radius_all(4)
	draw_style_box(background,Rect2(Vector2.ZERO,size))
	if _font == null:
		return
	draw_string(_font,Vector2(12,20),"MIRAGE / RADAR",HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("a7b1aa"))
	draw_string(_font,Vector2(size.x-26,20),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("d9b775"))
	if _terrain != null:
		var top_left := _project(_terrain_bounds.position)
		var bottom_right := _project(_terrain_bounds.end)
		draw_texture_rect(_terrain,Rect2(top_left,bottom_right-top_left),false)
	for site in _sites:
		var pos := _project(_sites[site])
		draw_circle(pos,10.0,Color(0.1,0.12,0.1,0.85))
		draw_string(_font,pos+Vector2(-4.5,4),str(site),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("e1bb74"))
	for ally in map_state.get("allies",[]):
		_marker(_project(ally),Color("a0c6d8"),3.1)
	for enemy in map_state.get("enemies",[]):
		_marker(_project(enemy),Color("e38768"),3.4)
	if map_state.has("player"):
		var p := _project(map_state.player)
		var heading := _point(map_state.get("heading",Vector3.FORWARD)).normalized()
		if heading.length_squared() < 0.1:
			heading = Vector2.UP
		var side := Vector2(-heading.y,heading.x)
		var points := PackedVector2Array([p+heading*8.0,p-heading*4.5+side*5.0,p-heading*2.5,p-heading*4.5-side*5.0])
		draw_circle(p,9.5,Color(0.04,0.06,0.05,0.7))
		draw_colored_polygon(points,Color("f1d497"))

func _marker(point: Vector2, color: Color, radius: float) -> void:
	if not _map_rect().grow(2).has_point(point):
		return
	draw_circle(point,radius+1.5,Color(0.03,0.06,0.06,0.9))
	draw_circle(point,radius,color)
