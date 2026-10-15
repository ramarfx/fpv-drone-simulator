extends Camera3D
## Kamera FPV — follow drone dengan lag + shake, tanpa stabilisasi gimbal.
## Uptilt 15-30 derajat (default 25), FOV 115.

@export var drone_path: NodePath
@export var uptilt_deg: float = 25.0
@export var fov_deg: float = 115.0
@export var follow_lerp_hz: float = 12.0
@export var shake_amount: float = 0.004

var _drone: Node3D
var _smooth_pos: Vector3
var _smooth_basis: Basis
var _initialized: bool = false

func _ready() -> void:
	fov = fov_deg
	if drone_path != NodePath(""):
		_drone = get_node_or_null(drone_path) as Node3D

func _process(delta: float) -> void:
	if _drone == null:
		return
	var target: Transform3D = _drone.global_transform
	# Offset kamera sedikit di depan + atas body.
	var cam_offset: Vector3 = target.basis * Vector3(0, 0.06, -0.10)
	var target_pos: Vector3 = target.origin + cam_offset
	if not _initialized:
		_smooth_pos = target_pos
		_smooth_basis = target.basis
		_initialized = true
	var a: float = 1.0 - exp(-follow_lerp_hz * delta)
	_smooth_pos = _smooth_pos.lerp(target_pos, a)
	# Slerp rotasi: pakai Quaternion.
	var q_cur: Quaternion = Quaternion(_smooth_basis)
	var q_tgt: Quaternion = Quaternion(target.basis)
	_smooth_basis = Basis(q_cur.slerp(q_tgt, a))
	# Uptilt: putar kamera ke atas sebesar uptilt di sekitar sumbu X lokal.
	var uptilt_basis: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(uptilt_deg))
	var final_basis: Basis = _smooth_basis * uptilt_basis
	global_position = _smooth_pos
	global_transform = Transform3D(final_basis, _smooth_pos)
	# Shake proporsional throttle + kecepatan (vibrasi motor).
	var drone_script = _drone as FPVDrone
	if drone_script != null:
		var thr: float = drone_script.effective_throttle
		var t: float = Time.get_ticks_msec() / 1000.0
		var shake: float = shake_amount * (0.3 + thr)
		# Tambah noise kecil pada posisi (dalam frame kamera).
		var off: Vector3 = Vector3(
			sin(t * 47.0) * shake,
			sin(t * 53.0 + 1.3) * shake,
			0.0
		)
		global_position += final_basis * off
	fov = fov_deg
