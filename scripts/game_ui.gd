class_name GameUI
extends CanvasLayer

signal start_requested(team: String, mode: String, difficulty: int)
signal buy_requested(id: String)
signal equip_requested(slot: int)
signal action_requested(action: String)
signal settings_changed(values: Dictionary)

const INK := Color("12191b")
const PAPER := Color("ece6d8")
const MUTED := Color("9da6a3")
const GOLD := Color("d9b775")
const CT_COLOR := Color("9ebac5")
const T_COLOR := Color("d9b775")
const WeaponIconScript := preload("res://assets/ui/weapon_icon.gd")
const MinimapScript := preload("res://assets/ui/minimap.gd")
const FirstPersonSettings := preload("res://scripts/first_person_settings.gd")

var root: Control
var menu: Control
var map_preview: Control
var _preview_projection: Button
var hud: Control
var modal: Control
var overlay: TacticalOverlay
var body_font: SystemFont
var display_font: SystemFont
var theme_ui: Theme
var team := "CT"
var mode := "bomb"
var difficulty := 1
var state: Dictionary = {}
var catalog: Array = []
var settings: Dictionary = FirstPersonSettings.sanitize({"sensitivity": 1.0, "volume": 0.65, "shake": 0.55, "zoom": 24.0, "fullscreen": false})
var _settings_controls: Dictionary = {}
var _controls_hint: Label
var _modal_kind := ""
var _paused_context := false
var _category := "全部"
var _shop_buttons: Array[Dictionary] = []
var _team_buttons: Array[Button] = []
var _mode_buttons: Array[Button] = []
var _category_buttons: Array[Button] = []
var _hotbar: Array[Button] = []
var _hotbar_icons: Array[Control] = []
var _hotbar_names: Array[Label] = []
var _hotbar_items: Array[Dictionary] = []
var _minimap: Control
var _last_inventory := ""
var _health_label: Label
var _armor_label: Label
var _money_label: Label
var _health_bar: ProgressBar
var _timer_label: Label
var _round_label: Label
var _ct_label: Label
var _t_label: Label
var _ct_alive: Label
var _t_alive: Label
var _location_label: Label
var _objective_label: Label
var _phase_label: Label
var _ammo_label: Label
var _weapon_label: Label
var _accuracy_label: Label
var _reload_bar: ProgressBar
var _feed_label: Label
var _toast_label: Label
var _round_panel: PanelContainer
var _result_title: Label
var _result_subtitle: Label
var _shop_grid: GridContainer
var _shop_balance: Label
var _shop_status: Label
var _inventory_grid: GridContainer
var _inventory_capacity: Label
var _toast_tween: Tween
var _round_tween: Tween
var _was_hit := false

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	body_font = SystemFont.new()
	body_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	display_font = SystemFont.new()
	display_font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	display_font.font_weight = 700
	theme_ui = Theme.new()
	theme_ui.default_font = body_font
	theme_ui.default_font_size = 15
	theme_ui.set_color("font_color", "Label", PAPER)
	theme_ui.set_color("font_color", "Button", PAPER)
	theme_ui.set_color("font_hover_color", "Button", Color.WHITE)
	theme_ui.set_color("font_pressed_color", "Button", PAPER)
	theme_ui.set_color("font_disabled_color", "Button", Color("636c6b"))
	theme_ui.set_stylebox("normal", "Button", _style(Color(0.08,0.11,0.12,0.7), Color(1,1,1,0.11), 1, 4))
	theme_ui.set_stylebox("hover", "Button", _style(Color("293331"), GOLD, 1, 4))
	theme_ui.set_stylebox("pressed", "Button", _style(Color("384039"), GOLD, 1, 4))
	theme_ui.set_stylebox("disabled", "Button", _style(Color(0.07,0.09,0.1,0.48), Color(1,1,1,0.06), 1, 4))
	theme_ui.set_stylebox("focus", "Button", _style(Color.TRANSPARENT, GOLD, 1, 4))
	root = Control.new()
	root.name = "GameInterface"
	root.theme = theme_ui
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	overlay = TacticalOverlay.new()
	root.add_child(overlay)
	_build_menu()
	_build_hud()
	_build_map_preview()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.visible = false
	root.add_child(modal)
	_toast_label = _label("", 16, PAPER)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_color_override("font_shadow_color", Color(0,0,0,0.9))
	_toast_label.add_theme_constant_override("shadow_outline_size", 6)
	_anchor(_toast_label, 0.5, 0.0, 0.5, 0.0, -360, 145, 360, 182)
	root.add_child(_toast_label)
	_toast_label.visible = false
	show_menu()

func _style(fill: Color, border: Color = Color.TRANSPARENT, width: int = 0, radius: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

func _label(text: String, font_size: int = 16, color: Color = PAPER, display: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if display:
		label.add_theme_font_override("font", display_font)
	return label

func _bar_style(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_content_margin_all(0)
	return sb

func _slider_style(fill: Color) -> StyleBoxFlat:
	var sb := _bar_style(fill)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb

func _anchor(control: Control, left: float, top: float, right: float, bottom: float, ol: float, ot: float, oright: float, ob: float) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.anchor_left = left
	control.anchor_top = top
	control.anchor_right = right
	control.anchor_bottom = bottom
	control.offset_left = ol
	control.offset_top = ot
	control.offset_right = oright
	control.offset_bottom = ob

func _at(control: Control, parent: Node, x: float, y: float, w: float, h: float) -> Control:
	parent.add_child(control)
	control.position = Vector2(x,y)
	control.size = Vector2(w,h)
	return control

func _button(text: String, callback: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size.y = 40
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	if primary:
		b.add_theme_stylebox_override("normal", _style(GOLD, GOLD, 0, 3))
		b.add_theme_stylebox_override("hover", _style(Color("efd092"), GOLD, 0, 3))
		b.add_theme_stylebox_override("pressed", _style(Color("c3a169"), GOLD, 0, 3))
		b.add_theme_color_override("font_color", INK)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_pressed_color", INK)
	return b

func _divider(parent: Node, x: float, y: float, w: float) -> void:
	var line := ColorRect.new()
	line.color = Color(1,1,1,0.12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(line, parent, x,y,w,1)

func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(menu)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.035,0.06,0.07,0.96))
	gradient.set_color(1, Color(0.035,0.06,0.07,0.07))
	gradient.add_point(0.36, Color(0.035,0.06,0.07,0.87))
	gradient.add_point(0.66, Color(0.035,0.06,0.07,0.18))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2.ZERO
	tex.fill_to = Vector2.RIGHT
	var shade := TextureRect.new()
	shade.texture = tex
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(shade)
	var left := Control.new()
	_anchor(left,0,0.5,0,0.5,58,-320,468,320)
	menu.add_child(left)
	_at(_label("TACTICAL OPERATIONS   /   01",12,GOLD,true),left,0,0,400,26)
	_at(_label("MIRAGE",87,PAPER,true),left,-5,27,450,110)
	_at(_label("荒漠迷城",29,PAPER),left,0,130,400,44)
	_at(_label("阳光下的沙城，每一步都关乎胜负。",14,MUTED),left,0,188,400,30)
	_divider(left,0,239,380)
	_at(_label("单人行动",17,PAPER),left,0,264,180,28)
	_at(_label("选择阵营",12,MUTED),left,0,303,120,22)
	var ct := _button("CT   反恐精英", func(): _set_team("CT"))
	var tt := _button("T   恐怖分子", func(): _set_team("T"))
	_at(ct,left,0,332,185,42)
	_at(tt,left,195,332,185,42)
	_team_buttons = [ct,tt]
	_at(_label("行动模式",12,MUTED),left,0,391,110,22)
	var classic := _button("爆破对局",func(): _set_mode("bomb"))
	var practice := _button("自由练习",func(): _set_mode("practice"))
	_at(classic,left,0,420,122,40)
	_at(practice,left,130,420,122,40)
	_mode_buttons = [classic,practice]
	var diff := OptionButton.new()
	diff.add_item("轻松",0)
	diff.add_item("标准",1)
	diff.add_item("精英",2)
	diff.select(1)
	diff.focus_mode = Control.FOCUS_NONE
	diff.add_theme_stylebox_override("normal",_style(Color(0.08,0.11,0.12,0.7),Color(1,1,1,0.11),1,4))
	diff.add_theme_stylebox_override("hover",_style(Color("293331"),GOLD,1,4))
	diff.item_selected.connect(func(index: int): difficulty = index)
	_at(diff,left,262,420,118,40)
	var start := _button("部署进入战局     →",func(): start_requested.emit(team,mode,difficulty),true)
	start.add_theme_font_size_override("font_size",19)
	_at(start,left,0,480,380,56)
	var multi := _button("多人游戏 · 即将开放",func(): pass)
	multi.disabled = true
	_at(multi,left,0,548,185,43)
	var preview := _button("地图预览     ↗",func(): action_requested.emit("map_preview"))
	preview.add_theme_color_override("font_color",GOLD)
	_at(preview,left,195,548,185,43)
	var options := _button("设置与操作",_open_settings)
	options.flat = true
	_at(options,left,0,612,155,36)
	var quit_button := _button("退出",func(): action_requested.emit("quit"))
	quit_button.flat = true
	_at(quit_button,left,169,612,72,36)
	var caption := _label("MIRAGE\n25°  /  晴朗",14,PAPER,true)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor(caption,1,0,1,0,-290,40,-44,100)
	menu.add_child(caption)
	var marker := _label("SINGLE PLAYER  /  BOT OPERATIONS",12,Color(0.91,0.88,0.80,0.75),true)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor(marker,1,1,1,1,-450,-50,-44,-20)
	menu.add_child(marker)
	_set_team(team)
	_set_mode(mode)

func _build_map_preview() -> void:
	map_preview = Control.new()
	map_preview.name = "MapPreviewInterface"
	map_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_preview.hide()
	root.add_child(map_preview)
	var title := _label("MIRAGE   /   地图预览",22,PAPER,true)
	title.add_theme_color_override("font_shadow_color",Color(0,0,0,0.9))
	title.add_theme_constant_override("shadow_outline_size",1)
	_at(title,map_preview,30,25,450,42)
	var subtitle := _label("自由观察完整模型",12,PAPER)
	subtitle.add_theme_color_override("font_shadow_color",Color(0,0,0,0.9))
	subtitle.add_theme_constant_override("shadow_outline_size",1)
	_at(subtitle,map_preview,32,69,360,26)
	var toolbar := HBoxContainer.new()
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toolbar.add_theme_constant_override("separation",8)
	_anchor(toolbar,1,0,1,0,-446,30,-30,73)
	map_preview.add_child(toolbar)
	_preview_projection = _button("正交 / 切换透视",func(): action_requested.emit("map_preview_projection"))
	_preview_projection.custom_minimum_size.x = 146
	toolbar.add_child(_preview_projection)
	var reset := _button("重置视角",func(): action_requested.emit("map_preview_reset"))
	reset.custom_minimum_size.x = 104
	toolbar.add_child(reset)
	var leave := _button("返回主菜单  Esc",func(): action_requested.emit("map_preview_exit"))
	leave.custom_minimum_size.x = 146
	toolbar.add_child(leave)
	var bottom := VBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation",12)
	_anchor(bottom,0.5,1,0.5,1,-345,-130,345,-24)
	map_preview.add_child(bottom)
	var locations := HBoxContainer.new()
	locations.mouse_filter = Control.MOUSE_FILTER_IGNORE
	locations.alignment = BoxContainer.ALIGNMENT_CENTER
	locations.add_theme_constant_override("separation",8)
	bottom.add_child(locations)
	for entry in [["A","A 包点"],["B","B 包点"],["MID","中路"],["CT","CT 出生点"],["T","T 出生点"]]:
		var id: String = entry[0]
		var landmark := _button(entry[1],func(): action_requested.emit("map_preview_focus:"+id))
		landmark.custom_minimum_size.x = 114
		locations.add_child(landmark)
	var hints := _label("左键拖拽 · 旋转    右键 / 中键 · 平移    滚轮 · 缩放    Home · 重置",13,PAPER)
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hints.add_theme_color_override("font_shadow_color",Color(0,0,0,0.95))
	hints.add_theme_constant_override("shadow_outline_size",1)
	bottom.add_child(hints)

func show_map_preview() -> void:
	close_panels()
	menu.hide()
	hud.hide()
	_round_panel.hide()
	_toast_label.hide()
	overlay.enabled = false
	map_preview.show()
	set_map_preview_projection("正交")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func set_map_preview_projection(label: String) -> void:
	_preview_projection.text = label+" / 切换"+("透视" if label == "正交" else "正交")

func _select_style(b: Button, selected: bool) -> void:
	b.add_theme_stylebox_override("normal",_style(Color(0.20,0.22,0.19,0.92) if selected else Color(0.08,0.11,0.12,0.7), GOLD if selected else Color(1,1,1,0.11),1,3))
	b.add_theme_color_override("font_color",GOLD if selected else PAPER)

func _set_team(value: String) -> void:
	team = value
	for i in _team_buttons.size():
		_select_style(_team_buttons[i],i == (0 if team == "CT" else 1))

func _set_mode(value: String) -> void:
	mode = value
	for i in _mode_buttons.size():
		_select_style(_mode_buttons[i],i == (0 if mode == "bomb" else 1))

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	var top := PanelContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_stylebox_override("panel",_style(Color(0.04,0.07,0.08,0.86),Color(1,1,1,0.08),1,5))
	_anchor(top,0.5,0,0.5,0,-225,20,225,103)
	hud.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(row)
	var ctbox := VBoxContainer.new()
	ctbox.custom_minimum_size.x = 104
	row.add_child(ctbox)
	_ct_label = _label("CT   0",27,CT_COLOR,true)
	ctbox.add_child(_ct_label)
	_ct_alive = _label("● ● ● ● ●",11,CT_COLOR)
	ctbox.add_child(_ct_alive)
	var clockbox := VBoxContainer.new()
	clockbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clockbox.add_theme_constant_override("separation",0)
	row.add_child(clockbox)
	_round_label = _label("第 1 回合",11,MUTED)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clockbox.add_child(_round_label)
	_timer_label = _label("01:55",31,PAPER,true)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clockbox.add_child(_timer_label)
	var tbox := VBoxContainer.new()
	tbox.custom_minimum_size.x = 104
	row.add_child(tbox)
	_t_label = _label("0   T",27,T_COLOR,true)
	_t_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tbox.add_child(_t_label)
	_t_alive = _label("● ● ● ● ●",11,T_COLOR)
	_t_alive.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tbox.add_child(_t_alive)
	_location_label = _label("MIRAGE  /  反恐精英出生点",17,PAPER)
	_location_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	_location_label.add_theme_constant_override("shadow_outline_size",0)
	_at(_location_label,hud,30,28,370,32)
	_objective_label = _label("守住爆破点，阻止炸弹引爆。",12,Color("dad9cf"))
	_objective_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	_objective_label.add_theme_constant_override("shadow_outline_size",0)
	_at(_objective_label,hud,30,63,375,30)
	_minimap = MinimapScript.new()
	_at(_minimap,hud,28,109,231,225)
	_phase_label = _label("准备阶段   ·   按 B 购买装备",13,GOLD)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	_phase_label.add_theme_constant_override("shadow_outline_size",0)
	_anchor(_phase_label,0.5,0,0.5,0,-290,109,290,137)
	hud.add_child(_phase_label)
	_feed_label = _label("",12,PAPER)
	_feed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	_feed_label.add_theme_constant_override("shadow_outline_size",0)
	_anchor(_feed_label,1,0,1,0,-350,28,-28,146)
	hud.add_child(_feed_label)
	var vitals := Panel.new()
	vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals.add_theme_stylebox_override("panel",_style(Color(0.04,0.07,0.08,0.78),Color(1,1,1,0.08),1,4))
	_anchor(vitals,0,1,0,1,24,-145,269,-49)
	hud.add_child(vitals)
	_at(_label("+",29,GOLD,true),vitals,13,8,30,39)
	_health_label = _label("100",33,PAPER,true)
	_at(_health_label,vitals,45,6,89,42)
	_armor_label = _label("护甲  0",14,MUTED)
	_at(_armor_label,vitals,145,16,99,32)
	_health_bar = ProgressBar.new()
	_health_bar.show_percentage = false
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_bar.add_theme_stylebox_override("background",_bar_style(Color(1,1,1,0.09)))
	_health_bar.add_theme_stylebox_override("fill",_bar_style(GOLD))
	_at(_health_bar,vitals,16,56,210,3)
	_money_label = _label("$ 800",18,GOLD,true)
	_at(_money_label,vitals,16,65,205,26)
	var belt := HBoxContainer.new()
	belt.add_theme_constant_override("separation",7)
	_anchor(belt,0.5,1,0.5,1,-242,-120,242,-49)
	hud.add_child(belt)
	for i in range(5):
		var slot := i
		var button := _button("",func(): _activate_hotbar(slot))
		button.custom_minimum_size = Vector2(91,70)
		button.add_theme_font_size_override("font_size",12)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		belt.add_child(button)
		_hotbar.append(button)
		_at(_label(str(i+1),10,MUTED,true),button,8,4,25,17)
		var icon := WeaponIconScript.new()
		_at(icon,button,6,19,79,28)
		_hotbar_icons.append(icon)
		var slot_name := _label("—",10,PAPER)
		slot_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_at(slot_name,button,3,47,85,19)
		_hotbar_names.append(slot_name)
	var ammo := Control.new()
	ammo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(ammo,1,1,1,1,-258,-164,-28,-50)
	hud.add_child(ammo)
	_weapon_label = _label("USP-S",15,PAPER,true)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_at(_weapon_label,ammo,0,0,230,25)
	_ammo_label = _label("12 / 24",45,PAPER,true)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_at(_ammo_label,ammo,0,23,230,56)
	_accuracy_label = _label("站定  ·  精准",12,GOLD)
	_accuracy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_at(_accuracy_label,ammo,0,85,230,25)
	_reload_bar = ProgressBar.new()
	_reload_bar.show_percentage = false
	_reload_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reload_bar.add_theme_stylebox_override("background",_bar_style(Color(1,1,1,0.1)))
	_reload_bar.add_theme_stylebox_override("fill",_bar_style(GOLD))
	_at(_reload_bar,ammo,40,80,190,2)
	_reload_bar.hide()
	_controls_hint = _label("",11,Color(0.93,0.91,0.86,0.8))
	_controls_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_controls_hint.add_theme_color_override("font_shadow_color",Color.BLACK)
	_controls_hint.add_theme_constant_override("shadow_outline_size",0)
	_anchor(_controls_hint,0.5,1,0.5,1,-660,-35,660,-10)
	hud.add_child(_controls_hint)
	_refresh_controls_hint()
	_round_panel = PanelContainer.new()
	_round_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_round_panel.add_theme_stylebox_override("panel",_style(Color(0.04,0.07,0.08,0.93),Color(0.85,0.71,0.46,0.45),1,4))
	_anchor(_round_panel,0.5,0,0.5,0,-270,190,270,297)
	hud.add_child(_round_panel)
	var result_stack := VBoxContainer.new()
	_round_panel.add_child(result_stack)
	_result_title = _label("回合胜利",29,GOLD)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_stack.add_child(_result_title)
	_result_subtitle = _label("",14,PAPER)
	_result_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_stack.add_child(_result_subtitle)
	_round_panel.hide()

func show_menu() -> void:
	close_panels()
	map_preview.hide()
	menu.show()
	hud.hide()
	overlay.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.modulate.a = 0.0
	create_tween().tween_property(menu,"modulate:a",1.0,0.45)

func show_hud() -> void:
	close_panels()
	map_preview.hide()
	menu.hide()
	hud.show()
	overlay.enabled = true
	_round_panel.hide()
	_minimap.set_state({})

func update_state(s: Dictionary) -> void:
	var old_health := float(state.get("health",100))
	state = s.duplicate()
	if not is_instance_valid(_health_label):
		return
	var health := maxi(0,int(s.get("health",100)))
	_health_label.text = str(health)
	_health_label.add_theme_color_override("font_color",Color("ef8c72") if health < 30 else PAPER)
	_health_bar.value = health
	_armor_label.text = "护甲  %d" % int(s.get("armor",0))
	_money_label.text = "$ %s" % _money(int(s.get("money",800)))
	_ct_label.text = "CT   %d" % int(s.get("score_ct",0))
	_t_label.text = "%d   T" % int(s.get("score_t",0))
	_ct_alive.text = _alive_dots(int(s.get("alive_ct",5)))
	_t_alive.text = _alive_dots(int(s.get("alive_t",5)))
	_round_label.text = "自由练习" if str(s.get("mode",mode)) == "practice" else "第 %d 回合" % int(s.get("round",1))
	var remaining := maxi(0,ceili(float(s.get("time",115))))
	_timer_label.text = "%02d:%02d" % [remaining / 60,remaining % 60]
	_timer_label.add_theme_color_override("font_color",Color("ed9672") if remaining <= 15 else PAPER)
	_location_label.text = "MIRAGE  /  " + str(s.get("location","荒漠迷城"))
	_objective_label.text = str(s.get("objective",""))
	var phase := str(s.get("phase","live"))
	var buy_allowed := bool(s.get("buy_allowed",false))
	if bool(s.get("bomb_planted",false)):
		_phase_label.text = "炸弹已安放   ·   E 拆除 / 守卫爆破点"
		_phase_label.add_theme_color_override("font_color",Color("ed9672"))
	elif phase in ["buy","freeze","warmup","home"] or buy_allowed:
		_phase_label.text = "准备阶段   ·   按 B 购买装备" if phase != "home" else "自由训练   ·   B 仅出生区补给   ·   F5 重置"
		_phase_label.add_theme_color_override("font_color",GOLD)
	else:
		_phase_label.text = "已阵亡 · 下一回合重新部署" if health <= 0 else ""
	_ammo_label.text = "%d / %d" % [int(s.get("ammo",0)),int(s.get("reserve",0))]
	_weapon_label.text = str(s.get("name",s.get("weapon","—")))
	if bool(s.get("reloading",false)):
		_accuracy_label.text = "更换弹匣…"
		_reload_bar.show()
		_reload_bar.value = float(s.get("reload_progress",0)) * 100.0
	else:
		_reload_bar.hide()
		_accuracy_label.text = "稳定瞄准  ·  移速降低" if bool(s.get("aiming",false)) else ("移动中  ·  弹道扩散" if bool(s.get("moving",false)) else "站定  ·  精准")
	var feed: Array = s.get("feed",[])
	_feed_label.text = "\n".join(PackedStringArray(feed.slice(maxi(0,feed.size()-4))))
	var inventory: Array = s.get("inventory",[])
	var active := int(s.get("active_slot",0))
	_hotbar_items.clear()
	for i in range(3):
		_hotbar_items.append(inventory[i] if i < inventory.size() and inventory[i] is Dictionary else {})
	for grenade_id in ["hegrenade","smokegrenade"]:
		var entry: Dictionary = {}
		for raw in inventory:
			if raw is Dictionary and str(raw.get("id","")) == grenade_id:
				entry = raw
		_hotbar_items.append(entry)
	for i in _hotbar.size():
		var item: Dictionary = _hotbar_items[i]
		var item_name := str(item.get("name","—"))
		if item_name.length() > 13:
			item_name = item_name.left(12)
		_hotbar_names[i].text = item_name
		_hotbar_names[i].add_theme_color_override("font_color",GOLD if i == active else PAPER)
		_hotbar_icons[i].item_id = str(item.get("id",""))
		_hotbar_icons[i].queue_redraw()
		_select_style(_hotbar[i],i == active)
		_hotbar[i].disabled = str(item.get("id","")).is_empty()
	overlay.aiming = bool(s.get("aiming",false))
	overlay.spread = float(s.get("crosshair_spread",s.get("spread",0.006)))
	if health < old_health:
		overlay.damage()
	if bool(s.get("hit_confirm",false)) and not _was_hit:
		overlay.confirm_hit()
	_was_hit = bool(s.get("hit_confirm",false))
	_minimap.set_state(s.get("map_data",{}) if s.get("map_data",{}) is Dictionary else {})
	if s.get("settings") is Dictionary:
		set_settings(s.settings)
	if _modal_kind == "shop":
		_refresh_shop()
	elif _modal_kind == "inventory":
		var inv_key := str(inventory) + str(active)
		if inv_key != _last_inventory:
			_populate_inventory()

func _activate_hotbar(slot: int) -> void:
	if slot < 3:
		equip_requested.emit(slot)
	elif slot < _hotbar_items.size() and not _hotbar_items[slot].is_empty():
		action_requested.emit("grenade:"+str(_hotbar_items[slot].get("id","")))

func set_settings(values: Dictionary) -> void:
	var previous := settings.duplicate()
	settings.merge(values,true)
	settings = FirstPersonSettings.sanitize(settings)
	settings.zoom = clampf(float(settings.zoom),16.0,34.0)
	if settings != previous:
		_refresh_controls_hint()
		_refresh_setting_controls()

func _refresh_controls_hint() -> void:
	if not is_instance_valid(_controls_hint):
		return
	var movement := "WASD 随朝向移动 · 鼠标转头" if settings.view_mode == "first_person" else "WASD 移动 · 鼠标瞄准"
	_controls_hint.text = movement + "    V 切换视角    右键 瞄准    R 换弹    4—8 投掷    TAB 背包    B 商店    E 交互    ESC 暂停"

func _alive_dots(count: int) -> String:
	var text := ""
	for i in 5:
		text += ("●" if i < count else "○") + (" " if i < 4 else "")
	return text

func _money(value: int) -> String:
	if value >= 1000:
		return "%d,%03d" % [value / 1000,value % 1000]
	return str(value)

func _open_panel(title: String, subtitle: String, kind: String, width: float = 940, height: float = 570) -> Control:
	for child in modal.get_children():
		modal.remove_child(child)
		child.queue_free()
	_modal_kind = kind
	modal.show()
	overlay.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.025,0.04,0.045,0.74)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(dim)
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel",_style(Color("131d20"),Color(0.85,0.71,0.46,0.38),1,5))
	_anchor(panel,0.5,0.5,0.5,0.5,-width/2,-height/2,width/2,height/2)
	modal.add_child(panel)
	_at(_label(title,30,PAPER),panel,30,23,width-110,44)
	_at(_label(subtitle,12,MUTED),panel,32,70,width-75,23)
	var close := _button("×",_close_panel_by_button)
	close.add_theme_font_size_override("font_size",24)
	_at(close,panel,width-67,25,38,38)
	_divider(panel,30,107,width-60)
	panel.modulate.a = 0.0
	var target_y := panel.position.y
	panel.position.y += 12
	var tween := create_tween().set_parallel(true)
	tween.tween_property(panel,"modulate:a",1.0,0.18)
	tween.tween_property(panel,"position:y",target_y,0.23).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return panel

func toggle_shop(items: Array, s: Dictionary) -> void:
	if _modal_kind == "shop":
		close_panels()
		return
	state = s.duplicate()
	catalog = items
	_category = "全部"
	var panel := _open_panel("军械商店","装备会立即加入你的物品栏。只能在安全屋或回合开始时的出生区购买。","shop")
	_shop_balance = _label("$ 800",23,GOLD,true)
	_shop_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_at(_shop_balance,panel,643,34,198,36)
	var categories := ["全部","步枪","手枪","冲锋枪","重型","投掷物","装备"]
	_category_buttons.clear()
	for i in categories.size():
		var category: String = categories[i]
		var b := _button(category,func(): _category = category; _populate_shop())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_at(b,panel,30,126+i*49,123,42)
		_category_buttons.append(b)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_at(scroll,panel,173,126,733,367)
	_shop_grid = GridContainer.new()
	_shop_grid.columns = 3
	_shop_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_grid.add_theme_constant_override("h_separation",10)
	_shop_grid.add_theme_constant_override("v_separation",10)
	scroll.add_child(_shop_grid)
	_shop_status = _label("",13,MUTED)
	_at(_shop_status,panel,174,511,724,29)
	_populate_shop()

func _item_category(item: Dictionary) -> String:
	var category := str(item.get("category","装备")).to_lower()
	if category in ["rifle","rifles","sniper","snipers","步枪","狙击枪"]:
		return "步枪"
	if category in ["pistol","pistols","手枪"]:
		return "手枪"
	if category in ["smg","smgs","冲锋枪"]:
		return "冲锋枪"
	if category in ["heavy","shotgun","shotguns","machinegun","重型"]:
		return "重型"
	if category in ["grenade","grenades","utility","投掷物"]:
		return "投掷物"
	return "装备"

func _populate_shop() -> void:
	for child in _shop_grid.get_children():
		_shop_grid.remove_child(child)
		child.queue_free()
	_shop_buttons.clear()
	for b in _category_buttons:
		_select_style(b,b.text == _category)
	for raw in catalog:
		if not raw is Dictionary:
			continue
		var item: Dictionary = raw
		if str(item.get("category","")) == "melee":
			continue
		if _category != "全部" and _item_category(item) != _category:
			continue
		var id := str(item.get("id",""))
		var b := _button("",func(): buy_requested.emit(id))
		b.custom_minimum_size = Vector2(225,116)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "%s\n价格 $%d  ·  弹匣 %d  ·  伤害 %s" % [str(item.get("name",id)),int(item.get("price",0)),int(item.get("magazine",item.get("mag",0))),str(item.get("damage","—"))]
		_shop_grid.add_child(b)
		var name_label := _label(str(item.get("name",id)),16,PAPER)
		_at(name_label,b,14,11,200,25)
		var icon := WeaponIconScript.new()
		icon.item_id = id
		_at(icon,b,63,29,145,58)
		var cat := _label(_item_category(item),10,MUTED)
		_at(cat,b,14,43,68,20)
		var price := _label("$ "+_money(int(item.get("price",0))),16,GOLD,true)
		_at(price,b,14,86,118,24)
		var restriction := _label("",10,MUTED)
		restriction.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_at(restriction,b,124,87,86,21)
		_shop_buttons.append({"button":b,"item":item,"restriction":restriction,"price":price,"name":name_label})
	_refresh_shop()

func _refresh_shop() -> void:
	if not is_instance_valid(_shop_balance):
		return
	var money := int(state.get("money",0))
	var allowed := bool(state.get("buy_allowed",false))
	var player_team := str(state.get("team",team)).to_upper()
	_shop_balance.text = "$ "+_money(money)
	_shop_status.text = "点击装备购买   ·   B / ESC 关闭" if allowed else "当前无法购买：请在安全屋，或购买阶段返回己方出生区。"
	_shop_status.add_theme_color_override("font_color",MUTED if allowed else Color("e0a184"))
	for row in _shop_buttons:
		var item: Dictionary = row.item
		var item_team := str(item.get("team","both")).to_upper()
		var wrong_team := item_team in ["CT","T"] and item_team != player_team
		var effective_price := _shop_price(item)
		var enough := money >= effective_price
		row.price.text = "$ "+_money(effective_price)
		row.button.tooltip_text = "%s\n价格 $%d  ·  弹匣 %d  ·  伤害 %s" % [str(item.get("name",item.get("id",""))),effective_price,int(item.get("magazine",item.get("mag",0))),str(item.get("damage","—"))]
		row.button.disabled = not allowed or wrong_team or not enough
		var purchase_label := "升级头盔" if effective_price < int(item.get("price",0)) else "购买"
		row.restriction.text = (item_team+" 专属") if wrong_team else ("资金不足" if not enough else purchase_label if allowed else "不可购买")
		row.name.modulate.a = 0.46 if row.button.disabled else 1.0
		row.price.modulate.a = 0.46 if row.button.disabled else 1.0

func _shop_price(item: Dictionary) -> int:
	if str(item.get("id","")) in ["helmet","vesthelm"] and float(state.get("armor",0)) >= 100.0 and not bool(state.get("helmet",false)):
		return 350
	return int(item.get("price",0))

func toggle_inventory(s: Dictionary) -> void:
	if _modal_kind == "inventory":
		close_panels()
		return
	state = s.duplicate()
	var panel := _open_panel("战术背包","选择武器切换装备。准备好主武器、副武器与投掷物，再进入交火区。","inventory",860,550)
	_inventory_capacity = _label("",14,GOLD)
	_inventory_capacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_at(_inventory_capacity,panel,610,38,158,29)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_at(scroll,panel,30,130,800,347)
	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = 4
	_inventory_grid.add_theme_constant_override("h_separation",12)
	_inventory_grid.add_theme_constant_override("v_separation",12)
	_inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inventory_grid)
	_at(_label("1—3 切换武器    ·    关闭背包后按 4—8 投掷    ·    战斗会继续，请留意四周。",12,MUTED),panel,32,486,780,25)
	_populate_inventory()

func _populate_inventory() -> void:
	if not is_instance_valid(_inventory_grid):
		return
	for child in _inventory_grid.get_children():
		_inventory_grid.remove_child(child)
		child.queue_free()
	var inventory: Array = state.get("inventory",[])
	var active := int(state.get("active_slot",0))
	_last_inventory = str(inventory) + str(active)
	var capacity := int(state.get("capacity",12))
	_inventory_capacity.text = "%d / %d 格" % [int(state.get("used_slots",inventory.size())),capacity]
	for i in maxi(capacity,inventory.size()):
		var slot := i
		var item: Dictionary = inventory[i] if i < inventory.size() and inventory[i] is Dictionary else {}
		var equippable := not item.is_empty() and not str(item.get("id","")).is_empty() and (item.has("slot") or (i < 3 and str(item.get("category","")) != "gear"))
		var b := _button("",func(): equip_requested.emit(int(item.get("slot",slot))))
		b.custom_minimum_size = Vector2(187,105)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = not equippable
		_inventory_grid.add_child(b)
		if not item.is_empty() and not str(item.get("id","")).is_empty():
			_select_style(b,active == i)
			_at(_label(str(i+1).pad_zeros(2),11,GOLD if active == i else MUTED,true),b,13,9,154,20)
			_at(_label(str(item.get("name",item.get("id","装备"))),14),b,13,31,169,25)
			var icon := WeaponIconScript.new()
			icon.item_id = str(item.get("id",""))
			_at(icon,b,68,58,105,37)
			var count := int(item.get("count",1))
			var status := "已装备" if active == i else "点击装备"
			if not equippable:
				var key := _grenade_key(str(item.get("id","")))
				status = "%s 投掷 · ×%d" % [key,count] if not key.is_empty() else "E 交互" if str(item.get("id","")) == "c4" else "被动装备"
			_at(_label(status,11,GOLD if active == i else MUTED),b,13,77,165,21)
		else:
			_at(_label("空闲",12,Color("505b5d")),b,14,39,161,27)

func _grenade_key(id: String) -> String:
	match id:
		"hegrenade": return "4"
		"smokegrenade": return "5"
		"flashbang": return "6"
		"molotov", "incgrenade": return "7"
		"decoy": return "8"
	return ""

func _open_settings() -> void:
	_settings_controls.clear()
	var panel := _open_panel("设置与操作","选择作战视角，调整镜头、持枪与准星。修改即时生效。","settings",1080,736)
	_at(_label("操作",17,PAPER),panel,32,128,290,29)
	var controls := ["W A S D       移动","第一人称时按镜头朝向前进 / 横移","鼠标左 / 右键   射击 / 稳定瞄准","V                     切换作战视角","R                     更换弹匣","1—3 / 4—8      武器 / 投掷物","TAB / B          物品栏 / 商店","E                     安放 / 拆除炸弹","F / G               拾取 / 丢弃武器","滚轮                 俯视镜头范围","ESC                 暂停 / 关闭面板"]
	for i in controls.size():
		_at(_label(controls[i],12 if i == 1 else 13,MUTED),panel,34,169+i*34,307,29)
	_divider(panel,32,563,292)
	var note := _label("第一人称：鼠标控制水平与俯仰。\n打开面板可释放鼠标；关闭后继续操作。\n右侧可滚动，或点击数值直接输入。",12,MUTED)
	_at(note,panel,34,579,304,73)
	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_at(scroll,panel,370,128,676,523)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation",8)
	scroll.add_child(stack)
	var view_row := HBoxContainer.new()
	view_row.custom_minimum_size.y = 43
	stack.add_child(view_row)
	var view_label := _label("作战视角",15,PAPER)
	view_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_row.add_child(view_label)
	var view_mode := OptionButton.new()
	view_mode.name = "ViewMode"
	view_mode.custom_minimum_size = Vector2(234,40)
	view_mode.focus_mode = Control.FOCUS_NONE
	view_mode.add_theme_stylebox_override("normal",_style(Color(0.08,0.11,0.12,0.7),Color(1,1,1,0.11),1,4))
	view_mode.add_theme_stylebox_override("hover",_style(Color("293331"),GOLD,1,4))
	view_mode.add_theme_stylebox_override("pressed",_style(Color("384039"),GOLD,1,4))
	view_mode.add_item("俯视 · 2.5D",0)
	view_mode.add_item("第一人称",1)
	view_mode.select(1 if settings.view_mode == "first_person" else 0)
	view_mode.item_selected.connect(func(index: int): _change_setting("view_mode","first_person" if index == 1 else "top_down"))
	view_row.add_child(view_mode)
	_settings_controls["view_mode"] = {"option":view_mode}
	_setting_group(stack,"01  /  镜头与瞄准","FOV 为垂直视野；瞄准视野始终不大于基础视野。")
	_setting_slider(stack,"基础视野","fp_fov","°")
	_setting_slider(stack,"瞄准视野","fp_ads_fov","°")
	_setting_slider(stack,"鼠标灵敏度","fp_sensitivity","°/像素")
	_setting_slider(stack,"瞄准灵敏度倍率","fp_ads_sensitivity","×")
	_setting_toggle(stack,"反转鼠标 Y 轴","fp_invert_y")
	_setting_slider(stack,"鼠标平滑响应","fp_smoothing","/秒","0 为即时响应；数值越大，跟随越快")
	_setting_slider(stack,"最大上仰角","fp_pitch_up","°")
	_setting_slider(stack,"最大下俯角","fp_pitch_down","°")
	_setting_group(stack,"02  /  相机空间","裁剪范围决定相机可见距离。")
	_setting_slider(stack,"视点高度","fp_eye_height","m")
	_setting_slider(stack,"近裁剪距离","fp_near","m")
	_setting_slider(stack,"远裁剪距离","fp_far","m")
	_setting_group(stack,"03  /  持枪模型","持枪视野独立于场景视野；偏移以相机为基准。")
	_setting_slider(stack,"持枪视野","fp_viewmodel_fov","°")
	_setting_slider(stack,"水平偏移","fp_weapon_x","m","正值向右")
	_setting_slider(stack,"垂直偏移","fp_weapon_y","m","负值向下")
	_setting_slider(stack,"前后偏移","fp_weapon_z","m","负值向前，越小离相机越远")
	_setting_slider(stack,"模型缩放","fp_weapon_scale","×")
	_setting_group(stack,"04  /  运动与后坐力","将步行晃动、转向摆动或镜头上跳设为 0 可关闭。")
	_setting_slider(stack,"步行晃动幅度","fp_bob","m")
	_setting_slider(stack,"步行晃动速度","fp_bob_speed","rad/秒")
	_setting_slider(stack,"转向摆动强度","fp_sway","×")
	_setting_slider(stack,"单发镜头上跳","fp_recoil","°/发")
	_setting_slider(stack,"后坐力回正响应","fp_recoil_recovery","/秒")
	_setting_group(stack,"05  /  准星","准星固定在屏幕中心；动态准星反映当前散布。")
	_setting_slider(stack,"线段长度","fp_crosshair_length","px")
	_setting_slider(stack,"中心间距","fp_crosshair_gap","px")
	_setting_slider(stack,"线条宽度","fp_crosshair_width","px")
	_setting_toggle(stack,"动态准星","fp_crosshair_dynamic")
	_setting_toggle(stack,"显示中心点","fp_crosshair_dot")
	_setting_group(stack,"06  /  通用与俯视","音量与全屏通用，其余选项用于俯视视角。")
	_setting_slider(stack,"音量","volume","×","",[0.0,1.0,0.05])
	_setting_slider(stack,"俯视镜头范围","zoom","m","",[16.0,34.0,1.0])
	_setting_slider(stack,"俯视转向响应倍率","sensitivity","×","",[0.1,3.0,0.05])
	_setting_slider(stack,"俯视射击震动","shake","×","",[0.0,1.0,0.05])
	_setting_toggle(stack,"全屏显示","fullscreen")
	_divider(panel,32,670,1016)
	_at(_button("恢复第一人称默认值",_reset_first_person_settings),panel,370,683,266,40)
	_at(_button("完成",_close_panel_by_button,true),panel,868,683,178,40)

func _setting_group(parent: VBoxContainer, title: String, detail: String) -> void:
	var space := Control.new()
	space.custom_minimum_size.y = 9
	parent.add_child(space)
	parent.add_child(_label(title,15,GOLD))
	var subtitle := _label(detail,11,MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(subtitle)

func _setting_slider(parent: VBoxContainer, title: String, key: String, unit: String, detail: String = "", range_override: Array = []) -> void:
	var limits: Array = FirstPersonSettings.RANGES.get(key,range_override)
	var row := Control.new()
	row.name = key
	row.custom_minimum_size.y = 74 if not detail.is_empty() else 61
	parent.add_child(row)
	_at(_label(title,13,PAPER),row,0,0,405,23)
	var range_label := _label("%s — %s %s" % [str(limits[0]),str(limits[1]),unit],11,MUTED)
	range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor(range_label,1,0,1,0,-218,0,-5,23)
	row.add_child(range_label)
	var slider := HSlider.new()
	slider.min_value = float(limits[0])
	slider.max_value = float(limits[1])
	slider.step = float(limits[2])
	slider.value = float(settings[key])
	slider.focus_mode = Control.FOCUS_NONE
	slider.add_theme_stylebox_override("slider",_slider_style(Color(1,1,1,0.12)))
	slider.add_theme_stylebox_override("grabber_area",_slider_style(GOLD))
	slider.add_theme_stylebox_override("grabber_area_highlight",_slider_style(GOLD.lightened(0.2)))
	slider.value_changed.connect(func(value: float): _change_setting(key,value))
	_anchor(slider,0,0,1,0,0,29,-164,49)
	row.add_child(slider)
	var numeric := SpinBox.new()
	numeric.min_value = float(limits[0])
	numeric.max_value = float(limits[1])
	numeric.step = float(limits[2])
	numeric.value = float(settings[key])
	numeric.suffix = unit
	numeric.add_theme_font_size_override("font_size",12)
	numeric.get_line_edit().add_theme_font_size_override("font_size",12)
	var input_style := _style(Color(0.05,0.08,0.09,0.9),Color(1,1,1,0.13),1,3)
	input_style.content_margin_left = 8
	input_style.content_margin_right = 8
	input_style.content_margin_top = 4
	input_style.content_margin_bottom = 4
	numeric.get_line_edit().add_theme_stylebox_override("normal",input_style)
	var focus_style := input_style.duplicate() as StyleBoxFlat
	focus_style.bg_color = Color.TRANSPARENT
	focus_style.border_color = GOLD
	numeric.get_line_edit().add_theme_stylebox_override("focus",focus_style)
	numeric.value_changed.connect(func(value: float): _change_setting(key,value))
	_anchor(numeric,1,0,1,0,-150,25,-5,55)
	row.add_child(numeric)
	if not detail.is_empty():
		_at(_label(detail,10,MUTED),row,0,55,490,18)
	_settings_controls[key] = {"slider":slider,"numeric":numeric}

func _setting_toggle(parent: VBoxContainer, title: String, key: String) -> void:
	var toggle := CheckButton.new()
	toggle.name = key
	toggle.text = title
	toggle.custom_minimum_size.y = 39
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.button_pressed = bool(settings[key])
	toggle.toggled.connect(func(value: bool): _change_setting(key,value))
	parent.add_child(toggle)
	_settings_controls[key] = {"toggle":toggle}

func _change_setting(key: String, value: Variant) -> void:
	settings[key] = value
	settings = FirstPersonSettings.sanitize(settings)
	_refresh_controls_hint()
	_refresh_setting_controls()
	settings_changed.emit(settings.duplicate(true))

func _refresh_setting_controls() -> void:
	if _modal_kind != "settings":
		return
	for key in _settings_controls:
		var controls: Dictionary = _settings_controls[key]
		if controls.has("slider") and is_instance_valid(controls.slider):
			controls.slider.set_value_no_signal(float(settings[key]))
			controls.numeric.set_value_no_signal(float(settings[key]))
		elif controls.has("toggle") and is_instance_valid(controls.toggle):
			controls.toggle.set_pressed_no_signal(bool(settings[key]))
		elif controls.has("option") and is_instance_valid(controls.option):
			controls.option.select(1 if settings.view_mode == "first_person" else 0)

func _reset_first_person_settings() -> void:
	for key in FirstPersonSettings.DEFAULTS:
		if str(key).begins_with("fp_"):
			settings[key] = FirstPersonSettings.DEFAULTS[key]
	_refresh_setting_controls()
	settings_changed.emit(settings.duplicate(true))

func show_pause() -> void:
	_paused_context = true
	var panel := _open_panel("行动暂停","喘口气，整理思路。","pause",490,419)
	_at(_button("继续行动",func(): close_panels(); action_requested.emit("resume"),true),panel,32,132,426,51)
	_at(_button("设置与操作",_open_settings),panel,32,195,426,46)
	_at(_button("重新开始",func(): close_panels(); action_requested.emit("restart")),panel,32,252,426,46)
	_at(_button("返回主界面",func(): close_panels(); action_requested.emit("menu")),panel,32,309,426,46)

func close_panels() -> void:
	if is_instance_valid(modal):
		modal.hide()
	_modal_kind = ""
	_paused_context = false
	if is_instance_valid(menu) and not menu.visible and not (is_instance_valid(map_preview) and map_preview.visible):
		if is_instance_valid(overlay):
			overlay.enabled = true

func _close_panel_by_button() -> void:
	var should_resume := _paused_context
	close_panels()
	if should_resume:
		action_requested.emit("resume")

func is_modal_open() -> bool:
	return _modal_kind != ""

func toast(message: String) -> void:
	if not is_instance_valid(_toast_label):
		return
	if is_instance_valid(_toast_tween):
		_toast_tween.kill()
	_toast_label.text = message
	_toast_label.show()
	_toast_label.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.5)
	_toast_tween.tween_property(_toast_label,"modulate:a",0.0,0.5)
	_toast_tween.tween_callback(_toast_label.hide)

func show_round_result(title: String, subtitle: String) -> void:
	if is_instance_valid(_round_tween):
		_round_tween.kill()
	_result_title.text = title
	_result_subtitle.text = subtitle
	_round_panel.show()
	_round_panel.modulate.a = 0.0
	_round_tween = create_tween()
	_round_tween.tween_property(_round_panel,"modulate:a",1.0,0.25)
	_round_tween.tween_interval(4.0)
	_round_tween.tween_property(_round_panel,"modulate:a",0.0,0.4)
	_round_tween.tween_callback(_round_panel.hide)

func confirm_hit() -> void:
	if is_instance_valid(overlay):
		overlay.confirm_hit()
