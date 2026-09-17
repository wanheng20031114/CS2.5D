class_name TacticalOverlay
extends Control

var enabled := false
var aiming := false
var spread := 0.004
var hit_timer := 0.0
var damage_timer := 0.0
var _gap := 7.0
var first_person := false
var fp_settings: Dictionary = {}
var fp_fov := 75.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	hit_timer = maxf(0.0, hit_timer - delta)
	damage_timer = maxf(0.0, damage_timer - delta)
	var target_gap := clampf(spread * 500.0, 4.0, 34.0)
	if first_person:
		target_gap = float(fp_settings.get("fp_crosshair_gap",4.0))
		if fp_settings.get("fp_crosshair_dynamic",true):
			target_gap += minf(100.0,tan(spread)*size.y/(2.0*tan(deg_to_rad(fp_fov)*0.5)))
	_gap = lerpf(_gap, target_gap, 1.0 - exp(-delta * 18.0))
	queue_redraw()

func _draw() -> void:
	if not enabled:
		return
	var p := get_local_mouse_position()
	if first_person: p = size*0.5
	var color := Color(0.98, 0.92, 0.75, 0.95) if aiming else Color(0.96, 0.96, 0.91, 0.88)
	var length := 7.0
	var width := 1.5
	if first_person:
		length = float(fp_settings.get("fp_crosshair_length",7.0))
		width = float(fp_settings.get("fp_crosshair_width",2.0))
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(p + d * _gap, p + d * (_gap + length), Color(0.05, 0.07, 0.08, 0.7), width+2.0, true)
		draw_line(p + d * _gap, p + d * (_gap + length), color, width, true)
	if not first_person or fp_settings.get("fp_crosshair_dot",false): draw_circle(p, maxf(1.0,width*0.5), color)
	if hit_timer > 0.0:
		var hit_color := Color(1.0, 0.52, 0.28, minf(hit_timer * 8.0, 1.0))
		for d in [Vector2(-1,-1), Vector2(1,-1), Vector2(-1,1), Vector2(1,1)]:
			draw_line(p + d * 12.0, p + d * 17.0, hit_color, 2.0, true)
	if damage_timer > 0.0:
		var c := Color(0.85, 0.19, 0.12, damage_timer * 0.55)
		draw_rect(Rect2(Vector2.ZERO, size), c, false, 10.0)

func confirm_hit() -> void:
	hit_timer = 0.18

func damage() -> void:
	damage_timer = 0.5
