extends Node3D
## Main — titik masuk scene. Menghubungkan Drone, Map, HUD, Kamera, Audio.
## Tidak ada logika fisika di sini; semua di drone_physics.gd.

@export var drone_path: NodePath = NodePath("Drone")
@export var camera_path: NodePath = NodePath("FPVCamera")

func _ready() -> void:
	# Pastikan orientasi landscape di Android (juga diatur di project.godot).
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	# Fokus input.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# Back Android / ESC TIDAK ditangani di sini: main.gd ber-pause_mode INHERIT,
# jadi _input-nya mati saat game ter-pause dan Back tidak bisa unpause
# (softlock). Penanganan Back ada di hud.gd — HUD ber-pause_mode PROCESS.
