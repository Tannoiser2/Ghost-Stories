#!/usr/bin/env python3
"""Prepara le miniature 3D prese dal modulo TTS: le centra, le porta ad altezza 1 (base a terra)
e alleggerisce quelle troppo dense (perché girino anche sull'iPad).

Uso: python3 tools/prepara_modelli.py <cartella Mods/Models del modulo TTS scompattato>
"""
import os, sys
import numpy as np
import trimesh, pyfqmr

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
M = sys.argv[1]
FILE = {
    'taoista': ('httpspasteeerUnnbB.obj', None),
    'fantasma': ('05a5b824e4ad7', 5000),
    'buddha': ('122426aefe11b', 6000),
    'ombra_wufeng': ('httpspasteeerycViU.obj', None),
    'cristallo': ('014fc6a8aab4d', None),
    'portale': ('afc87b906f325', None),
    'demone_cercatore': ('78f666cb36ee3', None),
    'demone_scavatore': ('31acb7f1e524c', None),
    'demone_becchino': ('76e847f93701d', 7000),
    'ricettacolo': ('httppastebincomrawsSbngjcm.obj', None),
}

def trova(chiave):
    for f in os.listdir(M):
        if f == chiave or chiave in f:
            return os.path.join(M, f)
    raise FileNotFoundError(chiave)

for nome, (chiave, facce) in FILE.items():
    m = trimesh.load(trova(chiave), force='mesh', process=False)
    uv = None
    if hasattr(m.visual, 'uv') and m.visual.uv is not None and len(m.visual.uv) == len(m.vertices):
        uv = np.array(m.visual.uv)
    v = np.array(m.vertices, dtype=np.float64)
    f = np.array(m.faces)
    if uv is None:
        mm = trimesh.Trimesh(vertices=v, faces=f, process=True)
        mm.merge_vertices()
        v = np.array(mm.vertices, dtype=np.float64)
        f = np.array(mm.faces)
    if facce and len(f) > facce and uv is None:
        s = pyfqmr.Simplify()
        s.setMesh(v, f)
        s.simplify_mesh(target_count=facce, aggressiveness=7, preserve_border=False, verbose=False)
        v, f, _ = s.getMesh()
    lo = v.min(axis=0)
    hi = v.max(axis=0)
    h = hi[1] - lo[1]
    c = (lo + hi) / 2
    v = (v - np.array([c[0], lo[1], c[2]])) / h
    mesh = trimesh.Trimesh(vertices=v, faces=f, process=False)
    n = mesh.vertex_normals
    righe = ['# %s - miniatura dal modulo TTS di Ghost Stories, altezza 1' % nome]
    for p in v:
        righe.append('v %.5f %.5f %.5f' % tuple(p))
    for p in n:
        righe.append('vn %.4f %.4f %.4f' % tuple(p))
    if uv is not None:
        for t in uv:
            righe.append('vt %.5f %.5f' % (t[0], t[1]))
        for a in f:
            righe.append('f ' + ' '.join('%d/%d/%d' % (i + 1, i + 1, i + 1) for i in a))
    else:
        for a in f:
            righe.append('f ' + ' '.join('%d//%d' % (i + 1, i + 1) for i in a))
    open(os.path.join(R, 'assets/modelli', nome + '.obj'), 'w').write('\n'.join(righe) + '\n')
    print(nome, len(v), 'vertici', len(f), 'facce', 'uv' if uv is not None else '')
