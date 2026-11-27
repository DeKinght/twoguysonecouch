"""Rzeźbi postacie tragarzy jako gładkie bryły (SDF + marching cubes) ze skinningiem.

Każda postać to suma miękko połączonych kształtów (elipsoidy, stożki, torusy). Kolor
wierzchołka bierze się z najbliższego kształtu, a wagi kości - z kształtów w pobliżu
(tylko kość dominująca i jej sąsiedzi w hierarchii, więc dłoń nie "przykleja się" do biodra).

Wynik: JSON z siatką (pozycje, normalne, kolory, kości, wagi, trójkąty), który
build_meshes.gd zamienia w zasoby ArrayMesh dla Godota.

Użycie (wymaga numpy, scikit-image i pyfqmr):
    python sculpt.py <katalog_wyjściowy>
"""
import json
import os
import sys

import numpy as np
import pyfqmr
from skimage.measure import marching_cubes

# Kolejność i pozycje spoczynkowe (globalne) MUSZĄ być takie jak w character_model.gd.
BONES = [
    ("Root", None, (0, 0, 0)),
    ("Hips", "Root", (0, 0.72, 0)),
    ("Spine", "Hips", (0, 0.92, 0)),
    ("Chest", "Spine", (0, 1.14, 0)),
    ("Neck", "Chest", (0, 1.36, 0)),
    ("Head", "Neck", (0, 1.44, 0)),
    ("UpperArm.L", "Chest", (-0.31, 1.29, 0)),
    ("LowerArm.L", "UpperArm.L", (-0.36, 1.03, 0)),
    ("Hand.L", "LowerArm.L", (-0.39, 0.81, 0)),
    ("UpperArm.R", "Chest", (0.31, 1.29, 0)),
    ("LowerArm.R", "UpperArm.R", (0.36, 1.03, 0)),
    ("Hand.R", "LowerArm.R", (0.39, 0.81, 0)),
    ("UpperLeg.L", "Hips", (-0.14, 0.68, 0)),
    ("LowerLeg.L", "UpperLeg.L", (-0.14, 0.38, 0)),
    ("Foot.L", "LowerLeg.L", (-0.14, 0.11, 0)),
    ("UpperLeg.R", "Hips", (0.14, 0.68, 0)),
    ("LowerLeg.R", "UpperLeg.R", (0.14, 0.38, 0)),
    ("Foot.R", "LowerLeg.R", (0.14, 0.11, 0)),
]
BONE_INDEX = {b[0]: i for i, b in enumerate(BONES)}
BONE_POS = {b[0]: np.array(b[2], float) for b in BONES}
NEIGHBOURS = {}
for name, parent, _ in BONES:
    NEIGHBOURS.setdefault(name, {name})
    if parent:
        NEIGHBOURS[name].add(parent)
        NEIGHBOURS.setdefault(parent, {parent}).add(name)

RES = 0.0125           # bok woksela [m] - równomierne, małe trójkąty dają czyste krawędzie kolorów
TARGET_TRIS = 0        # >0: dodatkowe uproszczenie siatki (rozmywa granice kolorów na dużych trójkątach)
BOUNDS = (np.array([-0.56, -0.01, -0.36]), np.array([0.56, 1.92, 0.4]))


# --- Kształty (SDF, ujemne w środku) -------------------------------------------------

def ellipsoid(c, r):
    c = np.array(c, float); r = np.array(r, float)
    def f(p):
        q = (p - c) / r
        k0 = np.linalg.norm(q, axis=-1)
        k1 = np.linalg.norm(q / r, axis=-1)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
    return f


def cone(a, b, ra, rb):
    """Stożek o zaokrąglonych końcach (kapsuła z promieniem zmiennym od ra do rb)."""
    a = np.array(a, float); b = np.array(b, float)
    ba = b - a; L2 = ba.dot(ba)
    def f(p):
        pa = p - a
        h = np.clip((pa @ ba) / L2, 0.0, 1.0)
        return np.linalg.norm(pa - h[..., None] * ba, axis=-1) - (ra + (rb - ra) * h)
    return f, (a, b)


def torus(c, R, r, axis="y"):
    c = np.array(c, float)
    def f(p):
        q = p - c
        if axis == "y":
            u, v = np.hypot(q[..., 0], q[..., 2]), q[..., 1]
        else:  # oś z (obwódka okularów)
            u, v = np.hypot(q[..., 0], q[..., 1]), q[..., 2]
        return np.hypot(u - R, v) - r
    return f


def cut(f, plane_fn):
    """Część kształtu f po stronie, gdzie plane_fn(p) <= 0."""
    return lambda p: np.maximum(f(p), plane_fn(p))


def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


class Part:
    def __init__(self, sdf, bone, mat, k=0.04):
        self.sdf, self.bone, self.mat, self.k = sdf, bone, mat, k


def colour_of(mat, p, palette):
    """mat: nazwa koloru albo funkcja p -> tablica nazw."""
    if callable(mat):
        names = mat(p)
        return np.array([palette[n] for n in names], float)
    return np.tile(np.array(palette[mat], float), (len(p), 1))


# --- Wspólne ciało -----------------------------------------------------------------------

def body(parts, v):
    """Krępa sylwetka: duży tułów-gruszka, krótkie nogi, duże dłonie i stopy."""
    g, belly = v["girth"], v["belly"]
    torso_mat = v["torso_mat"]
    parts += [
        Part(ellipsoid((0, 0.75, 0.01), (0.25 * g, 0.17, 0.2)), "Hips", "pants", 0.07),
        Part(ellipsoid((0, 0.96, 0.0), (0.29 * g, 0.27, 0.23)), "Spine", torso_mat, 0.08),
        Part(ellipsoid((0, 0.95, -0.07), (0.24 * g * belly, 0.22, 0.19 * belly)), "Spine", torso_mat, 0.08),
        Part(ellipsoid((0, 1.17, 0.0), (0.31 * g, 0.19, 0.21)), "Chest", torso_mat, 0.08),
        Part(cone((0, 1.27, 0.0), (0, 1.47, -0.01), 0.085, 0.08)[0], "Neck", "skin", 0.05),
    ]
    for side, sx in (("L", -1), ("R", 1)):
        sh = BONE_POS["UpperArm." + side]; el = BONE_POS["LowerArm." + side]; wr = BONE_POS["Hand." + side]
        parts += [
            Part(ellipsoid(sh + np.array([0.0, -0.01, 0]), (0.1, 0.1, 0.1)), "UpperArm." + side, v["sleeve_mat"], 0.06),
            Part(cone(sh, el, 0.085, 0.072)[0], "UpperArm." + side, v["sleeve_mat"], 0.03),
            Part(cone(el, wr, 0.07, 0.06)[0], "LowerArm." + side, v["forearm_mat"], 0.03),
            # dłoń-łapka z kciukiem
            Part(ellipsoid(wr + np.array([0.01 * sx, -0.075, 0.0]), (0.062, 0.088, 0.085)), "Hand." + side, v["hand_mat"], 0.025),
            Part(ellipsoid(wr + np.array([-0.025 * sx, -0.04, -0.065]), (0.03, 0.045, 0.032)), "Hand." + side, v["hand_mat"], 0.015),
        ]
        hip = BONE_POS["UpperLeg." + side]; knee = BONE_POS["LowerLeg." + side]; ank = BONE_POS["Foot." + side]
        parts += [
            Part(cone(hip, knee, 0.12, 0.095)[0], "UpperLeg." + side, "pants", 0.05),
            Part(cone(knee, ank + np.array([0, 0.02, 0]), 0.095, 0.08)[0], "LowerLeg." + side, v["shin_mat"], 0.03),
            # but: przód zaokrąglony, podeszwa płaska
            Part(cut(ellipsoid(ank + np.array([0, -0.03, -0.05]), (0.088, 0.085, 0.16)), lambda p: -p[..., 1]),
                 "Foot." + side, lambda p: np.where(p[..., 1] < 0.028, "sole", "shoes"), 0.03),
        ]


def face(parts, v):
    hc = np.array([0, 1.6, 0.0])
    parts += [
        Part(ellipsoid(hc, (0.185, 0.205, 0.19)), "Head", "skin", 0.05),
        Part(ellipsoid(hc + (0, -0.08, -0.04), (0.165, 0.12, 0.16)), "Head", "skin", 0.06),     # policzki/żuchwa
        Part(ellipsoid(hc + (0, -0.02, -0.2), (0.045, 0.05, 0.048)), "Head", "skin", 0.025),    # nos
    ]
    for sx in (-1, 1):
        parts += [
            Part(ellipsoid(hc + (0.185 * sx, -0.005, 0.01), (0.032, 0.058, 0.045)), "Head", "skin", 0.02),     # uszy
            Part(ellipsoid(hc + (0.07 * sx, 0.04, -0.163), (0.038, 0.05, 0.028)), "Head", "eye", 0.004),     # białka
            Part(ellipsoid(hc + (0.07 * sx, 0.036, -0.188), (0.022, 0.026, 0.012)), "Head", "pupil", 0.0),     # źrenice
            Part(cone(hc + (0.035 * sx, 0.11, -0.168), hc + (0.11 * sx, 0.1, -0.15), 0.013, 0.011)[0],
                 "Head", "brow", 0.004),                                                                         # brwi
        ]
    # uśmiech: dwa krótkie łuki
    parts += [
        Part(cone(hc + (-0.05, -0.085, -0.175), hc + (0.0, -0.1, -0.182), 0.009, 0.009)[0], "Head", "mouth", 0.003),
        Part(cone(hc + (0.0, -0.1, -0.182), hc + (0.05, -0.085, -0.175), 0.009, 0.009)[0], "Head", "mouth", 0.003),
    ]
    return hc


# --- Postacie ---------------------------------------------------------------------------

def bartek():
    """Krępy kierowca: polówka, robocze spodnie, czapka zimowa, gęsta broda."""
    pal = {"skin": (0.86, 0.64, 0.5), "shirt": (0.93, 0.47, 0.13), "collar": (0.96, 0.93, 0.86),
           "pants": (0.2, 0.25, 0.38), "shoes": (0.42, 0.26, 0.14), "sole": (0.18, 0.14, 0.1),
           "hair": (0.33, 0.2, 0.12), "brow": (0.3, 0.18, 0.1), "hat": (0.78, 0.16, 0.14), "hat2": (0.94, 0.9, 0.84),
           "eye": (0.97, 0.97, 0.97), "pupil": (0.08, 0.07, 0.07), "mouth": (0.45, 0.16, 0.14), "pocket": (0.85, 0.4, 0.1)}
    torso = lambda p: np.where(p[..., 1] < 0.8, "pants", "shirt")
    v = dict(girth=1.12, belly=1.25, torso_mat=torso, sleeve_mat="shirt", forearm_mat="skin", hand_mat="skin", shin_mat="pants")
    parts = []
    body(parts, v)
    hc = face(parts, v)
    parts += [
        Part(torus((0, 1.335, 0.0), 0.095, 0.028), "Neck", "collar", 0.01),
        # broda i wąsy (zachodzą na żuchwę, zostawiają usta)
        Part(cut(ellipsoid(hc + (0, -0.11, -0.05), (0.18, 0.14, 0.16)), lambda p: p[..., 1] - (hc[1] - 0.075)), "Head", "hair", 0.02),
        Part(ellipsoid(hc + (0, -0.06, -0.185), (0.07, 0.022, 0.025)), "Head", "hair", 0.01),
        # czapka zimowa z wywinięciem i pomponem
        Part(cut(ellipsoid(hc + (0, 0.08, 0.015), (0.198, 0.2, 0.205)), lambda p: (hc[1] + 0.125) - p[..., 1]), "Head", "hat", 0.01),
        Part(torus(hc + (0, 0.14, 0.015), 0.178, 0.028), "Head", "hat2", 0.01),
        Part(ellipsoid(hc + (0, 0.29, 0.02), (0.055, 0.055, 0.055)), "Head", "hat2", 0.02),
    ]
    return "bartek", parts, pal


def ola():
    """Tragarka w odblaskowej kurtce, z kucykiem."""
    pal = {"skin": (0.93, 0.73, 0.6), "shirt": (0.78, 0.94, 0.16), "stripe": (0.82, 0.84, 0.86),
           "pants": (0.24, 0.25, 0.29), "shoes": (0.95, 0.95, 0.96), "sole": (0.25, 0.55, 0.85),
           "hair": (0.55, 0.24, 0.12), "brow": (0.45, 0.2, 0.1), "glove": (0.25, 0.27, 0.3), "tie": (0.25, 0.55, 0.85),
           "eye": (0.97, 0.97, 0.97), "pupil": (0.12, 0.25, 0.22), "mouth": (0.7, 0.25, 0.28), "zip": (0.3, 0.32, 0.3)}
    def torso(p):
        y = p[..., 1]
        band = ((y > 0.9) & (y < 0.945)) | ((y > 1.1) & (y < 1.145))
        out = np.where(band, "stripe", "shirt")
        out = np.where((np.abs(p[..., 0]) < 0.012) & (p[..., 2] < -0.1) & (y > 0.8), "zip", out)
        return np.where(y < 0.79, "pants", out)
    def sleeve(p):  # odblaskowe paski na rękawach
        y = p[..., 1]
        return np.where((y > 1.1) & (y < 1.14), "stripe", "shirt")
    v = dict(girth=0.98, belly=0.95, torso_mat=torso, sleeve_mat=sleeve, forearm_mat=sleeve, hand_mat="glove", shin_mat="pants")
    parts = []
    body(parts, v)
    hc = face(parts, v)
    parts += [
        Part(torus((0, 1.34, 0.0), 0.09, 0.03), "Neck", "shirt", 0.01),   # kołnierz kurtki
        # włosy: czubek i tył głowy, grzywka zaczesana na bok
        Part(cut(ellipsoid(hc + (0, 0.05, 0.03), (0.2, 0.19, 0.2)),
                 lambda p: np.minimum(-(p[..., 2] - (hc[2] - 0.02)), (hc[1] + 0.13) - p[..., 1])), "Head", "hair", 0.015),
        Part(ellipsoid(hc + (0.05, 0.14, -0.13), (0.13, 0.05, 0.07)), "Head", "hair", 0.03),
        Part(ellipsoid(hc + (0, 0.07, 0.2), (0.045, 0.045, 0.045)), "Head", "tie", 0.01),
        Part(cone(hc + (0, 0.06, 0.23), hc + (0, -0.16, 0.25), 0.055, 0.035)[0], "Head", "hair", 0.03),   # kucyk
    ]
    return "ola", parts, pal


def dawid():
    """Wysoki, szczupły: ogrodniczki na białej koszulce, kręcone włosy, okulary, żółte rękawice."""
    pal = {"skin": (0.46, 0.3, 0.22), "shirt": (0.95, 0.95, 0.93), "denim": (0.24, 0.38, 0.6), "button": (0.9, 0.75, 0.3),
           "pants": (0.24, 0.38, 0.6), "shoes": (0.4, 0.27, 0.16), "sole": (0.15, 0.12, 0.1),
           "hair": (0.1, 0.08, 0.07), "brow": (0.08, 0.06, 0.05), "glove": (0.98, 0.78, 0.18), "frame": (0.12, 0.12, 0.14),
           "eye": (0.97, 0.97, 0.97), "pupil": (0.08, 0.06, 0.05), "mouth": (0.3, 0.12, 0.1)}
    def torso(p):
        x, y, z = p[..., 0], p[..., 1], p[..., 2]
        bib = (np.abs(x) < 0.17) & (z < -0.02) & (y < 1.2)
        straps = (np.abs(np.abs(x) - 0.13) < 0.03) & (y >= 1.0)
        out = np.where(bib | straps | (y < 1.0), "denim", "shirt")
        buttons = (np.abs(np.abs(x) - 0.13) < 0.018) & (np.abs(y - 1.17) < 0.018) & (z < -0.1)
        return np.where(buttons, "button", out)
    sleeve = lambda p: np.where(p[..., 1] > 1.17, "shirt", "skin")
    v = dict(girth=0.94, belly=0.85, torso_mat=torso, sleeve_mat=sleeve, forearm_mat="skin", hand_mat="glove", shin_mat="pants")
    parts = []
    body(parts, v)
    hc = face(parts, v)
    # kręcone włosy: kępki na czubku i z tyłu
    rng = np.random.default_rng(3)
    for i in range(26):
        th = rng.uniform(0, 2 * np.pi); ph = rng.uniform(0.0, 1.15)
        d = np.array([np.sin(ph) * np.cos(th), np.cos(ph), np.sin(ph) * np.sin(th)])
        if d[2] < -0.45 and d[1] < 0.6:
            continue  # nie na twarz
        c = hc + (0, 0.035, 0.01) + d * np.array([0.17, 0.17, 0.175])
        parts.append(Part(ellipsoid(c, (0.06, 0.055, 0.06)), "Head", "hair", 0.02))
    for sx in (-1, 1):   # okulary
        parts.append(Part(torus(hc + (0.072 * sx, 0.037, -0.196), 0.055, 0.009, "z"), "Head", "frame", 0.002))
        parts.append(Part(cone(hc + (0.127 * sx, 0.04, -0.19), hc + (0.18 * sx, 0.04, -0.06), 0.008, 0.008)[0], "Head", "frame", 0.002))
    parts.append(Part(cone(hc + (-0.018, 0.04, -0.205), hc + (0.018, 0.04, -0.205), 0.008, 0.008)[0], "Head", "frame", 0.002))
    return "dawid", parts, pal


# --- Siatka ------------------------------------------------------------------------------

def field(parts, p):
    d = parts[0].sdf(p)
    for part in parts[1:]:
        d = smin(part.sdf(p), d, part.k)
    return d


def _simplify(parts, verts, faces):
    """Uproszczenie siatki (pyfqmr) i dociągnięcie wierzchołków z powrotem na powierzchnię."""
    simp = pyfqmr.Simplify()
    simp.setMesh(verts, faces.astype(np.int32))
    simp.simplify_mesh(target_count=TARGET_TRIS, aggressiveness=5, preserve_border=True, verbose=False)
    verts, faces, _ = simp.getMesh()
    verts = np.asarray(verts, float); faces = np.asarray(faces, np.int64)
    for _ in range(2):  # krok Newtona po polu odległości
        e = RES * 0.5
        g = np.stack([field(parts, verts + d) - field(parts, verts - d) for d in np.eye(3) * e], -1) / (2 * e)
        verts = verts - field(parts, verts)[:, None] * g / np.maximum((g * g).sum(-1, keepdims=True), 1e-9)
    return verts, faces


def build(name, parts, pal):
    lo, hi = BOUNDS
    xs = np.arange(lo[0], hi[0], RES); ys = np.arange(lo[1], hi[1], RES); zs = np.arange(lo[2], hi[2], RES)
    P = np.stack(np.meshgrid(xs, ys, zs, indexing="ij"), -1).reshape(-1, 3)
    vol = np.empty(len(P))
    for i in range(0, len(P), 400000):
        vol[i:i + 400000] = field(parts, P[i:i + 400000])
    vol = vol.reshape(len(xs), len(ys), len(zs))
    verts, faces, _, _ = marching_cubes(vol, 0.0, spacing=(RES, RES, RES))
    verts = verts + lo

    # Uproszczenie siatki: płaskie miejsca dostają duże trójkąty, detale (twarz, dłonie) zostają.
    if TARGET_TRIS > 0:
        verts, faces = _simplify(parts, verts, faces)

    # Normalne z gradientu pola (gładkie).
    e = RES * 0.5
    grad = np.stack([field(parts, verts + d) - field(parts, verts - d) for d in np.eye(3) * e], -1)
    normals = grad / np.maximum(np.linalg.norm(grad, axis=-1, keepdims=True), 1e-9)

    # Godot: przód trójkąta = zgodnie ze wskazówkami zegara (normalna z iloczynu do środka).
    a, b, c = verts[faces[:, 0]], verts[faces[:, 1]], verts[faces[:, 2]]
    fn = np.cross(b - a, c - a)
    outward = normals[faces].mean(1)
    flip = (fn * outward).sum(-1) > 0
    faces[flip] = faces[flip][:, [0, 2, 1]]

    # Kolor i wagi z odległości do każdego kształtu.
    D = np.stack([part.sdf(verts) for part in parts], -1)
    dom = D.argmin(-1)
    colours = np.zeros((len(verts), 3))
    for i, part in enumerate(parts):
        sel = dom == i
        if sel.any():
            colours[sel] = colour_of(part.mat, verts[sel], pal)
    infl = np.exp(-np.maximum(D, 0.0) / 0.025)
    bone_w = np.zeros((len(verts), len(BONES)))
    for i, part in enumerate(parts):
        bone_w[:, BONE_INDEX[part.bone]] += infl[:, i]
    dom_bone = np.array([BONE_INDEX[parts[i].bone] for i in dom])
    allowed = np.zeros((len(BONES), len(BONES)), bool)
    for bn, nb in NEIGHBOURS.items():
        for o in nb:
            allowed[BONE_INDEX[bn], BONE_INDEX[o]] = True
    bone_w *= allowed[dom_bone]
    top = np.argsort(-bone_w, axis=1)[:, :4]
    w = np.take_along_axis(bone_w, top, 1)
    w = w / np.maximum(w.sum(1, keepdims=True), 1e-9)
    w[w < 0.02] = 0.0
    w = w / w.sum(1, keepdims=True)

    print(f"{name}: {len(verts)} wierzchołków, {len(faces)} trójkątów")
    return {
        "name": name,
        "vertices": np.round(verts, 5).flatten().tolist(),
        "normals": np.round(normals, 4).flatten().tolist(),
        "colors": np.round(colours, 4).flatten().tolist(),
        "bones": top.flatten().tolist(),
        "weights": np.round(w, 4).flatten().tolist(),
        "indices": faces.flatten().tolist(),
    }


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for maker in (bartek, ola, dawid):
        name, parts, pal = maker()
        data = build(name, parts, pal)
        with open(os.path.join(out, name + ".json"), "w") as fh:
            json.dump(data, fh)
