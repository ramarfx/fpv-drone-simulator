extends Node3D
## Main — titik masuk scene. Menghubungkan Drone, WarMap, HUD, Kamera,
## Audio, dan mengorkestrasi restart run (ledakan kamikaze / RESET).
## Tidak ada logika fisika di sini; semua di drone_physics.gd.

@export var drone_path: NodePath = NodePath("Drone")
@export var camera_path: NodePath = NodePath("FPVCamera")

var _drone: FPVDrone
var _war_map: Node
var _hud: Node

func _ready() -> void:
	# Pastikan orientasi landscape di Android (juga diatur di project.godot).
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	# Fokus input.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if drone_path != NodePath(""):
		_drone = get_node_or_null(drone_path) as FPVDrone
	_war_map = get_node_or_null("WarMap")
	_hud = get_node_or_null("HUD")
	if _drone != null:
		_drone.destroyed.connect(_on_drone_destroyed)

# Back Android / ESC TIDAK ditangani di sini: main.gd ber-pause_mode INHERIT,
# jadi _input-nya mati saat game ter-pause dan Back tidak bisa unpause
# (softlock). Penanganan Back ada di hud.gd — HUD ber-pause_mode PROCESS.

## Ledakan kamikaze -> pesan tampil 2 detik, lalu restart run otomatis.
func _on_drone_destroyed(_kills: int) -> void:
	await get_tree().create_timer(2.0).timeout
	restart_run()

## Restart run penuh (dipakai ledakan + tombol RESET): drone kembali ke
## spawn (HP/state penuh, RPG lepas), dunia di-roll ulang (seed baru),
## HUD di-reset (kill counter, timer, pesan). URUTAN PENTING: drone dulu
## (teleport ke spawn), baru WarMap (generate chunk di sekitar spawn).
func restart_run() -> void:
	if _drone != null:
		_drone.reset_to_start()
	if _war_map != null and _war_map.has_method("restart_world"):
		_war_map.call("restart_world")
	if _hud != null and _hud.has_method("reset_run"):
		_hud.call("reset_run")
