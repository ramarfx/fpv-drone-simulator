extends Node3D
## WarMap — medan perang parit INFINITE, prosedural, seeded.
## Menggantikan Map.tscn lama (800×800 statis + race gates).
## Chunk 100×100 m, 5×5 chunk di sekitar drone, chunk jauh di-despawn.
## RNG seeded per chunk: seed sama -> chunk sama saat dikunjungi lagi.
## Isi per chunk: tanah lumpur, parit (strip gelap + karung pasir),
## kawah, reruntuhan, pohon gundul, batu, prajurit + tank (non-shooting,
## target kamikaze). Semua mesh/material dipakai bersama (hemat draw call
## + memori). Restart (ledakan / RESET) = seed baru + chunk di-regenerasi.

class_name WarMap

const CHUNK_SIZE: float = 100.0
const RADIUS: int = 2 # 5×5 chunk di sekitar drone.
const BLAST_RADIUS: float = 12.0 # radius ledakan kamikaze.

## DEBUG: mob test untuk verifikasi kamikaze via ADB (prajurit + tank
## persis di depan spawn). Matikan (false) untuk build rilis.
## (Verifikasi on-device tertunda — Azunyan down saat BUILD 10 dibuat;
## nyalakan lagi sementara + rebuild saat verifikasi ADB bisa jalan.)
const DEBUG_TEST_MOBS: bool = false

var world_seed: int = 0
var kills: int = 0

var _chunks: Dictionary = {} # Vector2i(cx,cz) -> Node3D
var _gen_queue: Array[Vector2i] = []
var _mobs: Array[Mob] = []
var _drone: Node3D = null
var _audio: Node = null
var _chunk_timer: float = 0.0

# Material bersama.
var _mat_mud: Array[StandardMaterial3D] = []
var _mat_trench: StandardMaterial3D
var _mat_sand: StandardMaterial3D
var _mat_crater: StandardMaterial3D
var _mat_ruin: StandardMaterial3D
var _mat_ruin2: StandardMaterial3D
var _mat_trunk: StandardMaterial3D
var _mat_branch: StandardMaterial3D
var _mat_rock: StandardMaterial3D
var _mat_soldier_body: StandardMaterial3D
var _mat_soldier_legs: StandardMaterial3D
var _mat_soldier_head: StandardMaterial3D
var _mat_gun: StandardMaterial3D
var _mat_tank: StandardMaterial3D
var _mat_track: StandardMaterial3D
# Mesh bersama.
var _mesh_box: BoxMesh
var _mesh_ground: PlaneMesh
var _mesh_crater: CylinderMesh
var _mesh_trunk: CylinderMesh
var _mesh_barrel: CylinderMesh

func _ready() -> void:
	# Drone + audio dari parent (Main).
	var parent: Node = get_parent()
	if parent != null:
		_drone = parent.get_node_or_null("Drone") as Node3D
		_audio = parent.get_node_or_null("FPVAudio")
	_init_shared()
	# Seed awal acak.
	world_seed = int(Time.get_ticks_usec()) & 0x7FFFFFFF
	# Generate 3×3 awal sinkron (dunia langsung ada), sisanya antre.
	var ccx: int = 0
	var ccz: int = 0
	if _drone != null:
		ccx = floori(_drone.global_position.x / CHUNK_SIZE)
		ccz = floori(_drone.global_position.z / CHUNK_SIZE)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			_generate_chunk(ccx + dx, ccz + dz)
	_refresh_chunk_set()

func _init_shared() -> void:
	# Lumpur: 3 varian hijau-coklat.
	for c in [Color(0.42, 0.38, 0.26, 1), Color(0.38, 0.40, 0.26, 1), Color(0.46, 0.39, 0.24, 1)]:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = c
		_mat_mud.append(m)
	_mat_trench = StandardMaterial3D.new()
	_mat_trench.albedo_color = Color(0.22, 0.18, 0.14, 1)
	_mat_sand = StandardMaterial3D.new()
	_mat_sand.albedo_color = Color(0.65, 0.58, 0.42, 1)
	_mat_crater = StandardMaterial3D.new()
	_mat_crater.albedo_color = Color(0.18, 0.15, 0.12, 1)
	_mat_ruin = StandardMaterial3D.new()
	_mat_ruin.albedo_color = Color(0.5, 0.48, 0.44, 1)
	_mat_ruin2 = StandardMaterial3D.new()
	_mat_ruin2.albedo_color = Color(0.55, 0.50, 0.42, 1)
	_mat_trunk = StandardMaterial3D.new()
	_mat_trunk.albedo_color = Color(0.35, 0.25, 0.18, 1)
	_mat_branch = StandardMaterial3D.new()
	_mat_branch.albedo_color = Color(0.30, 0.28, 0.22, 1)
	_mat_rock = StandardMaterial3D.new()
	_mat_rock.albedo_color = Color(0.45, 0.45, 0.45, 1)
	_mat_soldier_body = StandardMaterial3D.new()
	_mat_soldier_body.albedo_color = Color(0.30, 0.38, 0.22, 1)
	_mat_soldier_legs = StandardMaterial3D.new()
	_mat_soldier_legs.albedo_color = Color(0.25, 0.25, 0.22, 1)
	_mat_soldier_head = StandardMaterial3D.new()
	_mat_soldier_head.albedo_color = Color(0.75, 0.60, 0.50, 1)
	_mat_gun = StandardMaterial3D.new()
	_mat_gun.albedo_color = Color(0.15, 0.15, 0.15, 1)
	_mat_tank = StandardMaterial3D.new()
	_mat_tank.albedo_color = Color(0.28, 0.32, 0.24, 1)
	_mat_track = StandardMaterial3D.new()
	_mat_track.albedo_color = Color(0.15, 0.15, 0.15, 1)
	_mesh_box = BoxMesh.new()
	_mesh_box.size = Vector3(1, 1, 1)
	_mesh_ground = PlaneMesh.new()
	_mesh_ground.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
	_mesh_crater = CylinderMesh.new()
	_mesh_crater.top_radius = 1.0
	_mesh_crater.bottom_radius = 1.0
	_mesh_crater.height = 0.15
	_mesh_trunk = CylinderMesh.new()
	_mesh_trunk.top_radius = 0.22
	_mesh_trunk.bottom_radius = 0.35
	_mesh_trunk.height = 3.0
	_mesh_barrel = CylinderMesh.new()
	_mesh_barrel.top_radius = 0.09
	_mesh_barrel.bottom_radius = 0.09
	_mesh_barrel.height = 2.4

func _process(_delta: float) -> void:
	# Streaming chunk: cek tiap 0.25 detik, generate maks 2 per frame
	# agar tidak hitch.
	_chunk_timer += _delta
	if _chunk_timer >= 0.25:
		_chunk_timer = 0.0
		_refresh_chunk_set()
	for _i in range(2):
		if _gen_queue.is_empty():
			break
		var key: Vector2i = _gen_queue.pop_front()
		if not _chunks.has(key):
			_generate_chunk(key.x, key.y)

func _refresh_chunk_set() -> void:
	if _drone == null:
		return
	var dp: Vector3 = _drone.global_position
	var ccx: int = floori(dp.x / CHUNK_SIZE)
	var ccz: int = floori(dp.z / CHUNK_SIZE)
	for dx in range(-RADIUS, RADIUS + 1):
		for dz in range(-RADIUS, RADIUS + 1):
			var key: Vector2i = Vector2i(ccx + dx, ccz + dz)
			if not _chunks.has(key) and not _gen_queue.has(key):
				_gen_queue.append(key)
	var to_remove: Array[Vector2i] = []
	for key in _chunks.keys():
		var k: Vector2i = key
		if abs(k.x - ccx) > RADIUS or abs(k.y - ccz) > RADIUS:
			to_remove.append(k)
	for key in to_remove:
		_remove_chunk(key)

func _remove_chunk(key: Vector2i) -> void:
	var node: Node = _chunks.get(key)
	if node is Node3D:
		for m in node.find_children("*", "Mob"):
			_mobs.erase(m)
		node.queue_free()
	_chunks.erase(key)

## Seed deterministik per chunk: seed dunia + koordinat chunk.
func _chunk_seed(cx: int, cz: int) -> int:
	var h: int = world_seed ^ (cx * 73856093) ^ (cz * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return abs(h) & 0x7FFFFFFF

func _box(parent: Node, mat: StandardMaterial3D, pos: Vector3, size: Vector3, rot_y: float = 0.0) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = _mesh_box
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	mi.scale = size
	mi.rotation.y = rot_y
	parent.add_child(mi)
	return mi

func _generate_chunk(cx: int, cz: int) -> void:
	var key: Vector2i = Vector2i(cx, cz)
	if _chunks.has(key):
		return
	var root: Node3D = Node3D.new()
	root.name = "Chunk_%d_%d" % [cx, cz]
	root.position = Vector3(cx * CHUNK_SIZE, 0, cz * CHUNK_SIZE)
	add_child(root)
	_chunks[key] = root
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _chunk_seed(cx, cz)
	# --- Tanah + collision (1 StaticBody per chunk) ---
	var ground: StaticBody3D = StaticBody3D.new()
	ground.position.y = -0.5
	var gshape: CollisionShape3D = CollisionShape3D.new()
	var gbox: BoxShape3D = BoxShape3D.new()
	gbox.size = Vector3(CHUNK_SIZE, 1.0, CHUNK_SIZE)
	gshape.shape = gbox
	ground.add_child(gshape)
	var gmesh: MeshInstance3D = MeshInstance3D.new()
	gmesh.mesh = _mesh_ground
	gmesh.set_surface_override_material(0, _mat_mud[rng.randi() % _mat_mud.size()])
	gmesh.position.y = 0.5 # sejajar atas box collision (y=0 dunia)
	ground.add_child(gmesh)
	root.add_child(ground)
	# --- Parit: 1-2 garis, strip gelap + karung pasir ---
	var trench_count: int = 1 + (rng.randi() % 2)
	var trench_centers: Array[Vector3] = []
	for _t in range(trench_count):
		var along_x: bool = rng.randf() < 0.5
		var tlen: float = rng.randf_range(30.0, 60.0)
		var tw: float = 3.0
		var tc: Vector3 = Vector3(rng.randf_range(15.0, 85.0), 0, rng.randf_range(15.0, 85.0))
		trench_centers.append(tc)
		# Strip gelap (cekung visual).
		if along_x:
			_box(root, _mat_trench, Vector3(tc.x, -0.02, tc.z), Vector3(tlen, 0.15, tw))
		else:
			_box(root, _mat_trench, Vector3(tc.x, -0.02, tc.z), Vector3(tw, 0.15, tlen))
		# Karung pasir: 1 balok panjang per sisi + 4 tonjolan.
		for side in [-1.0, 1.0]:
			var off: float = side * (tw / 2.0 + 0.4)
			var wall_pos: Vector3
			var wall_size: Vector3
			if along_x:
				wall_pos = Vector3(tc.x, 0.25, tc.z + off)
				wall_size = Vector3(tlen, 0.5, 0.7)
			else:
				wall_pos = Vector3(tc.x + off, 0.25, tc.z)
				wall_size = Vector3(0.7, 0.5, tlen)
			_box(root, _mat_sand, wall_pos, wall_size)
			for _b in range(4):
				var bx: float
				var bz: float
				if along_x:
					bx = tc.x + rng.randf_range(-tlen / 2.0, tlen / 2.0)
					bz = tc.z + off + rng.randf_range(-0.15, 0.15)
				else:
					bx = tc.x + off + rng.randf_range(-0.15, 0.15)
					bz = tc.z + rng.randf_range(-tlen / 2.0, tlen / 2.0)
				_box(root, _mat_sand, Vector3(bx, 0.55, bz), Vector3(0.8, 0.35, 0.5), rng.randf_range(0.0, TAU))
	# --- Kawah: 2-4 cakram gelap ---
	for _i in range(2 + rng.randi() % 3):
		var cxp: float = rng.randf_range(8.0, 92.0)
		var czp: float = rng.randf_range(8.0, 92.0)
		var cr: float = rng.randf_range(2.0, 4.5)
		var cm: MeshInstance3D = MeshInstance3D.new()
		cm.mesh = _mesh_crater
		cm.set_surface_override_material(0, _mat_crater)
		cm.position = Vector3(cxp, 0.05, czp)
		cm.scale = Vector3(cr, 1.0, cr)
		root.add_child(cm)
	# --- Reruntuhan: 50% chance, 2-4 dinding (collision ON) ---
	if rng.randf() < 0.5:
		var bx0: float = rng.randf_range(15.0, 70.0)
		var bz0: float = rng.randf_range(15.0, 70.0)
		var mat: StandardMaterial3D = _mat_ruin if rng.randf() < 0.5 else _mat_ruin2
		for _w in range(2 + rng.randi() % 3):
			var wlen: float = rng.randf_range(4.0, 10.0)
			var wh: float = rng.randf_range(2.0, 4.0)
			var wx: float = bx0 + rng.randf_range(-6.0, 6.0)
			var wz: float = bz0 + rng.randf_range(-6.0, 6.0)
			var rot: float = 0.0 if rng.randf() < 0.5 else PI / 2.0
			var wall: StaticBody3D = StaticBody3D.new()
			wall.position = Vector3(wx, wh / 2.0, wz)
			wall.rotation.y = rot
			var ws: CollisionShape3D = CollisionShape3D.new()
			var wb: BoxShape3D = BoxShape3D.new()
			wb.size = Vector3(wlen, wh, 0.6)
			ws.shape = wb
			wall.add_child(ws)
			var wm: MeshInstance3D = MeshInstance3D.new()
			wm.mesh = _mesh_box
			wm.set_surface_override_material(0, mat)
			wm.scale = Vector3(wlen, wh, 0.6)
			wall.add_child(wm)
			root.add_child(wall)
	# --- Pohon gundul: 1-3 (visual saja) ---
	for _i in range(1 + rng.randi() % 3):
		var tx: float = rng.randf_range(8.0, 92.0)
		var tz: float = rng.randf_range(8.0, 92.0)
		var trunk: MeshInstance3D = MeshInstance3D.new()
		trunk.mesh = _mesh_trunk
		trunk.set_surface_override_material(0, _mat_trunk)
		trunk.position = Vector3(tx, 1.5, tz)
		root.add_child(trunk)
		for _b in range(2 + rng.randi() % 2):
			var ang: float = rng.randf_range(0.0, TAU)
			var bx2: float = tx + cos(ang) * rng.randf_range(0.4, 0.9)
			var bz2: float = tz + sin(ang) * rng.randf_range(0.4, 0.9)
			var br: MeshInstance3D = MeshInstance3D.new()
			br.mesh = _mesh_box
			br.set_surface_override_material(0, _mat_branch)
			br.position = Vector3(bx2, 2.8 + rng.randf_range(-0.3, 0.5), bz2)
			br.scale = Vector3(rng.randf_range(0.8, 1.6), 0.18, 0.18)
			br.rotation.y = ang
			root.add_child(br)
	# --- Batu: 2-3 (visual saja) ---
	for _i in range(2 + rng.randi() % 2):
		var rx: float = rng.randf_range(8.0, 92.0)
		var rz: float = rng.randf_range(8.0, 92.0)
		_box(root, _mat_rock, Vector3(rx, rng.randf_range(0.2, 0.5), rz),
			Vector3(rng.randf_range(0.6, 1.6), rng.randf_range(0.4, 1.0), rng.randf_range(0.6, 1.6)),
			rng.randf_range(0.0, TAU))
	# --- Mob: prajurit 1-3 di 60% chunk, tank 0-1 di 25% chunk ---
	if rng.randf() < 0.6:
		var n: int = 1 + rng.randi() % 3
		for _s in range(n):
			var sp: Vector3
			var pa: Vector3
			var pb: Vector3
			if not trench_centers.is_empty() and rng.randf() < 0.7:
				var tc: Vector3 = trench_centers[rng.randi() % trench_centers.size()]
				sp = Vector3(tc.x + rng.randf_range(-12.0, 12.0), 0, tc.z + rng.randf_range(-3.0, 3.0))
				# Patroli 10 m lewat posisi spawn (sp = midpoint, tanpa pop).
				pa = Vector3(sp.x - 5.0, 0, sp.z)
				pb = Vector3(sp.x + 5.0, 0, sp.z)
			else:
				sp = Vector3(rng.randf_range(10.0, 90.0), 0, rng.randf_range(10.0, 90.0))
				pa = Vector3(sp.x - 5.0, 0, sp.z)
				pb = Vector3(sp.x + 5.0, 0, sp.z)
			_spawn_soldier(root, sp, pa, pb)
	if rng.randf() < 0.25:
		var tp: Vector3 = Vector3(rng.randf_range(12.0, 88.0), 0, rng.randf_range(12.0, 88.0))
		_spawn_tank(root, tp)
	# --- Mob test DEBUG (depan spawn, deterministik) ---
	if DEBUG_TEST_MOBS and cx == 0 and cz == -1:
		# Chunk (0,-1) origin (0,0,-100): lokal (0,1,75) = dunia (0,1,-25).
		# Prajurit test DIAM (patroli titik sama) agar tes kamikaze deterministik.
		_spawn_soldier(root, Vector3(0, 0, 75), Vector3(0, 0, 75), Vector3(0, 0, 75))
		_spawn_tank(root, Vector3(5, 0, 73))

func _spawn_soldier(parent: Node, pos: Vector3, patrol_a: Vector3, patrol_b: Vector3) -> void:
	var mob: Mob = Mob.new()
	mob.position = pos
	mob.collision_layer = 1
	mob.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.6, 1.8, 0.4)
	shape.shape = box
	shape.position.y = 0.9
	mob.add_child(shape)
	# Kaki.
	var legs: MeshInstance3D = MeshInstance3D.new()
	legs.mesh = _mesh_box
	legs.set_surface_override_material(0, _mat_soldier_legs)
	legs.position = Vector3(0, 0.35, 0)
	legs.scale = Vector3(0.45, 0.5, 0.28)
	mob.add_child(legs)
	# Badan.
	var body: MeshInstance3D = MeshInstance3D.new()
	body.mesh = _mesh_box
	body.set_surface_override_material(0, _mat_soldier_body)
	body.position = Vector3(0, 0.95, 0)
	body.scale = Vector3(0.5, 0.9, 0.3)
	mob.add_child(body)
	# Kepala.
	var head: MeshInstance3D = MeshInstance3D.new()
	head.mesh = _mesh_box
	head.set_surface_override_material(0, _mat_soldier_head)
	head.position = Vector3(0, 1.55, 0)
	head.scale = Vector3(0.3, 0.3, 0.3)
	mob.add_child(head)
	# Senjata (visual saja — tidak menembak).
	var gun: MeshInstance3D = MeshInstance3D.new()
	gun.mesh = _mesh_box
	gun.set_surface_override_material(0, _mat_gun)
	gun.position = Vector3(0.25, 1.15, -0.4)
	gun.scale = Vector3(0.08, 0.08, 0.7)
	mob.add_child(gun)
	parent.add_child(mob)
	mob.setup(Mob.MobType.SOLDIER, self, _drone, patrol_a, patrol_b)
	_mobs.append(mob)

func _spawn_tank(parent: Node, pos: Vector3) -> void:
	var mob: Mob = Mob.new()
	mob.position = pos
	mob.collision_layer = 1
	mob.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(2.4, 1.8, 3.8)
	shape.shape = box
	shape.position.y = 0.9
	mob.add_child(shape)
	# Rantai kiri/kanan.
	for side in [-1.0, 1.0]:
		var track: MeshInstance3D = MeshInstance3D.new()
		track.mesh = _mesh_box
		track.set_surface_override_material(0, _mat_track)
		track.position = Vector3(side * 1.0, 0.45, 0)
		track.scale = Vector3(0.6, 0.7, 3.8)
		mob.add_child(track)
	# Hull.
	var hull: MeshInstance3D = MeshInstance3D.new()
	hull.mesh = _mesh_box
	hull.set_surface_override_material(0, _mat_tank)
	hull.position = Vector3(0, 0.75, 0)
	hull.scale = Vector3(2.2, 0.9, 3.6)
	mob.add_child(hull)
	# Turret (berputar pelan, scan visual).
	var turret: MeshInstance3D = MeshInstance3D.new()
	turret.name = "Turret"
	turret.mesh = _mesh_box
	turret.set_surface_override_material(0, _mat_tank)
	turret.position = Vector3(0, 1.5, 0)
	turret.scale = Vector3(1.4, 0.6, 1.8)
	mob.add_child(turret)
	# Laras (anak turret, ikut berputar).
	var barrel: MeshInstance3D = MeshInstance3D.new()
	barrel.name = "Barrel"
	barrel.mesh = _mesh_barrel
	barrel.set_surface_override_material(0, _mat_track)
	barrel.position = Vector3(0, 0, -2.6)
	barrel.rotation.x = PI / 2.0
	turret.add_child(barrel)
	parent.add_child(mob)
	mob.setup(Mob.MobType.TANK, self, _drone, pos, pos)
	mob._turret = turret
	_mobs.append(mob)

## Ledakan kamikaze: visual + bunyi + bunuh semua mob dalam radius.
## Return jumlah kill dari ledakan ini.
func explode_at(pos: Vector3, radius: float) -> int:
	var ex: Explosion = Explosion.new()
	add_child(ex)
	ex.start(pos, radius)
	if _audio != null and _audio.has_method("play_explosion"):
		_audio.call("play_explosion")
	var gained: int = 0
	var to_erase: Array[Mob] = []
	for mob in _mobs:
		if mob == null or not is_instance_valid(mob) or mob.is_dead():
			continue
		if mob.global_position.distance_to(pos) <= radius:
			mob.die_by_blast()
			gained += 1
			if mob.mob_type == Mob.MobType.SOLDIER:
				to_erase.append(mob)
	for mob in to_erase:
		_mobs.erase(mob)
	kills += gained
	return gained

## Restart dunia: seed baru, semua chunk dihapus, regenerasi di spawn.
## Dipanggil main.restart_run() SETELAH drone di-reset ke spawn, agar
## chunk awal digenerate di sekitar spawn (bukan titik kematian).
func restart_world() -> void:
	for key in _chunks.keys():
		var node: Node = _chunks.get(key)
		if node is Node3D:
			remove_child(node)
			node.free()
	_chunks.clear()
	_mobs.clear()
	_gen_queue.clear()
	kills = 0
	world_seed = int(Time.get_ticks_usec()) & 0x7FFFFFFF
	var ccx: int = 0
	var ccz: int = 0
	if _drone != null:
		ccx = floori(_drone.global_position.x / CHUNK_SIZE)
		ccz = floori(_drone.global_position.z / CHUNK_SIZE)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			_generate_chunk(ccx + dx, ccz + dz)
	_refresh_chunk_set()
