extends RefCounted
class_name FlightController
## FlightController — Betaflight-style Actual Rates + PID angular-velocity.
## Dipakai oleh drone_physics.gd. Semua satuan SI, sudut dalam radian.
##
## Actual Rates (Betaflight) — pendekatan yang dipakai di sini:
##   rate = stick * max_rate * ((1 - expo) + expo * stick^2)  dengan center scaling.
## Nilai default: center=1.0, max=800 deg/s, expo=0.70.
## Ini memberi resolusi halus di tengah (presisi) dan agresif di ujung (flip/roll).

const MAX_RATE_DEG: float = 800.0
const CENTER: float = 1.0
const EXPO: float = 0.70

## Konversi stick [-1,1] -> laju sudut radian/detik (Actual Rates).
static func actual_rates(stick: float) -> float:
	var s: float = clampf(stick, -1.0, 1.0)
	var max_rad: float = deg_to_rad(MAX_RATE_DEG)
	# Center: sensitivitas di tengah. Expo: kurva.
	var curve: float = (1.0 - EXPO) + EXPO * s * s
	# Faktor center memperhalus area tengah tanpa mengubah ujung.
	var rate: float = s * max_rad * curve * CENTER
	return rate

## PID untuk angular velocity, satu sumbu.
## state disimpan per-sumbu di drone (integral, prev_error, d_filtered).
class PIDAxis:
	var kp: float = 4.2
	var ki: float = 0.9
	var kd: float = 0.025
	var ff: float = 0.6
	var integral: float = 0.0
	var prev_error: float = 0.0
	var d_filtered: float = 0.0
	var integral_limit: float = 0.6
	# Lowpass D-term 80 Hz -> alpha per tick dihitung di update().
	var d_cutoff: float = 80.0

	func reset() -> void:
		integral = 0.0
		prev_error = 0.0
		d_filtered = 0.0

	## desired & measured dalam rad/s, dt detik. Return torque (Nm) mentah.
	## Anti-windup: integral dijepit, dan tidak diintegrasikan saat output jenuh.
	func update(desired: float, measured: float, dt: float, output_limit: float) -> float:
		var err: float = desired - measured
		# D-term: turunan error, lowpass 80 Hz.
		var d_raw: float = 0.0
		if dt > 0.0:
			d_raw = (err - prev_error) / dt
		var alpha: float = 1.0
		if dt > 0.0:
			alpha = dt / (dt + 1.0 / (2.0 * PI * d_cutoff))
		d_filtered = lerp(d_filtered, d_raw, alpha)
		prev_error = err
		# Integrasi dengan anti-windup: hanya integrasikan jika belum jenuh
		# atau error mengarah menjauhi saturasi.
		var p_term: float = kp * err
		var ff_term: float = ff * desired
		var d_term: float = kd * d_filtered
		var out_wo_i: float = p_term + ff_term + d_term
		if absf(out_wo_i + ki * integral) < output_limit or signf(err) != signf(out_wo_i + ki * integral):
			integral = clampf(integral + err * dt, -integral_limit, integral_limit)
		var out: float = p_term + ki * integral + d_term + ff_term
		return clampf(out, -output_limit, output_limit)

## Mixing X-config: ubah kontribusi PID ternormalisasi -> perintah motor [0,1].
## Urutan motor: 0=FR, 1=FL, 2=RR, 3=RL.
## pitch>0 = nose-up (motor depan +), roll>0 = torque +Z (motor kanan +),
## yaw>0 = torque +Y (motor FR+RL +).
## Jika ada motor jenuh (>1), skala kontribusi pitch/roll agar yaw tetap punya otoritas.
static func mix_motors(throttle: float, pitch_n: float, roll_n: float, yaw_n: float) -> Array[float]:
	var p: float = pitch_n
	var r: float = roll_n
	# Cek saturasi, skala pitch/roll saja (yaw dipertahankan).
	for _i in range(2):
		var m0: float = throttle + p - r + yaw_n
		var m1: float = throttle + p + r - yaw_n
		var m2: float = throttle - p - r - yaw_n
		var m3: float = throttle - p + r + yaw_n
		var mx: float = maxf(maxf(m0, m1), maxf(m2, m3))
		if mx <= 1.0:
			break
		var scale: float = 0.9 / mx
		p *= scale
		r *= scale
	var out: Array[float] = []
	out.append(clampf(throttle + p - r + yaw_n, 0.0, 1.0))
	out.append(clampf(throttle + p + r - yaw_n, 0.0, 1.0))
	out.append(clampf(throttle - p - r - yaw_n, 0.0, 1.0))
	out.append(clampf(throttle - p + r + yaw_n, 0.0, 1.0))
	return out
