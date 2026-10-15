extends Camera3D
## Kamera FPV — RIGID MOUNT, 1:1 dengan frame drone.
## Kamera FPV asli dibaut ke frame dengan sudut up-tilt tetap: tidak ada
## gimbal, stabilisasi, smoothing, atau lerp. Kalau drone roll, horizon
## roll persis sama; kalau pitch, view pitch persis sama. Kamera di sini
## menyalin transform drone persis tiap frame (offset + up-tilt tetap
## dalam frame drone). Smoothing lama (lerp posisi + slerp rotasi) yang
## bikin kamera terasa "tidak nempel" sudah dihapus.
## Uptilt 20 derajat (beginner), FOV vertikal 80 — Godot fov adalah
## VERTIKAL, jangan salin angka diagonal hardware 150° mentah-mentah
## (itu ~75-90° vertikal di layar 16:9).

@export var drone_path: NodePath
@export var uptilt_deg: float = 20.0
@export var fov_deg: float = 80.0

var _drone: Node3D

func _ready() -> void:
	fov = fov_deg
	if drone_path != NodePath(""):
		_drone = get_node_or_null(drone_path) as Node3D

func _process(_delta: float) -> void:
	if _drone == null:
		return
	# Salin transform drone persis: posisi = origin drone + offset dalam
	# frame drone, rotasi = basis drone * up-tilt. Tanpa lerp/slerp/shake.
	var drone_t: Transform3D = _drone.global_transform
	var uptilt_basis: Basis = Basis(Vector3(1, 0, 0), deg_to_rad(uptilt_deg))
	var cam_offset: Vector3 = Vector3(0, 0.06, -0.10)
	var local_t: Transform3D = Transform3D(uptilt_basis, cam_offset)
	global_transform = drone_t * local_t
	fov = fov_deg
