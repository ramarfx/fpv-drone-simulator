extends RigidBody3D
## Drone FPV — fisika realistis 5" freestyle.
## RigidBody3D + _integrate_forces pada 240 Hz (lihat project.godot).
## Model lengkap ada di README_PHYSICS.md. Ringkasan:
##  m=0.65 kg, 4 motor X, thrust=kT*omega^2, lag motor orde-1,
##  baterai 4S + sag, PID angular-velocity Betaflight-style,
##  drag kuadratik + propwash + ground effect, mode ACRO / ANGLE.

class_name FPVDrone

signal crashed()
signal gate_passed(gate_index: int)
signal armed_changed(armed: bool)

enum FlightMode { ACRO, ANGLE }

# --- Parameter fisik (5" freestyle) ---
@export var mass_kg: float = 0.65
@export var max_thrust_per_motor: float = 10.0 # N, total 40 N, TWR ~6.2
@export var arm_length: float = 0.115 # m, jarak pusat -> motor
@export var motor_tau: float = 0.03 # s, lag motor orde-1
@export var battery_capacity_mah: float = 1500.0
@export var flight_mode: FlightMode = FlightMode.ANGLE
@export var max_tilt_angle_deg: float = 50.0 # mode ANGLE

# Input dari joystick / keyboard (diisi tiap frame oleh _process).
var throttle_input: float = 0.0 # 0..1
var pitch_input: float = 0.0 # -1..1, +1 = stick maju = nose-down
var roll_input: float = 0.0 # -1..1, +1 = stick kanan = roll kanan
var yaw_input: float = 0.0 # -1..1, +1 = stick kanan = yaw kanan

var armed: bool = false
var is_crashed: bool = false
var battery_charge: float = 1.0 # 0..1
var battery_voltage: float = 16.8
var battery_current: float = 0.0
var motor_cmd: Array[float] = [0.0, 0.0, 0.0, 0.0] # target 0..1
var motor_filtered: Array[float] = [0.0, 0.0, 0.0, 0.0] # setelah lag
var rpm: Array[float] = [0.0, 0.0, 0.0, 0.0]
var effective_throttle: float = 0.0
var speed_ms: float = 0.0
var altitude_m: float = 0.0
var vertical_speed_ms: float = 0.0
var crash_speed: float = 0.0

# PID per sumbu (x=pitch, y=yaw, z=roll dalam koordinat body Godot).
var pid_x: FlightController.PIDAxis = FlightController.PIDAxis.new()
var pid_y: FlightController.PIDAxis = FlightController.PIDAxis.new()
var pid_z: FlightController.PIDAxis = FlightController.PIDAxis.new()

const RHO: float = 1.225
const GRAVITY: float = 9.81
# CdA per sumbu body: x lateral, y vertikal, z depan/belakang.
const CDA: Vector3 = Vector3(0.025, 0.060, 0.025)
const LINEAR_DRAG: float = 0.02
const ANGULAR_DRAG: Vector3 = Vector3(0.0008, 0.0015, 0.0008)
const MAX_TORQUE_XZ: float = 2.3 # Nm, dari thrust diferensial * arm
const MAX_TORQUE_Y: float = 0.45 # Nm, yaw dari drag prop
const R_INTERNAL: float = 0.02 # ohm, pack 4S
const MAX_CURRENT_PER_MOTOR: float = 25.0 # A pada full throttle
const CRASH_SPEED_THRESHOLD: float = 6.0 # m/s saat kontak = crash

var _time: float = 0.0
var _prev_contact: bool = false
var _start_transform: Transform3D

# Node anak untuk visual baling-baling (opsional, dicari di _ready).
var _props: Array[MeshInstance3D] = []

func _ready() -> void:
	mass = mass_kg
	# Inersia diagonal: Ixx=Izz=0.0042 (pitch/roll), Iyy=0.0075 (yaw).
	inertia = Vector3(0.0042, 0.0075, 0.0042)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0, 0)
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	_start_transform = global_transform
	# PID yaw sedikit berbeda: P lebih kecil karena otoritas yaw lemah.
	pid_y.kp = 3.2
	pid_y.ki = 0.7
	pid_y.kd = 0.015
	for child in get_children():
		if child is MeshInstance3D and child.name.begins_with("Prop"):
			_props.append(child)
	body_entered.connect(_on_body_entered)

func set_armed(value: bool) -> void:
	if is_crashed and value:
		return
	if armed == value:
		return
	armed = value
	if not armed:
		throttle_input = 0.0
		for i in range(4):
			motor_cmd[i] = 0.0
		pid_x.reset()
		pid_y.reset()
		pid_z.reset()
	armed_changed.emit(armed)

func toggle_mode() -> void:
	if flight_mode == FlightMode.ACRO:
		flight_mode = FlightMode.ANGLE
	else:
		flight_mode = FlightMode.ACRO
	pid_x.reset()
	pid_y.reset()
	pid_z.reset()

func reset_to_start() -> void:
	is_crashed = false
	battery_charge = 1.0
	battery_voltage = 16.8
	pid_x.reset()
	pid_y.reset()
	pid_z.reset()
	for i in range(4):
		motor_cmd[i] = 0.0
		motor_filtered[i] = 0.0
		rpm[i] = 0.0
	# Reset state fisika langsung. Rotasi DIPAKSA tegak (Basis.IDENTITY):
	# reset harus mengembalikan drone yang kebalik ke posisi datar, bukan
	# mengembalikan transform apa adanya.
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	throttle_input = 0.0
	global_transform = Transform3D(Basis.IDENTITY, _start_transform.origin)
	# Bangunkan body agar tidak tidur.
	sleeping = false

func _process(_delta: float) -> void:
	# Keyboard fallback (joystick Android menimpa nilai ini via set_stick_input).
	if not Engine.is_editor_hint():
		var kb_throttle: float = 0.0
		if Input.is_action_pressed("throttle_up"):
			throttle_input = clampf(throttle_input + 0.008, 0.0, 1.0)
		if Input.is_action_pressed("throttle_down"):
			throttle_input = clampf(throttle_input - 0.008, 0.0, 1.0)
		kb_throttle = throttle_input
		# Keyboard hanya dipakai jika joystick tidak aktif (ditandai flag).
		if not _joystick_active:
			pitch_input = Input.get_axis("pitch_back", "pitch_forward")
			roll_input = Input.get_axis("roll_left", "roll_right")
			yaw_input = Input.get_axis("yaw_left", "yaw_right")
		if Input.is_action_just_pressed("arm_toggle"):
			set_armed(not armed)
		if Input.is_action_just_pressed("reset_drone"):
			reset_to_start()
		if Input.is_action_just_pressed("mode_toggle"):
			toggle_mode()
	# Visual baling-baling berputar sesuai RPM.
	for i in range(_props.size()):
		if i < 4:
			_props[i].rotate_y(rpm[i] * get_process_delta_time() * 0.001 * 60.0)

var _joystick_active: bool = false

## Dipanggil HUD/joystick setiap frame. throttle 0..1, lainnya -1..1.
func set_stick_input(throttle: float, pitch: float, roll: float, yaw: float) -> void:
	throttle_input = clampf(throttle, 0.0, 1.0)
	pitch_input = clampf(pitch, -1.0, 1.0)
	roll_input = clampf(roll, -1.0, 1.0)
	yaw_input = clampf(yaw, -1.0, 1.0)
	_joystick_active = true

func clear_joystick_active() -> void:
	_joystick_active = false

func _on_body_entered(_body: Node) -> void:
	# Kontak keras = crash. Kecepatan saat kontak menentukan.
	var spd: float = linear_velocity.length()
	if armed and spd > CRASH_SPEED_THRESHOLD and not is_crashed:
		_do_crash(spd)

func _do_crash(spd: float) -> void:
	is_crashed = true
	crash_speed = spd
	armed = false
	for i in range(4):
		motor_cmd[i] = 0.0
		motor_filtered[i] = 0.0
		rpm[i] = 0.0
	armed_changed.emit(false)
	crashed.emit()

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt: float = state.step
	_time += dt
	var basis: Basis = state.transform.basis
	var vel_world: Vector3 = state.linear_velocity
	var omega_world: Vector3 = state.angular_velocity
	# Kecepatan dalam frame body.
	var vel_body: Vector3 = basis.inverse() * vel_world
	var omega_body: Vector3 = basis.inverse() * omega_world
	speed_ms = vel_world.length()
	altitude_m = global_position.y
	vertical_speed_ms = vel_world.y

	# --- Baterai: sag + pengosongan ---
	var total_cmd: float = 0.0
	for c in motor_cmd:
		total_cmd += c
	var avg_cmd: float = total_cmd / 4.0
	battery_current = total_cmd * MAX_CURRENT_PER_MOTOR * 0.25 + (1.0 if armed else 0.0)
	var open_v: float = 14.0 + battery_charge * 2.8 # 4S: 14.0 kosong -> 16.8 penuh
	battery_voltage = maxf(open_v - battery_current * R_INTERNAL, 12.0)
	var battery_factor: float = clampf(battery_voltage / 16.8, 0.72, 1.0)
	if armed:
		var consumed_mah: float = battery_current * dt / 3600.0 * 1000.0
		battery_charge = maxf(0.0, battery_charge - consumed_mah / battery_capacity_mah)

	# --- Tentukan perintah motor (target) ---
	if not armed or is_crashed:
		for i in range(4):
			motor_cmd[i] = 0.0
	else:
		# Desired angular velocity.
		var desired_omega: Vector3 = Vector3.ZERO
		if flight_mode == FlightMode.ACRO:
			desired_omega = Vector3(
				-FlightController.actual_rates(pitch_input),
				-FlightController.actual_rates(yaw_input),
				-FlightController.actual_rates(roll_input)
			)
		else:
			# ANGLE: self-level. Desired tilt dari stick, lalu P pada error sudut.
			desired_omega = _angle_mode_omega(basis)
			# Yaw tetap rate (tidak self-level).
			desired_omega.y = -FlightController.actual_rates(yaw_input)
		# PID per sumbu -> torque.
		var tau_x: float = pid_x.update(desired_omega.x, omega_body.x, dt, MAX_TORQUE_XZ)
		var tau_y: float = pid_y.update(desired_omega.y, omega_body.y, dt, MAX_TORQUE_Y)
		var tau_z: float = pid_z.update(desired_omega.z, omega_body.z, dt, MAX_TORQUE_XZ)
		# Ternormalisasi untuk mixing (-1..1).
		var pitch_n: float = tau_x / MAX_TORQUE_XZ
		var yaw_n: float = tau_y / MAX_TORQUE_Y
		var roll_n: float = tau_z / MAX_TORQUE_XZ
		# Throttle stick -> motor cmd lewat kurva expo + limit SCALE
		# (hover di stick ~38%, punch-out dibatasi 60%).
		var thr_eff: float = FlightController.apply_throttle(throttle_input)
		var mixed: Array[float] = FlightController.mix_motors(thr_eff, pitch_n, roll_n, yaw_n)
		for i in range(4):
			motor_cmd[i] = mixed[i]
		# Terapkan torque PID + angular drag.
		var torque_body: Vector3 = Vector3(tau_x, tau_y, tau_z)
		# Angular drag kuadratik: -k * omega * |omega|.
		torque_body -= Vector3(
			ANGULAR_DRAG.x * omega_body.x * absf(omega_body.x),
			ANGULAR_DRAG.y * omega_body.y * absf(omega_body.y),
			ANGULAR_DRAG.z * omega_body.z * absf(omega_body.z)
		)
		# Propwash: saat turun cepat, tambah guncangan acak halus pada torque.
		if vel_body.y < -3.0:
			var wob: float = clampf((-vel_body.y - 3.0) / 6.0, 0.0, 1.0)
			var t: float = _time * 13.0
			torque_body.x += sin(t * 1.7) * 0.12 * wob
			torque_body.z += cos(t * 2.3) * 0.12 * wob
		var torque_world: Vector3 = basis * torque_body
		state.apply_torque(torque_world)
		# Anti-windup tambahan: jika motor jenuh penuh, PID sudah menahan integral.

	# --- Lag motor orde-1 + RPM ---
	for i in range(4):
		var alpha: float = 1.0
		if dt > 0.0:
			alpha = dt / (motor_tau + dt)
		motor_filtered[i] = lerp(motor_filtered[i], motor_cmd[i], alpha)
		# RPM: 0..~28000, skala dengan akar throttle + faktor baterai.
		rpm[i] = sqrt(maxf(motor_filtered[i], 0.0)) * 28000.0 * battery_factor
	effective_throttle = (motor_filtered[0] + motor_filtered[1] + motor_filtered[2] + motor_filtered[3]) / 4.0

	# --- Gaya thrust ---
	var thrust_factor: float = battery_factor
	# Propwash: efektivitas thrust turun saat turun cepat dalam wash sendiri.
	if vel_body.y < -2.0:
		var pw: float = clampf((-vel_body.y - 2.0) / 6.0, 0.0, 1.0)
		thrust_factor *= (1.0 - 0.22 * pw)
	# Ground effect: lift ekstra dalam 0.5 m di atas tanah (y ~ 0).
	var ge: float = 1.0
	if global_position.y < 0.5 and global_position.y > -0.2:
		ge = 1.0 + 0.18 * (1.0 - clampf(global_position.y / 0.5, 0.0, 1.0))
	var total_thrust: float = 0.0
	for i in range(4):
		# thrust = kT * omega^2 ~ proporsional motor_filtered (karena omega ~ sqrt).
		total_thrust += max_thrust_per_motor * motor_filtered[i]
	total_thrust *= thrust_factor * ge
	var thrust_world: Vector3 = basis * Vector3(0, total_thrust, 0)
	state.apply_central_force(thrust_world)

	# --- Drag aerodinamik ---
	# Drag kuadratik per-sumbu body: F = -0.5 * rho * CdA * |v| * v.
	var drag_body: Vector3 = Vector3(
		-0.5 * RHO * CDA.x * absf(vel_body.x) * vel_body.x,
		-0.5 * RHO * CDA.y * absf(vel_body.y) * vel_body.y,
		-0.5 * RHO * CDA.z * absf(vel_body.z) * vel_body.z
	)
	# Drag linier kecil (stabil di kecepatan rendah).
	drag_body -= vel_body * LINEAR_DRAG
	var drag_world: Vector3 = basis * drag_body
	state.apply_central_force(drag_world)
	# Gravitasi ditangani engine (gravity_scale default 1). Pastikan aktif.
	# Catatan: Godot menerapkan gravitasi otomatis pada RigidBody3D.

	# --- Deteksi crash via kontak (cadangan selain body_entered) ---
	var contacts: int = state.get_contact_count()
	if contacts > 0 and armed and not is_crashed:
		if speed_ms > CRASH_SPEED_THRESHOLD:
			# Hanya crash jika kontak baru (hindari crash berulang saat mendarat pelan).
			if not _prev_contact:
				_do_crash(speed_ms)
	_prev_contact = contacts > 0

## Mode ANGLE: hitung desired omega dari error sudut.
func _angle_mode_omega(basis: Basis) -> Vector3:
	# Tilt yang diminta: pitch & roll dari stick, maks 50 derajat.
	var desired_pitch: float = -pitch_input * deg_to_rad(max_tilt_angle_deg)
	var desired_roll: float = -roll_input * deg_to_rad(max_tilt_angle_deg)
	# Estimasi pitch/roll saat ini dari basis: proyeksi sumbu up.
	# up_world = basis.y. Pitch ~ asin(-forward.y)? Gunakan Euler.
	var e: Vector3 = basis.get_euler()
	# e.x = pitch, e.z = roll (urutan YXZ di Godot, pendekatan cukup untuk self-level).
	var err_pitch: float = desired_pitch - e.x
	var err_roll: float = desired_roll - e.z
	# P kuat agar snap-back ke level terasa tegas saat stick dilepas.
	var kp_angle: float = 8.0
	var max_rate: float = deg_to_rad(360.0)
	return Vector3(
		clampf(kp_angle * err_pitch, -max_rate, max_rate),
		0.0,
		clampf(kp_angle * err_roll, -max_rate, max_rate)
	)
