#!/usr/bin/env python3
"""Hand-builds the minimal module/sample seeds for the ft2-clone harnesses (the FLAC/OGG/MP3/WAV/AIFF
seeds come from ffmpeg/flac). Output directory: argv[1]."""
import math, struct, sys, os

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
w = lambda n, d: open(os.path.join(out, n), 'wb').write(d)

def sine8(n, amp=100):
    return bytes((int(amp * math.sin(2 * math.pi * i / 16)) & 0xFF) for i in range(n))

def pad(s, n):
    return s.encode('latin1')[:n].ljust(n, b'\0')

# ---- MOD (M.K.) and STK (15 sample, no id)
def mod_hdr(nsamp, name, smplen):
    h = pad(name, 20)
    for i in range(nsamp):
        if i == 0:
            h += pad('sine', 22) + struct.pack('>HBBHH', smplen // 2, 0, 64, 0, 1)
        else:
            h += pad('', 22) + struct.pack('>HBBHH', 0, 0, 0, 0, 1)
    h += bytes([2, 127]) + bytes([0, 1]) + bytes(126)
    return h

def mod_patt():
    p = bytearray(1024)
    # row 0 ch 0: period 428 (C-2), sample 1, no effect; row 4: sample 1 with set-volume
    p[0:4] = bytes([0x01, 0xAC, 0x10, 0x00])
    p[16 * 4:16 * 4 + 4] = bytes([0x01, 0x5A, 0x1C, 0x20])  # period 346, effect C20 (vol 32)
    p[5 * 16 + 4:5 * 16 + 8] = bytes([0x00, 0x00, 0x0F, 0x04])  # F04 set speed
    return bytes(p)

smp = sine8(64)
w('song.mod', mod_hdr(31, 'ft2 test mod', 64) + b'M.K.' + mod_patt() * 2 + smp)
w('song.stk', mod_hdr(15, 'ft2 test stk', 64)[:20 + 15 * 30] + bytes([2, 120]) + bytes([0, 1]) + bytes(126) + mod_patt() * 2 + smp)

# ---- XM
def xm():
    h = b'Extended Module: ' + pad('ft2 test xm', 20) + b'\x1a' + pad('FastTracker v2.00', 20) + struct.pack('<H', 0x0104)
    order = bytes([0, 1]) + bytes(254)
    h += struct.pack('<IHHHHHHHH', 276, 2, 0, 4, 2, 1, 1, 6, 125) + order
    # two patterns, 8 rows, packed: row0 ch0 note C-4 instr 1 vol 0x50 ; empty rows
    def patt(rows):
        d = bytes([0x80 | 0x1 | 0x2 | 0x4, 49, 1, 0x50]) + bytes([0x80]) * (rows * 4 - 1)
        return struct.pack('<IBHH', 9, 0, rows, len(d)) + d
    h += patt(8) + patt(16)
    n = 64
    ins = struct.pack('<I', 263) + pad('sine', 22) + b'\0' + struct.pack('<H', 1)
    ins += struct.pack('<I', 40) + bytes(96) + bytes(96) + bytes([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) + struct.pack('<H', 0) + bytes(22)
    ins = ins[:29 + 4 + 96 + 96 + 14 - 14 + 14 + 2 + 22 - 0] if False else ins
    s = sine8(n)
    delta = bytes(((s[i] - (s[i - 1] if i else 0)) & 0xFF) for i in range(n))
    ins += struct.pack('<IIIBbBBbB', n, 0, 0, 64, 0, 0, 128, 0, 0) + pad('sine', 22) + delta
    return h + ins

x = xm()
w('song.xm', x)

# ---- S3M
def s3m():
    ordn, insn, patn = 2, 1, 1
    hdr = bytearray(96)
    hdr[0:28] = pad('ft2 test s3m', 28)
    hdr[0x1C] = 0x1A
    hdr[0x1D] = 16
    struct.pack_into('<HHH', hdr, 0x20, ordn, insn, patn)
    struct.pack_into('<HHH', hdr, 0x26, 0, 0x1320, 2)  # flags, tracker, ffi (unsigned samples)
    hdr[0x2C:0x30] = b'SCRM'
    hdr[0x30] = 64; hdr[0x31] = 6; hdr[0x32] = 125; hdr[0x33] = 0xB0; hdr[0x35] = 0xFC
    hdr[0x40:0x60] = bytes([0, 8, 1, 9] + [255] * 28)
    body = bytes([0, 255])
    base = 96 + len(body) + 2 * insn + 2 * patn
    insoff = (base + 15) // 16
    patoff = insoff + 5          # instrument header = 0x50 bytes = 5 paragraphs
    smpoff = patoff + 4          # pattern: 2-byte len + 64 row terminators + note => pad to 4 paragraphs
    n = 64
    ins = bytearray(0x50)
    ins[0] = 1
    ins[1:13] = pad('sine.smp', 12)
    ins[13] = 0; struct.pack_into('<H', ins, 14, smpoff)
    struct.pack_into('<III', ins, 16, n, 0, 0)
    ins[28] = 64; ins[30] = 0; ins[31] = 0
    struct.pack_into('<I', ins, 32, 8363)
    ins[48:76] = pad('sine', 28)
    ins[76:80] = b'SCRS'
    rows = bytearray()
    for r in range(64):
        if r == 0:
            rows += bytes([0x20 | 0x40 | 0x80 | 0, 0x40, 1, 64, 3, 0x10])  # ch0: note+instr, vol, effect C10
        rows += b'\0'
    pat = struct.pack('<H', len(rows)) + bytes(rows)
    pat = pat.ljust(4 * 16, b'\0')
    img = bytes(hdr) + body + struct.pack('<H', insoff) + struct.pack('<H', patoff)
    img = img.ljust(insoff * 16, b'\0') + bytes(ins) + pat
    img = img.ljust(smpoff * 16, b'\0') + sine8(n) + bytes(16)
    return img

w('song.s3m', s3m())

# ---- STM
def stm():
    h = pad('ft2 test stm', 20) + b'!Scream!' + bytes([0x1A, 2, 2, 21, 0x60, 1, 64]) + bytes(13)
    for i in range(31):
        if i == 0:
            h += pad('sine', 12) + struct.pack('<BBHHHHBBHiH', 0, 0, 0, 64, 0, 65535, 64, 0, 8363, 0, 0)
        else:
            h += pad('', 12) + struct.pack('<BBHHHHBBHiH', 0, 0, 0, 0, 0, 65535, 0, 0, 8363, 0, 0)
    h += bytes([0, 99]) + bytes(126)
    patt = bytearray(64 * 4 * 4)
    patt[0:4] = bytes([0x21, 0x11, 0x40, 0x00])  # note, instr<<3|oct, vol<<... 
    h += bytes(patt)
    h = h.ljust(((len(h) + 15) // 16) * 16, b'\0')
    return h + sine8(64)

w('song.stm', stm())

# ---- DIGI Booster
def digi():
    h = b'DIGI Booster module\0' + b'V1.6' + bytes([1, 4, 0]) + bytes(19) + bytes([0, 0]) + bytes(128)
    lens = [64] + [0] * 30
    h += b''.join(struct.pack('>I', v) for v in lens)
    h += bytes(31 * 4) + bytes(31 * 4)
    h += bytes([64] + [0] * 30) + bytes(31) + pad('ft2 test digi', 32) + b''.join(pad('sine' if i == 0 else '', 30) for i in range(31))
    # unpacked pattern: 64 rows * 4 ch * 4 bytes
    p = bytearray(64 * 4 * 4)
    p[0:4] = bytes([0x01, 0xAC, 0x10, 0x00])
    return h + bytes(p) + sine8(64)

w('song.digi', digi())

# ---- IT (sample mode)
def it():
    smpn, patn, ordn = 1, 1, 3
    hdr = bytearray(192)
    hdr[0:4] = b'IMPM'; hdr[4:30] = pad('ft2 test it', 26)
    struct.pack_into('<HHHHHHHHH', hdr, 30, 0x1004, ordn, 0, smpn, patn, 0x0214, 0x0214, 0x0009, 0)
    hdr[0x30] = 128; hdr[0x31] = 48; hdr[0x32] = 6; hdr[0x33] = 125; hdr[0x34] = 128
    hdr[0x40:0x80] = bytes([32] * 64); hdr[0x80:0xC0] = bytes([64] * 64)
    orders = bytes([0, 254, 255])
    ptrs_at = 192 + ordn
    smp_off = ptrs_at + 4 * smpn + 4 * patn
    pat_off = smp_off + 80
    data_off = pat_off + 8 + 20
    n = 64
    sh = bytearray(80)
    sh[0:4] = b'IMPS'; sh[4:16] = pad('sine.smp', 12)
    sh[17] = 1; sh[18] = 64; sh[19] = 64; sh[20:46] = pad('sine', 26)
    sh[46] = 1; sh[47] = 0x80 | 32
    struct.pack_into('<IIIIIII', sh, 48, n, 0, 0, 8363, 0, 0, data_off)
    rows = bytearray()
    for r in range(64):
        if r == 0:
            rows += bytes([0x81, 0x03, 60, 1])
        rows += b'\0'
    pat = struct.pack('<HHI', len(rows), 64, 0) + bytes(rows)
    pat_off = smp_off + 80
    data_off = pat_off + len(pat)
    struct.pack_into('<I', sh, 48 + 24, data_off)
    img = bytes(hdr) + orders + struct.pack('<I', smp_off) + struct.pack('<I', pat_off) + bytes(sh) + pat + sine8(n)
    return img

w('song.it', it())

# ---- IFF 8SVX
def chunk(tag, data):
    return tag + struct.pack('>I', len(data)) + data + (b'\0' if len(data) & 1 else b'')

def iff():
    n = 64
    vhdr = struct.pack('>IIIHBBI', 0, 0, 32, 8363, 1, 0, 0x10000)
    body = chunk(b'VHDR', vhdr) + chunk(b'NAME', b'sine') + chunk(b'BODY', sine8(n))
    return b'FORM' + struct.pack('>I', 4 + len(body)) + b'8SVX' + body

w('sample.iff', iff())

# ---- BRR: 4 blocks of 9 bytes; first header must not have the end bit, last must
blocks = b''
for i in range(4):
    hdr = (0x90 if i < 3 else 0x91)  # shift 9, filter 0; end bit on the last
    blocks += bytes([hdr]) + bytes([(0x12 * (i + 1)) & 0xFF, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0])
w('sample.brr', blocks)
