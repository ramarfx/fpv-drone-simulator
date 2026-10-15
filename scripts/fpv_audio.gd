extends AudioStreamPlayer
## Suara FPV prosedural — tanpa file eksternal.
## AudioStreamGenerator 44100 Hz: 4 osilator motor (sawtooth + detune),
## wind noise (filtered white noise, gain ~ speed^2), beep gate, thud crash.
## Mulai saat ARM, berhenti saat disarm/crash (kecuali wind).

@export var drone_path: NodePath
@export var master_volume: float = 0.7
@export var muted: bool = false

var _playback: AudioStreamGeneratorPlayback
var _phases: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _lp_motor: float = 0.0
var _lp_wind: float = 0.0
var _beep_time: float = 0.0
var _thud_time: float = 0.0
var _thud_level: float = 0.0
var _drone: FPVDrone

func _ready() -> void:
	var gen: AudioStreamGenerator = AudioStreamGenerator.new()
	gen.mix_rate = 44100.0
	gen.buffer_length = 0.1
	stream = gen
	volume_db = -6.0
	if drone_path != NodePath(""):
		_drone = get_node_or_null(drone_path) as FPVDrone
	# Hubungkan sinyal crash dari drone.
	if _drone != null:
		_drone.crashed.connect(_on_drone_crashed)
	play()

func _process(_delta: float) -> void:
	if _playback == null:
		_playback = get_stream_playback() as AudioStreamGeneratorPlayback
		if _playback == null:
			return
	if muted:
		# Kosongkan buffer dengan silence.
		var avail_m: int = _playback.get_frames_available()
		for _i in range(avail_m):
			_playback.push_frame(Vector2.ZERO)
		return
	var sr: float = 44100.0
	var dt: float = 1.0 / sr
	# Turunkan timer efek.
	if _beep_time > 0.0:
		_beep_time -= get_process_delta_time()
	if _thud_time > 0.0:
		_thud_time -= get_process_delta_time()
	var armed: bool = _drone != null and _drone.armed
	var throttle: float = 0.0
	var speed: float = 0.0
	var vert_speed: float = 0.0
	if _drone != null:
		throttle = _drone.effective_throttle
		speed = _drone.speed_ms
		vert_speed = _drone.vertical_speed_ms
	# Jika tidak armed, motor diam (throttle 0) tapi wind tetap bunyi.
	if not armed:
		throttle = 0.0
	var frames: int = _playback.get_frames_available()
	for _i in range(frames):
		var sample: float = 0.0
		# --- Motor: 4 sawtooth, freq 180 + throttle*900 + detune + ripple ---
		if armed or throttle > 0.01:
			var motor_sum: float = 0.0
			for m in range(4):
				var detune: float = float(m) * 7.0 - 10.5
				var ripple: float = sin(_phases[m] * 2.0 * PI * 0.5) * 12.0
				var freq: float = 180.0 + throttle * 900.0 + detune + ripple
				_phases[m] += freq * dt
				if _phases[m] >= 1.0:
					_phases[m] -= 1.0
				var saw: float = 2.0 * (_phases[m] - 0.5)
				# Tambah sedikit harmonik kedua agar terdengar seperti prop.
				var saw2: float = 2.0 * (fmod(_phases[m] * 2.0, 1.0) - 0.5)
				motor_sum += saw * 0.7 + saw2 * 0.3
			motor_sum /= 4.0
			# Lowpass motor: cutoff naik dengan throttle (1400 -> 4500 Hz).
			var cutoff: float = 1400.0 + throttle * 3100.0
			var alpha: float = cutoff / (cutoff + sr)
			_lp_motor = lerp(_lp_motor, motor_sum, alpha)
			sample += _lp_motor * (0.15 + throttle * 0.55) * master_volume
		# --- Wind: white noise filtered, gain ~ speed^2 ---
		var wind_gain: float = clampf(speed * speed * 0.0012, 0.0, 0.5)
		# Propwash wobble saat turun cepat: modulasi wind.
		if vert_speed < -3.0:
			var wob: float = clampf((-vert_speed - 3.0) / 6.0, 0.0, 1.0)
			var t: float = Time.get_ticks_msec() / 1000.0
			wind_gain *= (1.0 + sin(t * 22.0) * 0.35 * wob)
		if wind_gain > 0.001:
			var noise: float = randf_range(-1.0, 1.0)
			var wcut: float = 400.0 + speed * 80.0
			var walpha: float = wcut / (wcut + sr)
			_lp_wind = lerp(_lp_wind, noise, walpha)
			sample += _lp_wind * wind_gain * master_volume
		# --- Gate beep: sine 880 Hz ---
		if _beep_time > 0.0:
			var bt: float = Time.get_ticks_msec() / 1000.0
			sample += sin(bt * 2.0 * PI * 880.0) * 0.35 * master_volume
		# --- Crash thud: noise burst lowpass berat ---
		if _thud_time > 0.0:
			var n: float = randf_range(-1.0, 1.0)
			# Lowpass kasar dengan decay.
			var decay: float = _thud_time / 0.35
			sample += n * _thud_level * decay * 0.9
		# Soft clip.
		sample = clampf(sample, -0.95, 0.95)
		_playback.push_frame(Vector2(sample, sample))

func play_gate_beep() -> void:
	_beep_time = 0.12

func play_crash_thud(intensity: float = 1.0) -> void:
	_thud_time = 0.35
	_thud_level = clampf(intensity, 0.2, 1.0)

func _on_drone_crashed() -> void:
	play_crash_thud(1.0)

func set_muted(value: bool) -> void:
	muted = value
