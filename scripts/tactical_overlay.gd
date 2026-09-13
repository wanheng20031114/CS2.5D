class_name TacticalOverlay
extends Control

var enabled := false
var aiming := false
var spread := 0.004
var hit_timer := 0.0
var damage_timer := 0.0
var _gap := 7.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	hit_timer = maxf(0.0, hit_timer - delta)
	damage_timer = maxf(0.0, damage_timer - delta)
	_gap = lerpf(_gap, clampf(spread * 500.0, 4.0, 34.0), 1.0 - exp(-delta * 18.0))
	queue_redraw()

func _draw() -> void:
	if not enabled:
		return
	var p := get_local_mouse_position()
	var color := Color(0.98, 0.92, 0.75, 0.95) if aiming else Color(0.96, 0.96, 0.91, 0.88)
	var length := 7.0
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(p + d * _gap, p + d * (_gap + length), Color(0.05, 0.07, 0.08, 0.7), 4.0, true)
		draw_line(p + d * _gap, p + d * (_gap + length), color, 1.5, true)
	draw_circle(p, 1.5, color)
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
