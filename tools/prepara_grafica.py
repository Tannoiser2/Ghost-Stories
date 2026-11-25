#!/usr/bin/env python3
"""Estrae dal modulo Tabletop Simulator la grafica originale usata dal gioco e traduce i nomi sulle carte.

Uso: python3 tools/prepara_grafica.py <cartella Mods/Images del modulo TTS scompattato>
Scrive in assets/ (carte, villaggio, plance, segnalini) e ludoteca/copertina.webp.
Serve solo per rifare la grafica: i file prodotti sono già nel repository.
"""
import json, os, sys
import cv2, numpy as np
from PIL import Image, ImageDraw, ImageFont

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
IMG = sys.argv[1]
FONT = R + '/assets/font/KaushanScript-Regular.ttf'

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

# ------------------------------------------------------------------ nomi italiani sulle carte
def traduci(card, nome, testo_scuro):
    a = np.array(card.convert('RGB'))
    hsv = cv2.cvtColor(a, cv2.COLOR_RGB2HSV)
    y0, y1, x0, x1 = 6, 42, 66, 346
    reg = a[y0:y1, x0:x1].astype(int)
    lum = reg.mean(axis=2)
    sat = hsv[y0:y1, x0:x1, 1].astype(int)
    m = (lum < 120) if testo_scuro else ((lum > 170) & (sat < 90))
    mask = np.zeros(a.shape[:2], np.uint8)
    mask[y0:y1, x0:x1] = m.astype(np.uint8) * 255
    mask = cv2.dilate(mask, np.ones((3, 3), np.uint8), iterations=2)
    out = cv2.inpaint(a, mask, 5, cv2.INPAINT_TELEA)
    im = Image.fromarray(out)
    d = ImageDraw.Draw(im)
    size = 26
    while True:
        f = ImageFont.truetype(FONT, size)
        bb = d.textbbox((0, 0), nome, font=f)
        if bb[2] - bb[0] <= 250 or size <= 14:
            break
        size -= 1
    x = 338 - (bb[2] - bb[0]) - bb[0]
    y = 24 - (bb[1] + bb[3]) / 2
    col = (20, 14, 8) if testo_scuro else (250, 248, 240)
    ombra = (255, 236, 170) if testo_scuro else (10, 10, 20)
    d.text((x + 1, y + 1), nome, font=f, fill=ombra)
    d.text((x, y), nome, font=f, fill=col)
    return im

dati = json.load(open(R + '/assets/dati/fantasmi.json', encoding='utf-8'))
foglio = apri('aSbCd9x')  # 55 fantasmi del gioco base (10 x 7, carte 350 x 544)
for g in dati['fantasmi']:
    i = g['n'] - 1
    r, c = divmod(i, 10)
    card = foglio.crop((c * 350, r * 544, (c + 1) * 350, (r + 1) * 544))
    salva(traduci(card, g['nome'], g['colore'] == 'giallo'), f"assets/carte/fantasma_{g['n']:02d}.webp")
foglio = apri('GF67QEw')  # incarnazioni di Wu-Feng (8 x 3)
for k, g in enumerate(dati['incarnazioni']):
    r, c = divmod(k, 8)
    card = foglio.crop((c * 350, r * 544, (c + 1) * 350, (r + 1) * 544))
    salva(traduci(card, g['nome'], g['colore_banda'] == 'giallo'), f"assets/carte/fantasma_{g['n']:02d}.webp")
salva(apri('8ii7Ey1').convert('RGB'), 'assets/carte/dorso_fantasma.webp')
salva(apri('pbUa6iE').convert('RGB'), 'assets/carte/dorso_incarnazione.webp')

# ------------------------------------------------------------------ villaggio (fronte attivo / retro infestato)
TESSERE = {
    'casa_te': ('2oF7uQ3', 'wAXyWfo'), 'erborista': ('ALRHmgQ', 'erhkaFQ'),
    'padiglione': ('SIituh7', 'F2oKkBm'), 'altare': ('c0oDsvp', '7XJRWfK'),
    'tempio': ('mBPesrm', 'z7fRo2g'), 'cerchio': ('O8tXjRn', 'b9wIlwA'),
    'stregone': ('k15DTSF', 'G1fULFl'), 'cimitero': ('dEJfhZW', 'MEgNZA9'),
    'guardiano': ('eOfUMms', 'KDYPsFb'),
}
for k, (a, b) in TESSERE.items():
    salva(apri(a).convert('RGB'), f'assets/villaggio/{k}.webp')
    salva(apri(b).convert('RGB'), f'assets/villaggio/{k}_infestata.webp')

# ------------------------------------------------------------------ plance dei Taoisti (due lati)
PLANCE = {
    'blu_0': 'E9nhDp5', 'blu_1': '4MgRHvG', 'rosso_0': 'EvBzYyc', 'rosso_1': 'uwmlNFW',
    'giallo_0': '5zUJpDh', 'giallo_1': 'D0j9GCM', 'verde_0': 'NVs2ukc', 'verde_1': '2a1zuAc',
}
for k, v in PLANCE.items():
    salva(apri(v).convert('RGB'), f'assets/plance/{k}.webp', 90)

# ------------------------------------------------------------------ segnalini
def tondo(im, d=160):
    im = im.convert('RGBA').resize((d, d), Image.LANCZOS)
    m = Image.new('L', (d, d), 0)
    ImageDraw.Draw(m).ellipse((1, 1, d - 2, d - 2), fill=255)
    im.putalpha(m)
    return im
SEG = {'tao_giallo': 'Zlxr5ta', 'tao_verde': '7ecSKVd', 'tao_rosso': 'o3pPEEe', 'tao_blu': 'hAfpbYp', 'tao_nero': 'gve38aX',
       'yinyang_rosso': '5wrc0bw', 'yinyang_blu': 'R55rFGo', 'yinyang_verde': 'a4UNULn', 'yinyang_giallo': 'is8LVia'}
for k, v in SEG.items():
    salva(tondo(apri(v)), f'assets/segnalini/{k}.webp', 92)
qi = apri('hhWzzxZ').convert('RGBA')
w, h = qi.size
salva(tondo(qi.crop((int(w * .12), int(h * .12), int(w * .88), int(h * .88)))), 'assets/segnalini/qi.webp', 92)
pot = apri('QXkrBq6').convert('RGBA')
w, h = pot.size
salva(tondo(pot.crop((0, (h - w) // 2, w, (h - w) // 2 + w))), 'assets/segnalini/potere.webp', 92)
mantra = apri('SOB2rHh').convert('RGBA')
a = np.array(mantra)
bianco = (a[:, :, 0] > 235) & (a[:, :, 1] > 235) & (a[:, :, 2] > 235)
a[bianco, 3] = 0
salva(Image.fromarray(a), 'assets/segnalini/mantra.webp', 92)
# icone dalle carte: figurina infestante, Buddha e dado della maledizione
c1 = Image.open(R + '/assets/carte/fantasma_01.webp')
salva(tondo(c1.crop((176 - 33, 470 - 33, 176 + 33, 470 + 33)), 120), 'assets/segnalini/infestante.webp', 92)
pl = apri('NVs2ukc').convert('RGBA')
salva(tondo(pl.crop((235 - 60, 570 - 60, 235 + 60, 570 + 60)), 120), 'assets/segnalini/buddha.webp', 92)

# ------------------------------------------------------------------ copertina per la ludoteca
cop = Image.open(f'{IMG}/httpiimgurcomSkwihoHjpg.jpg').convert('RGB')
k = cop.size[0] / 800.0
cop = cop.crop((int(24 * k), int(24 * k), int(776 * k), int(776 * k)))
# toglie la scritta "Rules" del regolamento
a = np.array(cop)
mask = np.zeros(a.shape[:2], np.uint8)
mask[int(255 * k):int(305 * k), 0:int(112 * k)] = 255
a = cv2.inpaint(a, mask, 9, cv2.INPAINT_TELEA)
cop = Image.fromarray(a)
grande = cop.copy()
grande.thumbnail((1400, 1400))
os.makedirs(R + '/assets/img', exist_ok=True)
grande.save(R + '/assets/img/sfondo.webp', 'WEBP', quality=84)
cop.thumbnail((560, 560))
os.makedirs(R + '/ludoteca', exist_ok=True)
cop.save(R + '/ludoteca/copertina.webp', 'WEBP', quality=86)
print('fatto')
