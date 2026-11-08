#!/usr/bin/env python3
"""
DUSHANBE-X world generator.

Produces the data the Godot runtime streams and turns into 3D geometry:
  data/heightmap.bin   uint16 LE, N x N, 5 m cells (terrain after carving)
  data/splat.png       RGBA ground types  (R dirt, G farmland, B urban, A sand/gravel)
  data/veg.png         RGBA vegetation    (R forest, G orchard, B vineyard, A meadow)
  data/holes.bin       uint8 N x N (1 = no terrain, tunnel portals)
  data/world.json      roads / rivers / lakes / buildings / landmarks / POIs ...
  data/minimap.png     top-down map for the HUD
  docs/world_map.png   annotated overview map for the design document

Run:  python3 tools/worldgen/worldgen.py   (from the project root)
"""
import json
import math
import os
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(__file__))
import layout as L  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(ROOT, "data")
DOCS = os.path.join(ROOT, "docs")
os.makedirs(DATA, exist_ok=True)
os.makedirs(DOCS, exist_ok=True)

SIZE = 10000.0
ORIGIN = -5000.0
CELL = 5.0
N = int(SIZE / CELL) + 1          # 2001
HMIN, HRANGE = -50.0, 2600.0
SEED = 1991                         # year of independence

rng = np.random.default_rng(SEED)
T0 = time.time()


def log(msg):
    print(f"[{time.time() - T0:6.1f}s] {msg}", flush=True)


# ----------------------------------------------------------------------------
# Grid helpers
# ----------------------------------------------------------------------------
xs = ORIGIN + np.arange(N) * CELL
GX, GZ = np.meshgrid(xs, xs)        # GX[j,i] = x, GZ[j,i] = z   (row = z)


def to_grid(x, z):
    return (np.asarray(x) - ORIGIN) / CELL, (np.asarray(z) - ORIGIN) / CELL


def sample(arr, x, z, order=1):
    gi, gj = to_grid(x, z)
    return ndimage.map_coordinates(arr, [np.atleast_1d(gj), np.atleast_1d(gi)], order=order, mode="nearest")


def max_step(A, label):
    g = np.maximum(np.abs(np.diff(A, axis=1))[:-1, :], np.abs(np.diff(A, axis=0))[:, :-1])
    log(f"  [check] {label}: max step {g.max():.1f} m, cells>30m: {int((g > 30).sum())}")
    ys, xs = np.where(g > 30)
    if len(ys):
        sel = np.linspace(0, len(ys) - 1, min(6, len(ys))).astype(int)
        log("     at " + ", ".join(f"({ORIGIN + xs[k] * CELL:.0f},{ORIGIN + ys[k] * CELL:.0f})" for k in sel))


def smoothstep(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def poly_mask(poly, res=N):
    img = Image.new("L", (res, res), 0)
    pts = [((x - ORIGIN) / SIZE * (res - 1), (z - ORIGIN) / SIZE * (res - 1)) for x, z in poly]
    ImageDraw.Draw(img).polygon(pts, fill=255)
    return np.asarray(img, dtype=np.float32) / 255.0


def densify(pts, step):
    """Resample a polyline (list of tuples, first two comps = x,z, extra comps interpolated)."""
    pts = np.asarray(pts, dtype=np.float64)
    out = [pts[0]]
    for a, b in zip(pts[:-1], pts[1:]):
        d = math.hypot(b[0] - a[0], b[1] - a[1])
        n = max(1, int(math.ceil(d / step)))
        for k in range(1, n + 1):
            out.append(a + (b - a) * (k / n))
    return np.array(out)


def chaikin(pts, it=2, keep_ends=True):
    pts = np.asarray(pts, dtype=np.float64)
    for _ in range(it):
        if len(pts) < 3:
            return pts
        q = 0.75 * pts[:-1] + 0.25 * pts[1:]
        r = 0.25 * pts[:-1] + 0.75 * pts[1:]
        mid = np.empty((len(q) * 2, pts.shape[1]))
        mid[0::2] = q
        mid[1::2] = r
        if keep_ends:
            pts = np.vstack([pts[:1], mid, pts[-1:]])
        else:
            pts = mid
    return pts


def arclen(p):
    d = np.hypot(np.diff(p[:, 0]), np.diff(p[:, 1]))
    return np.concatenate([[0.0], np.cumsum(d)])


def smooth_1d(v, sigma_samples, pinned=None, iters=0):
    out = ndimage.gaussian_filter1d(v, max(0.1, sigma_samples), mode="nearest")
    if pinned is not None and pinned.any():
        for _ in range(iters):
            out[pinned] = v[pinned]
            out = ndimage.gaussian_filter1d(out, max(0.1, sigma_samples * 0.5), mode="nearest")
        out[pinned] = v[pinned]
    return out


# ----------------------------------------------------------------------------
# Noise: smooth value noise on low-res lattices sampled with cubic interpolation
# ----------------------------------------------------------------------------
class Noise:
    def __init__(self, seed, period_m, res=None):
        r = np.random.default_rng(seed)
        self.period = period_m
        self.res = res or max(4, int(SIZE / period_m) + 4)
        self.grid = r.uniform(-1, 1, (self.res, self.res)).astype(np.float32)

    def at(self, x, z):
        scalar = np.ndim(x) == 0 and np.ndim(z) == 0
        u = np.atleast_1d((np.asarray(x, dtype=np.float64) - ORIGIN) / self.period + 1.0)
        v = np.atleast_1d((np.asarray(z, dtype=np.float64) - ORIGIN) / self.period + 1.0)
        r = ndimage.map_coordinates(self.grid, [v, u], order=3, mode="wrap")
        return float(r[0]) if scalar else r


def fbm(x, z, base_period, octaves, seed, gain=0.5, ridged=False):
    total = np.zeros_like(x, dtype=np.float32)
    amp, norm, period = 1.0, 0.0, base_period
    for o in range(octaves):
        n = Noise(seed + o * 101, period).at(x, z).astype(np.float32)
        if ridged:
            n = 1.0 - np.abs(n)
            n = n * n
        total += n * amp
        norm += amp
        amp *= gain
        period *= 0.5
    return total / norm


# ----------------------------------------------------------------------------
# 1. Base terrain
# ----------------------------------------------------------------------------
log("terrain: masks")
plain_poly = [(-5000, 300), (-1700, 300), (-1100, -180), (2050, -180), (2600, 650), (3500, 1150),
              (4350, 1400), (4500, 5000), (-5000, 5000)]
V_plain = poly_mask(plain_poly)
V_plain = ndimage.gaussian_filter(V_plain, 12)

log("terrain: noise")
plain_h = 22.0 - 0.0028 * GZ - 12.0 * np.clip((-GX - 1500) / 3500, 0, 1)
roll = fbm(GX, GZ, 1400, 4, SEED + 1) * 9.0
city_mask_soft = ndimage.gaussian_filter(poly_mask(L.CITY_POLY), 30)
plain_h += roll * (1.0 - 0.75 * city_mask_soft)
north_ramp = np.clip(-GZ, 0, None) * 0.062
floor_base = plain_h + north_ramp

# mountains: domain warped ridged noise, rising away from the plain (warped foothill line)
dist_plain = ndimage.distance_transform_edt(V_plain < 0.5) * CELL
dist_plain += fbm(GX, GZ, 1800, 3, SEED + 5) * 350 + fbm(GX, GZ, 450, 2, SEED + 6) * 90
dist_plain = np.maximum(dist_plain, 0)
wx = fbm(GX, GZ, 2600, 3, SEED + 11) * 350
wz = fbm(GX, GZ, 2600, 3, SEED + 12) * 350
ridge = fbm(GX + wx, GZ + wz, 3000, 7, SEED + 20, gain=0.5, ridged=True)
ridge = (ridge - ridge.min()) / (ridge.max() - ridge.min())
detail = fbm(GX + wz * 0.2, GZ + wx * 0.2, 380, 4, SEED + 30, ridged=True)
amp = 750 + 1500 * smoothstep(0, 3500, dist_plain)
mountain = amp * (0.25 + 0.75 * ridge ** 1.2) + detail * 90
M = smoothstep(0, 1300, dist_plain) ** 1.25
H = floor_base + M * mountain


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


# valleys and basins: V/U shaped walls, combined with smooth-min so that ridges and spurs survive
warp_x = fbm(GX, GZ, 600, 3, SEED + 40) * 70
warp_z = fbm(GX, GZ, 600, 3, SEED + 41) * 70
floor_noise = fbm(GX, GZ, 250, 3, SEED + 7) * 2.5
wall_var = 0.8 + 0.45 * fbm(GX, GZ, 520, 3, SEED + 42)
gully = (detail - float(np.median(detail))) * 160
KS = dict(varzob=0.42, sabz=0.36, gusgarf=0.55, sangtuda=0.34)
corr_mask = np.zeros((N, N), np.float32)
for c in L.CORRIDORS:
    d = densify(c["pts"], 5.0)
    tree = cKDTree(d[:, :2])
    dist, idx = tree.query(np.c_[(GX + warp_x).ravel(), (GZ + warp_z).ravel()], workers=-1)
    dist = dist.reshape(N, N)
    cf = d[idx.reshape(N, N), 2]
    excess = np.maximum(0, dist - c["half"])
    # the nearest-sample floor jumps between distant parts of the polyline: blur it away from the corridor
    cf_blur = ndimage.gaussian_filter(cf, 60)
    cf = cf * (1 - smoothstep(0, 250, excess)) + cf_blur * smoothstep(0, 250, excess)
    wall = cf + floor_noise + KS[c["name"]] * excess ** 1.18 * wall_var + gully * np.clip(excess / 140, 0, 1)
    H = smin(H, wall, 30.0)
    corr_mask = np.maximum(corr_mask, 1 - smoothstep(c["half"], c["half"] + 150, dist))
for bx, bz, br, bh in L.BASINS:
    dist = np.hypot(GX + warp_x - bx, GZ + warp_z - bz)
    excess = np.maximum(0, dist - br)
    wall = bh + floor_noise + 0.40 * excess ** 1.18 * wall_var + gully * np.clip(excess / 140, 0, 1)
    H = smin(H, wall, 30.0)
    corr_mask = np.maximum(corr_mask, 1 - smoothstep(br, br + 150, dist))
valley = np.maximum(V_plain, corr_mask)
M = np.maximum(0, M * (1 - corr_mask))

# hills
for hx, hz, hr, hh in L.HILLS:
    d = np.hypot(GX - hx, GZ - hz) / hr
    H += hh * np.exp(-d * d * 2.2)

# light thermal-like smoothing on steep areas to soften spikes
H = H.astype(np.float32)
log(f"terrain: base range {H.min():.1f} .. {H.max():.1f}")

H_natural = H.copy()
max_step(H, "base terrain")

# ----------------------------------------------------------------------------
# 2. Rivers, creeks, canals
# ----------------------------------------------------------------------------
log("water: rivers")
river_out = []
water_level = np.full((N, N), np.nan, np.float32)    # for road clearance
sand_mask = np.zeros((N, N), np.float32)
waterfalls = []
for r in L.RIVERS:
    p = chaikin(densify(r["pts"], 40.0), 3)
    p = densify(p, 5.0)
    p = p[:, :2]
    ground = sample(H, p[:, 0], p[:, 1])
    ground_s = ndimage.gaussian_filter1d(ground, 6, mode="nearest")
    level = np.minimum.accumulate(ground_s - (1.6 if r["kind"] != "river" else 2.6))
    if r["kind"] == "canal":
        # canals keep a very gentle gradient
        level = np.minimum.accumulate(np.maximum(level, level[0] - arclen(p) * 0.0015))
    w = r["width"]
    depth = r["depth"]
    tree = cKDTree(p)
    reach = w * 0.5 + 40
    dist, idx = tree.query(np.c_[GX.ravel(), GZ.ravel()], distance_upper_bound=reach, workers=-1)
    dist = dist.reshape(N, N)
    idx = idx.reshape(N, N)
    v = np.isfinite(dist)
    lv = np.zeros((N, N), np.float32)
    lv[v] = level[idx[v]]
    hw = w * 0.5
    d = dist
    tgt = np.full((N, N), np.nan, np.float32)
    inner = v & (d < hw)
    tgt[inner] = (lv[inner] - depth) + (d[inner] / hw) ** 2 * (depth + 0.5)
    bank = v & (d >= hw) & (d < hw + 6)
    tgt[bank] = lv[bank] + 0.5 + (d[bank] - hw) / 6.0 * 2.0
    outer = v & (d >= hw + 6)
    t = smoothstep(hw + 6, reach, d[outer])
    tgt[outer] = (lv[outer] + 2.5) * (1 - t) + H[outer] * t
    # banks only lower the terrain (and fill where needed close to channel)
    cut = v & ((tgt < H) | (d < hw + 6))
    H[cut] = tgt[cut]
    wl = v & (d < hw + 2)
    water_level[wl] = np.where(np.isnan(water_level[wl]), lv[wl], np.fmax(water_level[wl], lv[wl]))
    sand_mask[v & (d < hw + (10 if r["kind"] == "river" else 4))] = 1.0
    # waterfalls: steep drops
    drop = np.diff(level)
    steep = np.where(drop < -1.4)[0]
    if len(steep):
        groups = np.split(steep, np.where(np.diff(steep) > 2)[0] + 1)
        for g in groups:
            a, b = int(g[0]), int(g[-1]) + 1
            if level[a] - level[b] > 6:
                waterfalls.append(dict(name=r["name"], x0=float(p[a, 0]), z0=float(p[a, 1]), y0=float(level[a] + 0.3),
                                       x1=float(p[b, 0]), z1=float(p[b, 1]), y1=float(level[b] + 0.3), width=float(w * 0.9)))
    river_out.append(dict(name=r["name"], kind=r["kind"], width=w,
                          pts=[[round(float(a), 2), round(float(c) + 0.0, 2), round(float(b), 2)]
                               for a, b, c in zip(p[:, 0], p[:, 1], level)]))
log(f"water: {len(waterfalls)} waterfalls")

log("water: lakes")
lakes_out = []
for name, lx, lz, lr, ldepth in L.LAKES:
    d = np.hypot(GX - lx, GZ - lz)
    ring = (d > lr) & (d < lr + 40)
    level = float(np.percentile(H[ring], 15)) - 1.2
    bowl = level - ldepth * np.clip(1 - (d / lr) ** 2, 0, 1) - 0.6
    shore = level + 0.4 + np.clip((d - lr) / 30, 0, 1) * 2.0
    inside = d < lr
    H[inside] = np.minimum(H[inside], bowl[inside])
    sh = (d >= lr) & (d < lr + 30)
    H[sh] = np.minimum(H[sh], np.maximum(shore[sh], level + 0.4))
    sand_mask[(d >= lr - 8) & (d < lr + 14)] = 1.0
    water_level[d < lr + 2] = level
    lakes_out.append(dict(name=name, x=lx, z=lz, r=lr, level=round(level, 2)))

max_step(H, "after water")
# ----------------------------------------------------------------------------
# 3. Landmark pads
# ----------------------------------------------------------------------------
log("landmarks: pads")


def rect_dist(cx, cz, yaw_deg, hx, hz):
    a = math.radians(yaw_deg)
    ca, sa = math.cos(a), math.sin(a)
    lx = (GX - cx) * ca - (GZ - cz) * sa
    lz = (GX - cx) * sa + (GZ - cz) * ca
    dx = np.abs(lx) - hx
    dz = np.abs(lz) - hz
    return np.maximum(dx, dz)


pad_block = np.zeros((N, N), bool)
done_pads = set()
for lm in L.LANDMARKS:
    key = (lm["x"], lm["z"])
    hx, hz = lm["pad"]
    rd = rect_dist(lm["x"], lm["z"], 0, hx, hz)
    inside = rd < 0
    if key not in done_pads:
        h0 = float(np.median(H[inside]))
        t = smoothstep(0, 35, rd)
        sel = rd < 35
        H[sel] = (h0 * (1 - t) + H * t)[sel]
        done_pads.add(key)
        lm["y"] = round(h0, 2)
    else:
        lm["y"] = round(float(np.median(H[inside])), 2)
    pad_block |= inside

# ----------------------------------------------------------------------------
# 4. Road network: generated streets + village lanes
# ----------------------------------------------------------------------------
log("roads: generating city grid + village lanes")
roads_in = [dict(r) for r in L.ROADS]
river_line = densify(chaikin(densify(L.RIVER_MAIN, 40), 3), 5)
river_tree = cKDTree(river_line[:, :2])


def river_dist(x, z):
    d, _ = river_tree.query(np.c_[np.atleast_1d(x), np.atleast_1d(z)])
    return d


ns_avenues = [500, -890, 1710]
ew_avenues = [1680, 1070, 2430, 2840, 970, 4110, 330, -120]
city_poly = L.CITY_POLY
gen_streets = []
noise_street = Noise(SEED + 99, 400)


def landmark_hit(x, z, margin=8):
    for lm in L.LANDMARKS:
        hx, hz = lm["pad"]
        if abs(x - lm["x"]) < hx + margin and abs(z - lm["z"]) < hz + margin:
            return True
    for name, lx, lz, lr, _ in L.LAKES:
        if math.hypot(x - lx, z - lz) < lr + 25:
            return True
    return False


def split_line(points, ok_fn):
    segs, cur = [], []
    for p in points:
        if ok_fn(p):
            cur.append(p)
        else:
            if len(cur) > 1:
                segs.append(cur)
            cur = []
    if len(cur) > 1:
        segs.append(cur)
    return segs


street_names_ns = ["улица Бохтар", "улица Шотемур", "улица Лохути", "улица Пушкина", "улица Ниёзи",
                   "улица Чехова", "улица Гагарина", "улица Хувайдуллоева", "улица Борбад", "улица Саъди Шерози",
                   "улица Мирзо Ризо", "улица Шерозӣ", "улица Карамова", "улица Бобоева", "улица Дехоти",
                   "улица Пайкар", "улица Истаравшан", "улица Хамадони", "улица Кахорова"]
street_names_ew = ["улица Бухоро", "улица Турсунзода", "улица Шевченко", "улица Худжанд", "улица Негмата Карабаева",
                   "улица Мухаммадиева", "улица Логинова", "улица Валаматзода", "улица Хусейнзода", "улица Озоди",
                   "улица Фотеха Ниязи", "улица Маяковского", "улица Каххорова", "улица Рахимова",
                   "улица Тошкент", "улица Нусратулло Махсум", "улица Сомониён", "улица Зебунисо", "улица Абая",
                   "улица Санои", "улица Рахмона Набиева"]
k = 0
for gx in np.arange(-1340, 2620, 225):
    gx = gx + rng.uniform(-25, 25)
    if min(abs(gx - a) for a in ns_avenues) < 95:
        continue
    zs = np.arange(-110, 4110, 25.0)
    pts = [(gx + noise_street.at(gx, z) * 10, z) for z in zs]

    def ok(p):
        return river_dist(*p)[0] > 70 and not landmark_hit(*p)
    for seg in split_line(pts, ok):
        if len(seg) * 25 > 120:
            gen_streets.append(dict(name=street_names_ns[k % len(street_names_ns)], type="street", pts=seg[::4] + [seg[-1]]))
    k += 1
k = 0
for gz in np.arange(80, 4100, 205):
    gz = gz + rng.uniform(-25, 25)
    if min(abs(gz - a) for a in ew_avenues) < 90:
        continue
    xs_ = np.arange(-1440, 2660, 25.0)
    pts = [(x, gz + noise_street.at(x, gz + 500) * 10) for x in xs_]
    bridge_ok = (k % 3 == 1)

    def ok(p, bridge_ok=bridge_ok):
        rd = river_dist(*p)[0]
        if rd < 60 and not bridge_ok:
            return False
        return not landmark_hit(*p)
    for seg in split_line(pts, ok):
        if len(seg) * 25 > 120:
            gen_streets.append(dict(name=street_names_ew[k % len(street_names_ew)], type="street", pts=seg[::4] + [seg[-1]]))
    k += 1
log(f"roads: {len(gen_streets)} generated street segments")
roads_in += gen_streets

# village lanes
village_lanes = []
for vname, vx, vz, vr, vstyle, nh in L.VILLAGES:
    vr_rng = np.random.default_rng(abs(hash(vname)) % (2**32))
    n_l = 3 if vstyle == "mountain" else 5
    base_ang = vr_rng.uniform(0, math.pi)
    for li in range(n_l):
        a = base_ang + li * (2 * math.pi / n_l) + vr_rng.uniform(-0.3, 0.3)
        length = vr * vr_rng.uniform(0.8, 1.15)
        pts = []
        for s in np.linspace(0, length, 8):
            bend = math.sin(s / length * 3.0 + li) * 25
            px = vx + math.cos(a) * s - math.sin(a) * bend
            pz = vz + math.sin(a) * s + math.cos(a) * bend
            pts.append((px, pz))
        h_c = float(sample(H, vx, vz)[0])
        kept = []
        for p_ in pts:
            if abs(float(sample(H, p_[0], p_[1])[0]) - h_c) > 22.0:
                break       # stop where the lane would climb the mountainside
            kept.append(p_)
        pts = [p_ for p_ in kept if not landmark_hit(*p_) and river_dist(*p_)[0] > 25]
        if len(pts) > 2:
            village_lanes.append(dict(name=f"{vname}, улица {li + 1}", type="dirt" if vstyle == "mountain" else "rural",
                                      pts=pts, village=vname))
roads_in += village_lanes

# ----------------------------------------------------------------------------
# 5. Road profiles, bridges, tunnels, carving
# ----------------------------------------------------------------------------
log("roads: profiles and carving")
road_h = np.full((N, N), np.nan, np.float32)      # carved road surface height
road_occ = np.zeros((N, N), bool)                 # carriageway+sidewalk footprint
road_dirt = np.zeros((N, N), np.float32)
holes = np.zeros((N, N), np.uint8)
roads_out = []
all_samples_by_tier = {0: [], 1: [], 2: []}
H_pre_roads = H.copy()

def carve_piece(P, Hh, W):
    global H
    reach = float(W.max()) + 3.0 + 140.0
    i0 = max(0, int((P[:, 0].min() - reach - ORIGIN) / CELL))
    i1 = min(N, int((P[:, 0].max() + reach - ORIGIN) / CELL) + 2)
    j0 = max(0, int((P[:, 1].min() - reach - ORIGIN) / CELL))
    j1 = min(N, int((P[:, 1].max() + reach - ORIGIN) / CELL) + 2)
    sub = (slice(j0, j1), slice(i0, i1))
    gx = GX[sub]
    gz = GZ[sub]
    tree = cKDTree(P)
    dist, idx = tree.query(np.c_[gx.ravel(), gz.ravel()], distance_upper_bound=reach)
    dist = dist.reshape(gx.shape)
    idx = idx.reshape(gx.shape)
    v = np.isfinite(dist)
    if not v.any():
        return
    idx[~v] = 0
    hr = Hh[idx].astype(np.float32)
    wr = W[idx].astype(np.float32)
    Hs = H[sub]
    occ_sub = road_occ[sub]
    flat = v & (dist <= wr + 3.0)
    newH = Hs.copy()
    newH[flat] = hr[flat] - 0.30
    sl = v & ~flat
    diff = np.abs(Hs[sl] - hr[sl])
    blend = np.clip(diff * 1.45, 4.0, 140.0)
    t = smoothstep(0.0, 1.0, (dist[sl] - wr[sl] - 3.0) / blend)
    newH[sl] = (hr[sl] - 0.30) * (1 - t) + Hs[sl] * t
    if occ_sub.any():
        d_old = ndimage.distance_transform_edt(~occ_sub) * CELL
        protect = 1.0 - smoothstep(4.0, 40.0, d_old)
        protect[flat] = 0.0
        newH = newH * (1.0 - protect) + Hs * protect
    newH[occ_sub] = Hs[occ_sub]
    H[sub] = newH
    occ = v & (dist <= wr + 1.0)
    rh = road_h[sub]
    rh[occ & ~occ_sub] = hr[occ & ~occ_sub]
    road_h[sub] = rh
    road_occ[sub] = occ_sub | occ


for tier in (0, 1, 2):
    tier_roads = [r for r in roads_in if L.ROAD_TYPES[r["type"]]["tier"] == tier]
    carve_runs = []
    for r in tier_roads:
        rt = L.ROAD_TYPES[r["type"]]
        pts = np.asarray(r["pts"], float)
        sm = chaikin(densify(pts, 60.0) if not r.get("serpentine") else pts, 3 if not r.get("serpentine") else 4)
        p = densify(sm, 4.0)[:, :2]
        s = arclen(p)
        if s[-1] < 30:
            continue
        terr = sample(H, p[:, 0], p[:, 1])
        existing = sample(np.nan_to_num(road_h, nan=-9999.0), p[:, 0], p[:, 1], order=0)
        pinned = existing > -9000
        if r["type"] == "highway":
            env = ndimage.minimum_filter1d(terr, 31 if r["type"] == "highway" else 25, mode="nearest")
            terr_use = np.minimum(terr, ndimage.gaussian_filter1d(env, 8, mode="nearest") + 1.5)
        else:
            terr_use = terr
        raw = np.where(pinned, existing, terr_use)
        for tzx, tzz, tzr in r.get("tunnel_zones", []):
            inz = np.hypot(p[:, 0] - tzx, p[:, 1] - tzz) < tzr
            if inz.any() and (~inz).any():
                ii = np.arange(len(raw))
                raw[inz] = np.interp(ii[inz], ii[~inz], raw[~inz])
        sig = rt["smooth"] / 4.0
        if r.get("serpentine"):
            h0, h1 = terr[0], terr[-1]
            prof = h0 + (h1 - h0) * s / s[-1]
            prof = smooth_1d(prof, 3)
        else:
            prof = smooth_1d(raw, sig, pinned, iters=6)
        # clearance over water
        wl = sample(np.nan_to_num(water_level, nan=-9999.0), p[:, 0], p[:, 1], order=0)
        need = np.where(wl > -9000, wl + (3.2 if r["type"] in ("avenue", "boulevard", "highway") else 2.0), -9999)
        # spread the clearance requirement along the road (bridge deck span)
        need = ndimage.maximum_filter1d(need, 9)
        g = rt["grade"] * 4.0
        # symmetric grade limit (cut at the top, fill at the bottom) unless pinned to existing roads
        if not r.get("serpentine"):
            for _ in range(2):
                for i in range(1, len(prof)):
                    if not pinned[i]:
                        prof[i] = min(max(prof[i], prof[i - 1] - g), prof[i - 1] + g)
                for i in range(len(prof) - 2, -1, -1):
                    if not pinned[i]:
                        prof[i] = min(max(prof[i], prof[i + 1] - g), prof[i + 1] + g)
        prof = np.maximum(prof, need)
        # raise-only ramps up to bridge decks
        for i in range(1, len(prof)):
            prof[i] = max(prof[i], prof[i - 1] - g)
        for i in range(len(prof) - 2, -1, -1):
            prof[i] = max(prof[i], prof[i + 1] - g)
        if not r.get("serpentine"):
            fixed = pinned | (need > -9000)
            prof = smooth_1d(prof, 2.0, fixed, iters=2)
        # bridges & tunnels from the pre-road terrain
        nat = sample(H_pre_roads, p[:, 0], p[:, 1])
        is_bridge = (prof - nat > 3.0) & ~pinned
        is_bridge |= (need > -9000) & (prof - nat > 1.5)
        is_tunnel = (nat - prof > 16.0) if r.get("tunnel") else np.zeros(len(prof), bool)
        # cleanup tiny runs
        is_bridge = ndimage.binary_closing(is_bridge, iterations=3)
        is_bridge = ndimage.binary_opening(is_bridge, iterations=2)
        is_tunnel = ndimage.binary_closing(is_tunnel, iterations=4)
        is_tunnel = ndimage.binary_opening(is_tunnel, iterations=3)
        # bridges only make sense over water or gullies; drop low long fills (> 120 m) not over water
        lab, nl = ndimage.label(is_bridge)
        for li in range(1, nl + 1):
            idxs = np.where(lab == li)[0]
            over_water = (wl[idxs] > -9000).any()
            if not over_water and (len(idxs) * 4 > 160 or (prof[idxs] - nat[idxs]).max() < 5):
                is_bridge[idxs] = False
        # extend bridges a little at both ends (abutments)
        is_bridge = ndimage.binary_dilation(is_bridge, iterations=2) & ~pinned
        is_tunnel = ndimage.binary_dilation(is_tunnel, iterations=1)

        def runs(mask):
            lab, nl = ndimage.label(mask)
            out = []
            for li in range(1, nl + 1):
                ii = np.where(lab == li)[0]
                out.append([int(ii[0]), int(ii[-1])])
            return out

        half = rt["half"]
        walk = rt["sidewalk"]
        keep = ~is_bridge & ~is_tunnel
        carve_runs.append((p, prof, np.full(len(p), half + walk), keep))
        # portal holes
        for a, b in runs(is_tunnel):
            for end, direction in ((a, 1), (b, -1)):
                for kk in range(0, 9):
                    ii = end + direction * kk
                    if 0 <= ii < len(p):
                        dd = np.hypot(GX - p[ii, 0], GZ - p[ii, 1])
                        holes[dd < half + 3.5] = 1
        out = dict(name=r["name"], type=r["type"], tier=tier,
                   pts=[[round(float(a), 2), round(float(c), 2), round(float(b), 2)]
                        for a, b, c in zip(p[:, 0], p[:, 1], prof)],
                   bridges=runs(is_bridge), tunnels=runs(is_tunnel))
        if "village" in r:
            out["village"] = r["village"]
        roads_out.append(out)
        all_samples_by_tier[tier].append((len(roads_out) - 1, p, prof, half + walk))

    # sequential carving in ~240 m pieces: every piece blends into the terrain carved so far,
    # so switchbacks and parallel roads never create cliffs between their flat zones
    for (pp, hh, ww, kk) in carve_runs:
        lab, nl = ndimage.label(kk)
        for li in range(1, nl + 1):
            ids = np.where(lab == li)[0]
            for s0 in range(0, len(ids), 60):
                sel = ids[max(0, s0 - 2): s0 + 62]
                if len(sel) < 2:
                    continue
                carve_piece(pp[sel], hh[sel], ww[sel])
    log(f"roads: tier {tier}: {len(tier_roads)} roads carved")

max_step(H, "after roads")
# terrain holes must never cut through a road that is carved on the surface
holes[road_occ & (holes == 1)] = 0

# gaps: lower tier samples inside higher tier roads (intersections)
log("roads: intersections")
intersections = []
higher = []
for tier in (0, 1, 2):
    if higher:
        hp = np.vstack([h[1] for h in higher])
        hw = np.concatenate([np.full(len(h[1]), h[3]) for h in higher])
        hid = np.concatenate([np.full(len(h[1]), h[0]) for h in higher])
        ht = cKDTree(hp)
        for ri, p, prof, w in all_samples_by_tier[tier]:
            d, ii = ht.query(p)
            gap = d < hw[ii] - 0.5
            roads_out[ri]["gaps"] = []
            lab, nl = ndimage.label(gap)
            for li in range(1, nl + 1):
                jj = np.where(lab == li)[0]
                roads_out[ri]["gaps"].append([int(jj[0]), int(jj[-1])])
                c = jj[len(jj) // 2]
                hi = ii[c]
                intersections.append([round(float(hp[hi, 0]), 1), round(float(hp[hi, 1]), 1),
                                      int(hid[hi]), ri])
    # same tier crossings (e.g. street x street)
    same = all_samples_by_tier[tier]
    if len(same) > 1:
        sp = np.vstack([s[1] for s in same])
        sid = np.concatenate([np.full(len(s[1]), s[0]) for s in same])
        st = cKDTree(sp)
        pairs = st.query_pairs(3.0, output_type="ndarray")
        if len(pairs):
            pairs = pairs[sid[pairs[:, 0]] != sid[pairs[:, 1]]]
            for a, b in pairs[:: max(1, len(pairs) // 4000)]:
                intersections.append([round(float(sp[a, 0]), 1), round(float(sp[a, 1]), 1), int(sid[a]), int(sid[b])])
    higher += all_samples_by_tier[tier]

# merge intersections
if intersections:
    arr = np.array([[i[0], i[1]] for i in intersections])
    t = cKDTree(arr)
    groups = t.query_ball_point(arr, 22.0)
    used = np.zeros(len(arr), bool)
    merged = []
    for i, g in enumerate(groups):
        if used[i]:
            continue
        g = [j for j in g if not used[j]]
        used[g] = True
        c = arr[g].mean(0)
        rr = sorted({intersections[j][2] for j in g} | {intersections[j][3] for j in g})
        merged.append([round(float(c[0]), 1), round(float(c[1]), 1), rr])
    intersections = merged
log(f"roads: {len(intersections)} intersections")

# sidewalk cuts, crosswalks and traffic lights around intersections
CITY_T = ("avenue", "boulevard", "street")
crosswalks = []
traffic_lights = []
for r in roads_out:
    r["swcut"] = []
for cx, cz, rl in intersections:
    types = [roads_out[j]["type"] for j in rl]
    if sum(t in CITY_T for t in types) >= 2 and any(t in ("avenue", "boulevard") for t in types):
        traffic_lights.append([cx, cz])
    for ri in rl:
        r = roads_out[ri]
        others = [j for j in rl if j != ri]
        if not others:
            continue
        R = max(L.ROAD_TYPES[roads_out[j]["type"]]["half"] + L.ROAD_TYPES[roads_out[j]["type"]]["sidewalk"] for j in others) + 2.5
        pts = np.array(r["pts"])
        d = np.hypot(pts[:, 0] - cx, pts[:, 2] - cz)
        near = np.where(d < R)[0]
        if len(near) == 0:
            continue
        r["swcut"].append([int(near[0]), int(near[-1])])
        if r["type"] in CITY_T and all(t in CITY_T for t in types):
            for idx in (int(near[0]) - 1, int(near[-1]) + 1):
                if 1 <= idx < len(pts) - 1:
                    t = pts[idx + 1] - pts[idx - 1]
                    yaw = math.degrees(math.atan2(t[0], t[2]))
                    crosswalks.append([round(float(pts[idx, 0]), 2), round(float(pts[idx, 1]), 2), round(float(pts[idx, 2]), 2),
                                       round(yaw, 1), L.ROAD_TYPES[r["type"]]["half"] * 2])
log(f"roads: {len(crosswalks)} crosswalks, {len(traffic_lights)} traffic lights")

# ----------------------------------------------------------------------------
# 6. POIs snapped beside roads, pads flattened
# ----------------------------------------------------------------------------
log("pois")
allp = np.vstack([np.c_[np.array(r["pts"])[:, [0, 2, 1]], np.full(len(r["pts"]), i)] for i, r in enumerate(roads_out)])
road_tree = cKDTree(allp[:, :2])
pois_out = []
POI_SIZE = dict(gas_station=(26, 20), cafe=(14, 12), chaikhana=(18, 14), viewpoint=(16, 12), tourist_base=(40, 30),
                restaurant=(20, 16), market=(40, 28), parking=(30, 20), shop=(10, 8))
occ_build = road_occ.copy() | pad_block
for typ, px, pz, _ in L.POIS:
    d, ii = road_tree.query([px, pz])
    rp = allp[ii]
    road = roads_out[int(rp[3])]
    pts = np.array(road["pts"])
    j = int(np.argmin(np.hypot(pts[:, 0] - rp[0], pts[:, 2] - rp[1])))
    j0, j1 = max(0, j - 1), min(len(pts) - 1, j + 1)
    tx, tz = pts[j1, 0] - pts[j0, 0], pts[j1, 2] - pts[j0, 2]
    tl = math.hypot(tx, tz) or 1
    tx, tz = tx / tl, tz / tl
    nx, nz = -tz, tx
    side = 1 if (px - rp[0]) * nx + (pz - rp[1]) * nz >= 0 else -1
    rt = L.ROAD_TYPES[road["type"]]
    hx, hz = POI_SIZE[typ]
    off = rt["half"] + rt["sidewalk"] + hz + 4
    cx, cz = rp[0] + nx * side * off, rp[1] + nz * side * off
    yaw = math.degrees(math.atan2(-nx * side, -nz * side))   # +Z of the POI faces the road
    y = float(pts[j, 1])
    dd = rect_dist(cx, cz, 0, max(hx, hz) + 2, max(hx, hz) + 2)
    sel = (dd < 25) & ~road_occ
    t = smoothstep(0, 25, dd)
    H[sel] = ((y - 0.05) * (1 - t) + H * t)[sel]
    occ_build |= dd < 4
    pois_out.append(dict(type=typ, x=round(cx, 1), z=round(cz, 1), y=round(y, 2), yaw=round(yaw, 1),
                         road=road["name"]))

# ----------------------------------------------------------------------------
# 7. Buildings
# ----------------------------------------------------------------------------
log("buildings")
water_any = ~np.isnan(water_level)
occ_build |= water_any
occ_build |= ndimage.binary_dilation(road_occ, iterations=1)
city_mask = poly_mask(L.CITY_POLY) > 0.5
slope = np.hypot(*np.gradient(H, CELL))
buildings = []


def footprint_cells(cx, cz, yaw, w, d):
    a = math.radians(yaw)
    ca, sa = math.cos(a), math.sin(a)
    r = math.hypot(w, d) * 0.5 + CELL
    i0 = int(max(0, (cx - r - ORIGIN) / CELL))
    i1 = int(min(N - 1, (cx + r - ORIGIN) / CELL + 1))
    j0 = int(max(0, (cz - r - ORIGIN) / CELL))
    j1 = int(min(N - 1, (cz + r - ORIGIN) / CELL + 1))
    sx = GX[j0:j1 + 1, i0:i1 + 1] - cx
    sz = GZ[j0:j1 + 1, i0:i1 + 1] - cz
    lx = sx * ca + sz * sa
    lz = -sx * sa + sz * ca
    m = (np.abs(lx) <= w * 0.5 + 2.5) & (np.abs(lz) <= d * 0.5 + 2.5)
    return (slice(j0, j1 + 1), slice(i0, i1 + 1)), m


def try_place(cx, cz, yaw, w, d, style, floors, extra=None, max_slope=0.25):
    if not (ORIGIN + 50 < cx < -ORIGIN - 50 and ORIGIN + 50 < cz < -ORIGIN - 50):
        return False
    sl, m = footprint_cells(cx, cz, yaw, w, d)
    if (occ_build[sl] & m).any():
        return False
    hs = H[sl][m]
    if hs.max() - hs.min() > max(3.0, max_slope * max(w, d)):
        return False
    occ_build[sl] |= m
    base = float(hs.min())
    b = [round(cx, 1), round(cz, 1), round(yaw, 1), round(w, 1), round(d, 1), int(floors), int(style),
         round(base, 2), int(rng.integers(0, 1 << 30))]
    buildings.append(b)
    return True


center = np.array([500.0, 2000.0])


def city_style(x, z, frontage):
    dc = math.hypot(x - center[0], z - center[1])
    district_edge = (x > 1900 or x < -1100 or z > 3500 or z < 250)
    r = rng.random()
    if dc < 900:
        if frontage and r < 0.45:
            return 3
        if r < 0.62:
            return 2 if frontage else 1
        if r < 0.8:
            return 0
        return 4 if frontage else 1
    if district_edge:
        if r < 0.62:
            return 5
        if r < 0.75:
            return 4 if frontage else 5
        if r < 0.9:
            return 0
        return 6
    if r < 0.36:
        return 0
    if r < 0.62:
        return 1
    if r < 0.72:
        return 2 if frontage else 1
    if r < 0.84:
        return 4 if frontage else 0
    if r < 0.9:
        return 6
    return 5


def dims(style):
    if style == 0:
        return rng.uniform(45, 80), 12.5, int(rng.choice([4, 5, 5, 5]))
    if style == 1:
        return rng.uniform(40, 100), 13.5, int(rng.choice([9, 9, 9, 12, 16]))
    if style == 2:
        return rng.uniform(22, 36), rng.uniform(20, 30), int(rng.integers(12, 26))
    if style == 3:
        return rng.uniform(40, 85), 16.0, int(rng.integers(3, 6))
    if style == 4:
        return rng.uniform(12, 32), rng.uniform(10, 16), int(rng.integers(1, 3))
    if style == 5:
        return rng.uniform(18, 26), rng.uniform(20, 28), int(rng.choice([1, 1, 2]))
    if style == 6:
        return rng.uniform(55, 80), 16.0, 3
    return 12, 10, 1


# frontage pass along city roads
for ri, r in enumerate(roads_out):
    if r["type"] not in ("avenue", "boulevard", "street") or r.get("village"):
        continue
    rt = L.ROAD_TYPES[r["type"]]
    pts = np.array(r["pts"])
    if len(pts) < 4:
        continue
    step_i = 9
    i = int(rng.integers(2, 8))
    while i < len(pts) - 2:
        x, y, z = pts[i]
        if not city_mask[int((z - ORIGIN) / CELL), int((x - ORIGIN) / CELL)]:
            i += step_i
            continue
        tx, tz = pts[i + 1, 0] - pts[i - 1, 0], pts[i + 1, 2] - pts[i - 1, 2]
        tl = math.hypot(tx, tz) or 1
        tx, tz = tx / tl, tz / tl
        nx, nz = -tz, tx
        yaw_road = math.degrees(math.atan2(tx, tz))
        for side in (-1, 1):
            st = city_style(x, z, True)
            w, d, fl = dims(st)
            setback = rt["half"] + rt["sidewalk"] + rng.uniform(4, 12) + d * 0.5
            cx, cz = x + nx * side * setback, z + nz * side * setback
            # building local +Z faces the road; yaw such that local X follows the road
            yaw = yaw_road + 90 if side > 0 else yaw_road - 90
            try_place(cx, cz, (yaw + 180) % 360, w, d, st, fl)
        i += step_i + int(rng.integers(0, 8))
log(f"buildings: frontage {len(buildings)}")

# interior microdistricts
cand = rng.uniform([-1440, -140], [2690, 4140], (26000, 2))
for cx, cz in cand:
    jj, ii = int((cz - ORIGIN) / CELL), int((cx - ORIGIN) / CELL)
    if not city_mask[jj, ii]:
        continue
    st = city_style(cx, cz, False)
    w, d, fl = dims(st)
    yaw = float(rng.choice([0, 90, 180, 270])) + rng.uniform(-4, 4)
    try_place(cx, cz, yaw, w, d, st, fl)
log(f"buildings: city total {len(buildings)}")

# villages
village_out = []
for vname, vx, vz, vr, vstyle, nh in L.VILLAGES:
    placed = 0
    tries = 0
    lanes = [r for r in roads_out if r.get("village") == vname]
    lane_pts = np.vstack([np.array(r["pts"])[:, [0, 2]] for r in lanes]) if lanes else np.array([[vx, vz]])
    lt = cKDTree(lane_pts)
    while placed < nh and tries < nh * 40:
        tries += 1
        a = rng.uniform(0, 2 * math.pi)
        rr = vr * math.sqrt(rng.uniform(0.0, 1.0))
        cx, cz = vx + math.cos(a) * rr, vz + math.sin(a) * rr
        d, k2 = lt.query([cx, cz])
        if d > 55:
            continue
        # orient to the nearest lane
        kk = min(k2, len(lane_pts) - 2)
        tx, tz = lane_pts[kk + 1] - lane_pts[kk]
        yaw = math.degrees(math.atan2(tx, tz)) + 90 + float(rng.choice([0, 180]))
        st = 7
        if rng.random() < 0.08:
            st = 4
        w, dd = (rng.uniform(17, 24), rng.uniform(18, 26)) if st == 7 else (rng.uniform(9, 14), rng.uniform(8, 11))
        if try_place(cx, cz, yaw, w, dd, st, 1 if rng.random() < 0.85 else 2, max_slope=0.45):
            placed += 1
    village_out.append(dict(name=vname, x=vx, z=vz, r=vr, style=vstyle, houses=placed))
log(f"buildings: total {len(buildings)} (villages {sum(v['houses'] for v in village_out)})")

# ----------------------------------------------------------------------------
# 8. Splat + vegetation maps
# ----------------------------------------------------------------------------
log("splat & vegetation")
RS = 2048


def to_res(a, res=RS, order=1):
    return ndimage.zoom(a.astype(np.float32), res / N, order=order)


slope = np.hypot(*np.gradient(H, CELL))
nz1 = fbm(GX, GZ, 160, 3, SEED + 300)
nz2 = fbm(GX, GZ, 700, 3, SEED + 301)

urban = ndimage.gaussian_filter(city_mask.astype(np.float32), 3) * np.clip(0.55 + nz1 * 0.8, 0, 1)
park_mask = np.zeros((N, N), np.float32)
for lm in L.LANDMARKS:
    if lm["id"] in ("rudaki_park", "flag_park", "victory_park", "kohi_navruz", "palace_of_nations"):
        park_mask = np.maximum(park_mask, (rect_dist(lm["x"], lm["z"], 0, *lm["pad"]) < 0).astype(np.float32))
urban *= (1 - park_mask)

# farmland patchwork in Hisor and rural east
farm_region = (poly_mask([(-5000, 300), (-1500, 300), (-1500, 5000), (-5000, 5000)]) +
               poly_mask([(2700, 1300), (4400, 1500), (4500, 5000), (-1400, 5000), (-1400, 4200), (2700, 4200)]))
farm_region = np.clip(farm_region, 0, 1) * (1 - M) * (slope < 0.18)
village_mask = np.zeros((N, N), np.float32)
for vname, vx, vz, vr, vstyle, nh in L.VILLAGES:
    d = np.hypot(GX - vx, GZ - vz)
    village_mask = np.maximum(village_mask, 1 - smoothstep(vr * 0.9, vr * 1.25, d))
village_mask_far = np.zeros((N, N), np.float32)
for vname, vx, vz, vr, vstyle, nh in L.VILLAGES:
    village_mask_far = np.maximum(village_mask_far, 1 - smoothstep(vr * 1.1, vr * 2.2, np.hypot(GX - vx, GZ - vz)))
water_any_pre = ~np.isnan(water_level)

# --- agricultural parcels: fields (crop codes), apricot orchards, vineyards ---
parcels = []
field_img = Image.new("L", (RS, RS), 0)
fdraw = ImageDraw.Draw(field_img)
orch_img = Image.new("L", (N, N), 0)
vine_img = Image.new("L", (N, N), 0)
odraw, vdraw = ImageDraw.Draw(orch_img), ImageDraw.Draw(vine_img)
blocked_ag = ndimage.binary_dilation(road_occ, iterations=2) | water_any_pre | (village_mask > 0.6) | city_mask
for area_ang, area_seed in ((math.radians(8), 1), (math.radians(-14), 2)):
    ca, sa = math.cos(area_ang), math.sin(area_ang)
    v = -5200.0
    prng = np.random.default_rng(SEED + 500 + area_seed)
    while v < 5200:
        rowh = prng.uniform(45, 95)
        u = -5200.0 + prng.uniform(0, 60)
        while u < 5200:
            pw = prng.uniform(60, 190)
            cu, cv = u + pw / 2, v + rowh / 2
            cx, cz = cu * ca - cv * sa, cu * sa + cv * ca
            u += pw
            if not (-4990 < cx < 4990 and -4990 < cz < 4990):
                continue
            gi, gj = int((cx - ORIGIN) / CELL), int((cz - ORIGIN) / CELL)
            if farm_region[gj, gi] < 0.5 or (area_seed == 1) != (cx < -1000):
                continue
            hw, hd = pw / 2 - 2.5, rowh / 2 - 2.5
            corners = [(cx + sx * hw * ca - sz * hd * sa, cz + sx * hw * sa + sz * hd * ca)
                       for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            bad = False
            for qx, qz in corners + [(cx, cz)]:
                qi, qj = int((qx - ORIGIN) / CELL), int((qz - ORIGIN) / CELL)
                if not (0 <= qi < N and 0 <= qj < N) or blocked_ag[qj, qi] or farm_region[qj, qi] < 0.3:
                    bad = True
                    break
            if bad:
                continue
            r_ = prng.random()
            near_village = village_mask_far[gj, gi] > 0.3
            if near_village and r_ < 0.35:
                code = 6          # apricot orchard
            elif r_ < 0.10 or (near_village and r_ < 0.45):
                code = 7          # vineyard
            else:
                code = int(prng.choice([1, 1, 2, 2, 3, 4, 4, 5]))
            poly_rs = [((qx - ORIGIN) / SIZE * (RS - 1), (qz - ORIGIN) / SIZE * (RS - 1)) for qx, qz in corners]
            fdraw.polygon(poly_rs, fill=code * 30)
            poly_n = [((qx - ORIGIN) / CELL, (qz - ORIGIN) / CELL) for qx, qz in corners]
            if code == 6:
                odraw.polygon(poly_n, fill=255)
            if code == 7:
                vdraw.polygon(poly_n, fill=255)
            if code in (6, 7):
                parcels.append([round(cx, 1), round(cz, 1), round(math.degrees(area_ang), 1),
                                round(hw * 2, 1), round(hd * 2, 1), code])
        v += rowh
field_img.save(os.path.join(DATA, "fields.pngdat"), format="PNG", optimize=True)
field_codes = np.asarray(field_img.resize((N, N), Image.NEAREST))
farmland = ((field_codes > 0) & (field_codes < 180)).astype(np.float32)
orch_parcels = np.asarray(orch_img, np.float32) / 255
vine = np.asarray(vine_img, np.float32) / 255
log(f"parcels: {len(parcels)} orchards/vineyards")
farmland *= (1 - village_mask)

dirt = np.clip(village_mask * (0.35 + 0.5 * nz1), 0, 1)
road_buffer = ndimage.binary_dilation(road_occ, iterations=1) & ~road_occ
dirt = np.maximum(dirt, road_buffer * 0.6)
for r in roads_out:
    if r["type"] == "dirt":
        p = np.array(r["pts"])
        gi, gj = to_grid(p[:, 0], p[:, 2])
        dirt[np.clip(gj.astype(int), 0, N - 1), np.clip(gi.astype(int), 0, N - 1)] = 1.0
dirt = np.maximum(dirt, ndimage.gaussian_filter(dirt, 0.7))
farmland *= (1 - road_occ)

splat = np.stack([
    np.clip(dirt, 0, 1),
    np.clip(farmland, 0, 1),
    np.clip(urban * (1 - farmland), 0, 1),
    np.clip(ndimage.gaussian_filter(sand_mask, 1.0), 0, 1),
], -1)
img = np.clip(np.stack([to_res(splat[..., c]) for c in range(4)], -1) * 255, 0, 255).astype(np.uint8)
# farmland weight straight from the high-res parcel raster (crisp, anti-aliased edges)
fr = np.asarray(field_img)
fmask = ((fr > 0) & (fr < 180)).astype(np.float32)
fmask = ndimage.gaussian_filter(fmask, 0.7) * (1.0 - np.clip(to_res(road_occ.astype(np.float32)), 0, 1))
img[..., 1] = np.clip(fmask * 255, 0, 255).astype(np.uint8)
Image.fromarray(img, "RGBA").save(os.path.join(DATA, "splat.pngdat"), format="PNG", optimize=True)

# vegetation
elev = H
forest = np.clip((nz2 * 0.9 + 0.35 + nz1 * 0.3), 0, 1) * smoothstep(80, 300, elev) * (1 - smoothstep(1500, 1800, elev))
forest *= (1 - smoothstep(0.65, 1.0, slope)) * (M > 0.05)
riparian = np.zeros((N, N), np.float32)
for r in L.RIVERS:
    p = densify(chaikin(densify(r["pts"], 40.0), 3), 10.0)
    t = cKDTree(p[:, :2])
    w = r["width"]
    d, _ = t.query(np.c_[GX.ravel(), GZ.ravel()], distance_upper_bound=w * 0.5 + 60, workers=-1)
    d = d.reshape(N, N)
    m = np.isfinite(d) & (d > w * 0.5 + 3)
    riparian[m] = np.maximum(riparian[m], (1 - smoothstep(w * 0.5 + 10, w * 0.5 + 60, d[m])) * 0.9)
forest = np.maximum(forest, riparian * np.clip(0.6 + nz1, 0, 1))
forest = np.maximum(forest, park_mask * 0.55)
forest *= (1 - city_mask * 0.75)
forest *= ~road_occ
forest *= (1 - farmland)
forest *= water_any == 0

orchard = village_mask * np.clip(0.4 + nz1, 0, 1)
orchard = np.maximum(orchard * 0.6, orch_parcels)
orchard *= ~road_occ * (1 - farmland * 0.7)
meadow = np.clip(0.55 + nz1 * 0.6, 0, 1) * (1 - smoothstep(1700, 2000, elev)) * (1 - smoothstep(0.7, 1.1, slope))
meadow *= (1 - urban * 0.8) * ~road_occ * (water_any == 0)
veg = np.stack([forest, orchard, vine, meadow], -1)
img = np.clip(np.stack([to_res(veg[..., c], 1024) for c in range(4)], -1) * 255, 0, 255).astype(np.uint8)
Image.fromarray(img, "RGBA").save(os.path.join(DATA, "veg.pngdat"), format="PNG", optimize=True)

# ----------------------------------------------------------------------------
# 9. Export heightmap / holes / json
# ----------------------------------------------------------------------------
log("export")
H.astype("<f4").tofile(os.path.join(DATA, "heightmap.f32"))
hj, hi = np.nonzero(holes)


def region_of(polys, x, z):
    for name, poly in polys:
        xs_ = [p[0] for p in poly]
        zs_ = [p[1] for p in poly]
        if min(xs_) <= x <= max(xs_) and min(zs_) <= z <= max(zs_):
            return name
    return None


world = dict(
    meta=dict(size=SIZE, origin=ORIGIN, cell=CELL, n=N, hmin=HMIN, hrange=HRANGE, seed=SEED,
              splat_res=RS, veg_res=1024, generated=time.strftime("%Y-%m-%d")),
    districts=[dict(name=n, poly=p) for n, p in L.DISTRICTS],
    regions=[dict(name=n, poly=p) for n, p in L.REGIONS],
    city_poly=L.CITY_POLY,
    road_types=L.ROAD_TYPES,
    roads=roads_out,
    intersections=intersections,
    holes=[[int(a), int(b)] for a, b in zip(hi, hj)],
    crosswalks=crosswalks,
    traffic_lights=traffic_lights,
    rivers=river_out,
    lakes=lakes_out,
    waterfalls=waterfalls,
    landmarks=L.LANDMARKS,
    villages=village_out,
    pois=pois_out,
    buildings=buildings,
    parcels=parcels,
    spawn=dict(x=L.PLAYER_SPAWN[0], z=L.PLAYER_SPAWN[1], yaw=L.PLAYER_SPAWN[2],
               y=round(float(sample(H, L.PLAYER_SPAWN[0], L.PLAYER_SPAWN[1])[0]), 2)),
)
with open(os.path.join(DATA, "world.json"), "w", encoding="utf-8") as f:
    json.dump(world, f, ensure_ascii=False, separators=(",", ":"))

# ----------------------------------------------------------------------------
# 10. Maps (minimap + annotated overview)
# ----------------------------------------------------------------------------
log("maps")
MR = 2048
Hm = to_res(H, MR)
gy, gx = np.gradient(Hm, SIZE / MR)
shade = np.clip(0.75 + (gx * -0.6 + gy * -0.6) * 0.9, 0.35, 1.25)
col = np.zeros((MR, MR, 3), np.float32)
low = np.array([118, 150, 82]) / 255
mid = np.array([132, 120, 92]) / 255
high = np.array([120, 112, 105]) / 255
snow = np.array([238, 240, 245]) / 255
hn = np.clip(Hm / 1200, 0, 1)[..., None]
col = low * (1 - hn) + mid * hn
col = np.where((Hm > 1100)[..., None], high, col)
col = np.where((Hm > 1550)[..., None], snow, col)
spl = np.stack([to_res(splat[..., c], MR) for c in range(4)], -1)
fr = to_res(forest, MR)[..., None]
col = col * (1 - fr * 0.45) + np.array([60, 98, 52]) / 255 * fr * 0.45
col = col * (1 - spl[..., 1:2] * 0.7) + np.array([170, 165, 95]) / 255 * spl[..., 1:2] * 0.7
col = col * (1 - spl[..., 2:3] * 0.8) + np.array([200, 196, 188]) / 255 * spl[..., 2:3] * 0.8
col *= shade[..., None]
wm = to_res(water_any.astype(np.float32), MR)[..., None] > 0.3
col = np.where(wm, np.array([70, 130, 190]) / 255, col)
img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
dr = ImageDraw.Draw(img)


def m2p(x, z):
    return ((x - ORIGIN) / SIZE * MR, (z - ORIGIN) / SIZE * MR)


for b in buildings:
    cx, cz, yaw, w, d = b[:5]
    a = math.radians(yaw)
    ca, sa = math.cos(a), math.sin(a)
    cs = []
    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        lx, lz = sx * w / 2, sz * d / 2
        cs.append(m2p(cx + lx * ca + lz * sa, cz - lx * sa + lz * ca))
    dr.polygon(cs, fill=(150, 140, 135) if b[6] != 7 else (176, 150, 112))
colors = dict(avenue=(255, 236, 150), boulevard=(255, 246, 200), highway=(255, 205, 120), street=(250, 250, 250),
              mountain=(240, 220, 190), rural=(235, 225, 205), dirt=(190, 160, 120))
widths = dict(avenue=6, boulevard=4, highway=4, street=2, mountain=3, rural=2, dirt=2)
for r in sorted(roads_out, key=lambda r: -r["tier"]):
    p = [m2p(q_[0], q_[2]) for q_ in r["pts"]]
    dr.line(p, fill=(60, 60, 60), width=widths[r["type"]] + 2)
for r in sorted(roads_out, key=lambda r: -r["tier"]):
    p = [m2p(q_[0], q_[2]) for q_ in r["pts"]]
    dr.line(p, fill=colors[r["type"]], width=widths[r["type"]])
    for a, b in r["tunnels"]:
        dr.line(p[a:b + 1], fill=(90, 70, 70), width=widths[r["type"]])
img.save(os.path.join(DATA, "minimap.pngdat"), format="PNG", optimize=True)

# annotated overview map
ov = img.resize((1600, 1600), Image.LANCZOS)
d2 = ImageDraw.Draw(ov)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 15)
    fsmall = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12)
    fbig = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 26)
except Exception:
    font = fsmall = fbig = ImageFont.load_default()


def o2p(x, z):
    return ((x - ORIGIN) / SIZE * 1600, (z - ORIGIN) / SIZE * 1600)


for lm in L.LANDMARKS:
    if lm["id"] == "dusti_square":
        continue
    px, pz = o2p(lm["x"], lm["z"])
    d2.ellipse([px - 4, pz - 4, px + 4, pz + 4], fill=(200, 30, 30), outline=(255, 255, 255))
    d2.text((px + 6, pz - 7), lm["name"], fill=(20, 20, 20), font=fsmall, stroke_width=2, stroke_fill=(255, 255, 255))
for v in village_out:
    px, pz = o2p(v["x"], v["z"])
    d2.text((px - 30, pz - 8), v["name"], fill=(60, 30, 0), font=font, stroke_width=2, stroke_fill=(255, 240, 210))
for name, poly in L.REGIONS:
    xs_ = [p[0] for p in poly]
    zs_ = [p[1] for p in poly]
    px, pz = o2p(sum(xs_) / len(xs_), sum(zs_) / len(zs_))
    d2.text((px - 80, pz), name.upper(), fill=(255, 255, 255), font=fbig, stroke_width=3, stroke_fill=(0, 0, 0))
d2.text((o2p(500, 300)[0] - 60, o2p(500, 300)[1]), "ДУШАНБЕ", fill=(255, 255, 255), font=fbig, stroke_width=3,
        stroke_fill=(120, 0, 0))
# scale bar
d2.line([(40, 1560), (40 + 160, 1560)], fill=(0, 0, 0), width=5)
d2.text((40, 1535), "1 км", fill=(0, 0, 0), font=font, stroke_width=2, stroke_fill=(255, 255, 255))
d2.text((1540, 20), "С ↑", fill=(0, 0, 0), font=fbig, stroke_width=2, stroke_fill=(255, 255, 255))
ov.save(os.path.join(DOCS, "world_map.png"))

# stats
total_len = {}
for r in roads_out:
    p = np.array(r["pts"])
    total_len[r["type"]] = total_len.get(r["type"], 0) + float(arclen(p[:, [0, 2]])[-1])
stats = dict(
    height_min=float(H.min()), height_max=float(H.max()),
    roads=len(roads_out), road_km={k: round(v / 1000, 1) for k, v in total_len.items()},
    bridges=sum(len(r["bridges"]) for r in roads_out), tunnels=sum(len(r["tunnels"]) for r in roads_out),
    intersections=len(intersections), buildings=len(buildings), villages=len(village_out),
    lakes=len(lakes_out), rivers=len(river_out), waterfalls=len(waterfalls), pois=len(pois_out),
    hole_cells=int(holes.sum()),
)
with open(os.path.join(DATA, "world_stats.json"), "w", encoding="utf-8") as f:
    json.dump(stats, f, ensure_ascii=False, indent=1)
log("done: " + json.dumps(stats, ensure_ascii=False))
