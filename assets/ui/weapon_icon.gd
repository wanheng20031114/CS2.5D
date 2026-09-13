extends Control

var item_id := "":
	set(value):
		if item_id == value:
			return
		item_id = value
		_texture = null
		var aliases := {"defuser":"kit","smoke":"smokegrenade","flash":"flashbang","he":"hegrenade","usp":"usp_silencer"}
		var path := "res://assets/weapons/icons/"+str(aliases.get(value,value))+".png"
		if ResourceLoader.exists(path):
			_texture = load(path) as Texture2D
		queue_redraw()
var tint := Color("a9b2ab")
var _texture: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if item_id.is_empty():
		return
	if _texture != null:
		var fitted := _texture.get_size()*minf(size.x/_texture.get_width(),size.y/_texture.get_height())
		draw_texture_rect(_texture,Rect2((size-fitted)*0.5,fitted),false,Color(1.6,1.6,1.6,1.0))
		return
	var factor := minf(size.x/120.0,size.y/44.0)
	draw_set_transform(Vector2((size.x-120.0*factor)*0.5,(size.y-44.0*factor)*0.5),0,Vector2.ONE*factor)
	var id := item_id.to_lower()
	var steel := tint
	var dark := tint.darkened(0.30)
	var wood := Color("ad8961")
	if "knife" in id:
		draw_colored_polygon(PackedVector2Array([Vector2(17,21),Vector2(82,18),Vector2(108,7),Vector2(96,29),Vector2(39,30)]),steel)
		draw_line(Vector2(14,23),Vector2(41,23),dark,10,true)
	elif id in ["armor","kevlar","helmet","vest","vesthelm","defuser","defuse_kit","kit"]:
		draw_colored_polygon(PackedVector2Array([Vector2(44,5),Vector2(53,10),Vector2(66,10),Vector2(75,5),Vector2(84,16),Vector2(78,37),Vector2(42,37),Vector2(36,16)]),steel)
		draw_line(Vector2(47,19),Vector2(71,19),dark,3,true)
		draw_line(Vector2(47,26),Vector2(71,26),dark,3,true)
	elif "grenade" in id or "smoke" in id or "flash" in id or "decoy" in id or "molotov" in id or "inc" in id or id == "he":
		draw_style_box(_capsule(steel),Rect2(49,13,24,28))
		draw_rect(Rect2(54,7,14,7),dark)
		draw_line(Vector2(58,6),Vector2(74,9),steel,3,true)
		draw_line(Vector2(74,9),Vector2(79,27),steel,3,true)
	elif id in ["glock","glock18","glock-18","usp","usp_s","usp-s","usp_silencer","p2000","hkp2000","p250","deagle","desert_eagle","tec9","tec-9","fiveseven","five-seven","cz75","cz75a","revolver","elite","dual_berettas","taser"]:
		draw_rect(Rect2(30,8,54,12),steel)
		draw_colored_polygon(PackedVector2Array([Vector2(34,18),Vector2(52,18),Vector2(46,40),Vector2(28,40)]),dark)
		draw_arc(Vector2(57,21),8,0,PI,10,dark,4,true)
		if "usp" in id:
			draw_line(Vector2(82,13),Vector2(108,13),dark,6,true)
	elif id == "c4" or "bomb" in id:
		draw_rect(Rect2(34,7,52,31),dark)
		draw_rect(Rect2(46,12,28,9),Color("b9b787"))
		for i in 3:
			draw_line(Vector2(49+i*8,25),Vector2(49+i*8,32),steel,4,true)
	else:
		var ak := "ak" in id
		var sniper := "awp" in id or "ssg" in id or "scar" in id or "g3sg" in id
		draw_colored_polygon(PackedVector2Array([Vector2(10,17),Vector2(36,16),Vector2(40,23),Vector2(12,31)]),wood if ak else dark)
		draw_rect(Rect2(35,13,44,11),steel)
		draw_line(Vector2(79,16),Vector2(112,16),dark,4,true)
		draw_rect(Rect2(70,12,21,9),wood if ak else dark)
		draw_colored_polygon(PackedVector2Array([Vector2(41,23),Vector2(50,23),Vector2(47,37),Vector2(39,34)]),dark)
		if ak:
			draw_colored_polygon(PackedVector2Array([Vector2(58,22),Vector2(68,22),Vector2(66,32),Vector2(57,42),Vector2(50,37),Vector2(57,29)]),steel)
		else:
			draw_rect(Rect2(58,22,10,14),dark)
		if sniper:
			draw_line(Vector2(45,6),Vector2(72,6),steel,6,true)
			draw_line(Vector2(55,8),Vector2(55,13),dark,3,true)
			draw_line(Vector2(66,8),Vector2(66,13),dark,3,true)
		else:
			draw_line(Vector2(46,11),Vector2(62,11),dark,3,true)

func _capsule(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(8)
	return box
