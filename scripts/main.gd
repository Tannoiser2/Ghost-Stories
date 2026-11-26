extends Control
## Menu iniziale: nuova partita, continua, gioco online (ospitare o entrare) e regole.

var rete: Rete
var schermo: Control
var partita: Partita
var livello := "iniziazione"
var n_taoisti := 4
var luna := false
var segreto := false
var wf := "ia"                       # chi gioca Wu-Feng in Black Secret
var wf_indulgente := true
var portale := "centro"
var controllo := ["locale", "ia", "ia", "ia"]
var ritmo := 0.7
var online := ""                 # "" sul dispositivo, "ospita" per chi apre la stanza
var codice := ""
var url := ""
var ospiti := {}                 # uid -> nome di chi è entrato nella stanza
var stato_rete: Label
var box_ospiti: VBoxContainer
var salvataggio_remoto := ""
var in_home := false

func _ready() -> void:
	theme = Stile.tema()
	# i pulsanti scattano appena toccati (più affidabile con il tocco su iPad e nel browser)
	get_tree().node_added.connect(func(n):
		if n is BaseButton:
			n.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS)
	rete = Rete.new()
	add_child(rete)
	rete.evento.connect(_evento_rete)
	var p := rete.parametri()
	rete.chiedi_remoto()
	if p.has("stanza"):
		_entra_schermo(str(p["stanza"]))
		return
	if p.has("prova"):
		_prova(str(p.get("prova", "")))
		return
	_home()

func _pulisci() -> void:
	if schermo:
		schermo.queue_free()
		schermo = null
	if partita:
		partita.queue_free()
		partita = null

func _base() -> Control:
	_pulisci()
	in_home = false
	schermo = Control.new()
	schermo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(schermo)
	var f := ColorRect.new()
	f.color = Stile.FONDO
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	schermo.add_child(f)
	# la copertina del regolamento: a sinistra (in alto se lo schermo è verticale), intera
	var img := TextureRect.new()
	img.texture = Stile.tex("res://assets/img/sfondo.webp")
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var vert := size.y > size.x
	var lato := minf(size.y, size.x * 0.55) if not vert else minf(size.x, size.y * 0.45)
	img.position = Vector2(maxf(0.0, size.x * 0.27 - lato / 2.0), (size.y - lato) / 2.0) if not vert else Vector2((size.x - lato) / 2.0, 0)
	img.size = Vector2(lato, lato)
	schermo.add_child(img)
	var sfuma := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.03, 0.07, 0.0))
	g.set_color(1, Color(0.03, 0.03, 0.07, 1.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.5) if not vert else Vector2(0.5, 0)
	gt.fill_to = Vector2(1, 0.5) if not vert else Vector2(0.5, 1)
	sfuma.texture = gt
	sfuma.position = img.position + (Vector2(lato * 0.75, 0) if not vert else Vector2(0, lato * 0.75))
	sfuma.size = Vector2(lato * 0.25, lato) if not vert else Vector2(lato, lato * 0.25)
	sfuma.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	schermo.add_child(sfuma)
	return schermo

## Il pannello del menu, a destra (o al centro in verticale)
func _pannello(larghezza := 640.0) -> VBoxContainer:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vert := size.y > size.x
	m.add_theme_constant_override("margin_left", 40 if vert else int(size.x * 0.52))
	m.add_theme_constant_override("margin_right", 40)
	m.add_theme_constant_override("margin_top", int(size.y * 0.42) if vert else 40)
	m.add_theme_constant_override("margin_bottom", 40)
	schermo.add_child(m)
	var cc := CenterContainer.new()
	m.add_child(cc)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(minf(larghezza, size.x - 80), 0)
	cc.add_child(p)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, minf(size.y * (0.5 if vert else 0.86), 940))
	p.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 14)
	sc.add_child(v)
	# il pannello è alto quanto il contenuto, fino al massimo dello schermo
	var massimo := sc.custom_minimum_size.y
	var adatta := func():
		if is_instance_valid(sc) and is_instance_valid(v):
			sc.custom_minimum_size.y = minf(v.get_combined_minimum_size().y + 4, massimo)
	v.minimum_size_changed.connect(adatta)
	adatta.call_deferred()
	return v

func _titolo(v: VBoxContainer, t: String, dim := 56) -> void:
	var l := Stile.etichetta(t, dim, Stile.ORO, Stile.titolo())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0.2, 0.02, 0.02))
	v.add_child(l)

# ------------------------------------------------------------------ home

func _home() -> void:
	online = ""
	_base()
	in_home = true
	var v := _pannello(560)
	_titolo(v, "Ghost Stories", 72)
	v.add_child(Stile.paragrafo("Wu-Feng, Signore dei Nove Inferi, vuole riprendersi le sue ceneri sepolte nel villaggio. I Taoisti lo difendono insieme: da soli, con compagni guidati dal computer o con gli amici online.", 21, Stile.TESTO))
	var salvato := rete.carica(Partita.CHIAVE_SALVATAGGIO)
	if salvato == "" and salvataggio_remoto != "":
		salvato = salvataggio_remoto
	if salvato != "":
		var bc := Stile.bottone_scelta("Continua la partita", true, 28)
		bc.custom_minimum_size.y = 64
		bc.pressed.connect(func(): _continua(salvato))
		v.add_child(bc)
	for x in [["Nuova partita", _nuova], ["Gioca online con gli amici", _online], ["Come si gioca", _regole]]:
		var b := Stile.bottone(x[0], 28)
		b.custom_minimum_size.y = 64
		b.pressed.connect(x[1])
		v.add_child(b)
	var sch := Stile.bottone("Schermo intero", 20)
	sch.pressed.connect(func(): rete.schermo_intero())
	v.add_child(sch)
	v.add_child(Stile.paragrafo("Gioco di Antoine Bauza, illustrazioni di Pierô (Repos Production). Versione digitale per la ludoteca, con la grafica originale e i testi in italiano.", 16, Stile.TESTO_DEBOLE))

# ------------------------------------------------------------------ nuova partita

func _nuova() -> void:
	_impostazioni(false)

func _online() -> void:
	_base()
	var v := _pannello(600)
	_titolo(v, "Gioco online", 56)
	v.add_child(Stile.paragrafo("Chi ospita sceglie il livello e i posti; gli amici entrano con il codice della stanza e giocano ognuno il proprio Taoista dal suo dispositivo. I posti senza amico li gioca il computer.", 20))
	var b1 := Stile.bottone("Ospita una partita", 26)
	b1.custom_minimum_size.y = 60
	b1.pressed.connect(func(): _impostazioni(true))
	v.add_child(b1)
	v.add_child(Stile.etichetta("Entra nella stanza di un amico", 24, Stile.ORO, Stile.titolo()))
	var cod := LineEdit.new()
	cod.placeholder_text = "Codice (4 lettere)"
	cod.max_length = 4
	cod.custom_minimum_size = Vector2(200, 56)
	v.add_child(cod)
	var nome := LineEdit.new()
	nome.placeholder_text = "Il tuo nome"
	nome.max_length = 16
	nome.text = rete.carica("ghoststories_nome")
	nome.custom_minimum_size = Vector2(200, 56)
	v.add_child(nome)
	var b2 := Stile.bottone("Entra", 26)
	b2.custom_minimum_size.y = 60
	b2.pressed.connect(func():
		if cod.text.strip_edges().length() == 4:
			rete.salva("ghoststories_nome", nome.text.strip_edges())
			_entra(cod.text.strip_edges().to_upper(), nome.text.strip_edges()))
	v.add_child(b2)
	var ind := Stile.bottone("Indietro", 22)
	ind.pressed.connect(_home)
	v.add_child(ind)

func _impostazioni(ospita: bool) -> void:
	online = "ospita" if ospita else ""
	_base()
	var v := _pannello(680)
	_titolo(v, "Ospita una partita" if ospita else "Nuova partita", 52)
	v.add_child(Stile.etichetta("Livello", 26, Stile.ORO, Stile.titolo()))
	var hl := GridContainer.new()
	hl.columns = 2
	hl.add_theme_constant_override("h_separation", 8)
	hl.add_theme_constant_override("v_separation", 8)
	v.add_child(hl)
	var desc := {"iniziazione": "4 Qi, un Tao nero in più, si perde con 4 tessere infestate",
		"normale": "3 Qi, si perde con 3 tessere infestate",
		"incubo": "come Normale, ma Wu-Feng si incarna più volte",
		"inferno": "come Incubo, senza Yin-Yang all'inizio"}
	for l in Dati.LIVELLI:
		var b := Stile.bottone_scelta(Dati.NOMI_LIVELLO[l], l == livello, 22)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = desc[l]
		b.pressed.connect(func(): livello = l; _impostazioni(ospita))
		hl.add_child(b)
	v.add_child(Stile.paragrafo(desc[livello], 18, Stile.TESTO_DEBOLE))
	v.add_child(Stile.etichetta("Taoisti in gioco", 26, Stile.ORO, Stile.titolo()))
	var hn := HBoxContainer.new()
	hn.add_theme_constant_override("separation", 8)
	v.add_child(hn)
	for n in [1, 2, 3, 4]:
		var b := Stile.bottone_scelta(str(n), n == n_taoisti, 24)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): n_taoisti = n; _impostazioni(ospita))
		hn.add_child(b)
	v.add_child(Stile.paragrafo("Con meno di quattro Taoisti le plance libere diventano neutre e si ricevono i segnalini potere.", 17, Stile.TESTO_DEBOLE))
	v.add_child(Stile.etichetta("Espansioni", 26, Stile.ORO, Stile.titolo()))
	var he := HBoxContainer.new()
	he.add_theme_constant_override("separation", 8)
	v.add_child(he)
	var bl := Stile.bottone_scelta("White Moon: " + ("sì" if luna else "no"), luna, 22)
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bl.pressed.connect(func(): luna = not luna; _impostazioni(ospita))
	he.add_child(bl)
	var bs := Stile.bottone_scelta("Black Secret: " + ("sì" if segreto else "no"), segreto, 22)
	bs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bs.pressed.connect(func(): segreto = not segreto; _impostazioni(ospita))
	he.add_child(bs)
	if segreto:
		v.add_child(Stile.paragrafo("Wu-Feng è un giocatore: decide dove vanno i fantasmi, evoca demoni che scavano le catacombe in cerca delle sue urne e lancia maledizioni. I Taoisti scendono con le scale a combattere i demoni; il Qi perso alimenta i Mantra di Sangue.", 17, Stile.TESTO_DEBOLE))
		var hw := HBoxContainer.new()
		hw.add_theme_constant_override("separation", 8)
		v.add_child(hw)
		var lw := Stile.etichetta("Wu-Feng", 22)
		lw.custom_minimum_size.x = 130
		lw.size_flags_horizontal = Control.SIZE_FILL
		hw.add_child(lw)
		var sw := [["ia", "Computer"], ["locale", "Tu"]]
		if ospita:
			sw.append(["remoto", "Amico online"])
		if not ospita and wf == "remoto":
			wf = "ia"
		for c in sw:
			var b := Stile.bottone_scelta(c[1], wf == c[0], 20)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(func(): wf = c[0]; _impostazioni(ospita))
			hw.add_child(b)
		if wf == "ia":
			var hd := HBoxContainer.new()
			hd.add_theme_constant_override("separation", 8)
			v.add_child(hd)
			var ld := Stile.etichetta("Carattere", 22)
			ld.custom_minimum_size.x = 130
			ld.size_flags_horizontal = Control.SIZE_FILL
			hd.add_child(ld)
			for c in [[true, "Indulgente"], [false, "Spietato"]]:
				var b := Stile.bottone_scelta(c[1], wf_indulgente == c[0], 20)
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				b.pressed.connect(func(): wf_indulgente = c[0]; _impostazioni(ospita))
				hd.add_child(b)
	if luna:
		v.add_child(Stile.paragrafo("Villici da portare al Portale, Su-Ling, Cristalli di Luna, Barriera Mistica, artefatti e 16 nuove carte. Si perde anche con 12 villici morti.", 17, Stile.TESTO_DEBOLE))
		var hp := HBoxContainer.new()
		hp.add_theme_constant_override("separation", 8)
		v.add_child(hp)
		var lp := Stile.etichetta("Portale", 22)
		lp.custom_minimum_size.x = 130
		hp.add_child(lp)
		for e in [["centro", "Al centro"], ["lato", "Sul lato (+2)"], ["angolo", "In un angolo (+4)"]]:
			var b := Stile.bottone_scelta(e[1], portale == e[0], 18)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(func(): portale = e[0]; _impostazioni(ospita))
			hp.add_child(b)
	v.add_child(Stile.etichetta("Chi gioca ogni Taoista", 26, Stile.ORO, Stile.titolo()))
	var scelte := [["locale", "Tu"], ["ia", "Computer"]]
	if ospita:
		scelte.append(["remoto", "Amico online"])
	for i in n_taoisti:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		v.add_child(h)
		var l := Stile.etichetta("Taoista %d" % (i + 1), 22)
		l.custom_minimum_size.x = 130
		l.size_flags_horizontal = Control.SIZE_FILL
		h.add_child(l)
		for c in scelte:
			if ospita and i == 0 and c[0] == "remoto":
				continue
			var b := Stile.bottone_scelta(c[1], controllo[i] == c[0], 20)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(func(): controllo[i] = c[0]; _impostazioni(ospita))
			h.add_child(b)
	if not ospita:
		for i in 4:
			if controllo[i] == "remoto":
				controllo[i] = "ia"
	v.add_child(Stile.paragrafo("I colori e i lati delle plance sono estratti a caso, come nel gioco da tavolo. Chi gioca sul dispositivo può essere più di uno: ci si passa il tablet.", 17, Stile.TESTO_DEBOLE))
	v.add_child(Stile.etichetta("Ritmo del computer", 26, Stile.ORO, Stile.titolo()))
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 8)
	v.add_child(hr)
	for r in [[1.2, "Lento"], [0.7, "Normale"], [0.25, "Veloce"]]:
		var b := Stile.bottone_scelta(r[1], is_equal_approx(ritmo, r[0]), 20)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): ritmo = r[0]; _impostazioni(ospita))
		hr.add_child(b)
	var vai := Stile.bottone_scelta("Apri la stanza" if ospita else "Inizia", true, 30)
	vai.custom_minimum_size.y = 66
	vai.pressed.connect(func():
		if ospita:
			_apri_stanza()
		else:
			_inizia())
	v.add_child(vai)
	var ind := Stile.bottone("Indietro", 22)
	ind.pressed.connect(_home)
	v.add_child(ind)

func _posti() -> Array:
	var p := []
	for i in 4:
		p.append({"tipo": "neutra", "nome": ""})
	var sedi: Array = {1: [0], 2: [0, 2], 3: [0, 1, 2], 4: [0, 1, 2, 3]}[n_taoisti]
	for k in sedi.size():
		p[sedi[k]] = {"tipo": controllo[k], "nome": "", "uid": ""}
	p.append({"tipo": wf if segreto else "neutra", "nome": "Wu-Feng", "uid": ""})
	return p

func _inizia() -> void:
	var p := _posti()
	_avvia_partita(func(pt: Partita): pt.avvia({"livello": livello, "taoisti": n_taoisti, "luna_bianca": luna, "portale": portale, "segreto_nero": segreto, "wf_indulgente": wf_indulgente and wf == "ia"}, p))

func _avvia_partita(cosa: Callable) -> void:
	_pulisci()
	partita = Partita.new()
	partita.rete = rete
	partita.ritmo = ritmo
	partita.online = online == "ospita"
	add_child(partita)
	partita.esci.connect(func():
		if online == "ospita":
			rete.chiudi()
		_home())
	cosa.call(partita)

func _continua(testo: String) -> void:
	_avvia_partita(func(pt: Partita):
		if not pt.riprendi(testo):
			_home())

# ------------------------------------------------------------------ online: chi ospita

func _apri_stanza() -> void:
	ospiti = {}
	_base()
	var v := _pannello(640)
	_titolo(v, "La stanza", 52)
	stato_rete = Stile.paragrafo("Apro la stanza...", 22)
	v.add_child(stato_rete)
	box_ospiti = VBoxContainer.new()
	box_ospiti.add_theme_constant_override("separation", 6)
	v.add_child(box_ospiti)
	var vai := Stile.bottone_scelta("Inizia la partita", true, 28)
	vai.custom_minimum_size.y = 62
	vai.pressed.connect(_inizia_online)
	v.add_child(vai)
	var ind := Stile.bottone("Indietro", 22)
	ind.pressed.connect(func(): rete.chiudi(); _home())
	v.add_child(ind)
	rete.avvia()
	_aggiorna_stanza()

func _aggiorna_stanza() -> void:
	if box_ospiti == null or not is_instance_valid(box_ospiti):
		return
	for c in box_ospiti.get_children():
		c.queue_free()
	if codice != "":
		var cod := Stile.etichetta("Codice: " + codice, 52, Stile.ORO, Stile.titolo())
		cod.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box_ospiti.add_child(cod)
		var q := _qr(url)
		if q:
			var cc := CenterContainer.new()
			cc.add_child(q)
			box_ospiti.add_child(cc)
		box_ospiti.add_child(Stile.paragrafo("Gli amici aprono il gioco e scrivono il codice in «Gioca online», oppure inquadrano il QR.", 18, Stile.TESTO_DEBOLE))
	var p := _posti()
	var liberi := []
	for i in p.size():
		if p[i].tipo == "remoto":
			liberi.append(i)
	var k := 0
	for uid in ospiti:
		var testo := "%s - " % ospiti[uid]
		testo += (("Wu-Feng" if liberi[k] == 4 else "Taoista %d" % (liberi[k] + 1)) if k < liberi.size() else "spettatore")
		box_ospiti.add_child(Stile.etichetta(testo, 22, Stile.VERDE))
		k += 1
	if liberi.size() > ospiti.size():
		box_ospiti.add_child(Stile.paragrafo("Posti per amici ancora liberi: %d (se nessuno entra li gioca il computer)." % (liberi.size() - ospiti.size()), 18, Stile.TESTO_DEBOLE))
	rete.stato({"tipo": "attesa", "ospiti": ospiti})

func _qr(testo: String) -> Control:
	var bit := rete.qr(testo)
	if bit == "":
		return null
	var n := int(sqrt(bit.length()))
	var img := Image.create(n + 4, n + 4, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for y in n:
		for x in n:
			if bit[y * n + x] == "1":
				img.set_pixel(x + 2, y + 2, Color.BLACK)
	var t := TextureRect.new()
	t.texture = ImageTexture.create_from_image(img)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.custom_minimum_size = Vector2(220, 220)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	return t

func _inizia_online() -> void:
	var p := _posti()
	var uids: Array = ospiti.keys()
	var k := 0
	for i in p.size():
		if p[i].tipo == "remoto":
			if k < uids.size():
				p[i].uid = uids[k]
				p[i].nome = ospiti[uids[k]]
				k += 1
			else:
				p[i].tipo = "ia"
	_avvia_partita(func(pt: Partita): pt.avvia({"livello": livello, "taoisti": n_taoisti, "luna_bianca": luna, "portale": portale, "segreto_nero": segreto, "wf_indulgente": wf_indulgente and wf == "ia"}, p))

# ------------------------------------------------------------------ online: chi entra

func _entra_schermo(c: String) -> void:
	_base()
	var v := _pannello(560)
	_titolo(v, "Entra nella stanza " + c, 44)
	var nome := LineEdit.new()
	nome.placeholder_text = "Il tuo nome"
	nome.max_length = 16
	nome.text = rete.carica("ghoststories_nome")
	nome.custom_minimum_size = Vector2(200, 56)
	v.add_child(nome)
	var b := Stile.bottone_scelta("Entra", true, 28)
	b.pressed.connect(func():
		rete.salva("ghoststories_nome", nome.text.strip_edges())
		_entra(c, nome.text.strip_edges()))
	v.add_child(b)

func _entra(c: String, nome: String) -> void:
	if nome == "":
		nome = "Taoista"
	_base()
	var v := _pannello(560)
	_titolo(v, "Stanza " + c, 52)
	stato_rete = Stile.paragrafo("Entro nella stanza...", 22)
	v.add_child(stato_rete)
	var ind := Stile.bottone("Esci", 22)
	ind.pressed.connect(func(): rete.chiudi(); _home())
	v.add_child(ind)
	rete.entra(c, nome)

func _evento_rete(e: Dictionary) -> void:
	match String(e.get("e", "")):
		"stanza":
			codice = e.get("codice", "")
			url = e.get("url", "")
			if stato_rete and is_instance_valid(stato_rete):
				stato_rete.text = "Stanza aperta. Aspetto gli amici..."
			_aggiorna_stanza()
		"entra":
			var uid: String = e.get("uid", "")
			if partita == null:
				ospiti[uid] = str(e.get("nome", "Amico"))
				_aggiorna_stanza()
			elif partita.m:
				# chi rientra riprende il suo posto
				partita._dopo_cambio()
		"esce":
			if partita == null:
				ospiti.erase(e.get("uid", ""))
				_aggiorna_stanza()
		"azione":
			if partita:
				partita.azione_remota(str(e.get("uid", "")), str(e.get("p", "")))
		"dentro":
			if stato_rete and is_instance_valid(stato_rete):
				stato_rete.text = "Sei nella stanza. Aspetta che chi ospita inizi la partita."
		"stato":
			var j: String = e.get("j", "")
			var d = JSON.parse_string(j)
			if d is Dictionary and d.get("tipo", "") == "partita":
				if partita == null:
					_pulisci()
					partita = Partita.new()
					partita.rete = rete
					partita.avvia_ospite()
					add_child(partita)
					partita.esci.connect(func(): rete.chiudi(); _home())
				partita.ricevi_stato(j)
			elif d is Dictionary and d.get("tipo", "") == "attesa":
				if stato_rete and is_instance_valid(stato_rete):
					var nomi: Array = d.get("ospiti", {}).values()
					stato_rete.text = "Sei nella stanza con: %s. Aspetta che chi ospita inizi la partita." % ", ".join(nomi)
		"errore":
			if stato_rete and is_instance_valid(stato_rete):
				stato_rete.text = "Errore: " + str(e.get("msg", ""))
		"salvataggio":
			salvataggio_remoto = str(e.get("j", ""))
			if in_home and partita == null and rete.carica(Partita.CHIAVE_SALVATAGGIO) == "" and salvataggio_remoto != "":
				_home()

# ------------------------------------------------------------------ regole

func _regole() -> void:
	_base()
	var v := _pannello(860)
	_titolo(v, "Come si gioca", 52)
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.text = Testi.REGOLE
	r.add_theme_font_size_override("normal_font_size", 20)
	r.add_theme_font_size_override("bold_font_size", 20)
	r.add_theme_font_override("bold_font", Stile.grassetto())
	v.add_child(r)
	var ind := Stile.bottone("Indietro", 22)
	ind.pressed.connect(_home)
	v.add_child(ind)

# ------------------------------------------------------------------ prove (screenshot automatici)

func _prova(tipo: String) -> void:
	livello = "normale"
	n_taoisti = 4 if tipo != "solo" else 1
	controllo = ["locale", "ia", "ia", "ia"]
	ritmo = 0.05
	_inizia()
