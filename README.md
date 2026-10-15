# FPV Drone Simulator (Android, Godot 4.3)

Simulator drone FPV 5" freestyle dengan fisika realistis, map low-poly,
suara FPV prosedural, dan kontrol sentuh Mode 2. Dibuat untuk Android
(landscape). Tanpa aset eksternal — semua mesh prosedural/primitif,
semua suara digenerate via `AudioStreamGenerator`.

## Fitur

- Fisika 240 Hz: thrust `kT·ω²`, lag motor, baterai 4S + sag, PID
  angular-velocity Betaflight-style (Actual Rates 800 °/s, expo 0.70),
  drag kuadratik, propwash, ground effect, mode ACRO (default) / ANGLE.
- Map 400×400: 10 pohon, 4 gedung, 2 ramp, bando, kolam, 5 bukit,
  8 gate balap (loop + lap timer + beep), H-pad, awan, matahari + bayangan.
- Kontrol Android: dual virtual joystick Mode 2 (throttle stays, yaw;
  pitch/roll spring), tombol ARM / MODE / RESET / CAM / PAUSE / MUTE.
  Fallback keyboard + gamepad.
- Suara: 4 osilator motor (sawtooth + detune, frekuensi ikut throttle),
  wind noise ∝ speed², beep gate 880 Hz, thud crash. Mute tersedia.
- HUD/OSD: baterai V + %, timer, kecepatan km/h, ketinggian, mode,
  ARMED/DISARMED/CRASHED, throttle bar, battery bar, horizon mini,
  crosshair, gate count / lap.

## Cara main

1. Install APK, buka (landscape).
2. Tap **ARM** → naikkan throttle stik kiri perlahan.
3. Terbang lewat gate oranye untuk lap time. Tabrak keras = CRASHED → RESET.

Detail fisika: `README_PHYSICS.md`. Cara build ulang: `README_BUILD.md`.
