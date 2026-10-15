extends CanvasLayer
## HUD / OSD FPV: baterai, timer, kecepatan, ketinggian, mode, ARM,
## throttle bar, horizon mini, crosshair, gate/lap, tombol.

@export var drone_path: NodePath
@export var audio_path: NodePath
@export var camera_path: NodePath

var _drone: FPVDrone
var _audio: Node
var _camera: Camera3D
var _left: VirtualJoystick
var _right: VirtualJoystick
var _elapsed: float = 0.0
var _lap_start: float = 0.0
var _gate_count: int = 0
var _last_lap: float = 0.0
var _best_lap: float = 0.0
var _paused: bool = false

## Tag build yang tampil di layar — naikkan tiap build agar jelas APK mana
## yang sedang jalan di HP (mencegah "kok tidak ada perubahan" karena APK lama).
const BUILD_TAG: String = "BUILD 7"

# Referensi UI (diisi di _ready via get_node).
var _btn_pause: Button
var _lbl_debug: Label
var _lbl_batt: Label
var _lbl_timer: Label
var _lbl_speed: Label
var _lbl_alt: Label
var _lbl_mode: Label
var _lbl_arm: Label
var _lbl_gate: Label
var _lbl_hint: Label
var _bar_throttle: ProgressBar
var _bar_batt: ProgressBar
var _horizon: ColorRect
var _horizon_line: ColorRect

func _ready() -> void:
	if drone_path != NodePath(""):
		_drone = get_node_or_null(drone_path) as FPVDrone
	if audio_path != NodePath(""):
		_audio = get_node_or_null(audio_path)
	if camera_path != NodePath(""):
		_camera = get_node_or_null(camera_path) as Camera3D
	# Cari node UI.
	_lbl_batt = get_node_or_null("TopBar/Battery") as Label
	_lbl_timer = get_node_or_null("TopBar/Timer") as Label
	_lbl_speed = get_node_or_null("TopBar/Speed") as Label
	_lbl_alt = get_node_or_null("TopBar/Altitude") as Label
	_lbl_mode = get_node_or_null("TopBar/Mode") as Label
	_lbl_arm = get_node_or_null("TopBar/ArmState") as Label
	_lbl_gate = get_node_or_null("TopBar/Gates") as Label
	_lbl_hint = get_node_or_null("Hint") as Label
	_lbl_debug = get_node_or_null("DebugLabel") as Label
	if _lbl_debug != null:
		_lbl_debug.text = BUILD_TAG
	_bar_throttle = get_node_or_null("ThrottleBar") as ProgressBar
	_bar_batt = get_node_or_null("BatteryBar") as ProgressBar
	_horizon = get_node_or_null("Horizon") as ColorRect
	_horizon_line = get_node_or_null("Horizon/Line") as ColorRect
	_left = get_node_or_null("LeftStick") as VirtualJoystick
	_right = get_node_or_null("RightStick") as VirtualJoystick
	# Tombol.
	var btn_arm: Button = get_node_or_null("Buttons/ArmButton") as Button
	if btn_arm != null:
		btn_arm.pressed.connect(_on_arm_pressed)
	var btn_mode: Button = get_node_or_null("Buttons/ModeButton") as Button
	if btn_mode != null:
		btn_mode.pressed.connect(_on_mode_pressed)
	var btn_reset: Button = get_node_or_null("Buttons/ResetButton") as Button
	if btn_reset != null:
		btn_reset.pressed.connect(_on_reset_pressed)
	var btn_cam_up: Button = get_node_or_null("Buttons/CamUp") as Button
	if btn_cam_up != null:
		btn_cam_up.pressed.connect(_on_cam_up)
	var btn_cam_dn: Button = get_node_or_null("Buttons/CamDown") as Button
	if btn_cam_dn != null:
		btn_cam_dn.pressed.connect(_on_cam_down)
	_btn_pause = get_node_or_null("Buttons/PauseButton") as Button
	if _btn_pause != null:
		_btn_pause.pressed.connect(_on_pause_pressed)
	var btn_mute: Button = get_node_or_null("Buttons/MuteButton") as Button
	if btn_mute != null:
		btn_mute.pressed.connect(_on_mute_pressed)
	if _drone != null:
		_drone.gate_passed.connect(_on_gate_passed)
		_drone.crashed.connect(_on_drone_crashed)

func _input(event: InputEvent) -> void:
	# Back Android / ESC = pause toggle. Ada di HUD (bukan main.gd) karena
	# HUD ber-pause_mode PROCESS, jadi tombol ini tetap jalan saat game
	# ter-pause — kalau di main.gd (INHERIT), Back tidak bisa unpause.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_toggle_pause()
	# Diagnostik sentuhan: tampilkan sentuhan terakhir yang TIDAK ditangani
	# GUI (misal tap di area kosong). Sentuhan di stik ditangani joystick
	# (knob-nya yang jadi indikator). Kalau label ini tidak pernah berubah
	# saat layar disentuh, berarti sentuhan tidak sampai ke game sama sekali.
	if _lbl_debug != null:
		if event is InputEventScreenTouch:
			var t: InputEventScreenTouch = event as InputEventScreenTouch
			_lbl_debug.text = "%s | TOUCH %s (%.0f, %.0f)" % [BUILD_TAG, "DOWN" if t.pressed else "UP", t.position.x, t.position.y]
		elif event is InputEventScreenDrag:
			var d: InputEventScreenDrag = event as InputEventScreenDrag
			_lbl_debug.text = "%s | DRAG (%.0f, %.0f)" % [BUILD_TAG, d.position.x, d.position.y]

func _process(delta: float) -> void:
	if _drone == null:
		return
	# Kirim input stick ke drone (Mode 2).
	# Kiri: value.x=yaw, value.y=throttle. Kanan: value.x=roll, value.y=pitch.
	var thr: float = 0.0
	var yaw: float = 0.0
	var roll: float = 0.0
	var pitch: float = 0.0
	if _left != null:
		yaw = _left.value.x
		thr = _left.value.y
	if _right != null:
		roll = _right.value.x
		pitch = _right.value.y
	# Jika joystick tidak disentuh dan keyboard dipakai, drone memakai keyboard.
	# Kami tetap kirim stick jika ada sentuhan aktif; jika tidak, biarkan drone
	# memakai keyboard dengan cara tidak menimpa (clear flag via nilai netral
	# hanya saat kedua stick benar-benar netral DAN tidak ada sentuhan).
	# Pendekatan sederhana: selalu kirim stick — keyboard fallback di drone
	# hanya aktif saat _joystick_active false. Karena HUD selalu mengirim,
	# keyboard fallback bekerja saat stick netral (nilai 0) — perilaku sama.
	_drone.set_stick_input(thr, pitch, roll, yaw)
	if not _paused and _drone.armed:
		_elapsed += delta
	# Update label.
	if _lbl_batt != null:
		_lbl_batt.text = "BAT %.1fV %d%%" % [_drone.battery_voltage, int(_drone.battery_charge * 100.0)]
		if _drone.battery_voltage < 14.0:
			_lbl_batt.modulate = Color(1, 0.2, 0.2)
		else:
			_lbl_batt.modulate = Color(1, 1, 1)
	if _lbl_timer != null:
		_lbl_timer.text = _fmt_time(_elapsed)
	if _lbl_speed != null:
		_lbl_speed.text = "%.0f km/h" % [_drone.speed_ms * 3.6]
	if _lbl_alt != null:
		_lbl_alt.text = "ALT %.1f m" % _drone.altitude_m
	if _lbl_mode != null:
		_lbl_mode.text = "ACRO" if _drone.flight_mode == FPVDrone.FlightMode.ACRO else "ANGLE"
	if _lbl_arm != null:
		if _drone.is_crashed:
			_lbl_arm.text = "CRASHED — RESET"
			_lbl_arm.modulate = Color(1, 0.2, 0.2)
		elif _drone.armed:
			_lbl_arm.text = "ARMED"
			_lbl_arm.modulate = Color(0.2, 1, 0.3)
		else:
			_lbl_arm.text = "DISARMED"
			_lbl_arm.modulate = Color(1, 1, 1)
	if _lbl_gate != null:
		_lbl_gate.text = "GATE %d/8  LAP %s" % [_gate_count, _fmt_time(_last_lap) if _last_lap > 0.0 else "--:--"]
	if _lbl_hint != null:
		if get_tree().paused:
			_lbl_hint.text = "PAUSED — TAP PAUSE TO RESUME"
			_lbl_hint.visible = true
		else:
			_lbl_hint.text = "TAP ARM TO FLY"
			_lbl_hint.visible = not _drone.armed and not _drone.is_crashed
	if _bar_throttle != null:
		_bar_throttle.value = _drone.effective_throttle * 100.0
	if _bar_batt != null:
		_bar_batt.value = _drone.battery_charge * 100.0
	# Horizon mini: rotasi dari roll drone, offset dari pitch.
	if _horizon_line != null and _drone != null:
		var e: Vector3 = _drone.global_transform.basis.get_euler()
		_horizon_line.rotation = e.z
		_horizon_line.position.y = clampf(e.x * 60.0, -25.0, 25.0) + 12.0

func _fmt_time(t: float) -> String:
	var m: int = int(t / 60.0)
	var s: float = fmod(t, 60.0)
	return "%02d:%05.2f" % [m, s]

func _on_arm_pressed() -> void:
	if _drone != null:
		if _drone.is_crashed:
			return
		_drone.set_armed(not _drone.armed)
		if _drone.armed and _lap_start == 0.0:
			_lap_start = _elapsed

func _on_mode_pressed() -> void:
	if _drone != null:
		_drone.toggle_mode()

func _on_reset_pressed() -> void:
	if _drone != null:
		_drone.reset_to_start()
		_elapsed = 0.0
		_lap_start = 0.0
		_gate_count = 0
		_last_lap = 0.0
	if _left != null:
		_left.reset_stick()
	if _right != null:
		_right.reset_stick()

func _on_cam_up() -> void:
	if _camera != null:
		var cam = _camera as Object
		if cam.get("uptilt_deg") != null:
			cam.set("uptilt_deg", clampf(float(cam.get("uptilt_deg")) + 5.0, 15.0, 30.0))

func _on_cam_down() -> void:
	if _camera != null:
		var cam = _camera as Object
		if cam.get("uptilt_deg") != null:
			cam.set("uptilt_deg", clampf(float(cam.get("uptilt_deg")) - 5.0, 15.0, 30.0))

func _on_pause_pressed() -> void:
	_toggle_pause()

## Satu-satunya jalan toggle pause (dipakai tombol PAUSE + Back/ESC).
## Sumber kebenaran = get_tree().paused, bukan _paused lokal, biar tidak
## desync. Tombol berubah jadi RESUME saat pause agar jelas bisa ditekan lagi.
func _toggle_pause() -> void:
	_paused = not get_tree().paused
	get_tree().paused = _paused
	if _btn_pause != null:
		_btn_pause.text = "RESUME" if _paused else "PAUSE"
	# Pasang indikator PAUSED langsung di sini, bukan hanya di _process:
	# saat pause, _process HUD tidak selalu jalan, jadi kalau indikator
	# hanya di _process, pause jadi tidak terlihat dan dikira joystick mati
	# (itulah yang bikin "tadi bisa, terus gabisa" — kepencet PAUSE tanpa
	# sadar, tanpa ada tulisan PAUSED). Saat resume, _process mengambil
	# alih lagi dan mengembalikan hint normal.
	if _paused and _lbl_hint != null:
		_lbl_hint.text = "PAUSED — TAP PAUSE TO RESUME"
		_lbl_hint.visible = true

func _on_mute_pressed() -> void:
	if _audio != null and _audio.has_method("set_muted"):
		var cur: bool = false
		if _audio.get("muted") != null:
			cur = bool(_audio.get("muted"))
		_audio.call("set_muted", not cur)

func _on_gate_passed(gate_index: int) -> void:
	_gate_count += 1
	if _audio != null and _audio.has_method("play_gate_beep"):
		_audio.call("play_gate_beep")
	# Lap selesai saat melewati gate 0 setelah minimal 2 gate lain.
	if gate_index == 0 and _gate_count > 2:
		var lap: float = _elapsed - _lap_start
		if lap > 3.0:
			_last_lap = lap
			if _best_lap == 0.0 or lap < _best_lap:
				_best_lap = lap
			_lap_start = _elapsed

func _on_drone_crashed() -> void:
	if _lbl_hint != null:
		_lbl_hint.visible = false
