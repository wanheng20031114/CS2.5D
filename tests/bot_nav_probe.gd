extends SceneTree

# Independent regression probe: compares the isolated route harness to the
# production bot controller on the same native CT ramp. Does not modify gameplay.
var game: Node3D
var cases: Array = []
var frame := 0
var ready := false
var finishing := false
var results: Array = []
var full_mode := false
var reverse_mode := false
var fixture_mode := false

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.rng.seed = 800
	game.start_game("T", "bomb", 1)
	full_mode = "--full" in OS.get_cmdline_user_args()
	if full_mode:
		var row := {"name":"production_main","controller":"main_full","units":[]}
		for actor in game.actors:
			if actor.team == "CT": row.units.append({"body":actor,"path":[],"index":0,"checkpoint":actor.position,"stagnant":0,"done":false,"trace":[]})
		cases.append(row)
		game.set_physics_process(true)
		ready = true
		return
	game.set_physics_process(false)
	for actor in game.actors: actor.queue_free()
	game.actors.clear()
	await physics_frame
	await physics_frame
	fixture_mode = "--fixtures" in OS.get_cmdline_user_args()
	if fixture_mode:
		_make_fixtures()
		ready=true
		return
	reverse_mode = "--reverse" in OS.get_cmdline_user_args()
	if reverse_mode:
		game.mode="practice"
		for site in ["A","B"]:
			_make_case("reference_from_"+site,"reference",false,false,1,false,site)
			_make_case("continuous_from_"+site,"continuous",false,true,1,false,site)
			_make_case("main_from_"+site,"main",false,true,1,false,site)
		ready=true
		return
	_make_case("reference_immediate", "reference", false, false, 1, false)
	_make_case("reference_settled", "reference", true, false, 1, false)
	_make_case("continuous_settled", "continuous", true, false, 1, false)
	_make_case("continuous_rotated", "continuous", true, true, 1, false)
	_make_case("main_immediate", "main", false, true, 1, false)
	_make_case("main_settled", "main", true, true, 1, false)
	_make_case("main_settled_fixed_yaw", "main", true, false, 1, false)
	_make_case("main_squad", "main", true, true, 5, true)
	_make_case("main_squad_no_separation", "main", true, true, 5, false)
	ready = true

func _make_case(label: String, controller: String, settle: bool, rotate: bool, count: int, squad: bool, source_site: String="") -> void:
	var row := {"name":label,"controller":controller,"settle":settle,"rotate":rotate,"squad":squad,"units":[],"done":false,"expected_traversal":true}
	for i in count:
		var actor = load("res://scripts/combatant.gd").new()
		game.add_child(actor)
		actor.setup("CT", false, "hkp2000")
		actor.display_name = label + "_" + str(i)
		actor.position = game.world.spawn_points["CT"][i] + (Vector3.UP * 0.12 if settle else Vector3.ZERO)
		actor.rotation.y = 0
		actor.goal = game.world.sites["A" if i % 2 == 0 else "B"]
		if not source_site.is_empty():
			actor.position=game.world.sites[source_site]+Vector3.UP*.08
			actor.goal=game.world.sites["B" if source_site=="A" else "A"]
		actor.think_timer = i * 0.11
		var path: Array = game.world.find_path(actor.position, actor.goal)
		row.units.append({"body":actor,"path":path,"index":0,"checkpoint":actor.position,"stagnant":0,"done":false,"trace":[]})
	cases.append(row)

func _box(position_value:Vector3,size:Vector3) -> void:
	var body:=StaticBody3D.new();body.position=position_value;body.collision_layer=1
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box
	body.add_child(shape);game.add_child(body)

func _make_fixtures() -> void:
	_box(Vector3(206,-.5,50),Vector3(24,1,80))
	var i:=0
	for height in [.32,.46,.50,.60,.90,1.8]:
		var z:float=20+i*8
		_box(Vector3(206,float(height)/2,z),Vector3(2,float(height),5))
		for controller in ["actual"]:
			_make_case(controller+"_wall_"+str(height),"continuous",false,false,1,false)
			cases[-1].expected_traversal=height<=.46
			var u:Dictionary=cases[-1].units[0]
			u.body.position=Vector3(202,.1,z)
			u.body.goal=Vector3(210,0,z)
			u.path=[u.body.goal];u.checkpoint=u.body.position
		i+=1
	for fixture in [{"name":"low_ceiling_block","height":.32,"ceiling":1.85,"z":68.0},{"name":"low_ceiling_pass","height":.10,"ceiling":1.90,"z":76.0}]:
		_box(Vector3(206,fixture.height/2,fixture.z),Vector3(2,fixture.height,5))
		_box(Vector3(206,fixture.ceiling+.25,fixture.z),Vector3(6,.5,5))
		for controller in ["actual"]:
			_make_case(controller+"_"+fixture.name,"continuous",false,false,1,false)
			cases[-1].expected_traversal=fixture.name.ends_with("pass")
			var u:Dictionary=cases[-1].units[0]
			u.body.position=Vector3(202,.1,fixture.z);u.body.goal=Vector3(210,0,fixture.z)
			u.path=[u.body.goal];u.checkpoint=u.body.position

func _physics_process(delta: float) -> bool:
	if not ready or finishing: return false
	frame += 1
	if full_mode:
		_observe_full()
		return false
	var remaining := 0
	for c in cases:
		if c.done: continue
		var live_frame: int = frame - (1200 if c.settle else 0)
		game.phase = "buy" if live_frame < 0 else "live"
		var squad: Array = []
		for u in c.units:
			if not u.done: squad.append(u.body)
		for u in c.units:
			if u.done: continue
			var body: CharacterBody3D = u.body
			if c.squad: game.actors.assign(squad)
			else: game.actors.assign([body])
			if c.controller == "main":
				game._bot_tick(body, delta)
				if not c.rotate: body.rotation.y = 0
			elif live_frame < 0:
				body.move_direction(Vector3.ZERO, delta)
			else:
				var path: Array = u.path
				if c.controller == "reference":
					if u.index < path.size():
						var direction: Vector3 = path[u.index] - body.position
						direction.y = 0
						if direction.length() < 0.18:
							u.index += 1
						else: body.move_direction(direction.normalized(), delta)
				else:
					while u.index < path.size() and Vector2(body.position.x-path[u.index].x,body.position.z-path[u.index].z).length() < 0.18:
						u.index += 1
					var direction := Vector3.ZERO
					if u.index < path.size():
						direction = path[u.index] - body.position
						direction.y = 0
						direction = direction.normalized()
						if c.rotate: body.rotation.y = lerp_angle(body.rotation.y,atan2(-direction.x,-direction.z),1.0-exp(-delta*8))
					body.move_direction(direction, delta)
			if live_frame <= 0: continue
			if live_frame % 120 == 0:
				var progress: float = body.position.distance_to(u.checkpoint)
				u.stagnant = int(u.stagnant) + 120 if progress < 0.3 else 0
				u.checkpoint = body.position
				u.trace.append({"live_seconds":live_frame/60.0,"position":_v(body.position),"velocity":_v(body.velocity),"floor":body.is_on_floor(),"path_size":body.path.size(),"reference_index":u.index})
			var reached: bool = body.position.distance_to(body.goal) < 2.2
			if reached or u.stagnant >= 240 or live_frame >= 3000:
				_finish_unit(c, u, reached, live_frame)
		var pending := false
		for u in c.units: pending = pending or not u.done
		c.done = not pending
		if pending: remaining += 1
	if remaining == 0:
		finishing = true
		_finish.call_deferred()
	return false

func _observe_full() -> void:
	var c: Dictionary=cases[0]
	var remaining:=0
	for u in c.units:
		if u.done: continue
		var body: CharacterBody3D=u.body
		if not is_instance_valid(body):u.done=true;continue
		remaining+=1
		if frame%60==0:
			var progress:float=body.position.distance_to(u.checkpoint)
			u.stagnant=int(u.stagnant)+60 if progress<.25 else 0
			u.checkpoint=body.position
			var next:Vector3=body.path[0] if not body.path.is_empty() else body.goal
			u.trace.append({"seconds":frame/60.0,"position":_v(body.position),"velocity":_v(body.velocity),"floor":body.is_on_floor(),"path_size":body.path.size(),"waypoint":_v(next),"goal":_v(body.goal),"target":is_instance_valid(body.target),"alive":body.alive,"phase":game.phase})
		var navigation_stalled:bool=u.stagnant>=240 and not is_instance_valid(body.target) and body.position.distance_to(body.goal)>3.0
		if frame>1300 and navigation_stalled or frame>=5400:
			_finish_unit(c,u,not navigation_stalled,frame)
	if remaining==0 or frame>=5401:
		finishing=true
		_finish.call_deferred()

func _finish_unit(c: Dictionary,u: Dictionary,passed: bool,live_frame: int) -> void:
	var body: CharacterBody3D = u.body
	var waypoint: Vector3 = body.path[0] if not body.path.is_empty() else (u.path[mini(u.index,u.path.size()-1)] if not u.path.is_empty() else body.goal)
	var hits: Array = []
	for i in body.get_slide_collision_count():
		var hit := body.get_slide_collision(i)
		hits.append({"collider":str(hit.get_collider().name),"normal":_v(hit.get_normal()),"position":_v(hit.get_position())})
	var output := {"case":c.name,"unit":body.display_name,"controller":c.controller,"passed":passed,"live_seconds":live_frame/60.0,"position":_v(body.position),"velocity":_v(body.velocity),"on_floor":body.is_on_floor(),"rotation_y":body.rotation.y,"waypoint":_v(waypoint),"goal":_v(body.goal),"remaining_path":body.path.size(),"reference_index":u.index,"slide_hits":hits,"step_probes":_step_snapshot(body,waypoint),"trace":u.trace}
	results.append(output)
	output["expected_traversal"]=c.get("expected_traversal",true)
	output["expectation_met"]=passed==c.get("expected_traversal",true)
	u.done = true
	print("PROBE ", c.name, " ", body.display_name," ","PASS" if passed else "BLOCKED_EXPECTED" if output.expectation_met else "STUCK"," ",body.position," next=",waypoint," on_floor=",body.is_on_floor()," seconds=",live_frame/60.0)

func _step_snapshot(body: CharacterBody3D,waypoint: Vector3) -> Array:
	var direction := waypoint-body.position
	direction.y=0
	direction=direction.normalized()
	var space := game.get_world_3d().direct_space_state
	var shape: CollisionShape3D
	for child in body.get_children():
		if child is CollisionShape3D: shape=child;break
	var output: Array = []
	for ahead in [0.37+5.7/60,0.22+5.7/60]:
		var sample := body.position+direction*float(ahead)
		var ray := PhysicsRayQueryParameters3D.create(sample+Vector3.UP*.47,sample-Vector3.UP*.14,5,[body.get_rid()])
		var hit := space.intersect_ray(ray)
		if hit.is_empty(): output.append({"ahead":ahead,"hit":false});continue
		var rise: float=hit.position.y-body.position.y+.022
		var q:=PhysicsShapeQueryParameters3D.new()
		q.shape=shape.shape
		q.transform=shape.global_transform.translated(Vector3.UP*rise)
		q.collision_mask=5
		q.exclude=[body.get_rid()]
		q.margin=.001
		var contacts: Array=[]
		for overlap in space.intersect_shape(q,8): contacts.append(str(overlap.collider.name))
		output.append({"ahead":ahead,"hit":true,"position":_v(hit.position),"normal":_v(hit.normal),"rise":rise,"headroom_contacts":contacts,"raised_motion_blocked":body.test_move(body.global_transform.translated(Vector3.UP*rise),direction*(5.7/60))})
	for distance in [44.0/3600.0,5.7/60.0]:
		var candidates:Array=[]
		for i in range(1,24):
			var rise:float=i*.02
			var q:=PhysicsShapeQueryParameters3D.new()
			q.shape=shape.shape;q.transform=shape.global_transform.translated(Vector3.UP*rise)
			q.collision_mask=5;q.exclude=[body.get_rid()];q.margin=.001
			var overlap:bool=not space.intersect_shape(q,1).is_empty()
			var collision:=KinematicCollision3D.new()
			var blocked:bool=body.test_move(body.global_transform.translated(Vector3.UP*rise),direction*float(distance),collision)
			var contacts:Array=[]
			if blocked:
				for k in collision.get_collision_count():contacts.append({"normal":_v(collision.get_normal(k)),"point":_v(collision.get_position(k)),"collider":str(collision.get_collider(k).name)})
			candidates.append({"rise":rise,"overlap":overlap,"motion_blocked":blocked,"contacts":contacts,"travel":_v(collision.get_travel()) if blocked else [],"remainder":_v(collision.get_remainder()) if blocked else []})
		output.append({"sweep_distance":distance,"rise_candidates":candidates})
	var samples:Array=[]
	for i in range(1,15):
		var ahead:float=i*.05
		var sample:=body.position+direction*ahead
		var ray:=PhysicsRayQueryParameters3D.create(sample+Vector3.UP*.6,sample-Vector3.UP*.2,5,[body.get_rid()])
		var hit:=space.intersect_ray(ray)
		if not hit.is_empty():samples.append({"ahead":ahead,"height":hit.position.y,"rise":hit.position.y-body.position.y+.022,"normal":_v(hit.normal)})
	output.append({"dense_forward_rays":samples})
	return output

func _v(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _finish() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var file := FileAccess.open("res://artifacts/bot_nav_probe"+("_full" if full_mode else "_reverse" if reverse_mode else "_fixtures" if fixture_mode else "")+".json",FileAccess.WRITE)
	var passed:=not results.is_empty()
	for row in results:passed=passed and row.expectation_met
	file.store_string(JSON.stringify({"frames":frame,"passed":passed,"controller":"res://scripts/combatant.gd","controller_sha256":FileAccess.get_sha256("res://scripts/combatant.gd"),"results":results},"  "))
	file.close()
	game.actors.clear()
	_stop_audio(game)
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(.15).timeout
	quit(0 if passed else 1)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer: node.stop();node.stream=null
	for child in node.get_children(): _stop_audio(child)
