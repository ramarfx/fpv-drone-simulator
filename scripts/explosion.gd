extends Node3D
class_name Explosion
## Efek ledakan kamikaze — visual saja (damage diurus war_map.explode_at).
## Bola api mengembang + memudar, asap membesar + memudar, cahaya titik
## oranye, 8 serpihan beterbangan. Semua dibuat via kode (tanpa scene),
## lalu node ini menghapus dirinya setelah ~0.9 detik.

var _fire: MeshInstance3D
var _smoke: MeshInstance3D
var _light: OmniLight3D
var _debris: Array[MeshInstance3D] = []
var _debris_vel: Array[Vector3] = []
var _fire_mat: StandardMaterial3D
var _smoke_mat: StandardMaterial3D
var _t: float = 0.0
const LIFE: float = 0.9

func start(pos: Vector3, radius: float) -> void:
	position = pos
	# Bola api.
	_fire = MeshInstance3D.new()
	var fire_mesh: SphereMesh = SphereMesh.new()
	fire_mesh.radius = radius * 0.25
	fire_mesh.height = radius * 0.5
	_fire.mesh = fire_mesh
	_fire_mat = StandardMaterial3D.new()
	_fire_mat.albedo_color = Color(1.0, 0.55, 0.1, 1)
	_fire_mat.emission_enabled = true
	_fire_mat.emission = Color(1.0, 0.45, 0.05, 1)
	_fire_mat.emission_energy_multiplier = 3.0
	_fire.set_surface_override_material(0, _fire_mat)
	add_child(_fire)
	# Asap.
	_smoke = MeshInstance3D.new()
	var smoke_mesh: SphereMesh = SphereMesh.new()
	smoke_mesh.radius = radius * 0.2
	smoke_mesh.height = radius * 0.4
	_smoke.mesh = smoke_mesh
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.albedo_color = Color(0.25, 0.25, 0.25, 1)
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.albedo_color.a = 0.55
	_smoke.set_surface_override_material(0, _smoke_mat)
	_smoke.position.y = radius * 0.15
	add_child(_smoke)
	# Cahaya ledakan.
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.2, 1)
	_light.light_energy = 14.0
	_light.omni_range = radius * 2.5
	_light.position.y = 1.0
	add_child(_light)
	# Serpihan.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec()) & 0x7FFFFFFF
	for _i in range(8):
		var d: MeshInstance3D = MeshInstance3D.new()
		var bm: BoxMesh = BoxMesh.new()
		var s: float = rng.randf_range(0.15, 0.45)
		bm.size = Vector3(s, s, s)
		d.mesh = bm
		var dm: StandardMaterial3D = StandardMaterial3D.new()
		dm.albedo_color = Color(0.32, 0.28, 0.25, 1)
		d.set_surface_override_material(0, dm)
		add_child(d)
		_debris.append(d)
		var v: Vector3 = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(0.5, 2.0),
			rng.randf_range(-1.0, 1.0)
		).normalized() * rng.randf_range(6.0, 14.0)
		_debris_vel.append(v)

func _process(delta: float) -> void:
	_t += delta
	var k: float = clampf(_t / LIFE, 0.0, 1.0)
	# Api: cepat membesar lalu memudar.
	if _fire != null:
		var fs: float = 1.0 + k * 2.2
		_fire.scale = Vector3(fs, fs * 0.8, fs)
		_fire_mat.albedo_color.a = 1.0 - k
		_fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if _smoke != null:
		var ss: float = 1.0 + k * 3.0
		_smoke.scale = Vector3(ss, ss, ss)
		_smoke.position.y += delta * 2.0
		_smoke_mat.albedo_color.a = 0.55 * (1.0 - k * 0.8)
	if _light != null:
		_light.light_energy = 14.0 * (1.0 - k)
	for i in range(_debris.size()):
		var d: MeshInstance3D = _debris[i]
		var v: Vector3 = _debris_vel[i]
		v.y -= 9.8 * delta
		_debris_vel[i] = v
		d.position += v * delta
		d.rotation.x += delta * 7.0
		d.rotation.y += delta * 5.0
		if d.position.y < 0.05:
			d.position.y = 0.05
			_debris_vel[i] = Vector3(v.x * 0.5, -v.y * 0.3, v.z * 0.5)
	if _t >= LIFE:
		queue_free()
