extends Node

var streams: Dictionary = {}
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 92137
	for kind in ["rifle", "pistol", "sniper", "silenced", "reload", "hit", "step", "empty", "bomb", "explode", "buy"]:
		streams[kind] = _synthesize(kind)

func play(kind: String, loudness: float = 1.0, pitch: float = 1.0) -> void:
	if not streams.has(kind):
		kind = "rifle"
	var voice := AudioStreamPlayer.new()
	voice.stream = streams[kind]
	voice.volume_db = linear_to_db(clampf(loudness, 0.001, 1.0)) - 9.0
	voice.pitch_scale = pitch
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()

func _synthesize(kind: String) -> AudioStreamWAV:
	var duration: float = {"rifle":0.22,"pistol":0.16,"sniper":0.5,"silenced":0.12,"reload":0.26,"hit":0.075,"step":0.06,"empty":0.05,"bomb":0.12,"explode":0.85,"buy":0.16}.get(kind,0.2)
	var sample_rate := 22050
	var count := int(duration * sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var filtered := 0.0
	for i in range(count):
		var t := float(i) / sample_rate
		var env := exp(-t * 24.0) * minf(1.0,t*2500.0)
		var noise := rng.randf_range(-1,1)
		filtered = lerpf(filtered,noise,0.16)
		var value := 0.0
		match kind:
			"rifle": value = (noise * 0.5 + sin(t*TAU*(110.0-80*t))*0.65 + filtered)*env
			"pistol": value = (noise * 0.6 + sin(t*TAU*145.0)*0.55)*env
			"sniper": value = (noise*0.45+filtered+sin(t*TAU*65.0)*0.8)*exp(-t*10.0)
			"silenced": value = (filtered + sin(t*TAU*240.0)*0.55)*env
			"reload": value = noise * pow(maxf(0.0,sin(t*TAU*9.0)),12.0)*exp(-t*7.0)*0.45
			"hit": value = sin(t*TAU*1100.0)*env*0.4
			"step": value = filtered * env * 1.6
			"empty": value = noise*env*0.3
			"bomb": value = sin(t*TAU*1500.0)*sin(PI*t/duration)*0.3
			"explode": value = (filtered*1.5+sin(t*TAU*42.0)*0.5)*exp(-t*6.0)
			"buy": value = (sin(t*TAU*740.0)+sin(t*TAU*1108.0))*exp(-t*18.0)*0.2
		bytes.encode_s16(i*2, int(clampf(value,-1,1)*27000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = bytes
	return stream
