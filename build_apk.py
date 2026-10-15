#!/usr/bin/env python3
"""Build FPV Drone Simulator APK manually, replicating Godot 4.3 Android export.

Why manual: `godot --export-debug Android` fails headless in this VM with an
empty config error, so we replicate what the exporter does (see
platform/android/export/export_plugin.cpp in Godot 4.3):
- Project files are NOT packed into a PCK on Android. They are stored as
  individual files under assets/ (res://X -> assets/X), including binary
  .scn scenes + .remap files, compiled .gdc scripts + .gd.remap files,
  project.binary, and .godot caches. The engine reads res:// from assets.
- assets/_cl_ holds command-line flags: u32 count, then per-arg u32 len + bytes.
- Compression per _should_compress_asset: STORED for already-compressed
  extensions (.scn, .ctex, .webp, images, audio, video...) and RSCC-header
  files; DEFLATED otherwise. Manifest/arsc/.so are always STORED.
- Manifest: package + FileProvider/startup authorities change to the app
  package, but the activity class MUST stay com.godot.game.GodotApp
  (that's the class actually in the template DEX).
"""
import os, struct, hashlib, zipfile, shutil, subprocess, sys

WORK = os.path.expanduser("~/workspace/fpv-drone-simulator/tmp-apkbuild5")
BUILD_DIR = os.path.expanduser("~/workspace/fpv-drone-simulator/builds")
GODOT = os.path.expanduser("~/tools/godot")
PROJECT = os.path.expanduser("~/workspace/fpv-drone-simulator")
TEMPLATE = os.path.expanduser("~/.local/share/godot/export_templates/4.3.stable/android_debug.apk")
BT = os.path.expanduser("~/tools/android/build-tools/34.0.0")
KEYSTORE = os.path.join(PROJECT, "debug.keystore")

UNCOMPRESSED_EXTS = {".jpg",".jpeg",".png",".gif",".wav",".mp2",".mp3",".ogg",".aac",
    ".mpg",".mpeg",".mid",".midi",".smf",".jet",".rtttl",".imy",".xmf",".mp4",".m4a",
    ".m4v",".3gp",".3gpp",".3g2",".3gpp2",".amr",".awb",".wma",".wmv",".webp",".cfb",
    ".scn",".ctex"}

def sh(cmd, **kw):
    print("+", " ".join(cmd)); subprocess.run(cmd, check=True, **kw)

def extract_pck(pck_path, assets_dir):
    with open(pck_path, 'rb') as f: data = f.read()
    magic, fmt, maj, mn, pat, flags = struct.unpack_from('<IIIIII', data, 0)
    assert magic == 0x43504447, f"bad PCK magic {magic:#x}"
    (file_base,) = struct.unpack_from('<Q', data, 24)
    off = 96
    (count,) = struct.unpack_from('<I', data, off); off += 4
    n = 0
    for _ in range(count):
        (slen,) = struct.unpack_from('<I', data, off); off += 4
        raw = data[off:off+slen]; off += slen
        p = raw.rstrip(b'\x00').decode('utf-8')
        foff, fsize = struct.unpack_from('<QQ', data, off); off += 16
        md5 = data[off:off+16]; off += 16
        (fflags,) = struct.unpack_from('<I', data, off); off += 4
        assert p.startswith("res://"), p
        rel = p[len("res://"):]
        blob = data[file_base+foff:file_base+foff+fsize]
        assert hashlib.md5(blob).digest() == md5, f"MD5 mismatch {p}"
        dest = os.path.join(assets_dir, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, 'wb') as f: f.write(blob)
        n += 1
    print(f"extracted {n} files from PCK -> {assets_dir}")
    return n

def write_cl(assets_dir):
    # get_command_line_flags for our preset: xr_mode=regular, immersive=true.
    args = [b"--xr_mode_regular", b"--use_immersive"]
    buf = struct.pack('<I', len(args))
    for a in args:
        buf += struct.pack('<I', len(a)) + a
    with open(os.path.join(assets_dir, "_cl_"), 'wb') as f: f.write(buf)
    print(f"wrote _cl_ with {len(args)} flags")

def should_store(rel, blob):
    if rel in ("AndroidManifest.xml", "resources.arsc") or rel.endswith(".so"):
        return True
    _, ext = os.path.splitext(rel)
    if ext.lower() in UNCOMPRESSED_EXTS:
        return True
    if len(blob) >= 4 and blob[:4] == b"RSCC":
        return True
    return False

def main():
    if os.path.exists(WORK): shutil.rmtree(WORK)
    os.makedirs(WORK)
    apk_dir = os.path.join(WORK, "apk")
    os.makedirs(apk_dir)
    # 1. Fresh PCK export (source of truth for the asset file set)
    sh([GODOT, "--headless", "--path", PROJECT, "--export-pack", "Android",
        os.path.join(WORK, "game.pck")])
    # 2. Extract PCK -> apk/assets/
    assets_dir = os.path.join(apk_dir, "assets")
    os.makedirs(assets_dir)
    extract_pck(os.path.join(WORK, "game.pck"), assets_dir)
    write_cl(assets_dir)
    # 3. Template APK contents
    sh(["unzip", "-o", "-q", TEMPLATE, "-d", apk_dir])
    for d in ("META-INF", "lib/x86", "lib/x86_64", "lib/armeabi-v7a"):
        p = os.path.join(apk_dir, d)
        if os.path.exists(p): shutil.rmtree(p)
    # 4. Patch manifest + arsc (fix_apk.py)
    sh(["python3", "/tmp/fix_apk.py", os.path.join(apk_dir, "AndroidManifest.xml"),
        os.path.join(apk_dir, "AndroidManifest.xml.new"),
        '{"com.godot.game":"com.ramadina.fpvsim","com.godot.game.fileprovider":"com.ramadina.fpvsim.fileprovider","com.godot.game.androidx-startup":"com.ramadina.fpvsim.androidx-startup"}'])
    os.replace(os.path.join(apk_dir, "AndroidManifest.xml.new"),
               os.path.join(apk_dir, "AndroidManifest.xml"))
    sh(["python3", "/tmp/fix_apk.py", os.path.join(apk_dir, "resources.arsc"),
        os.path.join(apk_dir, "resources.arsc.new"),
        '{"godot-project-name":"FPV Drone Simulator"}'])
    os.replace(os.path.join(apk_dir, "resources.arsc.new"),
               os.path.join(apk_dir, "resources.arsc"))
    # 5. Rebuild APK with correct compression
    unsigned = os.path.join(WORK, "fpv-unsigned.apk")
    skip = {"fpv-unsigned.apk", "fpv-aligned.apk", "fpv-signed.apk", "game.pck"}
    with zipfile.ZipFile(unsigned, 'w') as z:
        for root, _, files in os.walk(apk_dir):
            for fn in files:
                if fn in skip: continue
                full = os.path.join(root, fn)
                rel = os.path.relpath(full, apk_dir)
                with open(full, 'rb') as f: blob = f.read()
                comp = zipfile.ZIP_STORED if should_store(rel, blob) else zipfile.ZIP_DEFLATED
                z.writestr(rel, blob, compress_type=comp)
    print("unsigned APK:", os.path.getsize(unsigned))
    env = dict(os.environ, PATH=os.path.expanduser("~/tools/jdk/bin") + ":" + os.environ["PATH"])
    sh([os.path.join(BT, "zipalign"), "-f", "4", unsigned, os.path.join(WORK, "fpv-aligned.apk")], env=env)
    sh([os.path.join(BT, "zipalign"), "-f", "-c", "4", os.path.join(WORK, "fpv-aligned.apk")], env=env)
    print("ALIGN OK")
    sh([os.path.join(BT, "apksigner"), "sign", "--ks", KEYSTORE, "--ks-key-alias",
        "androiddebugkey", "--ks-pass", "pass:android", "--key-pass", "pass:android",
        "--out", os.path.join(WORK, "fpv-signed.apk"), os.path.join(WORK, "fpv-aligned.apk")], env=env)
    sh([os.path.join(BT, "apksigner"), "verify", "--verbose", os.path.join(WORK, "fpv-signed.apk")], env=env)
    sh([os.path.join(BT, "aapt"), "dump", "badging", os.path.join(WORK, "fpv-signed.apk")], env=env)
    out = os.path.join(BUILD_DIR, "fpv-drone-simulator.apk")
    os.makedirs(BUILD_DIR, exist_ok=True)
    shutil.copyfile(os.path.join(WORK, "fpv-signed.apk"), out)
    print("FINAL:", out, os.path.getsize(out))

if __name__ == "__main__":
    main()
