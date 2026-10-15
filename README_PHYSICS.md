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
rate = stick · (center + (max − center) · stick²)
```
- **Preset Beginner (mobile, BUILD 8): center 50 °/s, max 500 °/s, expo 0.**
  Center = slope di tengah (koreksi halus), max = ujung (500 °/s ≈ 1.4
  putaran/detik — cukup untuk belok cepat, tidak langsung nge-flip).
  Sebelumnya max 800 °/s + expo 0.70 di default ACRO: terlalu liar
  untuk layar sentuh.
- Pemetaan sumbu (Godot: X kanan, Y atas, Z belakang):
  `ω_des = (−pitch_rate, −yaw_rate, −roll_rate)`.

### Throttle: expo + limit (Betaflight `thr_expo` + `throttle_limit` SCALE)

```
motor_cmd = 0.60 · (stick·(1−0.35) + stick³·0.35)
```
- `THR_EXPO = 0.35`: melembutkan area sekitar hover (presisi ketinggian).
- `THR_LIMIT = 0.60` (SCALE): stick penuh → 60% motor. Resolusi stick
  penuh dipertahankan, tapi punch-out tidak melesat.
- **Hover di stick ≈ 38%** (bukan ~16% seperti tanpa limit: berat 6.38 N /
  thrust maks 40 N = 0.159 → dengan limit+expo, stick hover ≈ 0.38).
  Ada travel stick yang cukup DI BAWAH hover untuk turun dengan halus.
  HUD menandai titik ini dengan marker kuning "HOVER" + label "THR n%" —
  layar sentuh tidak memberi rasa posisi throttle seperti radio asli.

### Deadzone stick (layar sentuh)

- Radial (melingkar) **0.10** pada pitch/roll (pasangan 2D) dan yaw (1D),
  dengan rescale sisa travel ke 0..1 — diagonal tidak terdistorsi.
- **Tidak ada deadzone pada sumbu throttle** (deadzone di sana membuat
  hunting ketinggian di sekitar hover makin parah).

### Mode default: ANGLE (self-level)

- Default `flight_mode = ANGLE` (sebelumnya ACRO). Di ANGLE, stick kanan =
  target tilt, dilepas → drone kembali level sendiri. ACRO tetap tersedia
  via tombol ACRO/ANGLE (stick = rate, tanpa self-level, bisa flip).
- Mode ANGLE: desired tilt = stick × **50°**, lalu
  `ω_des = 8.0 · (tilt_des − tilt_now)` dijepit ±360 °/s. Yaw tetap rate.
  Cap 50° memberi belok yang responsif tanpa mudah terbalik; P=8.0 membuat
  snap-back ke level terasa tegas saat stick dilepas.

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
Diferensial diskala (faktor s ≤ 1, sama untuk keempat motor) agar semua
motor tetap di [0,1] — jumlah keempat motor SELALU = 4×throttle, jadi
net thrust tidak pernah berubah oleh PID. Tanpa ini, clamp motor
negatif ke 0 menambah net thrust (motor −1 → 0) dan drone naik sendiri
walau throttle 0 — itulah bug BUILD 8 ("naik terus, suara motor max"),
diperbaiki di BUILD 9. Konsekuensi yang benar secara fisik: di throttle
0 tidak ada otoritas attitude (semua motor 0, drone jatuh tanpa kontrol),
sama seperti quad asli. Airmode: PID selalu aktif walau throttle 0
(kecuali saat crash/disarm).

Mode ANGLE: lihat §4 (default, max tilt 50°, P=8.0, ±360 °/s).

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

## 6. Crash & Reset

Crash jika kontak dengan kecepatan > 6 m/s (via `body_entered` +
cadangan `get_contact_count()` di `_integrate_forces`).
Saat crash: disarm, motor 0, status CRASHED. Tombol RESET respawn di pad.
**Reset = instan tegak**: rotasi dipaksa `Basis.IDENTITY`, kecepatan
linier + angular nol, throttle nol, posisi kembali ke spawn. Tidak ada
animasi auto-rotate — reset instan adalah standar sim FPV.

## 7. Kamera

**Rigid mount 1:1** — kamera menyalin transform drone persis tiap frame
(offset + up-tilt tetap dalam frame drone). Tanpa lerp/slerp/shake:
smoothing lama bikin kamera terasa "tidak nempel" dengan drone.
Uptilt default **20°** (bisa 15–30° via tombol CAM +/−), **FOV vertikal 80°**.
Catatan: Godot `fov` adalah vertikal — jangan salin angka diagonal
hardware 150° mentah-mentah (itu ≈ 75–90° vertikal di layar 16:9).
FOV 115 lama membuat kecepatan sulit dinilai.

## 8. Map & Lighting (BUILD 8)

- Map **800×800 m** (dari 400×400): ground + collision diperluas, dinding
  pembatas tinggi 8 m di ±398, 26 pohon, 10 bangunan, 9 bukit, 4 ramp,
  2 kolam, 1 bando, **12 gate** (8 lama + 4 di lingkar luar), 12 awan.
  Tetap low-poly, material flat, tanpa SSAO — hemat di mobile.
- Lighting: matahari DirectionalLight + shadow (bias 0.02, shadow map
  2048 via `rendering/lights_and_shadows/directional_shadow/size`),
  Environment tone mapping **ACES** (exposure 1.05), ambient dari langit
  (energy 0.45) agar bayangan tidak hitam pekat, fog 0.0025 untuk depth cue.

## 9. Batasan model

- Tanah untuk ground effect diasumsikan y=0 (tidak membaca mesh bukit).
- Gyro coupling dari integrator engine, bukan persamaan eksplisit.
- Propwash & ground effect adalah aproksimasi fenomenologis, bukan CFD.
- Actual Rates adalah aproksimasi kurva Betaflight (bukan tabel RC exact).
