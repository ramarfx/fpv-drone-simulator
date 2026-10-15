extends Area3D
## Gate balap: Area3D pendeteksi lintasan drone.
## Saat drone melewati bidang gate, kirim gate_passed ke drone.

@export var gate_index: int = 0
var _drone: FPVDrone

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Cari drone di scene (parent Main -> Drone).
	var root: Node = get_tree().current_scene
	if root != null:
		_drone = root.get_node_or_null("Drone") as FPVDrone

func _on_body_entered(body: Node3D) -> void:
	if body is FPVDrone:
		# Hanya hitung jika drone melaju searah gate (dot forward > 0).
		var fwd: Vector3 = -global_transform.basis.z
		var vel: Vector3 = (body as FPVDrone).linear_velocity
		if vel.dot(fwd) > 0.0:
			if _drone != null:
				_drone.gate_passed.emit(gate_index)
