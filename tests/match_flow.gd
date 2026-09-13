extends SceneTree
class SilentSimulationAudio extends Node:
	func play(_kind: String, _loudness: float = 1.0, _pitch: float = 1.0) -> void:
		pass
var game: Node3D
var frame := 0
var recorded_round := 0
var summaries: Array = []
var finishing := false
var saw_combat := false
var saw_plant := false
var damage_observed := false
var controlled_side := "CT"

func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child.call_deferred(game)

func _physics_process(_delta: float) -> bool:
	if finishing: return false
	frame += 1
	if frame == 5:
		# Accelerated simulation is not paced to the audio mixer clock. Use a
		# test-local silent sink; rendered input QA exercises the actual audio.
		game.sound.queue_free()
		game.sound = SilentSimulationAudio.new()
		game.add_child(game.sound)
		controlled_side = "T" if "--t" in OS.get_cmdline_user_args() else "CT"
		game.rng.seed = 800
		game.start_game(controlled_side,"bomb",1)
	if frame > 5:
		saw_plant = saw_plant or game.planted
		for actor in game.actors:
			saw_combat = saw_combat or is_instance_valid(actor.target)
			damage_observed = damage_observed or actor.health < 99
	if frame > 5 and game.running and game.round_number != recorded_round:
		recorded_round = game.round_number
		print("ROUND ",recorded_round," score ",game.score_ct,"-",game.score_t)
	if frame % 1200 == 0 and frame > 5:
		var row := {"seconds":frame/60,"round":game.round_number,"phase":game.phase,"ct":game._alive_count("CT"),"t":game._alive_count("T"),"score_ct":game.score_ct,"score_t":game.score_t,"bomb":game.planted}
		var units: Array = []
		for a in game.actors: units.append({"team":a.team,"alive":a.alive,"position":[a.position.x,a.position.y,a.position.z],"path":a.path.size(),"target":is_instance_valid(a.target)})
		row["units"] = units
		summaries.append(row)
		print(JSON.stringify(row))
	if frame >= 12600:
		DirAccess.make_dir_recursive_absolute("res://artifacts")
		var file := FileAccess.open("res://artifacts/match_flow_"+controlled_side.to_lower()+".json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"side":controlled_side,"saw_combat":saw_combat,"saw_damage":damage_observed,"saw_plant":saw_plant,"round":game.round_number,"snapshots":summaries},"  "))
		var passed: bool = game.round_number >= 2 and game.score_ct+game.score_t>=1 and saw_combat and damage_observed
		print("MATCH_FLOW_", "PASS" if passed else "FAIL")
		finishing = true
		_finish.call_deferred(passed)
	return false

func _finish(passed: bool) -> void:
	Engine.max_fps = 60
	game.set_physics_process(false)
	_stop_audio(game)
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.15).timeout
	quit(0 if passed else 1)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		node.stop()
		node.stream = null
	for child in node.get_children(): _stop_audio(child)
