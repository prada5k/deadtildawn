extends AudioStreamPlayer
## One car's sound in the replay, synthesized live (no recordings): its
## engine from the replay's rpm and throttle, tire roar and wind with its
## speed, a squeal near the grip limit. main.gd (update_audio) sets the
## inputs every frame; _process fills the generator's buffer, sample by sample.
##
## The engine, physically: a four-stroke fires each cylinder once every two
## revolutions, so the firing frequency is f = rpm / 60 x cylinders / 2 (the
## DX's four at 6000 rpm: 200 Hz; the 280Z's straight six: 300 Hz). Each
## firing is a sharp pressure pulse that dies away down the exhaust: a
## decaying pulse repeated at f is rich in harmonics, which is why an engine
## buzzes instead of humming like a sine. On top: a little of f/2 (no two
## cylinders are quite even), noise riding each pulse (intake + exhaust rasp,
## more on the gas), soft clipping (grit on the gas), and a lowpass that
## opens with the throttle (off the gas it goes dull and burbly).

const RATE := 16000.0
const TABLE := 256

var rpm := 900.0
var throttle := 0.0
var speed := 0.0                 # m/s: tire roar and wind
var squeal := 0.0                # 0..1: tires at the limit
var alive := 1.0                 # 0 = engine off (a crash)
var pan := 0.0                   # -1 left .. +1 right (split screen: him left, Faba right)
var gain := 1.0                  # 0 = silent (the tape's paused)
var time_scale := 1.0            # slow-mo drops the pitch, like a slowed tape
var cylinders := 4

var _pb: AudioStreamGeneratorPlayback
var _f := 30.0                   # firing frequency, gliding toward the target (Hz)
var _phase := 0.0                # 0..1 through one firing
var _half := 0.0
var _jit := 1.0
var _amp := 0.0
var _gain := 0.0
var _lp := 0.0
var _road := 0.0
var _wind := 0.0
var _sq := 0.0
var _seed := 12345
var _pulse := PackedFloat32Array()   # one firing's pressure pulse, and the rasp's envelope
var _rasp := PackedFloat32Array()


func _ready() -> void:
	for i in TABLE:
		var p := float(i) / TABLE
		_pulse.append(exp(-p * 7.0) - (1.0 - exp(-7.0)) / 7.0)   # minus its mean: no DC
		_rasp.append(exp(-p * 4.0))
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.1
	stream = gen
	play()
	_pb = get_stream_playback() as AudioStreamGeneratorPlayback


## A cheap noise source (a linear congruential generator): -1..1.
func _noise() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return _seed / 1073741823.5 - 1.0


func _process(_delta: float) -> void:
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	var f_target := maxf(rpm, 300.0) / 60.0 * cylinders / 2.0 * time_scale
	var k_f := 1.0 - exp(-1.0 / (RATE * 0.025))      # the pitch glides over ~25 ms
	var k_a := 1.0 - exp(-1.0 / (RATE * 0.06))
	var amp_target := alive * (0.6 + 0.4 * throttle)
	var lp_k := 0.2 + 0.3 * throttle
	var drive := 1.3 + 2.2 * throttle
	var rasp_amt := 0.12 + 0.5 * throttle
	var half_amt := 0.1 * (1.0 - 0.6 * throttle)       # the uneven burble: most off the gas
	var road_amp := clampf(speed / 40.0, 0.0, 1.3) * 0.5
	var wind_amp := pow(clampf(speed / 45.0, 0.0, 1.3), 2.0) * 0.14
	var sq_amp := squeal * 0.13
	var sq_f := 1050.0 * time_scale / RATE
	var left := clampf(1.0 - pan, 0.0, 1.0) * 0.5
	var right := clampf(1.0 + pan, 0.0, 1.0) * 0.5
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		_f += (f_target - _f) * k_f
		_amp += (amp_target - _amp) * k_a
		_gain += (gain - _gain) * k_a
		_phase += _f / RATE
		if _phase >= 1.0:
			_phase -= 1.0
			_jit = 0.85 + 0.3 * (_noise() * 0.5 + 0.5)   # no two firings quite alike
		_half = fmod(_half + _f * 0.5 / RATE, 1.0)
		var at := int(_phase * TABLE)
		var w := _noise()
		var x := _pulse[at] * _jit + w * _rasp[at] * rasp_amt + sin(TAU * _half) * half_amt
		x = tanh(x * drive)
		_lp += (x - _lp) * lp_k
		_road += (w - _road) * 0.04                      # tires on asphalt: a low roar
		_wind += (w - _wind) * 0.3
		var s := _lp * _amp + _road * road_amp + (w - _wind) * wind_amp
		if sq_amp > 0.001:
			_sq = fmod(_sq + sq_f * (1.0 + _road * 2.0), 1.0)   # a squeal that wanders
			s += sin(TAU * _sq) * sq_amp
		s *= _gain
		buf[i] = Vector2(s * left, s * right)
	_pb.push_buffer(buf)


## Cylinders by the car's name (the replay's car names; default a four).
static func cylinders_for(car_name: String) -> int:
	for key in ["280Z", "370Z", "R33", "GT-R", "Supra", "E36", "E46"]:
		if car_name.contains(key):
			return 6
	for key in ["Mustang", "Camaro", "Corvette"]:
		if car_name.contains(key):
			return 8
	return 4
