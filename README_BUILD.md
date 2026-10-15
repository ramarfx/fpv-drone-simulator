# Build & Export — FPV Drone Simulator

## Cara 1: Dari Godot Editor (Azunyan, paling mudah)

1. Install Godot 4.3 stable (https://godotengine.org/download).
2. Buka Godot → Import → pilih folder `fpv-drone-simulator` → Open.
3. Project → Export → preset **Android** sudah ada
   (package `com.ramadina.fpvsim`, min SDK 24, target 34, landscape).
4. Klik **Export Project** → pilih lokasi → simpan sebagai `.apk`.
   - Untuk debug: pakai preset ini apa adanya (keystore debug `android`/`android`).
   - Untuk rilis: isi keystore rilis di Project → Export → Keystore.
5. Copy APK ke HP → izinkan "Install unknown apps" → install → mainkan landscape.

> Catatan: Godot butuh Android SDK + JDK untuk export. Jika Godot menanyakan
> lokasi SDK, isi di Editor Settings → Export → Android:
> `Android Sdk Path` (mis. `~/Android/Sdk`) dan `Jdk 17 Path`.

## Status export APK (2026-10-15, VM ini)

APK **sudah berhasil di-build dan jalan di HP**: `builds/fpv-drone-simulator.apk`
(~75 MB, arm64-v8a only, debug-signed, package `com.ramadina.fpvsim`,
label "FPV Drone Simulator"). Verifikasi via adb: install Success,
engine init `Godot 4.3 + Vulkan Mali-G77`, activity top-resumed, 0 SCRIPT ERROR.
Build ulang: `python3 build_apk.py` (lihat bawah).

Catatan: export headless standar Godot
(`godot --headless --export-debug "Android"`) gagal di VM ini dengan pesan
kosong (`Cannot export project... configuration errors: (empty)`), jadi
APK dirakit manual dengan `build_apk.py` yang mereplikasi exporter Godot 4.3
(`platform/android/export/export_plugin.cpp`). Tiga jebakan yang sempat
bikin gagal dan sudah diperbaiki (jangan diulang):
1. **Android TIDAK pakai PCK.** File proyek disimpan satu-per-satu di
   `assets/` (`res://X` → `assets/X`): `project.binary`, scene biner `.scn`
   + `.remap`, script `.gdc` + `.gd.remap`, cache `.godot/`, plus
   `assets/_cl_` (flags `--xr_mode_regular --use_immersive`). `assets/main.pck`
   diabaikan engine → error `Couldn't load project.binary`.
2. **Activity class jangan diganti.** Manifest `package` boleh jadi
   `com.ramadina.fpvsim`, tapi `android:name` activity harus tetap
   `com.godot.game.GodotApp` (class yang ada di DEX template). Mengganti
   jadi `com.ramadina.fpvsim.GodotApp` → `ClassNotFoundException` → force close.
3. **`resources.arsc` + `AndroidManifest.xml` harus STORED** (tanpa kompresi,
   zip-aligned) — kalau DEFLATED, Android 11+ menolak install (error -124).
   Kompresi asset ikut `_should_compress_asset` (`.scn`/`.ctex` STORED, sisanya
   DEFLATED kecuali header RSCC).

Toolchain yang sudah terinstall di VM ini (bisa dipakai ulang):
- Godot 4.3: `~/tools/godot`
- Export templates: `~/.local/share/godot/export_templates/4.3.stable/`
- JDK 17 (Temurin): `~/tools/jdk`
- Android SDK: `~/tools/android` (platform-tools, platforms/android-34,
  build-tools/34.0.0, cmdline-tools)

## Cara 2: Headless (VM / CI)

```bash
# 1. Godot 4.3 + export templates (sudah ada di ~/.local/share/godot/export_templates/4.3.stable/)
# 2. JDK 17 + Android SDK cmdline-tools, set:
export JAVA_HOME=/path/to/jdk17
export ANDROID_HOME=/path/to/Android/Sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME
# 3. Di dalam editor settings Godot (editor_settings-4.3.xml):
#    export/android/android_sdk_path, export/android/java_sdk_path
# 4. Export:
godot --headless --path . --export-debug "Android" builds/fpv-drone-simulator.apk
```

Jika export headless gagal karena SDK belum terkonfigurasi, pakai Cara 1 —
editor akan memandu setup SDK lewat dialog.

## Fresh clone: regenerate debug.keystore

`debug.keystore` tidak ikut di-commit (private key). Buat ulang sebelum build:

```bash
keytool -genkeypair -keystore debug.keystore -alias androiddebugkey \
  -keypass android -storepass android -keyalg RSA -keysize 2048 \
  -validity 10000 -d "CN=Android Debug,O=Android,C=US"
```

## Kontrol

- Android: stik kiri = throttle (vertikal, stays) + yaw (horizontal).
  Stik kanan = pitch + roll (spring ke tengah). Tombol ARM / ACRO-ANGLE /
  RESET / CAM +/− / PAUSE / MUTE.
- Keyboard: W/S pitch, A/D roll, Panah Atas/Bawah throttle,
  Panah Kiri/Kanan yaw, Spasi arm, R reset, M mode.
- Gamepad: sumbu standar (jika terdeteksi OS).

## Struktur

```
project.godot  export_presets.cfg  icon.svg
scenes/  Main.tscn  Drone.tscn  Map.tscn  HUD.tscn
scripts/ drone_physics.gd  flight_controller.gd  fpv_camera.gd
         fpv_audio.gd  joystick.gd  hud.gd  gate.gd  main.gd
README.md  README_PHYSICS.md  README_BUILD.md
```
