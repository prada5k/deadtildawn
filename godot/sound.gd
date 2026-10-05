extends Node
## Sound for the whole game (Spire), made in code: no audio files. Each effect
## is synthesized once at start into an AudioStreamWAV (tones, filtered
## noise, envelopes) and played from a small pool. Every button in the game
## clicks by itself (node_added): gaffer-tape buttons thunk, camcorder (OSD)
## buttons beep, the tool chest drawers slide, everything else clicks. The
## race's engines are live synths fed the replay's rpm (widgets/car_audio.gd).
##
## Autoload "Sound":  Sound.play("cash")   Sound.loop("hiss") / Sound.stop("hiss")
## Sound.muted = true  (code "mute", saved).

const RATE := 22050
const POOL := 10
const MASTER_DB := -4.0

var muted := false:
	set(m):
		muted = m
		AudioServer.set_bus_mute(0, m)

var sounds := {}                 # name -> AudioStreamWAV
var players: Array[AudioStreamPlayer] = []
var loops := {}                  # name -> its own AudioStreamPlayer
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 7
	AudioServer.set_bus_volume_db(0, MASTER_DB)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	build()
	get_tree().node_added.connect(_on_node_added)


## A one-shot. pitch varies a little each time so repeats don't sound canned.
func play(name: String, db := 0.0, pitch := 1.0) -> void:
	if not sounds.has(name):
		return
	var p := players[0]
	for q in players:
		if not q.playing:
			p = q
			break
	p.stream = sounds[name]
	p.volume_db = db
	p.pitch_scale = pitch * rng.randf_range(0.97, 1.03)
	p.play()


## A looping sound (tape hiss, static) until stop(name).
func loop(name: String, db := 0.0) -> void:
	if not sounds.has(name):
		return
	if not loops.has(name):
		var p := AudioStreamPlayer.new()
		add_child(p)
		p.stream = sounds[name]
		loops[name] = p
	loops[name].volume_db = db
	if not loops[name].playing:
		loops[name].play()


func stop(name: String) -> void:
	if loops.has(name):
		loops[name].stop()


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		(n as BaseButton).pressed.connect(_on_button.bind(n))


func _on_button(b: BaseButton) -> void:
	var v := str(b.theme_type_variation)
	if v.begins_with("Osd"):
		play("osd", -6.0)
	elif v.begins_with("Gaff"):
		play("tape")
	elif v.begins_with("Drawer"):
		return                                   # the nav bar: silent (Spire)
	else:
		play("click", -4.0)


# ------------------------------------------------------------------ synthesis

func build() -> void:
	sounds["click"] = wav(mix([noise(0.03, 0.004, 0.6), tone(1900.0, 0.03, 0.01, 0.3)]))
	sounds["osd"] = wav(square(2400.0, 0.06, 0.25))                     # camcorder menu beep
	sounds["tape"] = wav(mix([tone(150.0, 0.12, 0.05, 0.7), noise(0.08, 0.025, 0.15, 0.5)]))
	sounds["stamp"] = wav(mix([tone(70.0, 0.25, 0.09, 0.9), noise(0.08, 0.03, 0.2, 0.6)]))
	sounds["cash"] = wav(mix([noise(0.1, 0.04, 0.5, 0.35), delay(bell(1568.0, 0.6, 0.45), 0.06),
		delay(bell(2093.0, 0.7, 0.4), 0.16)]))                         # the register: cha-ching
	sounds["beep"] = wav(square(880.0, 0.14, 0.22))                     # the count: 3, 2, 1
	sounds["go"] = wav(square(1760.0, 0.42, 0.22))
	sounds["horn"] = wav(mix([square(350.0, 0.55, 0.16), square(440.0, 0.55, 0.16)]))   # the spotters, at the line
	sounds["honk_long"] = wav(mix([square(330.0, 1.6, 0.2), square(415.0, 1.6, 0.2)]))  # jorge mode: the sore loser
	sounds["honk_angry"] = wav(mix([square(330.0, 0.16, 0.2), square(415.0, 0.16, 0.2),
		delay(mix([square(330.0, 0.16, 0.2), square(415.0, 0.16, 0.2)]), 0.24),
		delay(mix([square(330.0, 0.5, 0.2), square(415.0, 0.5, 0.2)]), 0.48)]))   # honk honk HOOONK
	sounds["squelch"] = wav(mix([radio_noise(0.2), delay(square(1150.0, 0.07, 0.12), 0.21)]))   # radio + roger beep
	sounds["crash"] = wav(crash())
	sounds["box"] = wav(mix([noise(0.09, 0.03, 0.25, 0.6), delay(noise(0.07, 0.025, 0.25, 0.6), 0.1),
		delay(noise(0.3, 0.12, 0.5, 0.7), 0.22)]))                    # shake, shake, rip
	sounds["print"] = wav(printer(0.1))                                 # one dot-matrix line
	# The dyno sheet's verdict: a junk roll (under 20%) gets the sad trombone,
	# anything better a little rising chime
	sounds["bummer"] = wav(mix([brass(196.0, 0.32, 0.0), delay(brass(185.0, 0.32, 0.0), 0.36),
		delay(brass(174.6, 0.32, 0.0), 0.72), delay(brass(164.8, 1.1, 6.0), 1.08)]))
	sounds["decent"] = wav(mix([bell(1046.5, 0.5, 0.3), delay(bell(1318.5, 0.5, 0.3), 0.1),
		delay(bell(1568.0, 0.8, 0.35), 0.2)]))
	sounds["text"] = wav(mix([tone(1318.0, 0.09, 0.05, 0.35), delay(tone(1760.0, 0.16, 0.08, 0.35), 0.08)]))
	sounds["hiss"] = looped(noise(2.0, 99.0, 0.35, 0.12))               # VHS tape hiss
	sounds["static"] = looped(mix([noise(1.5, 99.0, 0.9, 0.35), crackle(1.5)]))


## A sine with a fast attack and an exponential decay (tau, s).
func tone(f: float, dur: float, tau: float, amp: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	for i in out.size():
		var t := float(i) / RATE
		out[i] = sin(TAU * f * t) * amp * exp(-t / tau) * minf(t * 400.0, 1.0)
	return out


## A bell: a tone with inharmonic partials that ring on.
func bell(f: float, dur: float, amp: float) -> PackedFloat32Array:
	return mix([tone(f, dur, 0.25, amp), tone(f * 2.76, dur, 0.12, amp * 0.4), tone(f * 5.4, dur, 0.05, amp * 0.25)])


## A muted trombone note: a sawtooth's first harmonics (1/n), swelling in
## and out like a breath ("wah"), with vibrato (Hz, 0 = none) on a held one.
func brass(f: float, dur: float, vibrato: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	var ph := 0.0
	for i in out.size():
		var t := float(i) / RATE
		ph += f * (1.0 + (0.012 * sin(TAU * vibrato * t) if vibrato > 0.0 else 0.0)) / RATE
		var x := 0.0
		for h in range(1, 7):
			x += sin(TAU * ph * h) / h
		var env := sin(PI * clampf(t / dur, 0.0, 1.0)) * (0.7 + 0.3 * minf(t * 8.0, 1.0))
		out[i] = x * 0.22 * env
	return out


## A square wave (beeps), flat with soft ends.
func square(f: float, dur: float, amp: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	for i in out.size():
		var t := float(i) / RATE
		var env := minf(t * 300.0, 1.0) * minf((dur - t) * 200.0, 1.0)
		out[i] = (1.0 if fmod(t * f, 1.0) < 0.5 else -1.0) * amp * env
	return out


## White noise through a one-pole lowpass (lp: 0 = dull .. 1 = bright),
## decaying with tau (99 = no decay).
func noise(dur: float, tau: float, lp: float, amp := 0.4) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	var y := 0.0
	for i in out.size():
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * lp
		out[i] = y * amp * (1.0 if tau >= 99.0 else exp(-t / tau)) * minf(t * 500.0, 1.0)
	return out


## Radio static: noise squeezed into the voice band (two lowpasses, subtracted).
func radio_noise(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	var a := 0.0
	var b := 0.0
	for i in out.size():
		var x := rng.randf_range(-1.0, 1.0)
		a += (x - a) * 0.5
		b += (x - b) * 0.06
		var t := float(i) / RATE
		out[i] = (a - b) * 0.6 * minf((dur - t) * 60.0, 1.0)
	return out


## A metal drawer on its runners: quick clicks fading.
func rattle(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	var y := 0.0
	for i in out.size():
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * 0.3
		out[i] = y * 0.4 * (0.5 + 0.5 * sin(TAU * 55.0 * t))
	return out


## A dot-matrix print head: a buzzing pulse train with grit.
func printer(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	for i in out.size():
		var t := float(i) / RATE
		var pulse := 1.0 if fmod(t * 180.0, 1.0) < 0.2 else 0.0
		out[i] = (pulse * 0.25 + rng.randf_range(-0.08, 0.08)) * minf((dur - t) * 80.0, 1.0)
	return out


## Tape static crackle: sparse pops.
func crackle(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	for i in out.size():
		if rng.randf() < 0.0015:
			out[i] = rng.randf_range(-0.6, 0.6)
	return out


## The crash: the hit (a low thump and a wall of noise), metal ringing, then
## glass and bits of trim landing.
func crash() -> PackedFloat32Array:
	var parts := [tone(48.0, 0.6, 0.18, 1.0), noise(1.2, 0.35, 0.35, 0.9), noise(0.4, 0.08, 0.9, 0.5),
		tone(610.0, 1.0, 0.3, 0.12), tone(1130.0, 1.0, 0.22, 0.09), tone(1720.0, 0.8, 0.15, 0.07)]
	for k in 14:                                     # glass and trim, scattered over a second
		parts.append(delay(tone(rng.randf_range(2800.0, 6000.0), 0.08, 0.02, 0.15), rng.randf_range(0.1, 1.1)))
	return mix(parts)


func delay(a: PackedFloat32Array, s: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(s * RATE))
	out.append_array(a)
	return out


## Sum (to the longest), soft-clipped so a busy mix never cracks.
func mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p: PackedFloat32Array in parts:
		n = maxi(n, p.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p: PackedFloat32Array in parts:
		for i in p.size():
			out[i] += p[i]
	for i in n:
		out[i] = tanh(out[i])
	return out


func wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


func looped(samples: PackedFloat32Array) -> AudioStreamWAV:
	var w := wav(samples)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = samples.size()
	return w
