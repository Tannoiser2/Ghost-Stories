class_name Tavolo
extends Control
## Il tavolo visto dall'alto: il villaggio 3 x 3 al centro e le quattro plance dei Taoisti attorno,
## con la grafica originale. Si sposta trascinando, si ingrandisce con la rotella o pizzicando
## e si ruota con il tasto destro, con Maiusc + trascinamento o con due dita.

signal toccato(cosa: Dictionary)
signal sopra(cosa: Dictionary)

const T := 220.0                     # lato di una tessera del villaggio
const SCALA_PLANCIA := 660.0 / 1450.0
const CENTRO_PLANCIA := Vector2(725, 533)
const DIST_PLANCIA := 330.0 + 1066.0 * 660.0 / 1450.0 / 2.0
const SPAZI_X := [230.0, 724.0, 1217.0]
const SPAZIO_Y := 553.0
const CARTA := Vector2(344, 531)
const ICONA_INFESTA_Y := 82.0
const ICONA_INFESTANTE_Y := 193.0
const PIETRA_POTERE := Vector2(167, 940)
const ANGOLI := [0.0, PI / 2.0, PI, -PI / 2.0]
const NOMI_POS := ["Sud", "Ovest", "Nord", "Est"]
# Black Secret: catacombe nell'angolo in alto a destra, plancia di Wu-Feng in alto a sinistra
const C_CATA := Vector2(575, -575)
const LATO_CATA := 450.0
const C_WF := Vector2(-575, -575)
const LATO_WF := 450.0
const DEMONI := ["cercatore", "scavatore", "becchino"]

var s: Dictionary = {}               # lo stato del motore da disegnare
var evidenzia: Array = []            # opzioni della domanda con tessera o spazio
var colore_evidenzia := Color(1, 0.85, 0.35)
var etichette := {}                  # posizione -> testo sotto la plancia (chi la gioca)

var centro := Vector2.ZERO           # punto del mondo al centro dell'area
var zoom := 0.5
var rot := 0.0
var rot_obiettivo := 0.0
var area_utile := Rect2()            # parte dello schermo libera dai pannelli
var _tempo := 0.0

# trascinamento e tocchi
var _premuto := false
var _trascinato := false
var _ultimo := Vector2.ZERO
var _rotando := false
var _tocchi := {}
var _gesto_iniziale := {}
var _sopra_attuale := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

func _process(d: float) -> void:
	_tempo += d
	if absf(rot - rot_obiettivo) > 0.001:
		rot = lerp_angle(rot, rot_obiettivo, minf(1.0, d * 6.0))
	queue_redraw()

func adatta() -> void:
	var a := area_utile if area_utile.size.x > 10 else Rect2(Vector2.ZERO, size)
	zoom = clampf(minf(a.size.x, a.size.y) / 1760.0, 0.2, 2.0)
	centro = Vector2.ZERO

func ruota_verso(pos: int) -> void:
	rot_obiettivo = -ANGOLI[pos]

func ruota_di(delta: float) -> void:
	rot_obiettivo += delta

# ------------------------------------------------------------ trasformazioni

func _xform() -> Transform2D:
	var a := area_utile if area_utile.size.x > 10 else Rect2(Vector2.ZERO, size)
	var c := a.position + a.size / 2.0
	return Transform2D(rot, Vector2(zoom, zoom), 0.0, c) * Transform2D(0.0, -centro)

func mondo_da_schermo(p: Vector2) -> Vector2:
	return _xform().affine_inverse() * p

func xf_plancia(pos: int) -> Transform2D:
	var dir := Vector2(0, DIST_PLANCIA).rotated(ANGOLI[pos])
	return Transform2D(ANGOLI[pos], Vector2(SCALA_PLANCIA, SCALA_PLANCIA), 0.0, dir) * Transform2D(0.0, -CENTRO_PLANCIA)

func centro_tessera(t: int) -> Vector2:
	return Vector2((t % 3 - 1) * T, (t / 3 - 1) * T)

func centro_cata(i: int) -> Vector2:
	var c := LATO_CATA / 3.0
	return C_CATA + Vector2((i % 3 - 1) * c, (i / 3 - 1) * c)

## Dove sta il Taoista: tessera del villaggio o spazio delle catacombe
func centro_luogo(p: int) -> Vector2:
	var b: Dictionary = s.plance[p]
	if b.get("sotto", false):
		return centro_cata(int(b.tessera))
	return centro_tessera(int(b.tessera))

## Posizioni (sulla plancia di Wu-Feng larga 1374 px) degli spazi della piramide e delle urne
func pos_piramide(r: int, j: int) -> Vector2:
	var y: float = [655.0, 470.0, 285.0, 95.0][r]
	var x0: float = [100.0, 195.0, 290.0, 385.0][r]
	return C_WF + (Vector2(x0 + j * 190.0, y) / 1374.0 - Vector2(0.5, 0.5)) * LATO_WF

func pos_urna(j: int) -> Vector2:
	return C_WF + (Vector2(1215.0, 110.0 + j * 225.0) / 1374.0 - Vector2(0.5, 0.5)) * LATO_WF

func pos_demone_wf(d: String) -> Vector2:
	var x: float = {"cercatore": 138.0, "scavatore": 410.0, "becchino": 770.0, "ombra": 1150.0}[d]
	return C_WF + (Vector2(x, 1100.0) / 1374.0 - Vector2(0.5, 0.5)) * LATO_WF

func centro_spazio(p: int, k: int) -> Vector2:
	return xf_plancia(p) * Vector2(SPAZI_X[k], SPAZIO_Y)

# ------------------------------------------------------------ disegno

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0a0c16"))
	if s.is_empty():
		return
	var x := _xform()
	draw_set_transform_matrix(x)
	# un alone di nebbia attorno al villaggio
	draw_circle(Vector2.ZERO, 1150, Color(0.12, 0.15, 0.28, 0.35))
	draw_circle(Vector2.ZERO, 900, Color(0.14, 0.18, 0.32, 0.35))
	for p in 4:
		_disegna_plancia(p)
	for t in 9:
		_disegna_tessera(t)
	if s.get("segreto", false):
		_disegna_segreto()
	_disegna_taoisti()
	_disegna_evidenze()
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_disegna_etichette()

## Le targhette con chi gioca ogni plancia, sempre dritte sullo schermo
func _disegna_etichette() -> void:
	var f := Stile.grassetto()
	var dim := int(clampf(22.0 * zoom / 0.5, 14.0, 26.0))
	var vis := area_utile.grow(-2) if area_utile.size.x > 10 else Rect2(Vector2.ZERO, size)
	for p in 4:
		var et: String = etichette.get(p, "")
		if et == "":
			continue
		var b: Dictionary = s.plance[p]
		var bordo := _xform() * (xf_plancia(p) * Vector2(725, 1066))
		var cen := _xform() * (xf_plancia(p) * CENTRO_PLANCIA)
		var dir := (bordo - cen).normalized()
		var w := f.get_string_size(et, HORIZONTAL_ALIGNMENT_LEFT, -1, dim).x
		# la targhetta sta tutta fuori dalla plancia, dalla parte di chi la gioca
		var punto := bordo + dir * (absf(dir.x) * (w / 2 + 16) + absf(dir.y) * (dim * 0.9))
		# dentro la parte visibile del tavolo
		punto.x = clampf(punto.x, vis.position.x + w / 2 + 14, vis.end.x - w / 2 - 14)
		punto.y = clampf(punto.y, vis.position.y + dim, vis.end.y - dim)
		var r := Rect2(punto - Vector2(w / 2 + 12, dim * 0.75), Vector2(w + 24, dim * 1.5))
		draw_rect(r, Color(0.04, 0.05, 0.1, 0.9))
		draw_rect(r, Stile.colore(b.colore), false, 2)
		draw_string(f, Vector2(punto.x - w / 2, punto.y + dim * 0.35), et, HORIZONTAL_ALIGNMENT_LEFT, -1, dim, Stile.TESTO)

func _disegna_plancia(p: int) -> void:
	var b: Dictionary = s.plance[p]
	var xf := xf_plancia(p)
	draw_set_transform_matrix(_xform() * xf)
	var tex := Stile.tex("res://assets/plance/%s_%d.webp" % [b.colore, int(b.lato)])
	draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(1450, 1066)), false)
	if not b.taoista:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1450, 1066)), Color(0, 0, 0, 0.28))
	# potere spento
	var spento := _potere_spento(p)
	if spento:
		_croce(PIETRA_POTERE, 62, Color(0.95, 0.15, 0.1, 0.95), 16)
	for k in 3:
		var sp: Dictionary = b.spazi[k]
		var c := int(sp.c)
		var cen := Vector2(SPAZI_X[k], SPAZIO_Y)
		var r := Rect2(cen - CARTA / 2.0, CARTA)
		if c > 0:
			# ombra e carta
			draw_rect(Rect2(r.position + Vector2(10, 14), r.size), Color(0, 0, 0, 0.5))
			draw_texture_rect(Stile.carta(c), r, false)
			if Dati.e_incarnazione(c):
				var pulsa := 0.5 + 0.5 * sin(_tempo * 3.0)
				draw_rect(r.grow(8), Color(1.0, 0.2, 0.1, 0.5 + 0.4 * pulsa), false, 10)
			if sp.dado:
				_dado_catturato(cen + Vector2(-110, 150))
			if int(s.mantra.p) == p and int(s.mantra.s) == k:
				var mt := Stile.tex("res://assets/segnalini/mantra.webp")
				draw_texture_rect(mt, Rect2(cen + Vector2(70, -250), Vector2(80, 150)), false)
		if sp.buddha:
			var bt := Stile.tex("res://assets/segnalini/buddha.webp")
			var bp := cen if c == 0 else cen + Vector2(105, 170)
			_ombra_tonda(bp, 66)
			draw_texture_rect(bt, Rect2(bp - Vector2(66, 66), Vector2(132, 132)), false, Color(1.0, 0.86, 0.45))
			draw_arc(bp, 66, 0, TAU, 40, Stile.ORO, 6)
		if s.get("luna", false) and int(s.suling.p) == p and int(s.suling.k) == k:
			var sl := Vector2(SPAZI_X[k] + 120, ICONA_INFESTANTE_Y + 10)
			var pulsa := 0.5 + 0.5 * sin(_tempo * 2.4)
			draw_circle(sl, 92 + 8 * pulsa, Color(0.7, 0.85, 1.0, 0.18))
			draw_texture_rect(Stile.tex("res://assets/segnalini/suling.webp"), Rect2(sl - Vector2(56, 86), Vector2(112, 172)), false)
		var inf := int(sp.inf)
		if c > 0 and inf >= 0:
			var it := Stile.tex("res://assets/segnalini/infestante.webp")
			var ip := Vector2(SPAZI_X[k], ICONA_INFESTANTE_Y) if inf == 1 else cen + Vector2(0, 150)
			var raggio := 62.0
			_ombra_tonda(ip, raggio)
			draw_texture_rect(it, Rect2(ip - Vector2(raggio, raggio), Vector2(raggio, raggio) * 2), false)
			draw_arc(ip, raggio, 0, TAU, 40, Color(0.2, 0.9, 1.0, 0.9) if inf == 1 else Color(0.6, 0.7, 0.9, 0.8), 8)
			if inf == 1:
				var pulsa := 0.5 + 0.5 * sin(_tempo * 5.0)
				draw_arc(ip, raggio + 14 + 6 * pulsa, 0, TAU, 40, Color(0.4, 0.9, 1.0, 0.5 * pulsa), 6)
	draw_set_transform_matrix(_xform())

func _potere_spento(p: int) -> bool:
	for k in 3:
		var c := int(s.plance[p].spazi[k].c)
		if c > 0 and Dati.ha(c, "arrivo", "potere"):
			return true
	for q in 4:
		for k in 3:
			var c := int(s.plance[q].spazi[k].c)
			if c > 0 and Dati.ha(c, "permanente", "nopoteri"):
				return true
	return false

func _croce(c: Vector2, r: float, col: Color, w: float) -> void:
	draw_line(c + Vector2(-r, -r), c + Vector2(r, r), col, w)
	draw_line(c + Vector2(-r, r), c + Vector2(r, -r), col, w)

func _ombra_tonda(c: Vector2, r: float) -> void:
	draw_circle(c + Vector2(6, 8), r, Color(0, 0, 0, 0.45))

func _dado_catturato(c: Vector2) -> void:
	var r := Rect2(c - Vector2(46, 46), Vector2(92, 92))
	draw_rect(r, Color(0.96, 0.95, 0.9))
	draw_rect(r, Color(0.1, 0.1, 0.1), false, 5)
	draw_circle(c, 16, Color(0.85, 0.12, 0.1))
	# catena del fantasma
	draw_arc(c, 60, 0, TAU, 24, Color(0.8, 0.1, 0.1, 0.8), 5)

func _disegna_tessera(t: int) -> void:
	var v: Dictionary = s.villaggio[t]
	var c := centro_tessera(t)
	var r := Rect2(c - Vector2(T, T) / 2.0, Vector2(T, T))
	var nome := "res://assets/villaggio/%s%s.webp" % [v.id, "_infestata" if v.inf else ""]
	draw_texture_rect(Stile.tex(nome), r.grow(-2), false)
	draw_rect(r.grow(-2), Color(0, 0, 0, 0.6), false, 3)
	if v.inf:
		var pulsa := 0.5 + 0.5 * sin(_tempo * 2.0 + t)
		draw_rect(r.grow(-6), Color(0.35, 0.85, 1.0, 0.25 + 0.25 * pulsa), false, 6)
	match String(v.id):
		"tempio":
			for i in int(s.buddha_tempio):
				var bp := c + Vector2(-60 + i * 44, -62)
				_ombra_tonda(bp, 28)
				draw_texture_rect(Stile.tex("res://assets/segnalini/buddha.webp"), Rect2(bp - Vector2(28, 28), Vector2(56, 56)), false, Color(1, 0.86, 0.45))
				draw_arc(bp, 28, 0, TAU, 24, Stile.ORO, 3)
		"cerchio":
			if s.cerchio != "":
				var cp := c + Vector2(-58, -58)
				_ombra_tonda(cp, 36)
				draw_texture_rect(Stile.tex("res://assets/segnalini/tao_%s.webp" % s.cerchio), Rect2(cp - Vector2(36, 36), Vector2(72, 72)), false)
				draw_arc(cp, 36, 0, TAU, 24, Stile.ORO, 4)
	if s.get("luna", false):
		_disegna_luna_tessera(t, c)
	if t == 4 and int(s.poteri_centro) > 0:
		var pp := c + Vector2(62, -62)
		_ombra_tonda(pp, 30)
		draw_texture_rect(Stile.tex("res://assets/segnalini/potere.webp"), Rect2(pp - Vector2(30, 30), Vector2(60, 60)), false)
		_numero(pp + Vector2(24, 24), str(int(s.poteri_centro)))

## White Moon: Portale, ricettacoli e pila dei villici su una tessera
func _disegna_luna_tessera(t: int, c: Vector2) -> void:
	if t == int(s.get("portale", -1)):
		var pp := c + Vector2(0, -8)
		var pulsa := 0.5 + 0.5 * sin(_tempo * 1.6)
		draw_circle(pp, 70 + 6 * pulsa, Color(0.55, 0.75, 1.0, 0.16))
		draw_texture_rect(Stile.tex("res://assets/segnalini/portale.webp"), Rect2(pp - Vector2(58, 58), Vector2(116, 116)), false, Color(1, 1, 1, 0.92))
	var ri: int = [0, 2, 6, 8].find(t)
	if ri >= 0:
		# il ricettacolo sta sull'angolo esterno della tessera d'angolo
		var dir := Vector2(-1 if t % 3 == 0 else 1, -1 if t < 3 else 1)
		var rp := c + dir * (T * 0.5 + 34)
		_ombra_tonda(rp, 30)
		draw_circle(rp, 30, Color(0.08, 0.09, 0.16))
		draw_arc(rp, 30, 0, TAU, 30, Color(0.65, 0.8, 1.0, 0.9), 4)
		if s.ricettacoli[ri]:
			var pulsa := 0.5 + 0.5 * sin(_tempo * 3.0 + ri)
			draw_circle(rp, 34 + 4 * pulsa, Color(0.6, 0.85, 1.0, 0.25))
			draw_texture_rect(Stile.tex("res://assets/segnalini/cristallo.webp"), Rect2(rp - Vector2(26, 26), Vector2(52, 52)), false)
	var ab: Array = s.villaggio[t].get("ab", [])
	if not ab.is_empty():
		var base := c + Vector2(T * 0.5 - 52, T * 0.5 - 52)
		for i in ab.size():
			var q := base + Vector2(-i * 9, -i * 9)
			var r := Rect2(q - Vector2(40, 40), Vector2(80, 80))
			draw_rect(Rect2(r.position + Vector2(4, 5), r.size), Color(0, 0, 0, 0.5))
			if i == ab.size() - 1:
				draw_texture_rect(Stile.tex("res://assets/villici/%s.webp" % ab[i]), r, false)
			else:
				draw_texture_rect(Stile.tex("res://assets/villici/dorso.webp"), r, false)
			draw_rect(r, Color(0.1, 0.08, 0.05), false, 2)
		if ab.size() > 1:
			_numero(base + Vector2(30, 30), str(ab.size()))

func _numero(p: Vector2, testo: String) -> void:
	draw_circle(p, 18, Color(0.05, 0.05, 0.1))
	draw_arc(p, 18, 0, TAU, 20, Stile.ORO, 3)
	var f := Stile.grassetto()
	var w := f.get_string_size(testo, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string(f, p + Vector2(-w / 2, 9), testo, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Stile.TESTO)

func _disegna_taoisti() -> void:
	var per_tessera := {}
	for p in 4:
		var b: Dictionary = s.plance[p]
		if not b.taoista:
			continue
		var t := int(b.tessera) + (10 if b.get("sotto", false) else 0)
		if not per_tessera.has(t):
			per_tessera[t] = []
		per_tessera[t].append(p)
	for t in per_tessera:
		var l: Array = per_tessera[t]
		var c := centro_tessera(t) if t < 10 else centro_cata(t - 10)
		if t >= 10:
			c += Vector2(0, -20)
		for i in l.size():
			var off := Vector2.ZERO
			if l.size() > 1:
				off = Vector2(52, 0).rotated(TAU * i / l.size() + PI / 4)
			var p: int = l[i]
			_figura(c + off + Vector2(0, 20), s.plance[p].colore, s.plance[p].vivo, p == int(s.turno_di))

## Il Taoista: un disco del suo colore con la sagoma del monaco e il cappello
func _figura(c: Vector2, col: String, vivo: bool, di_turno: bool) -> void:
	var colore := Stile.colore(col)
	var r := 40.0
	if di_turno and vivo:
		var pulsa := 0.5 + 0.5 * sin(_tempo * 4.0)
		draw_circle(c, r + 12 + 5 * pulsa, Color(1, 0.9, 0.5, 0.35))
	draw_circle(c + Vector2(5, 7), r, Color(0, 0, 0, 0.55))
	draw_circle(c, r, colore if vivo else Color(0.35, 0.35, 0.38))
	draw_arc(c, r, 0, TAU, 32, Stile.ORO if vivo else Color(0.2, 0.2, 0.2), 4)
	var bianco := Color(0.98, 0.96, 0.9) if vivo else Color(0.75, 0.75, 0.75)
	var scuro := Color(0.08, 0.07, 0.1)
	# veste con le maniche larghe
	draw_colored_polygon(PackedVector2Array([c + Vector2(-24, 30), c + Vector2(24, 30), c + Vector2(15, 2), c + Vector2(22, 8), c + Vector2(12, -4), c + Vector2(-12, -4), c + Vector2(-22, 8), c + Vector2(-15, 2)]), bianco)
	draw_line(c + Vector2(0, -2), c + Vector2(0, 30), scuro, 2.5)
	# volto
	draw_circle(c + Vector2(0, -11), 8.5, Color(0.96, 0.82, 0.66) if vivo else Color(0.7, 0.7, 0.7))
	# cappello di paglia largo e piatto
	draw_colored_polygon(PackedVector2Array([c + Vector2(-25, -14), c + Vector2(25, -14), c + Vector2(0, -29)]), scuro)
	draw_line(c + Vector2(-25, -14), c + Vector2(25, -14), Stile.ORO, 2.0)
	if not vivo:
		_croce(c, 26, Color(0.9, 0.1, 0.1), 7)

## Black Secret: catacombe con scale, pile, demoni e Ombra; plancia di Wu-Feng con piramide e urne
func _disegna_segreto() -> void:
	var r := Rect2(C_CATA - Vector2(LATO_CATA, LATO_CATA) / 2.0, Vector2(LATO_CATA, LATO_CATA))
	draw_rect(Rect2(r.position + Vector2(10, 14), r.size), Color(0, 0, 0, 0.5))
	draw_texture_rect(Stile.tex("res://assets/bs/catacombe.webp"), r, false, Color(0.85, 0.85, 0.85))
	draw_rect(r, Color(0.25, 0.2, 0.15), false, 6)
	var lato := LATO_CATA / 3.0
	var ingressi: Array = Dati.catacombe().get("ingressi", [])
	for i in 9:
		var c := centro_cata(i)
		var cata: Dictionary = s.cata[i]
		if i in ingressi:
			draw_rect(Rect2(c - Vector2(lato, lato) / 2.0, Vector2(lato, lato)).grow(-4), Color(0.9, 0.25, 0.2, 0.7), false, 4)
		# la scala: due montanti e i pioli
		if cata.scala:
			var a := c + Vector2(-58, -50)
			var col := Color(0.55, 0.38, 0.2)
			draw_line(a, a + Vector2(0, 54), col, 5)
			draw_line(a + Vector2(18, 0), a + Vector2(18, 54), col, 5)
			for j in 4:
				draw_line(a + Vector2(0, 8 + j * 13), a + Vector2(18, 8 + j * 13), col, 3)
		# la pila dei segnalini, coperta
		var pila: Array = cata.pila
		if not pila.is_empty():
			var pp := c + Vector2(38, -38)
			for j in pila.size():
				var q := pp + Vector2(-j * 4, -j * 4)
				draw_texture_rect(Stile.tex("res://assets/bs/cat_dorso_%d.webp" % (j + 1)), Rect2(q - Vector2(26, 26), Vector2(52, 52)), false)
			_numero(pp + Vector2(22, 22), str(pila.size()))
		# i demoni
		var dd := []
		for d in DEMONI:
			if int(s.demoni[d]) == i:
				dd.append(d)
		if int(s.ombra) == i and s.ombra_sotto:
			dd.append("ombra")
		for j in dd.size():
			var q := c + Vector2(-30 + j * 46, 34)
			_ritratto(q, dd[j], 30)
	# l'Ombra sopra il villaggio
	if int(s.ombra) >= 0 and not s.ombra_sotto:
		_ritratto(centro_tessera(int(s.ombra)) + Vector2(-60, -60), "ombra", 40)
	# plancia di Wu-Feng
	var w := Rect2(C_WF - Vector2(LATO_WF, LATO_WF) / 2.0, Vector2(LATO_WF, LATO_WF))
	draw_rect(Rect2(w.position + Vector2(10, 14), w.size), Color(0, 0, 0, 0.5))
	draw_texture_rect(Stile.tex("res://assets/bs/wufeng.webp"), w, false, Color(0.85, 0.85, 0.85))
	draw_rect(w, Color(0.4, 0.1, 0.1), false, 6)
	for rr in 4:
		var ids: Array = s.pir_id[rr]
		for j in ids.size():
			var q := pos_piramide(rr, j)
			draw_texture_rect(Stile.tex("res://assets/bs/maledizione_%s.webp" % ids[j]), Rect2(q - Vector2(28, 28), Vector2(56, 56)), false)
	for j in int(s.urne):
		var q := pos_urna(j)
		draw_texture_rect(Stile.tex("res://assets/bs/cat_urna.webp"), Rect2(q - Vector2(32, 32), Vector2(64, 64)), false)
	for d in DEMONI:
		if int(s.demoni[d]) != -1:
			var q := pos_demone_wf(d)
			draw_rect(Rect2(q - Vector2(40, 60), Vector2(80, 120)), Color(0, 0, 0, 0.6))
	if int(s.scheletri) < 3:
		var q := C_WF + (Vector2(870, 150) / 1374.0 - Vector2(0.5, 0.5)) * LATO_WF
		_numero(q + Vector2(30, 30), str(int(s.scheletri)))
	if not s.inc_mano.is_empty():
		var q := C_WF + Vector2(LATO_WF / 2.0 - 40, -LATO_WF / 2.0 + 30)
		_numero(q, str(s.inc_mano.size()))

func _ritratto(c: Vector2, d: String, r: float) -> void:
	var pulsa := 0.5 + 0.5 * sin(_tempo * 3.0)
	draw_circle(c + Vector2(3, 4), r, Color(0, 0, 0, 0.5))
	if d == "ombra":
		draw_circle(c, r + 6 + 4 * pulsa, Color(0.9, 0.1, 0.05, 0.3))
	draw_texture_rect(Stile.tex("res://assets/bs/ritratto_%s.webp" % d), Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
	draw_arc(c, r, 0, TAU, 32, Color(0.85, 0.2, 0.15), 3)

func _disegna_evidenze() -> void:
	var pulsa := 0.55 + 0.45 * sin(_tempo * 5.0)
	var col := Color(colore_evidenzia.r, colore_evidenzia.g, colore_evidenzia.b, 0.55 + 0.4 * pulsa)
	var fatte := {}
	for o in evidenzia:
		if o.has("tessera"):
			var t := int(o.tessera)
			if fatte.has("t%d" % t):
				continue
			fatte["t%d" % t] = true
			var r := Rect2(centro_tessera(t) - Vector2(T, T) / 2.0, Vector2(T, T)).grow(-8)
			draw_rect(r, col, false, 8)
		elif o.has("spazio"):
			var x: Array = o.spazio
			var k := "s%d.%d" % [x[0], x[1]]
			if fatte.has(k):
				continue
			fatte[k] = true
			draw_set_transform_matrix(_xform() * xf_plancia(int(x[0])))
			var cen := Vector2(SPAZI_X[int(x[1])], SPAZIO_Y)
			draw_rect(Rect2(cen - CARTA / 2.0, CARTA).grow(14), col, false, 18)
			draw_set_transform_matrix(_xform())
		elif o.has("cata") and s.get("segreto", false):
			var i := int(o.cata)
			if fatte.has("c%d" % i):
				continue
			fatte["c%d" % i] = true
			var l := LATO_CATA / 3.0
			draw_rect(Rect2(centro_cata(i) - Vector2(l, l) / 2.0, Vector2(l, l)).grow(-6), col, false, 7)
		elif o.has("plancia"):
			var q := int(o.plancia)
			var k2 := "p%d" % q
			if fatte.has(k2):
				continue
			fatte[k2] = true
			draw_set_transform_matrix(_xform() * xf_plancia(q))
			draw_rect(Rect2(Vector2.ZERO, Vector2(1450, 1066)).grow(-6), col, false, 16)
			draw_set_transform_matrix(_xform())

# ------------------------------------------------------------ che cosa c'è in un punto

func cosa_in(schermo: Vector2) -> Dictionary:
	if s.is_empty():
		return {}
	return cosa_in_mondo(mondo_da_schermo(schermo))

## Che cosa c'è in un punto del tavolo (coordinate del mondo, usate anche dalla vista 3D)
func cosa_in_mondo(w: Vector2) -> Dictionary:
	if s.is_empty():
		return {}
	if s.get("segreto", false):
		var rc := Rect2(C_CATA - Vector2(LATO_CATA, LATO_CATA) / 2.0, Vector2(LATO_CATA, LATO_CATA))
		if rc.has_point(w):
			var l := LATO_CATA / 3.0
			var i := clampi(int((w.y - rc.position.y) / l), 0, 2) * 3 + clampi(int((w.x - rc.position.x) / l), 0, 2)
			return {"cata": i}
		if Rect2(C_WF - Vector2(LATO_WF, LATO_WF) / 2.0, Vector2(LATO_WF, LATO_WF)).has_point(w):
			return {"wufeng": true}
	# tessere
	if absf(w.x) <= T * 1.5 and absf(w.y) <= T * 1.5:
		var c := int(floor((w.x + T * 1.5) / T))
		var r := int(floor((w.y + T * 1.5) / T))
		return {"tessera": clampi(r, 0, 2) * 3 + clampi(c, 0, 2)}
	for p in 4:
		var loc := xf_plancia(p).affine_inverse() * w
		if loc.x < 0 or loc.y < 0 or loc.x > 1450 or loc.y > 1066:
			continue
		for k in 3:
			var cen := Vector2(SPAZI_X[k], SPAZIO_Y)
			if Rect2(cen - CARTA / 2.0, CARTA).has_point(loc):
				var o := {"spazio": [p, k], "plancia": p}
				var c := int(s.plance[p].spazi[k].c)
				if c > 0:
					o["carta"] = c
				return o
		return {"plancia": p}
	return {}

# ------------------------------------------------------------ input

func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		_tocco(e)
		accept_event()
		return
	if e is InputEventMouse and e.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_zoom_in(e.position, 1.12)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_zoom_in(e.position, 1.0 / 1.12)
		elif e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT:
			if e.pressed:
				_premuto = true
				_trascinato = false
				_ultimo = e.position
				_rotando = e.button_index == MOUSE_BUTTON_RIGHT or e.shift_pressed
			else:
				if _premuto and not _trascinato and e.button_index == MOUSE_BUTTON_LEFT:
					toccato.emit(cosa_in(e.position))
				_premuto = false
				_rotando = false
		accept_event()
	elif e is InputEventMouseMotion:
		if _premuto:
			var dlt: Vector2 = e.position - _ultimo
			if dlt.length() > 3 or _trascinato:
				_trascinato = true
				if _rotando:
					var c := _centro_area()
					var a0 := (_ultimo - c).angle()
					var a1: float = (e.position - c).angle()
					rot += a1 - a0
					rot_obiettivo = rot
				else:
					centro -= dlt.rotated(-rot) / zoom
				_ultimo = e.position
		else:
			var q := cosa_in(e.position)
			if q.get("carta", 0) != _sopra_attuale.get("carta", 0):
				_sopra_attuale = q
				sopra.emit(q)

func _centro_area() -> Vector2:
	var a := area_utile if area_utile.size.x > 10 else Rect2(Vector2.ZERO, size)
	return a.position + a.size / 2.0

func _zoom_in(punto: Vector2, f: float) -> void:
	var prima := mondo_da_schermo(punto)
	zoom = clampf(zoom * f, 0.15, 3.0)
	var dopo := mondo_da_schermo(punto)
	centro += prima - dopo

func _tocco(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_tocchi[e.index] = e.position
			if _tocchi.size() == 1:
				_trascinato = false
				_ultimo = e.position
			_inizia_gesto()
		else:
			if _tocchi.size() == 1 and not _trascinato:
				toccato.emit(cosa_in(e.position))
			_tocchi.erase(e.index)
			_inizia_gesto()
	elif e is InputEventScreenDrag:
		_tocchi[e.index] = e.position
		if _tocchi.size() == 1:
			var dlt: Vector2 = e.position - _ultimo
			if dlt.length() > 6 or _trascinato:
				_trascinato = true
				centro -= dlt.rotated(-rot) / zoom
				_ultimo = e.position
		elif _tocchi.size() >= 2 and not _gesto_iniziale.is_empty():
			_trascinato = true
			var k: Array = _tocchi.keys()
			var a: Vector2 = _tocchi[k[0]]
			var b: Vector2 = _tocchi[k[1]]
			var g := _gesto_iniziale
			var dist := maxf(10.0, a.distance_to(b))
			var mezzo := (a + b) / 2.0
			zoom = clampf(g.zoom * dist / g.dist, 0.15, 3.0)
			rot = g.rot + ((b - a).angle() - g.ang)
			rot_obiettivo = rot
			# il punto del mondo sotto le dita resta sotto le dita
			var cen := _centro_area()
			centro = g.mondo - (mezzo - cen).rotated(-rot) / zoom

func _inizia_gesto() -> void:
	_gesto_iniziale = {}
	if _tocchi.size() >= 2:
		var k: Array = _tocchi.keys()
		var a: Vector2 = _tocchi[k[0]]
		var b: Vector2 = _tocchi[k[1]]
		var mezzo := (a + b) / 2.0
		_gesto_iniziale = {"dist": maxf(10.0, a.distance_to(b)), "ang": (b - a).angle(), "zoom": zoom, "rot": rot, "mondo": mondo_da_schermo(mezzo)}
	elif _tocchi.size() == 1:
		_ultimo = _tocchi.values()[0]
