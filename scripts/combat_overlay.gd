extends Control
var game: Node3D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(game) or not game.running or game.ui.is_modal_open(): return
	for actor in game.actors:
		if actor == game.player or not actor.alive or not actor.visible: continue
		var at: Vector2 = game.camera.unproject_position(actor.position+Vector3.UP*2.1)
		if not Rect2(Vector2.ZERO,size).has_point(at): continue
		var color := Color("da785e") if actor.team != game.side else Color("8bb3ba")
		draw_style_box(_background(),Rect2(at+Vector2(-24,-4),Vector2(48,7)))
		draw_rect(Rect2(at+Vector2(-22,-2),Vector2(44*actor.health/100.0,3)),color)

func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05,0.08,0.08,0.8)
	style.set_corner_radius_all(3)
	return style
