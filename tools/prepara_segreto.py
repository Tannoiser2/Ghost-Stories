#!/usr/bin/env python3
"""Grafica dell'espansione Black Secret dal modulo TTS (stessa cartella Images di prepara_grafica.py).

Uso: python3 tools/prepara_segreto.py <cartella Mods/Images>
"""
import json, os, sys, importlib.util
from PIL import Image, ImageDraw, ImageFont, ImageFilter

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
sys.argv = [sys.argv[0], sys.argv[1]]
IMG = sys.argv[1]

def apri(nome):
    for est in ('jpg', 'png'):
        p = f'{IMG}/httpiimgurcom{nome}{est}.{est}'
        if os.path.exists(p):
            return Image.open(p)
    raise FileNotFoundError(nome)

def salva(im, percorso, q=88):
    p = R + '/' + percorso
    os.makedirs(os.path.dirname(p), exist_ok=True)
    im.save(p, 'WEBP', quality=q, method=6)

# la funzione che traduce i nomi sulle carte è quella del gioco base
src = open(R + '/tools/prepara_grafica.py', encoding='utf-8').read()
src = src[:src.index("dati = json.load")]
ns = {'__file__': R + '/tools/prepara_grafica.py'}
exec(src, ns)
traduci = ns['traduci']

dati = json.load(open(R + '/assets/dati/fantasmi.json', encoding='utf-8'))
# fogli 10 x 7 da 3654 x 4096: si riportano le carte a 350 x 544 come quelle del gioco base
def carta(foglio, i):
    w, h = foglio.size[0] / 10, foglio.size[1] / 7
    r, c = divmod(i, 10)
    return foglio.crop((round(c * w), round(r * h), round((c + 1) * w), round((r + 1) * h))).convert('RGB').resize((350, 544), Image.LANCZOS)

f1 = apri('GOrNxOL')
for g in dati['fantasmi']:
    if g.get('espansione') == 'segreto' and 'foglio' in g:
        salva(traduci(carta(f1, g['foglio']), g['nome'], g['colore'] == 'giallo'), f"assets/carte/fantasma_{g['n']:02d}.webp")
f2 = apri('vu6Nx3m')
for g in dati['incarnazioni']:
    if g.get('espansione') == 'segreto':
        salva(traduci(carta(f2, g['foglio']), g['nome'], g['colore'] == 'giallo'), f"assets/carte/fantasma_{g['n']:02d}.webp")

FT = R + '/assets/font/KaushanScript-Regular.ttf'
FB = R + '/assets/font/AlegreyaSans-Bold.ttf'
def centrato(d, y, testo, font, col, w=350):
    bb = d.textbbox((0, 0), testo, font=font)
    d.text(((w - (bb[2] - bb[0])) / 2, y), testo, font=font, fill=col)

# scheletro come "carta" (in realtà è un segnalino sullo spazio)
sch = apri('u2raJoJ').convert('RGBA')
c = Image.new('RGB', (350, 544), (22, 16, 14))
d = ImageDraw.Draw(c)
d.rectangle((6, 6, 343, 537), outline=(120, 96, 70), width=4)
s2 = sch.copy(); s2.thumbnail((300, 300))
c.paste(s2, ((350 - s2.width) // 2, 110), s2)
centrato(d, 30, 'Scheletro', ImageFont.truetype(FT, 40), (236, 224, 200))
centrato(d, 440, 'Resistenza 1 del colore', ImageFont.truetype(FB, 24), (220, 210, 190))
centrato(d, 470, 'della plancia', ImageFont.truetype(FB, 24), (220, 210, 190))
salva(c, 'assets/carte/fantasma_200.webp')
salva(sch, 'assets/bs/scheletro.webp', 92)

# carta Evocazione (sostituisce le incarnazioni nel mazzo): disegnata qui sul dorso delle incarnazioni
dorso = Image.open(R + '/assets/carte/dorso_incarnazione.webp').convert('RGB').resize((350, 544))
ev = dorso.filter(ImageFilter.GaussianBlur(2))
ov = Image.new('RGBA', ev.size, (60, 0, 0, 120))
ev = Image.alpha_composite(ev.convert('RGBA'), ov).convert('RGB')
d = ImageDraw.Draw(ev)
d.rectangle((8, 8, 341, 535), outline=(200, 60, 40), width=5)
centrato(d, 200, 'Evocazione', ImageFont.truetype(FT, 50), (255, 220, 180))
centrato(d, 270, 'Wu-Feng prende', ImageFont.truetype(FB, 26), (245, 235, 220))
centrato(d, 302, "un'incarnazione e ne", ImageFont.truetype(FB, 26), (245, 235, 220))
centrato(d, 334, 'mette una in gioco', ImageFont.truetype(FB, 26), (245, 235, 220))
salva(ev, 'assets/carte/fantasma_300.webp')

# plance
cat = apri('qVD10Rs').convert('RGB'); cat.thumbnail((1200, 1200))
salva(cat, 'assets/bs/catacombe.webp', 85)
wf = apri('jhTR1Mr').convert('RGB'); wf.thumbnail((1200, 1200))
salva(wf, 'assets/bs/wufeng.webp', 85)
salva(apri('BcCfMHR').convert('RGB'), 'assets/villaggio/calligrafo.webp')
salva(apri('k2R8kx2').convert('RGB'), 'assets/villaggio/calligrafo_infestata.webp')

# segnalini delle catacombe
CAT = {'buddha': '5F2w0Fw', 'sangue_suling': 'MJbWnw1', 'tavoletta': 'uKGJa3A', 'ossa': 'ySyiZFn',
       'sangue_giusto': 'bADCA8s', 'urna': 'aCk1VJS', 'terra': 'SrArQ8r',
       'dorso_1': 'AY67AGg', 'dorso_2': '4mtDTSs', 'dorso_3': 's9nv2cp', 'dorso_4': 'juIeKG9'}
for k, v in CAT.items():
    im = apri(v).convert('RGB'); im.thumbnail((200, 200))
    salva(im, f'assets/bs/cat_{k}.webp', 88)

# maledizioni: si ritaglia la parte colorata (il segnalino è stampato su fondo bianco)
import numpy as np
for m in dati['maledizioni']:
    im = apri(m['id']).convert('RGBA')
    a = np.array(im)
    bianco = (a[:, :, 0] > 235) & (a[:, :, 1] > 235) & (a[:, :, 2] > 235)
    nero = (a[:, :, 0] < 12) & (a[:, :, 1] < 12) & (a[:, :, 2] < 12)
    a[bianco | nero, 3] = 0
    im = Image.fromarray(a)
    # la faccia è nella metà alta a sinistra
    w, h = im.size
    fac = im.crop((0, int(h * 0.12), int(w * 0.55), int(h * 0.72)))
    bb = fac.getbbox()
    if bb:
        fac = fac.crop(bb)
    fac.thumbnail((160, 160))
    salva(fac, f"assets/bs/maledizione_{m['id']}.webp", 90)
    if m['id'] in ('LBnrdXv', 'aWas5tb', 'exHyZsS', 'pX2lKCP'):
        dor = im.crop((int(w * 0.45), int(h * 0.45), w, h))
        bb = dor.getbbox()
        if bb:
            dor = dor.crop(bb)
        dor.thumbnail((160, 160))
        salva(dor, f"assets/bs/maledizione_dorso_{m['rango']}.webp", 90)

FR = {'blu': 'mCE3VGN', 'rosso': 'Jjpjzkt', 'giallo': 'v0s2ykw', 'verde': 'RDQmIE6'}
for k, v in FR.items():
    im = apri(v).convert('RGBA'); im.thumbnail((160, 160))
    salva(im, f'assets/bs/fratello_{k}.webp', 90)
print('fatto')

# ritratti dei demoni e dell'Ombra presi dalla plancia di Wu-Feng (coordinate sulla plancia a 1374 px)
wf = apri('jhTR1Mr').convert('RGB')
k = wf.size[0] / 1374
RIT = {'cercatore': (138, 1250, 115), 'scavatore': (410, 1110, 120), 'becchino': (770, 1080, 150), 'ombra': (1150, 930, 150)}
for nome, (cx, cy, r) in RIT.items():
    sq = wf.crop((int((cx - r) * k), int((cy - r) * k), int((cx + r) * k), int((cy + r) * k))).resize((200, 200), Image.LANCZOS).convert('RGBA')
    m = Image.new('L', (200, 200), 0)
    ImageDraw.Draw(m).ellipse((2, 2, 197, 197), fill=255)
    sq.putalpha(m)
    salva(sq, f'assets/bs/ritratto_{nome}.webp', 90)
print('ritratti')
