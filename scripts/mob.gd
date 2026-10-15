extends StaticBody3D
## Mob perang — target kamikaze NON-SHOOTING.
## Prajurit + tank HANYA patroli/idle. Mereka tidak menembak, tidak
## memberi damage, tidak punya HP bar. Satu-satunya cara mereka hancur
## adalah ledakan kamikaze drone (war_map.explode_at).
## Perilaku: prajurit patroli bolak-balik di dekat parit; tank diam
## dengan turret berputar pelan (scan). Semua visual low-poly, material
## + mesh dipakai bersama (dibuat war_map, diteruskan ke sini).

class_name Mob

enum MobType { SOLDIER, TANK }

@export var mob_type: MobType = MobType.SOLDIER

var war_map: Node = null
var _drone: Node3D = null
var _patrol_a: Vector3 = Vector3.ZERO
var _patrol_b: Vector3 = Vector3.ZERO
var _patrol_t: float = 0.0
var _patrol_dir: float = 1.0
var _patrol_speed: float = 0.8
var _turret: MeshInstance3D = null
var _turret_scan: float = 0.0
var _dead: bool = false

func setup(type: MobType, map_ref: Node, drone_ref: Node3D, patrol_a: Vector3, patrol_b: Vector3) -> void:
	mob_type = type
	war_map = map_ref
	_drone = drone_ref
	_patrol_a = patrol_a
	_patrol_b = patrol_b
	# Mulai di tengah segmen patroli (sp = midpoint) agar tidak teleport
	# di frame pertama.
	_patrol_t = 0.5
	_patrol_speed = randf_range(0.6, 1.1)
	# Tank: turret diputar pelan untuk kesan "scan" (visual saja).
	_turret_scan = randf_range(0.0, TAU)

func _process(delta: float) -> void:
	if _dead:
		return
	if mob_type == MobType.SOLDIER:
		# Patroli bolak-balik antara dua titik (ping-pong), pelan.
		_patrol_t += delta * _patrol_speed * _patrol_dir * 0.08
		if _patrol_t >= 1.0:
			_patrol_t = 1.0
			_patrol_dir = -1.0
		elif _patrol_t <= 0.0:
			_patrol_t = 0.0
			_patrol_dir = 1.0
		var target: Vector3 = _patrol_a.lerp(_patrol_b, _patrol_t)
		# Hadap arah jalan.
		var dir: Vector3 = _patrol_b - _patrol_a
		if dir.length_squared() > 0.01:
			var yaw: float = atan2(dir.x, dir.z)
			rotation.y = lerp_angle(rotation.y, yaw if _patrol_dir > 0.0 else yaw + PI, delta * 3.0)
		position.x = target.x
		position.z = target.z
	else:
		# Tank diam; turret scan pelan kiri-kanan.
		_turret_scan += delta * 0.15
		if _turret != null:
			_turret.rotation.y = sin(_turret_scan) * 0.6

func is_dead() -> bool:
	return _dead

## Dipanggil war_map saat mob mati kena ledakan kamikaze.
## Tank jadi bangkai (hitam, turret hilang) sampai chunk di-despawn;
## prajurit langsung hilang.
func die_by_blast() -> void:
	if _dead:
		return
	_dead = true
	if mob_type == MobType.TANK:
		# Jadi bangkai: hitamkan hull, sembunyikan turret + laras.
		for child in get_children():
			if child is MeshInstance3D:
				var mi: MeshInstance3D = child
				if mi.name == "Turret" or mi.name == "Barrel":
					mi.visible = false
				else:
					# Bangkai tetap gelap tapi TIDAK hitam pekat (0.08 -> 0.20)
					# agar tetap terlihat di bawah global light.
					var black: StandardMaterial3D = StandardMaterial3D.new()
					black.albedo_color = Color(0.20, 0.20, 0.20, 1)
					mi.set_surface_override_material(0, black)
		# Bangkai tidak lagi jadi target (tidak bisa diledakkan 2x).
		collision_layer = 0
	else:
		queue_free()
