extends Control
## Joystick virtual — Control kustom (lebih andal di Android daripada TouchScreenButton).
## Kiri (Mode 2): vertikal = throttle (0..1, TIDAK spring — stays where left),
##   horizontal = yaw. Kanan: pitch + roll, spring ke tengah.
## Mendukung sentuhan + mouse (fallback desktop).
##
## ATURAN KOORDINAT (penting!): posisi event di _gui_input SUDAH dalam
## koordinat LOKAL control ini — engine mentransformasi event ke ruang lokal
## sebelum memanggil _gui_input (lihat Viewport::_gui_input_event:
## pos = over->get_global_transform_with_canvas().affine_inverse().xform(pos)).
## Jadi JANGAN bandingkan event.position dengan get_global_rect() (ruang
## global/canvas) — has_point() akan selalu FALSE dan stick tidak pernah
## mengklaim sentuhan. Pakai Rect2(Vector2.ZERO, size) untuk hit-test dan
## langsung kurangi _center untuk drag.

class_name VirtualJoystick

@export var is_left_stick: bool = true
@export var radius: float = 70.0

## Deadzone radial 0.10 (10% radius) untuk pitch/roll/yaw, dengan rescale
## sisa travel ke 0..1 — diagonal tidak jadi kotak. Perbaiki getaran jari
## di tengah tanpa membuat tengah terasa mati. TIDAK dipakai pada sumbu
## throttle: deadzone di throttle membuat hunting ketinggian di sekitar
## hover makin parah; presisi hover diatur throttle expo.
const DEADZONE: float = 0.10

signal stick_changed(value: Vector2)

var value: Vector2 = Vector2.ZERO # x: -1..1 (yaw / roll), y: -1..1 (throttle / pitch)
var _touch_id: int = -1
var _center: Vector2 = Vector2.ZERO
var _knob_pos: Vector2 = Vector2.ZERO
var _base: ColorRect
var _knob: ColorRect

func _ready() -> void:
	_center = size / 2.0
	_knob_pos = _center
	# Buat visual base + knob via kode (tidak butuh scene terpisah).
	# PENTING: visual base/knob HARUS IGNORE. _gui_find_control_at_pos
	# mengembalikan Control TERDALAM di bawah sentuhan, dan STOP menghentikan
	# rantai propagasi — jadi kalau base/knob (ColorRect, default STOP)
	# dibiarkan, merekalah yang menerima sentuhan dan joystick (parent)
	# tidak pernah melihatnya. IGNORE membuat pencarian tembus ke joystick.
	_base = ColorRect.new()
	_base.color = Color(1, 1, 1, 0.18)
	_base.size = Vector2(radius * 2.0, radius * 2.0)
	_base.position = _center - _base.size / 2.0
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_base)
	_knob = ColorRect.new()
	_knob.color = Color(1, 1, 1, 0.85)
	_knob.size = Vector2(radius * 0.9, radius * 0.9)
	_knob.position = _center - _knob.size / 2.0
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_knob)
	# Throttle kiri mulai di bawah (0).
	if is_left_stick:
		_knob_pos = Vector2(_center.x, _center.y + radius * 0.9)
		value = Vector2(0, 0)
		_update_knob()
	mouse_filter = Control.MOUSE_FILTER_STOP

func _update_knob() -> void:
	if _knob != null:
		_knob.position = _knob_pos - _knob.size / 2.0

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		# Sentuhan-down di dalam rect SELALU mengklaim stick (sentuhan
		# terbaru menang). Ini self-healing: kalau _touch_id pernah nyangkut
		# karena event touch-up hilang (app kehilangan fokus, dsb.), sentuhan
		# baru tetap bisa merebut stick — stick tidak mati selamanya.
		if touch.pressed:
			# Hanya terima sentuhan yang mulai di dalam joystick ini.
			# touch.position di _gui_input adalah LOKAL — uji terhadap
			# rect lokal (0,0)-(size), BUKAN get_global_rect().
			if Rect2(Vector2.ZERO, size).has_point(touch.position):
				_touch_id = touch.index
				_handle_drag(touch.position)
				accept_event()
		elif not touch.pressed and touch.index == _touch_id:
			_touch_id = -1
			_release()
			accept_event()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _touch_id:
			_handle_drag(drag.position)
			accept_event()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _touch_id == -1:
				# mb.position di _gui_input juga LOKAL — uji rect lokal.
				if Rect2(Vector2.ZERO, size).has_point(mb.position):
					_touch_id = 1000
					_handle_drag(mb.position)
					accept_event()
			elif not mb.pressed and _touch_id == 1000:
				_touch_id = -1
				_release()
				accept_event()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if _touch_id == 1000:
			_handle_drag(mm.position)
			accept_event()

## Deadzone 1D dengan rescale (untuk yaw): |v| < dz -> 0, sisanya
## dipetakan ulang ke 0..1 agar stick penuh tetap memberi perintah penuh.
func _deadzone_1d(v: float) -> float:
	if absf(v) < DEADZONE:
		return 0.0
	return signf(v) * (absf(v) - DEADZONE) / (1.0 - DEADZONE)

## Deadzone RADIAL (melingkar) dengan rescale (untuk pitch+roll):
## arah dipertahankan, jadi diagonal tidak terdistorsi jadi kotak.
func _deadzone_2d(v: Vector2) -> Vector2:
	var l: float = v.length()
	if l < DEADZONE:
		return Vector2.ZERO
	if l >= 1.0:
		return v.normalized()
	return v.normalized() * ((l - DEADZONE) / (1.0 - DEADZONE))

## local_pos = posisi event dari _gui_input (sudah LOKAL, bukan global).
func _handle_drag(local_pos: Vector2) -> void:
	var local: Vector2 = local_pos - _center
	# Jepit ke lingkaran radius.
	if local.length() > radius:
		local = local.normalized() * radius
	# Knob menampilkan posisi jari mentah (tanpa deadzone) — yang
	# di-deadzone hanya nilai perintah yang dikirim ke drone.
	_knob_pos = _center + local
	if is_left_stick:
		# Kiri: x = yaw (-1 kiri, +1 kanan), y = throttle (atas=1, bawah=0).
		# Di layar, y ke bawah positif, jadi throttle = 1 - (local.y/radius+1)/2.
		# Deadzone hanya pada yaw; throttle tanpa deadzone.
		var yaw: float = _deadzone_1d(clampf(local.x / radius, -1.0, 1.0))
		var thr: float = clampf(1.0 - ((local.y / radius) + 1.0) / 2.0, 0.0, 1.0)
		value = Vector2(yaw, thr)
	else:
		# Kanan: x = roll (kanan=+1), y = pitch (stick atas = pitch maju = +1).
		# Layar y bawah positif -> pitch = -local.y/radius.
		# Deadzone radial pada pasangan (roll, pitch).
		var raw: Vector2 = Vector2(
			clampf(local.x / radius, -1.0, 1.0),
			clampf(-local.y / radius, -1.0, 1.0)
		)
		value = _deadzone_2d(raw)
	_update_knob()
	stick_changed.emit(value)

func _release() -> void:
	if is_left_stick:
		# Throttle STAYS (tidak spring). Yaw kembali ke tengah.
		value.x = 0.0
		_knob_pos.x = _center.x
		# Y tetap (throttle dipertahankan).
		_update_knob()
		stick_changed.emit(value)
	else:
		value = Vector2.ZERO
		_knob_pos = _center
		_update_knob()
		stick_changed.emit(value)

## Reset dari luar (mis. setelah RESET).
func reset_stick() -> void:
	_touch_id = -1
	if is_left_stick:
		value = Vector2(0, 0)
		_knob_pos = Vector2(_center.x, _center.y + radius * 0.9)
	else:
		value = Vector2.ZERO
		_knob_pos = _center
	_update_knob()
