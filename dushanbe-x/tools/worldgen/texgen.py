#!/usr/bin/env python3
"""Procedural, seamlessly tiling textures for DUSHANBE-X (512x512, sRGB PNG)."""
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "textures")
os.makedirs(OUT, exist_ok=True)
S = 512
rng = np.random.default_rng(7)


def pnoise(beta=2.0, seed=0, size=S):
    """Periodic 1/f^beta noise in [0,1] via FFT (tiles seamlessly)."""
    r = np.random.default_rng(seed)
    w = r.normal(size=(size, size))
    f = np.fft.fft2(w)
    ky = np.fft.fftfreq(size)[:, None]
    kx = np.fft.fftfreq(size)[None, :]
    k = np.sqrt(kx * kx + ky * ky)
    k[0, 0] = 1
    f = f / k ** (beta / 2)
    f[0, 0] = 0
    n = np.real(np.fft.ifft2(f))
    n = (n - n.min()) / (n.max() - n.min())
    return n


def band(lo_beta, seed):
    return pnoise(lo_beta, seed)


def save(name, rgb):
    img = Image.fromarray(np.clip(rgb * 255, 0, 255).astype(np.uint8), "RGB")
    img.save(os.path.join(OUT, name), optimize=True)
    print("wrote", name)


def mix(a, b, t):
    t = t[..., None] if t.ndim == 2 else t
    return a * (1 - t) + b * t


def col(r, g, b):
    return np.array([r, g, b], np.float32) / 255.0


def speck(density, seed):
    r = np.random.default_rng(seed)
    return (r.random((S, S)) < density).astype(np.float32)


n_lo = pnoise(3.0, 1)
n_mid = pnoise(2.0, 2)
n_hi = pnoise(1.0, 3)
n_hi2 = pnoise(0.6, 4)

# grass (lush)
g = mix(col(58, 92, 38), col(98, 132, 52), n_lo * 0.7 + n_mid * 0.3)
g = mix(g, col(40, 70, 30), np.clip(n_hi - 0.55, 0, 1) * 2.0)
g = mix(g, col(120, 150, 70), np.clip(n_hi2 - 0.7, 0, 1) * 2.5)
g = mix(g, col(150, 170, 90), speck(0.02, 5) * 0.6)
save("grass.png", g)

# dry grass / steppe
d = mix(col(150, 140, 80), col(185, 165, 105), n_lo * 0.6 + n_mid * 0.4)
d = mix(d, col(120, 120, 60), np.clip(n_hi - 0.5, 0, 1) * 1.6)
d = mix(d, col(205, 190, 140), speck(0.03, 6) * 0.5)
save("grass_dry.png", d)

# rock: layered strata + cracks
yy = np.linspace(0, 2 * np.pi * 6, S)[:, None]
strata = (np.sin(yy + n_lo * 8.0) * 0.5 + 0.5)
r = mix(col(112, 104, 96), col(150, 142, 132), n_mid * 0.6 + strata * 0.4)
cr = np.clip(1.0 - np.abs(pnoise(1.6, 9) - 0.5) * 18, 0, 1)
r = mix(r, col(70, 64, 60), cr * 0.7)
r = mix(r, col(165, 155, 140), np.clip(n_hi2 - 0.6, 0, 1) * 2)
r *= (0.85 + 0.3 * n_hi)[..., None]
save("rock.png", r)

# snow
s = mix(col(228, 234, 242), col(250, 252, 255), n_mid)
s = mix(s, col(200, 212, 230), np.clip(n_lo - 0.6, 0, 1) * 2)
save("snow.png", s)

# dirt (village yards, dirt roads)
dt = mix(col(120, 92, 64), col(156, 124, 90), n_lo * 0.5 + n_mid * 0.5)
dt = mix(dt, col(95, 75, 55), np.clip(n_hi - 0.6, 0, 1) * 2)
dt = mix(dt, col(175, 160, 140), speck(0.05, 11) * 0.7)
save("dirt.png", dt)

# river gravel / sand
gv = mix(col(150, 142, 128), col(185, 176, 160), n_mid)
peb = np.clip(pnoise(0.4, 12) - 0.55, 0, 1) * 3
gv = mix(gv, col(120, 115, 108), np.clip(peb, 0, 1) * 0.6)
gv = mix(gv, col(210, 205, 195), speck(0.06, 13) * 0.6)
save("gravel.png", gv)

# asphalt
a = mix(col(52, 53, 56), col(70, 71, 74), n_mid * 0.5 + n_lo * 0.5)
a = mix(a, col(110, 110, 112), speck(0.10, 14) * 0.45)
a = mix(a, col(30, 30, 32), speck(0.05, 15) * 0.5)
cracks = np.clip(1.0 - np.abs(pnoise(1.8, 16) - 0.5) * 40, 0, 1) * (n_lo > 0.6)
a = mix(a, col(28, 28, 30), cracks * 0.8)
save("asphalt.png", a)

# paving tiles (8x8 tiles over the texture -> 0.5 m tiles at 4 m tiling)
t = np.zeros((S, S, 3), np.float32)
tiles = 8
ts = S // tiles
tr = np.random.default_rng(17)
for ty in range(tiles):
    for tx in range(tiles):
        v_ = int(tr.integers(150, 190)); c = col(v_, v_ - 3, v_ - 8) if tr.random() > 0.06 else col(160, 128, 112)
        t[ty * ts:(ty + 1) * ts, tx * ts:(tx + 1) * ts] = c
t *= (0.88 + 0.24 * n_hi)[..., None]
grid = np.zeros((S, S), bool)
for k in range(tiles):
    grid[k * ts:k * ts + 3, :] = True
    grid[:, k * ts:k * ts + 3] = True
t[grid] = col(95, 92, 88)
save("paving.png", t)

# concrete
c = mix(col(160, 158, 152), col(190, 188, 182), n_mid * 0.6 + n_lo * 0.4)
c = mix(c, col(130, 128, 124), np.clip(n_hi2 - 0.7, 0, 1) * 2)
save("concrete.png", c)

# plowed soil with furrows (stripes along U)
xx = np.linspace(0, 2 * np.pi * 16, S)[None, :]
furrow = (np.sin(xx + n_lo * 2) * 0.5 + 0.5)
so = mix(col(92, 70, 50), col(140, 110, 80), furrow * 0.7 + n_mid * 0.3)
save("soil.png", so)

# crop rows: green rows (R channel mask stored as luminance variation)
rows = np.clip((np.sin(xx * 1.0) * 0.5 + 0.5) * 1.6 - 0.3, 0, 1)
cp = mix(col(110, 90, 62), col(255, 255, 255), rows * (0.75 + 0.25 * n_hi))
save("crop_rows.png", cp)

# generic multi-purpose noise (R lo, G mid, B hi, A detail)
rgba = np.stack([n_lo, n_mid, n_hi, n_hi2], -1)
Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "noise.png"))
print("wrote noise.png")

# water normal map from periodic noise heights
h = pnoise(2.4, 21) * 0.6 + pnoise(1.6, 22) * 0.4
gy, gx = np.gradient(h)
nx, ny = -gx * 40, -gy * 40
nz = np.ones_like(nx)
ln = np.sqrt(nx * nx + ny * ny + nz * nz)
nm = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5
Image.fromarray((nm * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, "water_normal.png"))
print("wrote water_normal.png")

# rock normal
hr = r.mean(-1)
gy, gx = np.gradient(hr)
nx, ny = -gx * 12, -gy * 12
ln = np.sqrt(nx * nx + ny * ny + 1)
nm = np.stack([nx / ln, ny / ln, 1 / ln], -1) * 0.5 + 0.5
Image.fromarray((nm * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, "rock_normal.png"))
print("wrote rock_normal.png")

# bark
yy2 = np.linspace(0, 2 * np.pi * 24, S)[None, :]
bark = mix(col(70, 55, 42), col(110, 92, 72), (np.sin(yy2 + pnoise(1.2, 30) * 6) * 0.5 + 0.5) * 0.6 + n_hi * 0.4)
save("bark.png", bark)

# roof tin (corrugated)
cor = np.sin(np.linspace(0, 2 * np.pi * 32, S))[None, :] * 0.5 + 0.5
roof = mix(col(150, 155, 160), col(200, 205, 210), np.repeat(cor, S, 0) * 0.6 + n_mid * 0.4)
save("tin.png", roof)

# stone blocks (masonry) for monuments / palaces
mb = np.zeros((S, S, 3), np.float32)
rows_n, cols_n = 8, 4
bh, bw = S // rows_n, S // cols_n
rr = np.random.default_rng(31)
for ry in range(rows_n):
    off = (bw // 2) * (ry % 2)
    for cx in range(-1, cols_n + 1):
        v_ = int(rr.integers(205, 235)); c = col(v_, v_ - 4, v_ - 12)
        x0 = cx * bw + off
        x1 = x0 + bw
        mb[ry * bh:(ry + 1) * bh, max(0, x0):min(S, x1)] = c
mb *= (0.92 + 0.12 * n_hi)[..., None]
for ry in range(rows_n):
    mb[ry * bh:ry * bh + 2, :] *= 0.75
    off = (bw // 2) * (ry % 2)
    for cx in range(0, cols_n + 1):
        x = (cx * bw + off) % S
        mb[ry * bh:(ry + 1) * bh, x:x + 2] *= 0.75
save("masonry.png", mb)
