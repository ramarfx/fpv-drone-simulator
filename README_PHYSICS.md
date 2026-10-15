# Fisika FPV Drone Simulator — Model & Tuning

Drone 5" freestyle. Semua di `scripts/drone_physics.gd` + `scripts/flight_controller.gd`.
Fisika jalan di **240 Hz** (`physics_ticks_per_second=240` di `project.godot`),
via `RigidBody3D._integrate_forces`.

## 1. Parameter dasar

| Parameter | Nilai |
|---|---|
| Massa | 0.65 kg |
| Inersia (diagonal) | Ixx=0.0042, Iyy=0.0075 (yaw), Izz=0.0042 kg·m² |
| Konfigurasi | X, arm 0.115 m (pusat → motor) |
| Max thrust / motor | 10 N → total 40 N, TWR ≈ 6.2 |
| Gravitasi | 9.81 m/s² (engine) |
| Udara | ρ = 1.225 kg/m³ |

Inersia disetel lewat properti `RigidBody3D.inertia`. Integrator Godot
memakai tensor inersia ini, sehingga kopling giroskopik `ω × (I·ω)` muncul
secara alami dari integrasi rigid-body — tidak ditambah manual (menghindari
double-count).

## 2. Motor

Thrust per motor: `F = kT · ω²`. Di kode, `ω ∝ √cmd` sehingga
`F = 10 N · cmd` (cmd 0..1 setelah lag).

Dinamika motor: lag orde-1
```
filtered += (target - filtered) * dt / (tau + dt),  tau = 0.03 s
```
RPM untuk suara/visual: `RPM = √filtered · 28000 · battery_factor`.

## 3. Baterai 4S

- Kapasitas 1500 mAh, open-voltage: `14.0 + charge·2.8` (14.0 kosong → 16.8 penuh).
- Arus: `I = Σcmd · 25 A · 0.25 + 1 A` (idle).
- Sag: `V = V_open − I·R`, `R = 0.02 Ω`.
- Faktor thrust: `clamp(V / 16.8, 0.72, 1.0)`.
- Pengosongan: `charge -= I·dt/3600·1000 / 1500`.
- Di bawah ~14.0 V, OSD merah + thrust turun (low-batt).

## 4. Flight Controller — Actual Rates + PID

Stick → desired angular velocity (Actual Rates Betaflight):
```
rate = stick · 800°/s · ((1−0.70) + 0.70·stick²) · 1.0 (center)
```
- Center 1.0, max 800 °/s, expo 0.70.
- Pemetaan sumbu (Godot: X kanan, Y atas, Z belakang):
  `ω_des = (−pitch_rate, −yaw_rate, −roll_rate)`.

PID angular-velocity per sumbu:
```
τ = P·err + I·∫err + D·d(err)/dt (lowpass 80 Hz) + FF·ω_des
P=4.2, I=0.9 (anti-windup, integral dijepit ±0.6), D=0.025, FF=0.6
Yaw: P=3.2, I=0.7, D=0.015 (otoritas yaw lebih lemah)
```
Batas torque: pitch/roll 2.3 N·m (thrust diferensial × arm), yaw 0.45 N·m.

Mixing X (0=FR, 1=FL, 2=RR, 3=RL):
```
FR = thr + pitch − roll + yaw
FL = thr + pitch + roll − yaw
RR = thr − pitch − roll − yaw
RL = thr − pitch + roll + yaw
```
Jika ada motor jenuh (>1), kontribusi pitch/roll diskala turun agar
yaw tetap punya otoritas. Airmode: PID selalu aktif walau throttle 0.

Mode ANGLE: desired tilt = stick × 35°, lalu
`ω_des = 6.0 · (tilt_des − tilt_now)` dijepit ±300 °/s. Yaw tetap rate.

## 5. Gaya aerodinamik

Drag kuadratik per-sumbu body:
```
F_drag = −0.5 · ρ · CdA · |v| · v
CdA = (0.025, 0.060, 0.025) — x lateral, y vertikal, z depan/belakang
+ drag linier kecil: −0.02 · v
```
Angular drag: `τ_drag = −k·ω·|ω|`, `k = (0.0008, 0.0015, 0.0008)`.

Propwash: saat turun cepat (`v_body.y < −2 m/s`), efektivitas thrust
turun hingga 22% dan ditambah guncangan torque sinus kecil.

Ground effect: dalam 0.5 m di atas tanah, lift ekstra hingga +18%,
memudar linear ke 0 di 0.5 m.

## 6. Crash

Crash jika kontak dengan kecepatan > 6 m/s (via `body_entered` +
cadangan `get_contact_count()` di `_integrate_forces`).
Saat crash: disarm, motor 0, status CRASHED. Tombol RESET respawn di pad.

## 7. Kamera

Uptilt default 25° (bisa 15–30° via tombol CAM +/−), FOV 115.
Follow dengan smoothing 12 Hz (lerp posisi + slerp rotasi) + shake
proporsional throttle. Tanpa stabilisasi gimbal — murni FPV.

## 8. Batasan model

- Tanah untuk ground effect diasumsikan y=0 (tidak membaca mesh bukit).
- Gyro coupling dari integrator engine, bukan persamaan eksplisit.
- Propwash & ground effect adalah aproksimasi fenomenologis, bukan CFD.
- Actual Rates adalah aproksimasi kurva Betaflight (bukan tabel RC exact).
