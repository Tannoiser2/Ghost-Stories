class_name Partita
extends Control
## Lo schermo di gioco: il tavolo, le schede dei Taoisti, le scelte, i dadi e il diario.
## In una partita locale (o per chi ospita online) qui gira il motore; chi entra come ospite
## riceve lo stato dall'ospite e manda solo le proprie scelte.

signal esci

const CHIAVE_SALVATAGGIO := "ghoststories_partita"
const BREVE := {"casa_te": "Casa del Tè", "erborista": "Erborista", "padiglione": "Padiglione", "altare": "Altare",
	"tempio": "Tempio", "cerchio": "Cerchio", "stregone": "Stregone", "cimitero": "Cimitero", "guardiano": "Guardiano"}

var rete: Rete
var m: Motore = null              # nullo per gli ospiti online
var ia: IA = null
var s: Dictionary = {}            # lo stato disegnato
var posti: Array = []             # per ogni plancia: {tipo: locale/ia/remoto/neutra, uid, nome}
var cfg: Dictionary = {}
var ospite := false
var online := false
var versione := 0
var ritmo := 0.7                  # secondi tra una mossa del computer e l'altra
var segui := true

var tavolo: Tavolo
var pan_sx: PanelContainer
var box_schede: BoxContainer
var pan_dx: PanelContainer
var box_domanda: VBoxContainer
var box_dadi: HBoxContainer
var diario: RichTextLabel
var barra: Label
var barra_pan: PanelContainer
var comandi: HBoxContainer
var zoom_carta: PanelContainer
var zoom_tex: TextureRect
var zoom_testo: Label
var banner: TextureRect
var toast_box: VBoxContainer
var finale: Control
var regole: Control

var _attesa_ia := 0.0
var _versione_disegnata := -1
var _ultimo_evento := 0
var _banner_t := 0.0
var _ultimo_turno := -1
var _salvati := 0

# ============================================================ avvio

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tavolo = Tavolo.new()
	tavolo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(tavolo)
	tavolo.toccato.connect(_toccato)
	tavolo.sopra.connect(_sopra)
	_costruisci_pannelli()
	resized.connect(_riposiziona)
	_riposiziona.call_deferred()

## Partita sul dispositivo (o ospitata online)
func avvia(config: Dictionary, p: Array) -> void:
	cfg = config
	posti = p
	m = Motore.new()
	m.nuova_partita(cfg)
	ia = IA.new(m)
	_imposta_posti_neutri()
	s = m.s
	_dopo_cambio()

func riprendi(testo: String) -> bool:
	var j = JSON.parse_string(testo)
	if not j is Dictionary or not j.has("s"):
		return false
	m = Motore.new()
	m.s = Motore.normalizza(j.s)
	ia = IA.new(m)
	posti = Motore.normalizza(j.get("posti", []))
	cfg = j.get("cfg", {})
	# riprendendo da soli, i posti online tornano al computer
	if not online:
		for x in posti:
			if x.tipo == "remoto":
				x.tipo = "ia"
	s = m.s
	m.avanza()
	_dopo_cambio()
	return true

func avvia_ospite() -> void:
	ospite = true
	online = true

func _imposta_posti_neutri() -> void:
	for i in 4:
		if i >= posti.size():
			posti.append({"tipo": "neutra", "nome": ""})
		if not m.s.plance[i].taoista:
			posti[i] = {"tipo": "neutra", "nome": ""}

## L'ospite riceve lo stato dall'ospitante
func ricevi_stato(j: String) -> void:
	var d = JSON.parse_string(j)
	if not d is Dictionary or d.get("tipo", "") != "partita":
		return
	s = Motore.normalizza(d.s)
	posti = Motore.normalizza(d.get("posti", []))
	versione = int(d.get("v", 0))
	_aggiorna()

func _mio_posto(p: int) -> bool:
	if p < 0 or p >= posti.size():
		return false
	var x: Dictionary = posti[p]
	if ospite:
		return x.get("tipo", "") == "remoto" and x.get("uid", "") == rete.uid
	return x.get("tipo", "") == "locale"

# ============================================================ ciclo

func _process(d: float) -> void:
	if _banner_t > 0:
		_banner_t -= d
		banner.modulate.a = clampf(_banner_t / 0.4, 0.0, 1.0)
		if _banner_t <= 0:
			banner.visible = false
	if m == null or m.finita() or not m.in_attesa():
		return
	var chi := int(m.s.domanda.chi)
	var tipo: String = posti[chi].get("tipo", "ia") if chi >= 0 and chi < posti.size() else "ia"
	if tipo == "ia" or tipo == "neutra":
		_attesa_ia += d
		if _attesa_ia >= ritmo:
			_attesa_ia = 0.0
			_rispondi(ia.scegli())

func _rispondi(id: String) -> void:
	if ospite:
		rete.azione("r", {"id": id, "v": versione})
		box_domanda.modulate.a = 0.5
		return
	if m == null:
		return
	if m.rispondi(id):
		_dopo_cambio()

func _dopo_cambio() -> void:
	versione += 1
	s = m.s
	if online and not ospite:
		rete.stato({"tipo": "partita", "s": m.s, "posti": posti, "v": versione})
	_salva()
	_aggiorna()

func _salva() -> void:
	if m == null:
		return
	var testo := JSON.stringify({"s": m.s, "posti": posti, "cfg": cfg})
	if m.finita():
		rete.salva(CHIAVE_SALVATAGGIO, "")
		return
	rete.salva(CHIAVE_SALVATAGGIO, testo)
	_salvati += 1
	if _salvati % 6 == 1:
		rete.salva_remoto(testo)

## Mossa di un ospite online (solo chi ospita la riceve)
func azione_remota(uid: String, p: String) -> void:
	if m == null or not m.in_attesa():
		return
	var d = JSON.parse_string(p)
	if not d is Dictionary:
		return
	var chi := int(m.s.domanda.chi)
	if chi < 0 or posti[chi].get("uid", "") != uid:
		return
	if int(d.get("v", -1)) != versione:
		return
	if m.rispondi(str(d.get("id", ""))):
		_dopo_cambio()

# ============================================================ costruzione dell'interfaccia

func _costruisci_pannelli() -> void:
	# a sinistra: i Taoisti
	pan_sx = PanelContainer.new()
	add_child(pan_sx)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pan_sx.add_child(sc)
	box_schede = VBoxContainer.new()
	box_schede.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_schede.add_theme_constant_override("separation", 10)
	sc.add_child(box_schede)
	# a destra: la scelta, i dadi e il diario
	pan_dx = PanelContainer.new()
	add_child(pan_dx)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pan_dx.add_child(v)
	var scd := ScrollContainer.new()
	scd.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scd.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scd.size_flags_stretch_ratio = 1.4
	v.add_child(scd)
	box_domanda = VBoxContainer.new()
	box_domanda.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_domanda.add_theme_constant_override("separation", 8)
	scd.add_child(box_domanda)
	box_dadi = HBoxContainer.new()
	box_dadi.add_theme_constant_override("separation", 10)
	box_dadi.custom_minimum_size.y = 64
	v.add_child(box_dadi)
	var tdi := Stile.etichetta("Diario", 26, Stile.ORO, Stile.titolo())
	v.add_child(tdi)
	diario = RichTextLabel.new()
	diario.bbcode_enabled = true
	diario.scroll_following = true
	diario.size_flags_vertical = Control.SIZE_EXPAND_FILL
	diario.custom_minimum_size = Vector2(200, 120)
	diario.add_theme_font_size_override("normal_font_size", 20)
	diario.add_theme_font_size_override("bold_font_size", 20)
	diario.add_theme_font_override("bold_font", Stile.grassetto())
	diario.add_theme_color_override("default_color", Stile.TESTO)
	v.add_child(diario)
	# barra in alto
	barra_pan = PanelContainer.new()
	add_child(barra_pan)
	barra = Stile.etichetta("", 22, Stile.TESTO)
	barra.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	barra.custom_minimum_size.x = 400
	barra_pan.add_child(barra)
	# comandi della vista
	comandi = HBoxContainer.new()
	comandi.add_theme_constant_override("separation", 8)
	add_child(comandi)
	for c in [["Centra", func(): tavolo.adatta()], ["Ruota a sinistra", func(): tavolo.ruota_di(-PI / 2.0)],
			["Ruota a destra", func(): tavolo.ruota_di(PI / 2.0)], ["Segui il turno: sì", _cambia_segui],
			["Regole", _mostra_regole], ["Menu", func(): esci.emit()]]:
		var b := Stile.bottone(c[0], 19)
		b.custom_minimum_size = Vector2(0, 42)
		b.pressed.connect(c[1].bind(b) if c[0].begins_with("Segui") else c[1])
		comandi.add_child(b)
	# carta ingrandita
	zoom_carta = PanelContainer.new()
	zoom_carta.visible = false
	zoom_carta.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(zoom_carta)
	var zv := VBoxContainer.new()
	zv.add_theme_constant_override("separation", 8)
	zoom_carta.add_child(zv)
	zoom_tex = TextureRect.new()
	zoom_tex.custom_minimum_size = Vector2(300, 466)
	zoom_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	zoom_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	zv.add_child(zoom_tex)
	zoom_testo = Stile.paragrafo("", 19)
	zoom_testo.custom_minimum_size = Vector2(300, 0)
	zv.add_child(zoom_testo)
	var chiudi := Stile.bottone("Chiudi", 19)
	chiudi.pressed.connect(func(): zoom_carta.visible = false)
	zv.add_child(chiudi)
	# la carta che entra in gioco
	banner = TextureRect.new()
	banner.visible = false
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(banner)
	toast_box = VBoxContainer.new()
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_theme_constant_override("separation", 6)
	add_child(toast_box)

func _cambia_segui(b: Button) -> void:
	segui = not segui
	b.text = "Segui il turno: " + ("sì" if segui else "no")
	if segui and not s.is_empty():
		tavolo.ruota_verso(int(s.turno_di))

func _verticale() -> bool:
	return size.y > size.x * 1.05

func _riposiziona() -> void:
	var W := size.x
	var H := size.y
	if W < 10:
		return
	var area: Rect2
	if _verticale():
		var alto := 150.0
		var basso := H * 0.36
		pan_sx.position = Vector2(10, 10)
		pan_sx.size = Vector2(W - 20, alto)
		_orientamento_schede(true)
		pan_dx.position = Vector2(10, H - basso - 10)
		pan_dx.size = Vector2(W - 20, basso)
		area = Rect2(0, alto + 20, W, H - alto - basso - 40)
	else:
		var sx := clampf(W * 0.19, 300, 360)
		var dx := clampf(W * 0.24, 380, 470)
		pan_sx.position = Vector2(10, 10)
		pan_sx.size = Vector2(sx, H - 20)
		_orientamento_schede(false)
		pan_dx.position = Vector2(W - dx - 10, 10)
		pan_dx.size = Vector2(dx, H - 20)
		area = Rect2(sx + 20, 0, W - sx - dx - 40, H)
	tavolo.area_utile = Rect2(area.position + Vector2(0, 60), area.size - Vector2(0, 120))
	barra_pan.position = Vector2(area.position.x + 10, area.position.y + 8)
	barra_pan.size = Vector2(area.size.x - 20, 46)
	comandi.position = Vector2(area.position.x + 10, area.end.y - 54)
	comandi.size = Vector2(area.size.x - 20, 46)
	toast_box.position = Vector2(area.position.x + 20, area.position.y + 64)
	toast_box.size = Vector2(area.size.x - 40, 200)
	var zh := minf(H * 0.8, 800.0)
	zoom_carta.position = Vector2(area.position.x + 20, area.position.y + 70)
	zoom_carta.size = Vector2(330, 0)
	zoom_tex.custom_minimum_size = Vector2(300, minf(466, zh - 250))
	banner.size = Vector2(300, 466)
	banner.position = area.position + area.size / 2.0 - banner.size / 2.0
	if finale:
		finale.size = size
	if regole:
		regole.size = size
	tavolo.adatta()
	_versione_disegnata = -1
	_aggiorna()

func _orientamento_schede(orizzontale: bool) -> void:
	var vuole_h := orizzontale
	var e_h := box_schede is HBoxContainer
	if vuole_h == e_h:
		return
	var sc: ScrollContainer = box_schede.get_parent()
	sc.remove_child(box_schede)
	box_schede.queue_free()
	box_schede = HBoxContainer.new() if vuole_h else VBoxContainer.new()
	box_schede.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_schede.add_theme_constant_override("separation", 10)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if vuole_h else ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(box_schede)

# ============================================================ aggiornamento

func _aggiorna() -> void:
	if s.is_empty() or tavolo == null:
		return
	tavolo.s = s
	var et := {}
	for p in 4:
		et[p] = _nome_posto(p)
	tavolo.etichette = et
	_eventi()
	if _versione_disegnata == versione:
		return
	_versione_disegnata = versione
	_barra()
	_schede()
	_domanda()
	_dadi()
	_diario()
	if s.esito != "":
		_mostra_finale()

func _nome_posto(p: int) -> String:
	var b: Dictionary = s.plance[p]
	var col: String = "Taoista " + Dati.NOMI_COLORE[b.colore]
	if not b.taoista:
		return "Plancia neutra %s" % {"rosso": "rossa", "giallo": "gialla"}.get(b.colore, b.colore)
	var x: Dictionary = posti[p] if p < posti.size() else {}
	match x.get("tipo", ""):
		"locale": return "Taoista %s" % Dati.NOMI_COLORE[b.colore] + ("" if x.get("nome", "") == "" else " - " + str(x.nome))
		"ia": return "Taoista %s (computer)" % Dati.NOMI_COLORE[b.colore]
		"remoto": return "Taoista %s - %s" % [Dati.NOMI_COLORE[b.colore], x.get("nome", "amico")]
	return col

func _barra() -> void:
	var lim := 4 if s.livello == "iniziazione" else 3
	var inf := 0
	for v in s.villaggio:
		if v.inf:
			inf += 1
	var dadi := 3
	for p in 4:
		for k in 3:
			if int(s.plance[p].spazi[k].c) > 0 and s.plance[p].spazi[k].dado:
				dadi -= 1
	var t := "Giro %d  ·  %s  ·  Mazzo %d  ·  Wu-Feng %d/%d  ·  Infestate %d/%d  ·  Dadi Tao %d" % [
		int(s.giro), Dati.NOMI_LIVELLO[s.livello], s.mazzo.size(), int(s.inc_sconfitte), int(s.inc_totali), inf, lim, maxi(dadi, 0)]
	if s.cerchio != "":
		t += "  ·  Cerchio: %s" % Dati.NOMI_COLORE[s.cerchio]
	barra.text = t

func _schede() -> void:
	for c in box_schede.get_children():
		c.queue_free()
	var ordine := []
	for p in 4:
		if s.plance[p].taoista:
			ordine.append(p)
	for p in 4:
		if not s.plance[p].taoista:
			ordine.append(p)
	for p in ordine:
		box_schede.add_child(_scheda(p))

func _scheda(p: int) -> Control:
	var b: Dictionary = s.plance[p]
	var col := Stile.colore(b.colore)
	var pan := PanelContainer.new()
	var di_turno := p == int(s.turno_di)
	pan.add_theme_stylebox_override("panel", Stile.scatola(Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 0.96), Stile.ORO if di_turno else col.darkened(0.2), 10, 4 if di_turno else 2))
	if box_schede is HBoxContainer:
		pan.custom_minimum_size = Vector2(maxf(300.0, (size.x - 80) / 4.0), 0)
	pan.mouse_filter = Control.MOUSE_FILTER_STOP
	pan.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_mostra_info(Testi.potere("%s_%d" % [b.colore, int(b.lato)]), null))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	pan.add_child(v)
	var testa := HBoxContainer.new()
	v.add_child(testa)
	var n := Stile.etichetta(_nome_posto(p), 22, Color.WHITE, Stile.grassetto())
	n.clip_text = true
	testa.add_child(n)
	if di_turno:
		var tt := Stile.etichetta("di turno", 18, Stile.ORO, Stile.titolo())
		tt.size_flags_horizontal = Control.SIZE_SHRINK_END
		tt.custom_minimum_size.x = 70
		testa.add_child(tt)
	var pot := Dati.potere("%s_%d" % [b.colore, int(b.lato)])
	var pl := Stile.etichetta(pot.get("nome", ""), 18, Stile.ORO, Stile.titolo())
	if _potere_spento(p):
		pl.text += " (spento)"
		pl.add_theme_color_override("font_color", Stile.ROSSO)
	v.add_child(pl)
	var riga := HBoxContainer.new()
	riga.add_theme_constant_override("separation", 6)
	v.add_child(riga)
	riga.add_child(_icona("res://assets/segnalini/qi.webp", int(b.qi), 40))
	if b.taoista:
		if not b.vivo:
			riga.add_child(Stile.etichetta("MORTO", 22, Stile.ROSSO, Stile.grassetto()))
		else:
			if b.yinyang:
				riga.add_child(_icona("res://assets/segnalini/yinyang_%s.webp" % b.colore, -1, 40))
			if int(b.buddha) > 0:
				riga.add_child(_icona("res://assets/segnalini/buddha.webp", int(b.buddha), 40, Color(1, 0.86, 0.45)))
			if int(b.poteri) > 0:
				riga.add_child(_icona("res://assets/segnalini/potere.webp", int(b.poteri), 40))
		var tao := HBoxContainer.new()
		tao.add_theme_constant_override("separation", 4)
		v.add_child(tao)
		for c in Dati.COLORI_TAO:
			var q := int(b.tao[c])
			var ic := _icona("res://assets/segnalini/tao_%s.webp" % c, q, 38)
			if q == 0:
				ic.modulate.a = 0.28
			tao.add_child(ic)
	else:
		riga.add_child(Stile.etichetta("posseduta" if int(b.qi) <= 0 else "plancia neutra", 18, Stile.TESTO_DEBOLE))
	return pan

func _potere_spento(p: int) -> bool:
	return tavolo._potere_spento(p)

func _icona(percorso: String, n: int, dim: int, mod := Color.WHITE) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	var t := TextureRect.new()
	t.texture = Stile.tex(percorso)
	t.custom_minimum_size = Vector2(dim, dim)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = mod
	h.add_child(t)
	if n >= 0:
		var l := Label.new()
		l.text = str(n)
		l.add_theme_font_override("font", Stile.grassetto())
		l.add_theme_font_size_override("font_size", 22)
		l.custom_minimum_size.x = 14
		h.add_child(l)
	return h

func _domanda() -> void:
	for c in box_domanda.get_children():
		c.queue_free()
	box_domanda.modulate.a = 1.0
	tavolo.evidenzia = []
	if s.esito != "":
		var t := Stile.etichetta("Vittoria!" if s.esito == "vittoria" else "Sconfitta", 34, Stile.ORO, Stile.titolo())
		box_domanda.add_child(t)
		box_domanda.add_child(Stile.paragrafo(s.motivo, 20))
		return
	var d: Dictionary = s.domanda
	if d.is_empty():
		box_domanda.add_child(Stile.etichetta("I fantasmi si muovono...", 24, Stile.SPETTRO, Stile.titolo()))
		return
	var chi := int(d.chi)
	var mio := _mio_posto(chi)
	var nome := _nome_posto(chi) if chi >= 0 else ""
	var testa: Label
	if mio:
		testa = Stile.etichetta("Tocca a te: " + nome, 26, Stile.ORO, Stile.titolo())
	elif chi >= 0 and posti[chi].get("tipo", "") == "remoto":
		testa = Stile.etichetta("Aspettiamo " + str(posti[chi].get("nome", "l'amico")), 26, Stile.SPETTRO, Stile.titolo())
	else:
		testa = Stile.etichetta("Il computer pensa: " + nome, 24, Stile.SPETTRO, Stile.titolo())
	testa.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box_domanda.add_child(testa)
	box_domanda.add_child(Stile.paragrafo(d.testo, 21))
	var opz: Array = d.opzioni
	# sul tavolo si illuminano le scelte che hanno un posto
	var con_posto := []
	for o in opz:
		if o.has("tessera") or o.has("spazio") or o.has("plancia"):
			con_posto.append(o)
	tavolo.evidenzia = con_posto if mio else []
	if not mio:
		return
	_suono("tocca")
	if d.has("carta"):
		var tr := TextureRect.new()
		tr.texture = Stile.carta(int(d.carta))
		tr.custom_minimum_size = Vector2(0, 220)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box_domanda.add_child(tr)
	if d.has("facce"):
		box_domanda.add_child(_riga_dadi(d.facce, 46))
	var mosse := []
	var altre := []
	for o in opz:
		if String(o.id).begins_with("m:") or String(o.id).begins_with("mv:"):
			mosse.append(o)
		else:
			altre.append(o)
	if not mosse.is_empty():
		box_domanda.add_child(Stile.paragrafo("Tocca la tessera dove andare (anche sul tavolo):", 18, Stile.TESTO_DEBOLE))
		var g := GridContainer.new()
		g.columns = 3
		g.add_theme_constant_override("h_separation", 6)
		g.add_theme_constant_override("v_separation", 6)
		var per_t := {}
		for o in mosse:
			per_t[int(o.tessera)] = o
		var qui := int(s.plance[chi].tessera)
		for t in 9:
			var b := Stile.bottone(BREVE.get(s.villaggio[t].id, "?"), 17)
			b.custom_minimum_size = Vector2(110, 48)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.clip_text = true
			if per_t.has(t):
				var o: Dictionary = per_t[t]
				if t == qui:
					b.text = "Resta"
					b.add_theme_stylebox_override("normal", Stile.scatola(Color("1f3a2e"), Stile.GIADA, 8, 2))
				if s.villaggio[t].inf:
					b.text += " (inf.)"
				b.tooltip_text = o.t
				b.pressed.connect(_rispondi.bind(o.id))
			else:
				b.disabled = true
			g.add_child(b)
		box_domanda.add_child(g)
	for o in altre:
		var b := Stile.bottone(o.t, 20)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(160, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if o.has("colore"):
			b.icon = Stile.tex("res://assets/segnalini/tao_%s.webp" % o.colore)
			b.expand_icon = false
			b.add_theme_constant_override("icon_max_width", 34)
		if o.id in ["fine", "basta", "no", "tieni", "fallisce"]:
			b.add_theme_stylebox_override("normal", Stile.scatola(Color("16202e"), Color("4b5d78"), 8, 2))
		b.pressed.connect(_rispondi.bind(o.id))
		box_domanda.add_child(b)

func _riga_dadi(facce: Array, dim: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for f in facce:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(dim, dim)
		var col := Stile.colore(f)
		var st := Stile.scatola(col, Color(0.05, 0.05, 0.05), 8, 3)
		p.add_theme_stylebox_override("panel", st)
		p.tooltip_text = Dati.NOMI_COLORE[f]
		h.add_child(p)
	return h

func _dadi() -> void:
	for c in box_dadi.get_children():
		c.queue_free()
	var dd: Dictionary = s.get("dadi", {})
	if dd.is_empty():
		return
	box_dadi.add_child(Stile.etichetta("Dadi Tao:", 20, Stile.TESTO_DEBOLE))
	box_dadi.add_child(_riga_dadi(dd.get("facce", []), 52))

func _diario() -> void:
	var l: Array = s.diario
	var o := []
	for r in l.slice(maxi(0, l.size() - 120)):
		var t := str(r)
		if t.begins_with("—"):
			o.append("[color=#e2bb63][b]%s[/b][/color]" % t)
		elif t.begins_with("VITTORIA") or t.begins_with("SCONFITTA") or t.begins_with("ATTENZIONE"):
			o.append("[color=#ff7a6e][b]%s[/b][/color]" % t)
		elif "infestata" in t or "infesta il villaggio" in t or "è morto" in t:
			o.append("[color=#9fc4ff]%s[/color]" % t)
		elif "esorcizzato" in t:
			o.append("[color=#8fe0a8]%s[/color]" % t)
		else:
			o.append(t)
	diario.text = "\n".join(o)

# ============================================================ eventi, suoni e animazioni

func _suono(n: String) -> void:
	if rete:
		rete.suono(n)

func _eventi() -> void:
	var ev: Array = s.get("eventi", [])
	for e in ev:
		var n := int(e.get("n", 0))
		if n <= _ultimo_evento:
			continue
		_ultimo_evento = n
		match String(e.e):
			"pesca":
				_mostra_banner(int(e.c))
				_suono("gong" if Dati.e_incarnazione(int(e.c)) else "fantasma")
			"infesta":
				_toast("Infestata: " + Dati.tessera(s.villaggio[int(e.t)].id).get("nome", ""), Stile.SPETTRO)
				_suono("infesta")
			"libera":
				_toast("Liberata: " + Dati.tessera(s.villaggio[int(e.t)].id).get("nome", ""), Stile.VERDE)
			"esorcizza":
				_toast(("Esorcizzato: " if e.modo == "esorcismo" else "All'inferno: ") + Dati.nome(int(e.c)), Stile.VERDE)
				_suono("esorcismo")
			"buddha":
				_toast("Il Buddha ferma " + Dati.nome(int(e.c)), Stile.ORO)
				_suono("esorcismo")
			"dadi":
				_suono("dado")
			"maledizione":
				_toast("Dado della maledizione: " + {"nulla": "nessun effetto", "infesta": "infestazione", "fantasma": "un fantasma", "tao": "via i Tao", "qi": "-1 Qi"}.get(e.f, ""), Stile.ROSSO)
				_suono("maledizione")
			"qi":
				if int(e.d) < 0:
					_suono("qi")
			"morte":
				_toast("È morto il Taoista %s" % Dati.NOMI_COLORE[s.plance[int(e.p)].colore], Stile.ROSSO)
			"turno":
				if segui and s.plance[int(e.p)].taoista:
					tavolo.ruota_verso(int(e.p))

func _mostra_banner(c: int) -> void:
	banner.texture = Stile.carta(c)
	banner.visible = true
	banner.modulate.a = 1.0
	_banner_t = 1.6

func _toast(t: String, col: Color) -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", Stile.scatola(Color(0.04, 0.05, 0.1, 0.9), col, 10, 2))
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := Stile.etichetta(t, 22, col, Stile.grassetto())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	toast_box.add_child(p)
	while toast_box.get_child_count() > 4:
		toast_box.get_child(0).free()
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)

# ============================================================ tocchi sul tavolo

func _toccato(q: Dictionary) -> void:
	if q.is_empty() or s.is_empty():
		return
	var d: Dictionary = s.domanda
	if not d.is_empty() and _mio_posto(int(d.chi)):
		# una scelta che corrisponde al punto toccato?
		var trovate := []
		for o in d.opzioni:
			if q.has("tessera") and o.has("tessera") and int(o.tessera) == int(q.tessera):
				trovate.append(o)
			elif q.has("spazio") and o.has("spazio") and int(o.spazio[0]) == int(q.spazio[0]) and int(o.spazio[1]) == int(q.spazio[1]):
				trovate.append(o)
			elif not q.has("spazio") and q.has("plancia") and o.has("plancia") and not o.has("spazio") and int(o.plancia) == int(q.plancia):
				trovate.append(o)
		if trovate.size() == 1:
			_rispondi(trovate[0].id)
			return
	if q.has("carta"):
		_mostra_info(Testi.carta(int(q.carta)), Stile.carta(int(q.carta)))
	elif q.has("tessera"):
		var v: Dictionary = s.villaggio[int(q.tessera)]
		var t := Dati.tessera(v.id)
		var testo: String = t.get("nome", "") + "\n" + t.get("aiuto", "")
		if v.inf:
			testo += "\nÈ infestata: non dà aiuto finché qualcuno non la libera (Altare Taoista o Yin-Yang)."
		_mostra_info(testo, Stile.tex("res://assets/villaggio/%s.webp" % v.id))
	elif q.has("plancia"):
		var b: Dictionary = s.plance[int(q.plancia)]
		_mostra_info(Testi.potere("%s_%d" % [b.colore, int(b.lato)]), null)

func _sopra(q: Dictionary) -> void:
	if q.has("carta"):
		_mostra_info(Testi.carta(int(q.carta)), Stile.carta(int(q.carta)))

func _mostra_info(testo: String, tex: Texture2D) -> void:
	zoom_tex.visible = tex != null
	zoom_tex.texture = tex
	if tex != null and tex.get_width() == tex.get_height():
		zoom_tex.custom_minimum_size.y = 300
	else:
		zoom_tex.custom_minimum_size.y = minf(466, size.y * 0.8 - 250)
	zoom_testo.text = testo
	zoom_carta.visible = true
	zoom_carta.size = Vector2(330, 0)

# ============================================================ fine partita e regole

func _mostra_finale() -> void:
	if finale:
		return
	_suono("vittoria" if s.esito == "vittoria" else "sconfitta")
	finale = Control.new()
	finale.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	finale.size = size
	add_child(finale)
	var fondo := ColorRect.new()
	fondo.color = Color(0, 0, 0, 0.6)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	finale.add_child(fondo)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	finale.add_child(cc)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(620, 0)
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var vinto: bool = s.esito == "vittoria"
	var t := Stile.etichetta("Il villaggio è salvo!" if vinto else "Il villaggio è perduto", 54, Stile.ORO if vinto else Stile.ROSSO, Stile.titolo())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(Stile.paragrafo(s.motivo, 22))
	var pt: Dictionary = s.get("punteggio", {})
	if not pt.is_empty():
		var righe := ["Vittoria: %d" % int(pt.vittoria), "Qi rimasti: %d" % int(pt.qi), "Carte nel mazzo: %d" % int(pt.mazzo),
			"Taoisti morti: %d" % int(pt.morti), "Tessere infestate: %d" % int(pt.infestate)]
		if int(pt.get("incarnazioni", 0)) != 0:
			righe.append("Incarnazioni: %d" % int(pt.incarnazioni))
		v.add_child(Stile.paragrafo("\n".join(righe), 20, Stile.TESTO_DEBOLE))
		var tot := Stile.etichetta("Punteggio: %d" % int(pt.totale), 34, Stile.TESTO, Stile.titolo())
		tot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tot)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	var b1 := Stile.bottone("Guarda il tavolo", 22)
	b1.pressed.connect(func(): finale.visible = false)
	h.add_child(b1)
	var b2 := Stile.bottone("Torna al menu", 22)
	b2.pressed.connect(func(): esci.emit())
	h.add_child(b2)

func _mostra_regole() -> void:
	if regole:
		regole.queue_free()
	regole = Control.new()
	regole.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	regole.size = size
	add_child(regole)
	var fondo := ColorRect.new()
	fondo.color = Color(0, 0, 0, 0.65)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	regole.add_child(fondo)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	regole.add_child(cc)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(minf(980, size.x - 40), minf(860, size.y - 40))
	cc.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	var t := Stile.etichetta("Come si gioca", 40, Stile.ORO, Stile.titolo())
	v.add_child(t)
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = Testi.REGOLE
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", 21)
	r.add_theme_font_size_override("bold_font_size", 21)
	r.add_theme_font_override("bold_font", Stile.grassetto())
	v.add_child(r)
	var b := Stile.bottone("Chiudi", 22)
	b.pressed.connect(func(): regole.queue_free(); regole = null)
	v.add_child(b)
