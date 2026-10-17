#!/usr/bin/env python3
"""Binary string-pool replacement for AndroidManifest.xml (AXML) and
resources.arsc (ARSC).

Usage: fix_apk.py <input> <output> '<json mapping>'

Replaces strings in the FIRST string-pool chunk by EXACT match (never
substring: the manifest must keep the activity name
`com.godot.game.GodotApp` while only the package + authorities change).
Re-encodes the pool (UTF-8 or UTF-16, as the file uses), rebuilds
offsets, updates the chunk size and the file size. Later chunks reference
strings by INDEX, so they are untouched and stay valid.

Durable copy lives in the repo at tools/fix_apk.py (this /tmp copy is
ephemeral — /tmp is wiped on VM replacement, which is how it went
missing and broke the BUILD 12 build).
"""
import json
import struct
import sys


def decode_utf8(data, p):
    # Android UTF-8 string pool: FIRST varint = UTF-16 (char) length,
    # SECOND varint = UTF-8 (byte) length. (Getting this backwards slices
    # too few bytes on non-ASCII strings and breaks decoding.)
    c0 = data[p]
    if c0 & 0x80:
        p += 2
    else:
        p += 1
    b0 = data[p]
    if b0 & 0x80:
        nbytes = ((b0 & 0x7F) << 8) | data[p + 1]
        p += 2
    else:
        nbytes = b0
        p += 1
    raw = data[p:p + nbytes]
    return raw.decode("utf-8"), p + nbytes + 1  # +1 NUL


def decode_utf16(data, p):
    w0 = struct.unpack_from("<H", data, p)[0]
    if w0 & 0x8000:
        w1 = struct.unpack_from("<H", data, p + 2)[0]
        nchars = ((w0 & 0x7FFF) << 16) | w1
        p += 4
    else:
        nchars = w0
        p += 2
    raw = data[p:p + nchars * 2]
    return raw.decode("utf-16-le"), p + nchars * 2 + 2


def encode_utf8(s):
    raw = s.encode("utf-8")
    nbytes = len(raw)
    nchars = len(s.encode("utf-16-le")) // 2  # UTF-16 code units
    out = bytearray()
    # FIRST varint = UTF-16 (char) length, SECOND = UTF-8 (byte) length.
    if nchars < 0x80:
        out.append(nchars)
    else:
        out.append(0x80 | (nchars >> 8))
        out.append(nchars & 0xFF)
    if nbytes < 0x80:
        out.append(nbytes)
    else:
        out.append(0x80 | (nbytes >> 8))
        out.append(nbytes & 0xFF)
    out += raw
    out.append(0)
    return bytes(out)


def encode_utf16(s):
    nchars = len(s.encode("utf-16-le")) // 2
    out = bytearray()
    if nchars < 0x8000:
        out += struct.pack("<H", nchars)
    else:
        out += struct.pack("<HH", 0x8000 | (nchars >> 16), nchars & 0xFFFF)
    out += s.encode("utf-16-le")
    out += struct.pack("<H", 0)
    return bytes(out)


def parse_string_pool(data, off):
    typ, hsize, size = struct.unpack_from("<HHI", data, off)
    assert typ == 0x0001, f"not a string pool chunk: {typ:#x}"
    string_count, style_count, flags, strings_start, styles_start = (
        struct.unpack_from("<IIIII", data, off + 8))
    assert style_count == 0, "styled string pools not supported"
    is_utf8 = bool(flags & 0x100)
    offsets = struct.unpack_from(f"<{string_count}I", data, off + 28)
    str_base = off + strings_start
    strings = []
    for i in range(string_count):
        p = str_base + offsets[i]
        s, _ = decode_utf8(data, p) if is_utf8 else decode_utf16(data, p)
        strings.append(s)
    return {
        "off": off, "size": size, "string_count": string_count,
        "flags": flags, "strings_start": strings_start,
        "styles_start": styles_start, "is_utf8": is_utf8,
        "header_size": hsize, "strings": strings,
    }


def rebuild_string_pool(pool, new_strings):
    encoded = [encode_utf8(s) if pool["is_utf8"] else encode_utf16(s)
               for s in new_strings]
    offsets = []
    blob = bytearray()
    for e in encoded:
        offsets.append(len(blob))
        blob += e
    while len(blob) % 4 != 0:
        blob.append(0)
    out = bytearray()
    out += struct.pack("<HHI", 0x0001, pool["header_size"], 0)
    out += struct.pack("<IIIII", pool["string_count"], 0, pool["flags"],
                       pool["strings_start"], pool["styles_start"])
    for o in offsets:
        out += struct.pack("<I", o)
    out += blob
    struct.pack_into("<I", out, 4, len(out))
    return bytes(out)


def main():
    inp, outp, mapping_json = sys.argv[1], sys.argv[2], sys.argv[3]
    mapping = json.loads(mapping_json)
    data = open(inp, "rb").read()
    # First chunk after the file header is the string pool.
    # AXML header = 8 bytes (type 0x00080003); ARSC header = 12 bytes
    # (type 0x0002). BOTH have the file-size u32 at offset 4
    # (ResChunk_header: type u16, headerSize u16, size u32); ARSC's
    # packageCount lives at offset 8 — writing the size there corrupts
    # it (aapt then reports "52936 package chunks declared").
    if struct.unpack_from("<H", data, 0)[0] == 0x0002:
        pool_off, size_off = 12, 4
    else:
        pool_off, size_off = 8, 4
    pool = parse_string_pool(data, pool_off)
    new_strings = [mapping.get(s, s) for s in pool["strings"]]
    new_pool = rebuild_string_pool(pool, new_strings)
    new_data = bytearray(data[:pool_off]) + new_pool + data[pool_off + pool["size"]:]
    struct.pack_into("<I", new_data, size_off, len(new_data))
    open(outp, "wb").write(bytes(new_data))


if __name__ == "__main__":
    main()
