class_name Motore
extends RefCounted
## Il motore delle regole di Ghost Stories (gioco base, livelli Iniziazione, Normale, Incubo e Inferno).
##
## Tutto lo stato sta in `s` (un dizionario che si salva in JSON). Le regole avanzano da sole e si
## fermano quando serve una scelta: allora `s.domanda` dice chi deve scegliere (l'indice della plancia
## del Taoista) e quali opzioni ha. `rispondi(id)` dà la scelta e riparte.
##
## Le regole sono una pila di compiti (`s.pila`): ogni compito può aggiungerne altri sopra di sé,
## così gli effetti a catena (un fantasma che porta un fantasma che fa tirare la maledizione...)
## si risolvono nell'ordine giusto e lo stato resta sempre salvabile.

var s := {}

const POSIZIONI := 4
const QI_TOTALI := 20
const TAO_PER_COLORE := 4

# ============================================================ avvio

## cfg: livello (iniziazione/normale/incubo/inferno), taoisti (1-4), seme (facoltativo)
func nuova_partita(cfg: Dictionary) -> void:
	var seme := int(cfg.get("seme", 0))
	if seme == 0:
		seme = randi() % 2000000000 + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = seme
	var livello: String = cfg.get("livello", "iniziazione")
	var n := clampi(int(cfg.get("taoisti", 4)), 1, 4)
	s = {
		"versione": 1, "seme": seme, "rng": str(rng.state), "livello": livello, "n_taoisti": n,
		"plance": [], "villaggio": [], "cerchio": "", "mazzo": [], "scarti": [], "rimossi": 0,
		"riserva_tao": {}, "buddha_tempio": 2, "poteri_centro": 0,
		"mantra": {"p": -1, "s": -1, "perso": false},
		"inc_totali": 1, "inc_sconfitte": 0, "turno_di": 0, "giro": 1, "ultimo_taoista": 0,
		"pila": [], "domanda": {}, "esito": "", "motivo": "", "diario": [], "eventi": [], "dadi": {},
		"n_evento": 0, "punteggio": {},
	}
	for c in Dati.COLORI_TAO:
		s.riserva_tao[c] = TAO_PER_COLORE
	# villaggio: le 9 tessere in un quadrato 3 x 3, a caso
	var tess: Array = Dati.TESSERE.duplicate()
	_mescola(tess)
	for id in tess:
		s.villaggio.append({"id": id, "inf": false})
	# plance: colori e lati a caso; i Taoisti si siedono uno di fronte all'altro se sono in due
	var colori: Array = Dati.COLORI_PLANCIA.duplicate()
	_mescola(colori)
	var posti: Array = {1: [0], 2: [0, 2], 3: [0, 1, 2], 4: [0, 1, 2, 3]}[n]
	var qi_iniziali := 4 if livello == "iniziazione" else 3
	for i in POSIZIONI:
		var col: String = colori[i]
		var lato := _int(rng_int(2))
		if n == 1 and col == "rosso":
			lato = 1  # nel solitario la plancia rossa mostra la Danza delle Vette (si vola)
		var b := {
			"pos": i, "colore": col, "lato": lato, "taoista": i in posti, "vivo": i in posti,
			"qi": qi_iniziali if i in posti else 3, "tao": {}, "yinyang": false, "buddha": 0,
			"poteri": 0, "tessera": 4, "spazi": [],
		}
		for c in Dati.COLORI_TAO:
			b.tao[c] = 0
		for k in 3:
			b.spazi.append({"c": 0, "inf": -1, "buddha": false, "dado": false})
		if b.taoista:
			b.yinyang = livello != "inferno"
			if n == 1:
				for c in ["blu", "verde", "giallo", "rosso"]:
					_prendi_tao(b, c)
				b.poteri = 3
			else:
				_prendi_tao(b, col)
				if livello == "iniziazione":
					_prendi_tao(b, "nero")
				if n < 4:
					b.poteri = 1
		s.plance.append(b)
	# il mazzo dei fantasmi
	var fantasmi := []
	for k in range(1, 56):
		fantasmi.append(k)
	_mescola(fantasmi)
	var togli: int = {1: 15, 2: 10, 3: 5, 4: 0}[n]
	s.rimossi = togli
	if cfg.get("luna_bianca", false):
		_prepara_luna(cfg, posti)
		fantasmi = _mazzo_luna(fantasmi)
	if cfg.get("segreto_nero", false):
		fantasmi = _prepara_segreto(livello, n, fantasmi)
		togli = 0
		s.rimossi = 0
	fantasmi = fantasmi.slice(togli)
	var inc := []
	for k in range(56, 66):
		inc.append(k)
	if s.get("luna", false):
		for k in range(82, 88):
			inc.append(k)
	_mescola(inc)
	var n_inc := 1
	if livello in ["incubo", "inferno"]:
		n_inc = 4 if n >= 3 else 3
	s.inc_totali = n_inc
	if segreto():
		inc = []
		for k in n_inc:
			inc.append(300)
	# dal fondo: 10 fantasmi, un'incarnazione, 10 fantasmi, un'incarnazione... poi il resto in cima
	var fondo := []
	for k in n_inc:
		for j in 10:
			fondo.append(fantasmi.pop_back())
		fondo.append(inc[k])
	fondo.reverse()
	s.mazzo = fantasmi + fondo  # indice 0 = la carta in cima
	_diario("Inizia la partita: livello %s, %d Taoist%s%s." % [Dati.NOMI_LIVELLO[livello], n, "a" if n == 1 else "i", ", con White Moon" if s.get("luna", false) else ""])
	if segreto():
		_diario("Black Secret: Wu-Feng è in gioco con demoni, maledizioni e catacombe.")
	# chi comincia: il primo Taoista
	_poi([{"k": "turno", "p": posti[0]}])
	avanza()

# ============================================================ casualità (stato salvabile)

func rng_int(n: int) -> int:
	var r := RandomNumberGenerator.new()
	r.state = int(s.get("rng", "1"))
	var v := r.randi() % maxi(n, 1)
	s.rng = str(r.state)
	return v

func _mescola(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng_int(i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

func _tira_tao(n: int) -> Array:
	var f := []
	for i in n:
		f.append(Dati.FACCE_TAO[rng_int(6)])
	return f

# ============================================================ aiuti di lettura

static func _int(v) -> int:
	return int(v)

func plancia(p: int) -> Dictionary:
	return s.plance[p]

func spazio(p: int, k: int) -> Dictionary:
	return s.plance[p].spazi[k]

func nome_plancia(p: int) -> String:
	var b := plancia(p)
	if b.taoista:
		return "Taoista %s" % Dati.NOMI_COLORE[b.colore]
	return "plancia neutra %s" % _femminile(b.colore)

## "plancia del Taoista rosso" oppure "plancia neutra rossa"
func plancia_di(p: int) -> String:
	var b := plancia(p)
	if b.taoista:
		return "plancia del Taoista %s" % Dati.NOMI_COLORE[b.colore]
	return "plancia neutra %s" % _femminile(b.colore)

static func _maiuscola(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1)

static func _femminile(c: String) -> String:
	return {"rosso": "rossa", "giallo": "gialla", "nero": "nera"}.get(c, Dati.NOMI_COLORE.get(c, c))

func nome_tessera(t: int) -> String:
	return Dati.tessera(s.villaggio[t].id).get("nome", "?")

func indice_tessera(id: String) -> int:
	for i in 9:
		if s.villaggio[i].id == id:
			return i
	return -1

func limite_infestate() -> int:
	return 4 if s.livello == "iniziazione" else 3

func n_infestate() -> int:
	var n := 0
	for v in s.villaggio:
		if v.inf:
			n += 1
	return n

## Le tre tessere davanti allo spazio k della plancia p (dalla più vicina alla più lontana)
static func linea(p: int, k: int) -> Array:
	var rc := []
	match p:
		0: rc = [[2, k], [1, k], [0, k]]
		1: rc = [[k, 0], [k, 1], [k, 2]]
		2: rc = [[0, 2 - k], [1, 2 - k], [2, 2 - k]]
		_: rc = [[2 - k, 2], [2 - k, 1], [2 - k, 0]]
	var o := []
	for x in rc:
		o.append(x[0] * 3 + x[1])
	return o

## Gli spazi fantasma che una tessera ha di fronte (angoli due, lati uno, centro nessuno)
static func fronte(t: int) -> Array:
	var o := []
	for p in POSIZIONI:
		for k in 3:
			if linea(p, k)[0] == t:
				o.append([p, k])
	return o

static func adiacenti(t: int) -> Array:
	var o := []
	var r := t / 3
	var c := t % 3
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var rr: int = r + dr
			var cc: int = c + dc
			if rr >= 0 and rr < 3 and cc >= 0 and cc < 3:
				o.append(rr * 3 + cc)
	return o

func opposto(p: int, k: int) -> Array:
	return [(p + 2) % 4, 2 - k]

func fantasmi_in_gioco() -> Array:
	var o := []
	for p in POSIZIONI:
		for k in 3:
			if int(spazio(p, k).c) > 0:
				o.append([p, k])
	return o

func carta_in_gioco(n: int) -> bool:
	for x in fantasmi_in_gioco():
		if int(spazio(x[0], x[1]).c) == n:
			return true
	return false

func effetto_in_gioco(gruppo: String, eff: String) -> bool:
	for x in fantasmi_in_gioco():
		if gruppo == "arrivo" and spazio(x[0], x[1]).get("armatura", false):
			continue
		if Dati.ha(int(spazio(x[0], x[1]).c), gruppo, eff):
			return true
	return false

func tao_bloccati() -> bool:
	return effetto_in_gioco("arrivo", "notao")

func poteri_bloccati() -> bool:
	return effetto_in_gioco("permanente", "nopoteri")

func bianco_nullo() -> bool:
	return effetto_in_gioco("permanente", "bianco_nullo")

func potere_spento(p: int) -> bool:
	for k in 3:
		var c := int(spazio(p, k).c)
		if c > 0 and Dati.ha(c, "arrivo", "potere") and not spazio(p, k).get("armatura", false):
			return true
	return poteri_bloccati()

## Il potere della plancia del Taoista è utilizzabile da lui?
func potere(p: int, chiave: String) -> bool:
	var b := plancia(p)
	if not b.taoista or not b.vivo:
		return false
	if "%s_%d" % [b.colore, int(b.lato)] != chiave:
		if fratello(p) and chiave_potere((p + 2) % POSIZIONI) == chiave:
			return not potere_spento(p)
		return false
	return not potere_spento(p)

func chiave_potere(p: int) -> String:
	var b := plancia(p)
	return "%s_%d" % [b.colore, int(b.lato)]

func dadi_disponibili() -> int:
	var n := 3
	for x in fantasmi_in_gioco():
		if spazio(x[0], x[1]).dado:
			n -= 1
	return maxi(n, 0)

func taoisti_vivi() -> Array:
	var o := []
	for p in POSIZIONI:
		if plancia(p).taoista and plancia(p).vivo:
			o.append(p)
	return o

func taoisti_morti() -> Array:
	var o := []
	for p in POSIZIONI:
		if plancia(p).taoista and not plancia(p).vivo:
			o.append(p)
	return o

func qi_in_riserva() -> int:
	var n := QI_TOTALI - qi_sui_mantra()
	for b in s.plance:
		n -= int(b.qi)
	return maxi(n, 0)

## Chi decide quando la scelta è di gruppo o tocca a una plancia neutra
func decisore(p: int) -> int:
	if p == WU:
		return WU
	if p >= 0 and p < POSIZIONI and plancia(p).taoista and plancia(p).vivo:
		return p
	var vivi := taoisti_vivi()
	if vivi.is_empty():
		return -1
	var u := int(s.ultimo_taoista)
	for i in POSIZIONI:
		var q := (u + i) % POSIZIONI
		if q in vivi:
			return q
	return vivi[0]

## Poteri delle plance neutre utilizzabili da p con i segnalini potere (chiave colore_lato)
func poteri_neutri(p: int, usati: Array) -> Array:
	var o := []
	if int(plancia(p).poteri) <= 0 or poteri_bloccati():
		return o
	for q in POSIZIONI:
		var b := plancia(q)
		if b.taoista or int(b.qi) <= 0 or potere_spento(q):
			continue
		if b.colore in usati:
			continue
		o.append(chiave_potere(q))
	return o

func _usa_segnalino(p: int, colore: String, y: Dictionary) -> void:
	plancia(p).poteri = int(plancia(p).poteri) - 1
	s.poteri_centro = int(s.poteri_centro) + 1
	y.neutri.append(colore)
	_diario("%s usa un segnalino potere: %s." % [nome_plancia(p), Dati.potere(_chiave_neutra(colore)).get("nome", "")])

func _chiave_neutra(colore: String) -> String:
	for q in POSIZIONI:
		if plancia(q).colore == colore:
			return chiave_potere(q)
	return ""

# ============================================================ requisiti per esorcizzare

## Resistenza effettiva (dizionario colore -> quanti) del fantasma nello spazio, senza il mantra
func requisito(p: int, k: int) -> Dictionary:
	var c := int(spazio(p, k).c)
	var r := Dati.resistenza(c)
	if r.has("plancia"):
		r = {plancia(p).colore: int(r["plancia"])}
	var cer: String = s.cerchio
	if cer != "" and r.has(cer):
		r[cer] = maxi(0, int(r[cer]) - 1)
	return r

func ha_mantra(p: int, k: int) -> bool:
	return int(s.mantra.p) == p and int(s.mantra.s) == k

func esorcizzabile(p: int, k: int) -> bool:
	var c := int(spazio(p, k).c)
	if c <= 0:
		return false
	if Dati.ha(c, "permanente", "ululante"):
		var o := opposto(p, k)
		if int(spazio(o[0], o[1]).c) > 0:
			return false
	if Dati.ha(c, "permanente", "inafferrabile") and not spazio(p, k).buddha:
		return false
	return true

## Segnalini Tao utilizzabili da p (i suoi e quelli dei Taoisti sulla stessa tessera)
func tao_disponibili(p: int) -> Dictionary:
	var o := {}
	for c in Dati.COLORI_TAO:
		o[c] = 0
	o["cristalli"] = 0
	var t := int(plancia(p).tessera)
	for q in taoisti_vivi():
		if int(plancia(q).tessera) == t and sotto(q) == sotto(p):
			o["cristalli"] += int(plancia(q).get("cristalli", 0))
			if not tao_bloccati():
				for c in Dati.COLORI_TAO:
					o[c] += int(plancia(q).tao[c])
	return o

## Per un gruppo di fantasmi (lista di [p,k]) e le facce dei dadi: quanti segnalini servono per colore,
## oppure {} se non basta. "_ok" vale true se si riesce.
func costo(bersagli: Array, facce: Array, disp: Dictionary) -> Dictionary:
	var mantra_opz := [""]
	for x in bersagli:
		if ha_mantra(x[0], x[1]):
			mantra_opz = []
			for c in requisito(x[0], x[1]):
				mantra_opz.append("%d:%d:%s" % [x[0], x[1], c])
	var migliore := {}
	for mo in mantra_opz:
		var r := _costo_con(bersagli, facce, disp, mo)
		if r.get("_ok", false):
			if migliore.is_empty() or int(r["_tot"]) < int(migliore["_tot"]):
				migliore = r
	return migliore

func _costo_con(bersagli: Array, facce: Array, disp: Dictionary, mantra: String) -> Dictionary:
	var dadi := {}
	var bianchi := 0
	for f in facce:
		if f == "bianco":
			if not bianco_nullo():
				bianchi += 1
		else:
			dadi[f] = int(dadi.get(f, 0)) + 1
	var req := {}
	var solo_tao := {}
	for x in bersagli:
		var r := requisito(x[0], x[1])
		if mantra != "":
			var pz := mantra.split(":")
			if int(pz[0]) == int(x[0]) and int(pz[1]) == int(x[1]) and r.has(pz[2]):
				r[pz[2]] = maxi(0, int(r[pz[2]]) - 1)
		var imm := Dati.ha(int(spazio(x[0], x[1]).c), "permanente", "immune") and not suling_su(int(x[0]), int(x[1]))
		for c in r:
			if imm:
				solo_tao[c] = int(solo_tao.get(c, 0)) + int(r[c])
			else:
				req[c] = int(req.get(c, 0)) + int(r[c])
	var deficit := {}
	for c in req:
		deficit[c] = maxi(0, int(req[c]) - int(dadi.get(c, 0)))
	# i bianchi prima dove mancano i segnalini, poi dove fanno risparmiare;
	# i Cristalli di Luna (White Moon) valgono come un segnalino di qualunque colore
	var w := bianchi
	var cristalli := int(disp.get("cristalli", 0))
	var token := {}
	for c in Dati.COLORI_TAO:
		token[c] = int(solo_tao.get(c, 0))
	var colori := deficit.keys()
	colori.sort_custom(func(x, y): return int(deficit[x]) + int(token[x]) - int(disp.get(x, 0)) > int(deficit[y]) + int(token[y]) - int(disp.get(y, 0)))
	for c in colori:
		var manca := int(deficit[c]) + int(token[c]) - int(disp.get(c, 0))
		if manca > 0:
			var usa := mini(w, mini(manca, int(deficit[c])))
			w -= usa
			deficit[c] = int(deficit[c]) - usa
	for c in colori:
		var usa := mini(w, int(deficit[c]))
		w -= usa
		deficit[c] = int(deficit[c]) - usa
	var tot := 0
	var usati_cr := 0
	for c in Dati.COLORI_TAO:
		token[c] = int(token[c]) + int(deficit.get(c, 0))
		var oltre := int(token[c]) - int(disp.get(c, 0))
		if oltre > 0:
			usati_cr += oltre
			token[c] = int(disp.get(c, 0))
		tot += int(token[c])
	if usati_cr > cristalli:
		return {"_ok": false}
	token["cristalli"] = usati_cr
	token["_ok"] = true
	token["_tot"] = tot + usati_cr
	return token

## Probabilità (0-1) di esorcizzare almeno i bersagli dati tirando n dadi con i segnalini disponibili.
## Conta le combinazioni di facce (non le sequenze) e ricorda i risultati già calcolati.
static var _cache_prob := {}
static var _combinazioni := {}

func probabilita(bersagli: Array, n: int, disp: Dictionary) -> float:
	var chiave: String = str(n) + "|" + str(disp) + "|" + str(bianco_nullo()) + "|" + s.cerchio
	for x in bersagli:
		chiave += "|" + str(requisito(x[0], x[1])) + str(Dati.ha(int(spazio(x[0], x[1]).c), "permanente", "immune") and not suling_su(int(x[0]), int(x[1]))) + str(ha_mantra(x[0], x[1]))
	if _cache_prob.has(chiave):
		return _cache_prob[chiave]
	if n <= 0:
		var v0 := 1.0 if costo(bersagli, [], disp).get("_ok", false) else 0.0
		_cache_prob[chiave] = v0
		return v0
	var tot := 0.0
	var ok := 0.0
	for comb in _comb(n):
		var f := []
		for i in 6:
			for j in int(comb[0][i]):
				f.append(Dati.FACCE_TAO[i])
		var peso: float = comb[1]
		tot += peso
		if costo(bersagli, f, disp).get("_ok", false):
			ok += peso
	var v := ok / tot
	if _cache_prob.size() > 20000:
		_cache_prob.clear()
	_cache_prob[chiave] = v
	return v

## Tutti i modi di distribuire n dadi sulle 6 facce, con il loro peso (coefficiente multinomiale)
static func _comb(n: int) -> Array:
	if _combinazioni.has(n):
		return _combinazioni[n]
	var o := []
	var fatt := [1, 1, 2, 6, 24, 120, 720, 5040]
	# tutte le sequenze di 6 numeri che sommano a n
	var cur := [0, 0, 0, 0, 0, 0]
	var totale := int(pow(n + 1, 5))
	for code in totale:
		var x := code
		var somma := 0
		for i in 5:
			cur[i] = x % (n + 1)
			x = x / (n + 1)
			somma += cur[i]
		if somma > n:
			continue
		cur[5] = n - somma
		var den := 1
		for q in cur:
			den *= fatt[q]
		o.append([cur.duplicate(), float(fatt[n]) / den])
	_combinazioni[n] = o
	return o

# ============================================================ motore a pila

func _poi(compiti: Array) -> void:
	# il primo della lista va eseguito per primo: in cima alla pila
	for i in range(compiti.size() - 1, -1, -1):
		s.pila.append(compiti[i])

func finita() -> bool:
	return s.esito != ""

func in_attesa() -> bool:
	return not s.domanda.is_empty()

func avanza() -> void:
	var guardia := 0
	while not finita() and s.domanda.is_empty() and not s.pila.is_empty():
		guardia += 1
		if guardia > 5000:
			push_error("motore: troppi passi")
			return
		var t: Dictionary = s.pila.pop_back()
		_esegui(t)

func _chiedi(t: Dictionary, chi: int, tipo: String, testo: String, opzioni: Array) -> void:
	if opzioni.is_empty():
		return
	if chi < 0:
		chi = decisore(-1)
	s.domanda = {"chi": chi, "tipo": tipo, "testo": testo, "opzioni": opzioni, "task": t}

func rispondi(id: String) -> bool:
	if s.domanda.is_empty():
		return false
	var trovata := false
	for o in s.domanda.opzioni:
		if o.id == id:
			trovata = true
	if not trovata:
		return false
	var t: Dictionary = s.domanda.task
	t["r"] = id
	s.domanda = {}
	s.pila.append(t)
	avanza()
	return true

func _diario(testo: String) -> void:
	s.diario.append(testo)
	if s.diario.size() > 300:
		s.diario = s.diario.slice(s.diario.size() - 300)

func _evento(e: Dictionary) -> void:
	s.n_evento = int(s.n_evento) + 1
	e["n"] = s.n_evento
	s.eventi.append(e)
	if s.eventi.size() > 60:
		s.eventi = s.eventi.slice(s.eventi.size() - 60)

func _sconfitta(motivo: String) -> void:
	if finita():
		return
	s.esito = "sconfitta"
	s.motivo = motivo
	s.domanda = {}
	s.pila = []
	_diario("SCONFITTA: " + motivo)
	_calcola_punteggio()

func _vittoria() -> void:
	if finita():
		return
	s.esito = "vittoria"
	s.motivo = "Wu-Feng è stato ricacciato negli Inferi."
	s.domanda = {}
	s.pila = []
	_diario("VITTORIA! " + s.motivo)
	_calcola_punteggio()

func _calcola_punteggio() -> void:
	var p := {}
	var vinto: bool = s.esito == "vittoria"
	p["vittoria"] = (20 if s.livello == "inferno" else 10) if vinto else 0
	var qi := 0
	var morti := 0
	for b in s.plance:
		if b.taoista:
			qi += int(b.qi)
			if not b.vivo:
				morti += 1
	p["qi"] = qi
	p["mazzo"] = s.mazzo.size() if vinto else -s.mazzo.size()
	p["morti"] = -3 * morti
	p["infestate"] = -4 * n_infestate()
	var inc := 0
	if s.livello in ["incubo", "inferno"]:
		for i in int(s.inc_sconfitte):
			inc += [2, 4, 6, 6][mini(i, 3)]
	p["incarnazioni"] = inc
	if s.get("luna", false):
		p["villici"] = s.villici_salvi.size() if vinto else 0
		p["portale"] = int(s.get("bonus_portale", 0)) if vinto else 0
	var tot := 0
	for k in p:
		tot += int(p[k])
	p["totale"] = tot
	s.punteggio = p

# ============================================================ segnalini

func _prendi_tao(b: Dictionary, c: String) -> bool:
	if int(s.riserva_tao.get(c, 0)) <= 0:
		return false
	s.riserva_tao[c] = int(s.riserva_tao[c]) - 1
	b.tao[c] = int(b.tao[c]) + 1
	return true

func _rendi_tao(b: Dictionary, c: String, n := 1) -> void:
	var q := mini(n, int(b.tao[c]))
	b.tao[c] = int(b.tao[c]) - q
	s.riserva_tao[c] = int(s.riserva_tao[c]) + q

func colori_in_riserva() -> Array:
	var o := []
	for c in Dati.COLORI_TAO:
		if int(s.riserva_tao[c]) > 0:
			o.append(c)
	return o

func _opzioni_colore(colori: Array) -> Array:
	var o := []
	for c in colori:
		o.append({"id": "c:" + c, "t": "Tao " + Dati.NOMI_COLORE[c], "colore": c})
	return o

# ============================================================ i compiti

func _esegui(t: Dictionary) -> void:
	match String(t.k):
		"turno": _t_turno(t)
		"yin_azioni": _t_yin_azioni(t)
		"infestante": _t_infestante(t)
		"infesta": _t_infesta(t)
		"yin_arrivo": _t_yin_arrivo(t)
		"porta_fantasma": _t_porta_fantasma(t)
		"scegli_spazio": _t_scegli_spazio(t)
		"piazza": _t_piazza(t)
		"effetto": _t_effetto(t)
		"maledizione": _t_maledizione(t)
		"perdi_qi": _t_perdi_qi(t)
		"gruppo_tao": _t_gruppo_tao(t)
		"scarta": _t_scarta(t)
		"premio_qi_yy": _t_premio_qi_yy(t)
		"premio_tao": _t_premio_tao(t)
		"premio_incarnazione": _t_premio_incarnazione(t)
		"vittoria": _vittoria()
		"yang": _t_yang(t)
		"esorcismo": _t_esorcismo(t)
		"aiuto": _t_aiuto(t)
		"scegli_aiuto": _t_scegli_aiuto(t)
		"mantra": _t_mantra(t)
		"gemelli": _t_gemelli(t)
		"libera": _t_libera(t)
		"fine_turno": _t_fine_turno(t)
		"fuga": _t_fuga(t)
		"strage": _t_strage(t)
		"divora": _t_divora(t)
		"uccidi_scelto": _t_uccidi_scelto(t)
		"muta": _t_muta(t)
		"suling": _t_suling(t)
		"barriera": _t_barriera(t)
		"salva_villico": _t_salva_villico(t)
		"premio_cristallo": _t_premio_cristallo(t)
		"eredita": _t_eredita(t)
		"pozione": _t_pozione(t)
		"dai_artefatto": _t_dai_artefatto(t)
		"premio_tao_colore": _t_premio_tao_colore(t)
		"perdi_qi_scelto": _t_perdi_qi_scelto(t)
		"wf_carta": _t_wf_carta(t)
		"wf_gioca_inc": _t_wf_gioca_inc(t)
		"evoca_demone": _t_evoca_demone(t)
		"lancia_maledizione": _t_lancia_maledizione(t)
		"rinnova_maledizioni": _t_rinnova_maledizioni(t)
		"effetto_wf": _t_effetto_wf(t)
		"piazza_scheletro": _t_piazza_scheletro(t)
		"fase_demoni": _t_fase_demoni(t)
		"azione_demone": _t_azione_demone(t)
		"segnalino_cata": _t_segnalino_cata(t)
		"ms_scegli": _t_ms_scegli(t)
		"effetto_ms": _t_effetto_ms(t)
		"sposta_fantasma_ms": _t_sposta_fantasma_ms(t)
		"esorcizza_demone": _t_esorcizza_demone(t)
		_: push_error("compito sconosciuto " + str(t.k))

func _t_turno(t: Dictionary) -> void:
	var p := int(t.p)
	var b := plancia(p)
	s.turno_di = p
	s.dadi = {}
	s.suling_evento = false
	if b.taoista and b.vivo:
		b["cristalli_inizio"] = int(b.get("cristalli", 0))
	if b.taoista and b.vivo:
		s.ultimo_taoista = p
	_diario("— Turno: %s —" % nome_plancia(p) + (" (morto)" if b.taoista and not b.vivo else ""))
	_evento({"e": "turno", "p": p})
	var l := []
	if segreto() and b.taoista and b.vivo:
		l.append({"k": "fase_demoni", "p": p})
	l.append({"k": "yin_azioni", "p": p})
	l.append({"k": "yin_arrivo", "p": p})
	if b.taoista and b.vivo:
		l.append({"k": "yang", "p": p, "fase": "inizio", "azioni": 0, "tipi": [], "neutri": [], "usati": []})
	if s.get("luna", false):
		l.append({"k": "suling", "a": p})
		l.append({"k": "barriera", "a": p, "i": 0})
	l.append({"k": "fine_turno", "p": p})
	_poi(l)

func _t_yin_azioni(t: Dictionary) -> void:
	var p := int(t.p)
	var l := []
	for k in [2, 1, 0]:
		var c := int(spazio(p, k).c)
		if c <= 0:
			continue
		if suling_su(p, k):
			_diario("Su-Ling trattiene %s." % Dati.nome(c))
			continue
		for eff in Dati.carta(c).get("turno", []):
			match eff:
				"infestante": l.append({"k": "infestante", "p": p, "s": k, "c": c})
				"tormento": l.append({"k": "maledizione", "a": p, "p": p, "s": k, "c": c})
				"gruppo_tao": l.append({"k": "gruppo_tao", "c": c})
				"divoratore": l.append({"k": "divora", "p": p, "s": k, "c": c, "a": p})
				"uccidi_villico": l.append({"k": "uccidi_scelto", "a": p})
				"tempo": l.append({"k": "porta_fantasma", "a": p})
				"muta": l.append({"k": "muta", "p": p, "s": k, "c": c})
				"attiva_demone": l.append({"k": "azione_demone", "d": "?"})
				"scheletro": l.append({"k": "piazza_scheletro", "n": 1})
	_poi(l)

func _t_infestante(t: Dictionary) -> void:
	var p := int(t.p)
	var k := int(t.s)
	var sp := spazio(p, k)
	if int(sp.c) != int(t.c):
		return
	if int(sp.inf) <= 0:
		sp.inf = 1
		_diario("%s avanza verso il villaggio." % Dati.nome(int(sp.c)))
		_evento({"e": "avanza", "p": p, "s": k})
		if s.get("luna", false):
			_poi([{"k": "fuga", "p": p, "s": k}])
	else:
		sp.inf = 0
		_diario("%s infesta il villaggio!" % Dati.nome(int(sp.c)))
		_poi([{"k": "infesta", "p": p, "s": k}])

func _t_infesta(t: Dictionary) -> void:
	if t.has("t"):
		_infesta_o_strage(int(t.t))
		return
	var l := linea(int(t.p), int(t.s))
	for x in l:
		if not s.villaggio[x].inf:
			_infesta_o_strage(x)
			return
	_sconfitta("Le tre tessere davanti a un fantasma sono già infestate.")

func _infesta_o_strage(x: int) -> void:
	if s.get("luna", false) and not s.villaggio[x].get("ab", []).is_empty() and not s.villaggio[x].inf:
		_diario("Sulla tessera %s ci sono dei villici: muoiono tutti, ma la tessera non è infestata." % nome_tessera(x))
		_poi([{"k": "strage", "t": x}])
		return
	_infesta_tessera(x)

func _infesta_tessera(x: int) -> void:
	if s.villaggio[x].inf:
		return
	s.villaggio[x].inf = true
	s.suling_evento = true
	if segreto() and s.cata[x].scala:
		s.cata[x].scala = false
		_diario("La scala sotto la tessera %s crolla." % nome_tessera(x))
		_evento({"e": "scala", "i": x})
	_diario("La tessera %s è infestata." % nome_tessera(x))
	_evento({"e": "infesta", "t": x})
	if n_infestate() >= limite_infestate():
		_sconfitta("%d tessere del villaggio sono infestate: i fantasmi hanno ritrovato l'urna di Wu-Feng." % n_infestate())

func _t_yin_arrivo(t: Dictionary) -> void:
	var p := int(t.p)
	var b := plancia(p)
	var pieni := 0
	for k in 3:
		if int(spazio(p, k).c) > 0:
			pieni += 1
	if pieni >= 3:
		_diario("La %s è invasa: perde 1 Qi." % plancia_di(p))
		_poi([{"k": "perdi_qi", "p": p}])
		return
	if b.taoista and b.vivo:
		_poi([{"k": "porta_fantasma", "a": p}])

func _t_porta_fantasma(t: Dictionary) -> void:
	var a := int(t.a)
	if fantasmi_in_gioco().size() >= 12:
		_diario("Tutti gli spazi sono occupati: %s perde 1 Qi invece di far entrare un fantasma." % nome_plancia(a))
		_poi([{"k": "perdi_qi", "p": a}])
		return
	if s.mazzo.is_empty():
		_sconfitta("Il mazzo dei fantasmi è finito.")
		return
	var c := int(s.mazzo.pop_front())
	var giri := 0
	while ha_artefatto(a, "scudo") and int(s.turno_di) == a and not Dati.e_incarnazione(c) and Dati.carta(c).get("colore", "") == plancia(a).colore and s.mazzo.size() > 0 and giri < 6:
		_diario("Lo Scudo del Tempo rimanda %s in fondo al mazzo." % Dati.nome(c))
		s.mazzo.append(c)
		c = int(s.mazzo.pop_front())
		giri += 1
	if segreto():
		_evento({"e": "pesca", "c": c})
		_poi([{"k": "wf_carta", "a": a, "c": c}])
		return
	_diario("Entra in gioco: %s." % Dati.nome(c))
	_evento({"e": "pesca", "c": c})
	_poi([{"k": "scegli_spazio", "a": a, "c": c}])

func _spazi_liberi(p: int) -> Array:
	var o := []
	for k in 3:
		if int(spazio(p, k).c) == 0:
			o.append([p, k])
	return o

func spazi_per_carta(c: int, a: int) -> Array:
	var col: String = Dati.carta(c).get("colore", "nero")
	var dest := a
	if col != "nero":
		for q in POSIZIONI:
			if plancia(q).colore == col:
				dest = q
	var l := _spazi_liberi(dest)
	if l.is_empty():
		for q in POSIZIONI:
			l += _spazi_liberi(q)
	return l

func _t_scegli_spazio(t: Dictionary) -> void:
	var a := int(t.a)
	var c := int(t.c)
	if t.has("r"):
		var pz: PackedStringArray = String(t.r).split(":")
		_poi([{"k": "piazza", "a": a, "c": c, "p": int(pz[1]), "s": int(pz[2])}])
		return
	var l := spazi_per_carta(c, a)
	if l.size() == 1:
		_poi([{"k": "piazza", "a": a, "c": c, "p": l[0][0], "s": l[0][1]}])
		return
	var o := []
	for x in l:
		var testo := "%s, spazio %d" % [_maiuscola(plancia_di(x[0])), x[1] + 1]
		if spazio(x[0], x[1]).buddha:
			testo += " (Buddha)"
		o.append({"id": "s:%d:%d" % [x[0], x[1]], "t": testo, "spazio": x})
	_chiedi(t, int(t.get("chi", decisore(a))), "piazza", "Dove entra %s?" % Dati.nome(c), o)
	s.domanda["carta"] = c

func _t_piazza(t: Dictionary) -> void:
	var a := int(t.a)
	var c := int(t.c)
	var p := int(t.p)
	var k := int(t.s)
	var sp := spazio(p, k)
	var inc := Dati.e_incarnazione(c)
	if sp.buddha:
		if not inc:
			sp.buddha = false
			s.buddha_tempio = int(s.buddha_tempio) + 1
			s.scarti.append(c)
			_diario("%s finisce su un Buddha ed è subito ricacciato all'inferno." % Dati.nome(c))
			_evento({"e": "buddha", "p": p, "s": k, "c": c})
			_controlla_ultima()
			return
		if not Dati.ha(c, "permanente", "inafferrabile"):
			sp.buddha = false
			s.buddha_tempio = int(s.buddha_tempio) + 1
			_diario("Il Buddha non ferma un'incarnazione di Wu-Feng: torna al Tempio.")
	sp.c = c
	sp.inf = 0 if Dati.ha(c, "turno", "infestante") else -1
	sp.dado = false
	sp.armatura = false
	_evento({"e": "piazza", "c": c, "p": p, "s": k})
	if inc:
		_diario("ATTENZIONE: è arrivata un'incarnazione di Wu-Feng: %s!" % Dati.nome(c))
		if suling_su(p, k):
			s.suling.p = -1
			s.suling.k = -1
			_diario("Su-Ling non può stare davanti a Wu-Feng: torna nella riserva.")
	_controlla_ultima()
	if finita():
		return
	if not inc and ha_artefatto(p, "armatura"):
		sp.armatura = true
		_diario("L'Armatura del Giusto protegge la %s dalle abilità d'arrivo di %s." % [plancia_di(p), Dati.nome(c)])
		return
	var l := []
	for eff in Dati.carta(c).get("arrivo", []):
		l.append({"k": "effetto", "e": eff, "c": c, "p": p, "s": k, "a": a})
	if Dati.ha(c, "permanente", "nopoteri"):
		l.append({"k": "effetto", "e": "nopoteri", "c": c, "p": p, "s": k, "a": a})
	_poi(l)

func _controlla_ultima() -> void:
	if s.mazzo.is_empty() and int(s.inc_sconfitte) < int(s.inc_totali):
		_sconfitta("È entrata in gioco l'ultima carta del mazzo e Wu-Feng non è stato sconfitto.")

func _t_effetto(t: Dictionary) -> void:
	var p := int(t.p)
	var k := int(t.s)
	var c := int(t.c)
	var a := int(t.a)
	var sp := spazio(p, k)
	if int(sp.c) != c:
		return
	match String(t.e):
		"fantasma":
			_poi([{"k": "porta_fantasma", "a": a}])
		"potere":
			_diario("%s spegne il potere della %s." % [Dati.nome(c), plancia_di(p)])
			_controlla_mantra()
		"nopoteri":
			_diario("I Dimenticati impediscono a tutti i Taoisti di usare i poteri.")
			_controlla_mantra()
		"dado":
			if dadi_disponibili() > 0:
				sp.dado = true
				_diario("%s cattura un dado Tao." % Dati.nome(c))
		"notao":
			_diario("%s: finché resta in gioco non si possono usare i segnalini Tao." % Dati.nome(c))
		"gruppo_tao":
			_poi([{"k": "gruppo_tao", "c": c}])
		"infesta":
			_poi([{"k": "infesta", "p": p, "s": k}])
		"qi":
			_poi([{"k": "perdi_qi", "p": p}])
		"rapido":
			sp.inf = 1
			_evento({"e": "avanza", "p": p, "s": k})
			if s.get("luna", false):
				_poi([{"k": "fuga", "p": p, "s": k}])
		"maledizione":
			_poi([{"k": "maledizione", "a": a, "p": p, "s": k, "c": c}])
		"cerchio":
			if s.cerchio != "":
				s.riserva_tao[s.cerchio] = int(s.riserva_tao[s.cerchio]) + 1
				_diario("Il Senza Nome scaccia il segnalino del Cerchio di Preghiera.")
				s.cerchio = ""
		"divora":
			_poi([{"k": "divora", "p": p, "s": k, "c": c, "a": a}])
		"uccidi_villico":
			_poi([{"k": "uccidi_scelto", "a": a}])
		"via_portale":
			if int(s.get("portale", -1)) >= 0:
				s.portale = -1
				_diario("Il Guardiano della Porta si prende il Portale: non si possono salvare villici.")
		"via_suling":
			s.suling.via = true
			s.suling.p = -1
			s.suling.k = -1
			_diario("L'Ondina Ululante rapisce Su-Ling.")
		"tutti_a_terra":
			for q in taoisti_vivi():
				plancia(q).a_terra = true
			_diario("Il Signore delle Radici getta a terra tutti i Taoisti.")
		"via_due":
			for i in 2:
				if s.mazzo.size() > 1:
					s.mazzo.pop_back()
			_diario("Il Custode del Tempo toglie dal gioco le ultime due carte del mazzo.")
		"rapido_fuga":
			pass
		"attiva_demone":
			_poi([{"k": "azione_demone", "d": "?"}])
		"incarnazione_mano":
			_pesca_incarnazione()
		"scheletri3":
			_poi([{"k": "piazza_scheletro", "n": 3}])
		"scava_pila":
			_poi([{"k": "effetto_wf", "e": "scava_pila", "a": a}])

## Se il Taoista giallo perde il potere del mantra, il mantra esce dal gioco
func _controlla_mantra() -> void:
	if s.mantra.perso:
		return
	for q in POSIZIONI:
		if chiave_potere(q) == "giallo_0" and potere_spento(q):
			if plancia(q).taoista:
				s.mantra.perso = true
				s.mantra.p = -1
				s.mantra.s = -1
				_diario("Il Taoista giallo perde il potere: il Mantra dell'Indebolimento esce dal gioco.")

func _t_maledizione(t: Dictionary) -> void:
	var a := int(t.a)
	var b := plancia(a)
	if not t.has("faccia"):
		if potere(a, "verde_0"):
			_diario("Il Taoista verde non tira mai il dado della maledizione.")
			return
		t["faccia"] = Dati.FACCE_MALEDIZIONE[rng_int(6)]
		s.suling_evento = true
		_evento({"e": "maledizione", "f": t.faccia})
		_diario("Dado della maledizione: %s." % _testo_maledizione(t.faccia))
		if potere(a, "verde_1") and t.faccia != "nulla":
			_chiedi(t, a, "ritira_maledizione", "Dado della maledizione: %s. Lo ritiri? (vale il secondo tiro)" % _testo_maledizione(t.faccia),
				[{"id": "tieni", "t": "Tieni il risultato"}, {"id": "ritira", "t": "Ritira il dado"}])
			return
	if t.get("r", "") == "ritira":
		t.erase("r")
		t["faccia"] = Dati.FACCE_MALEDIZIONE[rng_int(6)]
		_evento({"e": "maledizione", "f": t.faccia})
		_diario("Nuovo tiro della maledizione: %s." % _testo_maledizione(t.faccia))
	match String(t.faccia):
		"infesta":
			if t.has("t"):
				_poi([{"k": "infesta", "t": int(t.t)}])
			elif t.has("p"):
				_poi([{"k": "infesta", "p": int(t.p), "s": int(t.s)}])
		"fantasma":
			_poi([{"k": "porta_fantasma", "a": a}])
		"tao":
			if b.taoista:
				for c in Dati.COLORI_TAO:
					_rendi_tao(b, c, int(b.tao[c]))
				_diario("%s scarta tutti i segnalini Tao." % nome_plancia(a))
		"qi":
			_poi([{"k": "perdi_qi", "p": a}])

func _testo_maledizione(f: String) -> String:
	return {"nulla": "nessun effetto", "infesta": "una tessera viene infestata", "fantasma": "entra un fantasma",
		"tao": "si scartano tutti i Tao", "qi": "si perde 1 Qi"}.get(f, f)

func _t_perdi_qi(t: Dictionary) -> void:
	var p := int(t.p)
	var b := plancia(p)
	if t.has("r"):
		_poi([{"k": "perdi_qi", "p": int(String(t.r).split(":")[1])}])
		return
	if int(b.qi) > 0 and (not b.taoista or b.vivo):
		b.qi = int(b.qi) - 1
		_evento({"e": "qi", "p": p, "d": -1})
		_diario("%s perde 1 Qi (ne restano %d)." % [nome_plancia(p), int(b.qi)])
		if segreto() and not effetto_in_gioco("permanente", "no_mantra") and not taoisti_vivi().is_empty():
			_poi([{"k": "ms_scegli", "modo": "qi", "a": p}])
		if int(b.qi) == 0:
			if b.taoista:
				_morte(p)
			else:
				_diario("La %s è posseduta: il suo potere non si può più usare." % plancia_di(p))
		return
	var vivi := taoisti_vivi()
	if vivi.is_empty():
		_sconfitta("Tutti i Taoisti sono morti.")
		return
	if vivi.size() == 1:
		_poi([{"k": "perdi_qi", "p": vivi[0]}])
		return
	var o := []
	for q in vivi:
		o.append({"id": "q:%d" % q, "t": "%s (%d Qi)" % [nome_plancia(q), int(plancia(q).qi)], "plancia": q})
	_chiedi(t, decisore(p), "chi_perde_qi", "La %s non ha più Qi: chi perde 1 Qi al suo posto?" % plancia_di(p), o)

func _morte(p: int) -> void:
	var b := plancia(p)
	b.vivo = false
	for c in Dati.COLORI_TAO:
		_rendi_tao(b, c, int(b.tao[c]))
	s.buddha_tempio = int(s.buddha_tempio) + int(b.buddha)
	b.buddha = 0
	b.yinyang = false
	s.poteri_centro = int(s.poteri_centro) + int(b.poteri)
	b.poteri = 0
	var cim := indice_tessera("cimitero")
	b.tessera = cim if cim >= 0 else 4
	b.sotto = false
	b.a_terra = false
	if not b.get("artefatti", []).is_empty():
		var eredi := []
		for q in taoisti_vivi():
			if q != p:
				eredi.append(q)
		if not eredi.is_empty():
			s.pila.append({"k": "eredita", "da": p})
	s.cristalli = int(s.get("cristalli", 0)) + int(b.get("cristalli", 0))
	b.cristalli = 0
	_diario("%s è morto. La sua figurina giace sul Cimitero; i fantasmi della sua plancia restano." % nome_plancia(p))
	_evento({"e": "morte", "p": p})
	if taoisti_vivi().is_empty():
		_sconfitta("Tutti i Taoisti sono morti.")

func _t_gruppo_tao(_t: Dictionary) -> void:
	for q in taoisti_vivi():
		var b := plancia(q)
		var best := ""
		for c in Dati.COLORI_TAO:
			if int(b.tao[c]) > 0 and (best == "" or int(b.tao[c]) > int(b.tao[best])):
				best = c
		if best != "":
			_rendi_tao(b, best)
			_diario("%s scarta un Tao %s." % [nome_plancia(q), Dati.NOMI_COLORE[best]])

## modo: esorcismo, stregone
func _t_scarta(t: Dictionary) -> void:
	var p := int(t.p)
	var k := int(t.s)
	var sp := spazio(p, k)
	var c := int(sp.c)
	if c <= 0:
		return
	sp.c = 0
	sp.inf = -1
	sp.dado = false
	if sp.buddha:
		sp.buddha = false
		s.buddha_tempio = int(s.buddha_tempio) + 1
	if ha_mantra(p, k):
		s.mantra.p = -1
		s.mantra.s = -1
	if c == 200:
		s.scheletri = int(s.scheletri) + 1
		_diario("Lo scheletro torna polvere.")
		_evento({"e": "esorcizza", "c": c, "p": p, "s": k, "modo": t.modo})
		return
	s.scarti.append(c)
	_evento({"e": "esorcizza", "c": c, "p": p, "s": k, "modo": t.modo})
	var a := int(t.get("a", -1))
	if c == 83 and int(s.get("portale_casa", -1)) >= 0:
		s.portale = s.portale_casa
		_diario("Il Portale torna al suo posto.")
	if c == 84:
		s.suling.via = false
		_diario("Su-Ling è di nuovo libera.")
	if t.modo != "esorcismo":
		_diario("%s è mandato all'inferno." % Dati.nome(c))
		return
	_diario("%s è esorcizzato!" % Dati.nome(c))
	var l := []
	for eff in Dati.carta(c).get("esorcismo", []):
		match eff:
			"maledizione": l.append({"k": "maledizione", "a": a, "p": p, "s": k, "c": c})
			"qi_yy": l.append({"k": "premio_qi_yy", "a": a})
			"tao1": l.append({"k": "premio_tao", "a": a, "n": 1})
			"tao2": l.append({"k": "premio_tao", "a": a, "n": 2})
			"cristallo": l.append({"k": "premio_cristallo", "a": a})
			"fantasma": l.append({"k": "porta_fantasma", "a": int(s.turno_di)})
			"maledizione_libera": l.append({"k": "effetto_wf", "e": "maledizione_libera", "a": a})
	if Dati.e_incarnazione(c):
		s.inc_sconfitte = int(s.inc_sconfitte) + 1
		_diario("Un'incarnazione di Wu-Feng è sconfitta (%d su %d)." % [int(s.inc_sconfitte), int(s.inc_totali)])
		if int(s.inc_sconfitte) >= int(s.inc_totali):
			l.append({"k": "vittoria"})
		else:
			if c >= 100:
				l.append({"k": "premio_incarnazione", "a": a, "fase": "yy"})
				l.append({"k": "ms_scegli", "modo": "qi", "a": a})
			else:
				l.append({"k": "premio_incarnazione", "a": a, "fase": "cristallo" if c >= 82 else "qi"})
	_poi(l)

func _t_premio_qi_yy(t: Dictionary) -> void:
	var a := int(t.a)
	var b := plancia(a)
	if not b.taoista or not b.vivo:
		return
	if t.has("r"):
		if t.r == "qi":
			b.qi = int(b.qi) + 1
			_evento({"e": "qi", "p": a, "d": 1})
			_diario("%s guadagna 1 Qi." % nome_plancia(a))
		else:
			b.yinyang = true
			_diario("%s riprende lo Yin-Yang." % nome_plancia(a))
		return
	var o := []
	if qi_in_riserva() > 0:
		o.append({"id": "qi", "t": "Guadagna 1 Qi"})
	if not b.yinyang:
		o.append({"id": "yy", "t": "Riprendi lo Yin-Yang"})
	if o.is_empty():
		return
	if o.size() == 1:
		t["r"] = o[0].id
		_t_premio_qi_yy(t)
		return
	_chiedi(t, a, "premio", "Ricompensa: 1 Qi oppure lo Yin-Yang?", o)

func _t_premio_tao(t: Dictionary) -> void:
	var a := int(t.a)
	var b := plancia(a)
	if not b.taoista or not b.vivo:
		return
	if t.has("r"):
		var c := String(t.r).substr(2)
		_prendi_tao(b, c)
		_diario("%s prende un Tao %s." % [nome_plancia(a), Dati.NOMI_COLORE[c]])
		if int(t.n) > 1:
			_poi([{"k": "premio_tao", "a": a, "n": int(t.n) - 1, "perche": t.get("perche", "")}])
		return
	var col := colori_in_riserva()
	if col.is_empty():
		return
	if col.size() == 1:
		t["r"] = "c:" + col[0]
		_t_premio_tao(t)
		return
	var testo := "Scegli un segnalino Tao" + ("" if int(t.n) == 1 else " (%d da prendere)" % int(t.n))
	if t.get("perche", "") != "":
		testo = String(t.perche) + ": scegli un segnalino Tao" + ("" if int(t.n) == 1 else " (%d da prendere)" % int(t.n))
	_chiedi(t, a, "colore_tao", testo, _opzioni_colore(col))

func _t_premio_incarnazione(t: Dictionary) -> void:
	var vivi := taoisti_vivi()
	if vivi.is_empty():
		return
	if t.has("r"):
		var q := int(String(t.r).split(":")[1])
		if t.fase == "qi":
			plancia(q).qi = int(plancia(q).qi) + 1
			_evento({"e": "qi", "p": q, "d": 1})
			_diario("%s riceve 1 Qi dall'incarnazione sconfitta." % nome_plancia(q))
			_poi([{"k": "premio_incarnazione", "a": t.a, "fase": "yy"}])
		elif t.fase == "solo_qi":
			if qi_in_riserva() > 0:
				plancia(q).qi = int(plancia(q).qi) + 1
				_evento({"e": "qi", "p": q, "d": 1})
				_diario("%s riceve 1 Qi." % nome_plancia(q))
		elif t.fase == "cristallo":
			_dai_cristallo(q)
			_poi([{"k": "premio_incarnazione", "a": t.a, "fase": "yy"}])
		else:
			plancia(q).yinyang = true
			_diario("%s riceve lo Yin-Yang dall'incarnazione sconfitta." % nome_plancia(q))
		return
	var o := []
	for q in vivi:
		if t.fase in ["qi", "cristallo", "solo_qi"] or not plancia(q).yinyang:
			o.append({"id": "q:%d" % q, "t": "%s (%d Qi)" % [nome_plancia(q), int(plancia(q).qi)], "plancia": q})
	if o.is_empty():
		return
	if (t.fase == "qi" and qi_in_riserva() <= 0) or (t.fase == "cristallo" and int(s.get("cristalli", 0)) <= 0):
		_poi([{"k": "premio_incarnazione", "a": t.a, "fase": "yy"}])
		return
	if o.size() == 1:
		t["r"] = o[0].id
		_t_premio_incarnazione(t)
		return
	_chiedi(t, decisore(int(t.a)), "premio_gruppo", "Chi riceve %s dell'incarnazione sconfitta?" % {"qi": "il Qi", "cristallo": "il Cristallo di Luna"}.get(t.fase, "lo Yin-Yang"), o)

# ============================================================ fase Yang

func _t_yang(t: Dictionary) -> void:
	var p := int(t.p)
	var b := plancia(p)
	if not b.vivo:
		return
	if t.has("r"):
		var r: String = t.r
		t.erase("r")
		_yang_risposta(t, r)
		return
	var o := opzioni_yang(t)
	var testo: String = {"inizio": "Muovi il tuo Taoista (o resta dove sei).", "azione": "Scegli l'azione: esorcismo o aiuto del villaggio.",
		"fine": "Fine del turno.", "livello": "C'è una scala: cambi livello?"}[t.fase]
	if t.fase == "azione" and sotto(p):
		testo = "Nelle catacombe si può solo esorcizzare un demone."
	_chiedi(t, p, "yang", testo, o)

func max_azioni(p: int, t: Dictionary) -> int:
	var n := 1
	if potere(p, "blu_0") or potere(p, "blu_1"):
		n = 2
	return n

func opzioni_yang(t: Dictionary) -> Array:
	var p := int(t.p)
	var b := plancia(p)
	var o := []
	var neutri := poteri_neutri(p, t.neutri)
	var qui := int(b.tessera)
	if t.fase == "inizio" and b.get("a_terra", false):
		# a terra: il movimento serve a rialzarsi (con la Danza delle Vette ci si rialza e si fa un passo)
		o.append({"id": "m:%d" % qui, "t": "Rialzati (niente movimento)", "tessera": qui})
		if potere(p, "rosso_1"):
			for x in adiacenti(qui):
				o.append({"id": "m:%d" % x, "t": "Rialzati e vai a %s" % nome_tessera(x), "tessera": x})
	elif t.fase == "livello":
		if b.get("sotto", false):
			o.append({"id": "sali", "t": "Sali nel villaggio: " + nome_tessera(qui), "tessera": qui})
		else:
			o.append({"id": "scendi", "t": "Scendi nella " + nome_cata(qui), "cata": qui})
		o.append({"id": "resta_livello", "t": "Resta qui"})
	elif t.fase == "azione" and sotto(p):
		var fatte := int(t.azioni)
		var mx := max_azioni(p, t)
		if not demoni_esorcizzabili(p).is_empty() and dadi_disponibili() > 0:
			var nomi := []
			for d in demoni_esorcizzabili(p):
				nomi.append(Dati.demone(d).nome)
			if fatte < mx and (fatte == 0 or potere(p, "blu_0") or potere(p, "blu_1")):
				o.append({"id": "esorcizza_demone", "t": "Esorcismo nelle catacombe contro " + " e ".join(nomi), "cata": qui})
		o.append({"id": "basta", "t": "Nessuna azione" if fatte == 0 else "Basta azioni"})
	elif t.fase == "fine" and sotto(p):
		o.append({"id": "fine", "t": "Fine turno"})
	elif t.fase == "inizio" and sotto(p):
		for x in 9:
			if x == qui:
				o.append({"id": "m:%d" % x, "t": "Resta nella " + nome_cata(x), "cata": x})
			elif x in adiacenti(qui) or potere(p, "rosso_1"):
				o.append({"id": "m:%d" % x, "t": "Vai nella " + nome_cata(x), "cata": x})
	elif t.fase == "inizio":
		var vicine := adiacenti(qui)
		var vola := potere(p, "rosso_1")
		var villico := villico_in_cima(qui)
		for x in 9:
			if x == qui:
				o.append({"id": "m:%d" % x, "t": "Resta su %s" % nome_tessera(x), "tessera": x})
			elif x in vicine or vola:
				o.append({"id": "m:%d" % x, "t": "Vai a %s" % nome_tessera(x), "tessera": x})
				if villico != "" and puo_ricevere_villico(x):
					o.append({"id": "mc:%d" % x, "t": "Vai a %s con %s" % [nome_tessera(x), nome_villico(villico)], "tessera_villico": x})
			elif "rosso_1" in neutri:
				o.append({"id": "mv:%d" % x, "t": "Vola a %s (segnalino potere)" % nome_tessera(x), "tessera": x, "neutro": true})
		if not "mantra" in t.usati and not s.mantra.perso and not fantasmi_in_gioco().is_empty():
			if potere(p, "giallo_0"):
				o.append({"id": "mantra", "t": "Mantra dell'Indebolimento"})
			elif "giallo_0" in neutri:
				o.append({"id": "n_mantra", "t": "Mantra dell'Indebolimento (segnalino potere)", "neutro": true})
		if not "tasche" in t.usati and not colori_in_riserva().is_empty():
			if potere(p, "giallo_1"):
				o.append({"id": "tasche", "t": "Tasche Senza Fondo: prendi un Tao"})
			elif "giallo_1" in neutri:
				o.append({"id": "n_tasche", "t": "Tasche Senza Fondo (segnalino potere)", "neutro": true})
	elif t.fase == "azione":
		if not "gemelli" in t.usati and _altri_vivi(p).size() > 0:
			if potere(p, "rosso_0"):
				o.append({"id": "gemelli", "t": "Danza dei Venti Gemelli: muovi un altro Taoista"})
			elif "rosso_0" in neutri:
				o.append({"id": "n_gemelli", "t": "Danza dei Venti Gemelli (segnalino potere)", "neutro": true})
		var fatte := int(t.azioni)
		var mx := max_azioni(p, t)
		var tipi: Array = t.tipi
		var puo := {"e": false, "a": false, "v": false}
		if fatte < mx:
			for x in puo:
				puo[x] = fatte == 0 or (potere(p, "blu_0") and _ammessa(x, tipi, "uguale")) or (potere(p, "blu_1") and _ammessa(x, tipi, "raffica"))
		var extra := {"e": false, "a": false, "v": false}
		if fatte >= 1 and fatte >= mx and not t.get("blu_neutro", false):
			for x in extra:
				extra[x] = ("blu_0" in neutri and _ammessa(x, tipi, "uguale")) or ("blu_1" in neutri and _ammessa(x, tipi, "raffica"))
		var puo_e: bool = puo.e
		var puo_a: bool = puo.a
		var extra_e: bool = extra.e
		var extra_a: bool = extra.a
		if s.get("luna", false) and qui == int(s.get("portale", -1)) and villico_in_cima(qui) != "":
			var nv := nome_villico(villico_in_cima(qui))
			if puo.v:
				o.append({"id": "salva", "t": "Metti in salvo %s (Portale)" % nv, "tessera": qui})
			elif extra.v:
				o.append({"id": "n_salva", "t": "Metti in salvo %s (segnalino potere)" % nv, "neutro": true})
		if ha_artefatto(p, "pergamena") and not _altri_vivi(p).is_empty():
			o.append({"id": "art:pergamena", "t": "Pergamena dell'Unità: chiama qui gli altri Taoisti"})
		var bersagli := bersagli_esorcismo(p)
		if not bersagli.is_empty():
			var nomi := []
			for x in bersagli:
				nomi.append(Dati.nome(int(spazio(x[0], x[1]).c)))
			var cosa := " e ".join(nomi)
			if puo_e:
				o.append({"id": "esorcizza", "t": "Esorcismo contro " + cosa, "spazio": bersagli[0]})
			elif extra_e:
				o.append({"id": "n_esorcizza", "t": "Altro esorcismo contro %s (segnalino potere)" % cosa, "neutro": true})
		if aiuto_possibile(qui, p):
			var nt := Dati.tessera(s.villaggio[qui].id).get("nome", "")
			if puo_a:
				o.append({"id": "aiuto", "t": "Aiuto: " + nt, "tessera": qui})
			elif extra_a:
				o.append({"id": "n_aiuto", "t": "Aiuto: %s (segnalino potere)" % nt, "neutro": true})
		o.append({"id": "basta", "t": "Nessuna azione" if fatte == 0 else "Basta azioni"})
	else:
		if int(b.buddha) > 0:
			for x in fronte(qui):
				var sp := spazio(x[0], x[1])
				if int(sp.c) == 0 and not sp.buddha:
					o.append({"id": "b:%d:%d" % [x[0], x[1]], "t": "Metti un Buddha sulla %s, spazio %d" % [plancia_di(x[0]), x[1] + 1], "spazio": x})
		if qui == 4 and int(s.poteri_centro) > 0:
			o.append({"id": "prendi_poteri", "t": "Prendi i segnalini potere (%d)" % int(s.poteri_centro)})
		if s.get("luna", false) and int(b.get("cristalli", 0)) > 0 and int(b.get("cristalli_inizio", 0)) > int(t.get("cr_posati", 0)):
			var ri := ricettacolo_di(qui)
			if ri >= 0 and not s.ricettacoli[ri]:
				o.append({"id": "cr:%d" % ri, "t": "Metti un Cristallo di Luna nel ricettacolo", "tessera": qui})
		o.append({"id": "fine", "t": "Fine turno"})
	# gli artefatti si usano nella fase Yang
	for art in b.get("artefatti", []):
		match art:
			"pozione":
				o.append({"id": "art:pozione", "t": "Pozione della Vita: 1 Qi a un Taoista (o un ritorno in vita)"})
			"polvere":
				if int(s.get("cristalli", 0)) > 0:
					o.append({"id": "art:polvere", "t": "Polvere di Luna: prendi un Cristallo di Luna"})
			"fuoco":
				o.append({"id": "art:fuoco", "t": "Fuoco d'Artificio: aiuto di un'altra tessera"})
	# lo Yin-Yang si può usare prima o dopo ogni passo
	if b.yinyang and not yinyang_bloccati():
		if n_infestate() > 0:
			o.append({"id": "yy_libera", "t": "Yin-Yang: libera una tessera infestata"})
		var dist := false
		for x in 9:
			if aiuto_possibile(x, p):
				dist = true
		if dist:
			o.append({"id": "yy_aiuto", "t": "Yin-Yang: aiuto di una tessera lontana"})
	return o

## Con il Secondo Respiro la seconda azione è dello stesso tipo; con la Raffica Celeste un esorcismo e un aiuto
## (l'aiuto può essere anche il salvataggio di un villico)
func _ammessa(x: String, tipi: Array, modo: String) -> bool:
	if tipi.is_empty():
		return true
	if modo == "uguale":
		return tipi[0] == x
	if x == "e":
		return not "e" in tipi
	return not ("a" in tipi or "v" in tipi)

func _plancia_colore(c: String) -> int:
	for q in POSIZIONI:
		if plancia(q).colore == c:
			return q
	return 0

func _altri_vivi(p: int) -> Array:
	var o := []
	for q in taoisti_vivi():
		if q != p:
			o.append(q)
	return o

func bersagli_esorcismo(p: int) -> Array:
	var o := []
	for x in fronte(int(plancia(p).tessera)):
		if esorcizzabile(x[0], x[1]):
			o.append(x)
	return o

## La tessera t può dare aiuto al Taoista p?
func aiuto_possibile(t: int, p: int) -> bool:
	if s.villaggio[t].inf or ombra_su_tessera(t):
		return false
	match String(s.villaggio[t].id):
		"casa_te": return true
		"erborista": return dadi_disponibili() > 0 and not colori_in_riserva().is_empty()
		"padiglione": return not fantasmi_in_gioco().is_empty() or not _altri_vivi(p).is_empty()
		"altare": return n_infestate() > 0
		"tempio": return int(s.buddha_tempio) > 0
		"cerchio": return not colori_in_riserva().is_empty()
		"stregone":
			for x in fantasmi_in_gioco():
				if not Dati.e_incarnazione(int(spazio(x[0], x[1]).c)):
					return true
			return false
		"cimitero": return (int(s.n_taoisti) > 1 and not taoisti_morti().is_empty()) or (s.get("luna", false) and not s.villici_morti.is_empty() and puo_ricevere_villico(t, true))
		"calligrafo": return segreto()
		"kungfu": return dadi_disponibili() > 0 and (not _bersagli_kungfu(p, "plancia").is_empty() or not _bersagli_kungfu(p, "nero").is_empty())
		"guardiano":
			for x in fantasmi_in_gioco():
				if int(spazio(x[0], x[1]).inf) == 1:
					return true
			return false
	return false

func _yang_risposta(t: Dictionary, r: String) -> void:
	var p := int(t.p)
	var b := plancia(p)
	if r.begins_with("m:") or r.begins_with("mv:") or r.begins_with("mc:"):
		var x := int(r.split(":")[1])
		if r.begins_with("mv:"):
			_usa_segnalino(p, "rosso", t)
		if b.get("a_terra", false):
			b.a_terra = false
			_diario("%s si rialza." % nome_plancia(p))
		if r.begins_with("mc:"):
			_sposta_villico(int(b.tessera), x)
		if x != int(b.tessera):
			b.tessera = x
			_diario("%s va: %s." % [nome_plancia(p), nome_luogo(p)])
			_evento({"e": "muovi", "p": p, "t": x})
		t.fase = "livello" if segreto() and s.cata[x].scala else "azione"
		s.pila.append(t)
		return
	if r == "scendi" or r == "sali":
		b.sotto = r == "scendi"
		_diario("%s %s per la scala: %s." % [nome_plancia(p), "scende" if b.sotto else "sale", nome_luogo(p)])
		_evento({"e": "muovi", "p": p, "t": int(b.tessera), "livello": true})
		t.fase = "azione"
		s.pila.append(t)
		return
	if r == "resta_livello":
		t.fase = "azione"
		s.pila.append(t)
		return
	if r == "esorcizza_demone" or r == "n_esorcizza_demone":
		if r == "n_esorcizza_demone":
			_usa_segnalino(p, "blu", t)
			t["blu_neutro"] = true
		t.azioni = int(t.azioni) + 1
		t.tipi.append("e")
		s.pila.append(t)
		_poi([{"k": "esorcizza_demone", "p": p}])
		return
	match r:
		"mantra", "n_mantra":
			if r == "n_mantra":
				_usa_segnalino(p, "giallo", t)
			t.usati.append("mantra")
			s.pila.append(t)
			_poi([{"k": "mantra", "p": p}])
		"tasche", "n_tasche":
			if r == "n_tasche":
				_usa_segnalino(p, "giallo", t)
			t.usati.append("tasche")
			s.pila.append(t)
			_poi([{"k": "premio_tao", "a": p, "n": 1, "perche": "Tasche Senza Fondo"}])
		"gemelli", "n_gemelli":
			if r == "n_gemelli":
				_usa_segnalino(p, "rosso", t)
			t.usati.append("gemelli")
			s.pila.append(t)
			_poi([{"k": "gemelli", "p": p}])
		"esorcizza", "n_esorcizza":
			if r == "n_esorcizza":
				_usa_segnalino(p, "blu", t)
				t["blu_neutro"] = true
			t.azioni = int(t.azioni) + 1
			t.tipi.append("e")
			s.pila.append(t)
			_poi([{"k": "esorcismo", "p": p, "neutri": t.neutri}])
		"salva", "n_salva":
			if r == "n_salva":
				_usa_segnalino(p, "blu", t)
				t["blu_neutro"] = true
			t.azioni = int(t.azioni) + 1
			t.tipi.append("v")
			s.pila.append(t)
			_poi([{"k": "salva_villico", "t": int(b.tessera), "a": p}])
		"art:pozione":
			_togli_artefatto(p, "pozione")
			s.pila.append(t)
			_poi([{"k": "pozione", "a": p}])
		"art:polvere":
			_togli_artefatto(p, "polvere")
			_dai_cristallo(p)
			s.pila.append(t)
		"art:fuoco":
			_togli_artefatto(p, "fuoco")
			_diario("%s accende il Fuoco d'Artificio." % nome_plancia(p))
			s.pila.append(t)
			_poi([{"k": "scegli_aiuto", "p": p}])
		"art:pergamena":
			_togli_artefatto(p, "pergamena")
			if int(s.n_taoisti) == 1:
				b.poteri = int(b.poteri) + int(s.poteri_centro)
				s.poteri_centro = 0
			else:
				for q in _altri_vivi(p):
					plancia(q).tessera = b.tessera
					plancia(q).a_terra = false
					_evento({"e": "muovi", "p": q, "t": int(b.tessera)})
			_diario("%s legge la Pergamena dell'Unità: i compagni accorrono." % nome_plancia(p))
			s.pila.append(t)
		"aiuto", "n_aiuto":
			if r == "n_aiuto":
				_usa_segnalino(p, "blu", t)
				t["blu_neutro"] = true
			t.azioni = int(t.azioni) + 1
			t.tipi.append("a")
			s.pila.append(t)
			_poi([{"k": "aiuto", "p": p, "t": int(b.tessera)}])
		"basta":
			t.fase = "fine"
			s.pila.append(t)
		"yy_libera":
			b.yinyang = false
			_diario("%s usa lo Yin-Yang." % nome_plancia(p))
			s.pila.append(t)
			_poi([{"k": "libera", "p": p, "ghost": false}])
		"yy_aiuto":
			b.yinyang = false
			_diario("%s usa lo Yin-Yang per chiedere aiuto a distanza." % nome_plancia(p))
			s.pila.append(t)
			_poi([{"k": "scegli_aiuto", "p": p}])
		"prendi_poteri":
			b.poteri = int(b.poteri) + int(s.poteri_centro)
			_diario("%s prende %d segnalini potere." % [nome_plancia(p), int(s.poteri_centro)])
			s.poteri_centro = 0
			s.pila.append(t)
		"fine":
			return
		_:
			if r.begins_with("cr:"):
				var ri := int(r.split(":")[1])
				b.cristalli = int(b.cristalli) - 1
				t["cr_posati"] = int(t.get("cr_posati", 0)) + 1
				s.ricettacoli[ri] = true
				_diario("%s mette un Cristallo di Luna nel ricettacolo." % nome_plancia(p))
				_evento({"e": "ricettacolo", "i": ri})
				_controlla_barriera()
				s.pila.append(t)
			elif r.begins_with("b:"):
				var pz := r.split(":")
				var sp := spazio(int(pz[1]), int(pz[2]))
				sp.buddha = true
				b.buddha = int(b.buddha) - 1
				_diario("%s piazza un Buddha." % nome_plancia(p))
				_evento({"e": "buddha_su", "p": int(pz[1]), "s": int(pz[2])})
				s.pila.append(t)

func _t_scegli_aiuto(t: Dictionary) -> void:
	var p := int(t.p)
	if t.has("r"):
		_poi([{"k": "aiuto", "p": p, "t": int(String(t.r).split(":")[1])}])
		return
	var o := []
	for x in 9:
		if aiuto_possibile(x, p):
			o.append({"id": "t:%d" % x, "t": nome_tessera(x), "tessera": x})
	_chiedi(t, p, "tessera_aiuto", "Quale tessera chiami in aiuto con lo Yin-Yang?", o)

func _t_libera(t: Dictionary) -> void:
	var p := int(t.p)
	if t.has("r"):
		var x := int(String(t.r).split(":")[1])
		s.villaggio[x].inf = false
		_diario("La tessera %s torna attiva." % nome_tessera(x))
		_evento({"e": "libera", "t": x})
		if t.get("ghost", false):
			_poi([{"k": "porta_fantasma", "a": p}])
		return
	var o := []
	for x in 9:
		if s.villaggio[x].inf:
			o.append({"id": "t:%d" % x, "t": nome_tessera(x), "tessera": x})
	if o.is_empty():
		return
	_chiedi(t, p, "libera", "Quale tessera infestata vuoi liberare?", o)

func _t_mantra(t: Dictionary) -> void:
	var p := int(t.p)
	if t.has("r"):
		var pz := String(t.r).split(":")
		s.mantra.p = int(pz[1])
		s.mantra.s = int(pz[2])
		_diario("Il Mantra dell'Indebolimento colpisce %s." % Dati.nome(int(spazio(int(pz[1]), int(pz[2])).c)))
		_evento({"e": "mantra", "p": int(pz[1]), "s": int(pz[2])})
		return
	var o := []
	for x in fantasmi_in_gioco():
		if not ha_mantra(x[0], x[1]):
			o.append({"id": "s:%d:%d" % [x[0], x[1]], "t": Dati.nome(int(spazio(x[0], x[1]).c)), "spazio": x})
	if o.is_empty():
		return
	_chiedi(t, p, "mantra", "Su quale fantasma metti il Mantra dell'Indebolimento?", o)

func _t_gemelli(t: Dictionary) -> void:
	var p := int(t.p)
	if t.has("r"):
		var r: String = t.r
		if r == "no":
			return
		if r.begins_with("q:"):
			t["q"] = int(r.split(":")[1])
			t.erase("r")
		else:
			var x := int(r.split(":")[1])
			var q := int(t.q)
			plancia(q).tessera = x
			plancia(q).a_terra = false
			_diario("%s accompagna %s a %s." % [nome_plancia(p), nome_plancia(q), nome_tessera(x)])
			_evento({"e": "muovi", "p": q, "t": x})
			return
	if not t.has("q"):
		var o := []
		for q in _altri_vivi(p):
			o.append({"id": "q:%d" % q, "t": nome_plancia(q), "plancia": q, "tessera": int(plancia(q).tessera)})
		o.append({"id": "no", "t": "Nessuno"})
		_chiedi(t, p, "gemelli", "Quale Taoista accompagni di una tessera?", o)
		return
	var q2 := int(t.q)
	var o2 := []
	for x in adiacenti(int(plancia(q2).tessera)):
		o2.append({"id": "t:%d" % x, "t": nome_tessera(x), "tessera": x})
	o2.append({"id": "no", "t": "Lascialo dov'è"})
	_chiedi(t, p, "gemelli_dove", "Dove sposti %s?" % nome_plancia(q2), o2)

# ------------------------------------------------------------ esorcismo

func _t_esorcismo(t: Dictionary) -> void:
	var p := int(t.p)
	var b := plancia(p)
	var bers := bersagli_esorcismo(p)
	if bers.is_empty():
		return
	var neutri: Array = t.get("neutri", [])
	var r: String = t.get("r", "")
	t.erase("r")
	if not t.has("facce"):
		# segnalino potere verde (dado in più o ritiro) prima del tiro
		if not t.has("verde") and not potere(p, "verde_0") and not potere(p, "verde_1"):
			var nv := poteri_neutri(p, neutri)
			if ("verde_0" in nv or "verde_1" in nv) and r == "":
				var chiave := "verde_0" if "verde_0" in nv else "verde_1"
				t["verde_chiave"] = chiave
				_chiedi(t, p, "verde_neutro", "Usi il segnalino potere della plancia verde (%s) per questo esorcismo?" % Dati.potere(chiave).nome,
					[{"id": "si", "t": "Sì, usa il segnalino"}, {"id": "no", "t": "No"}])
				return
			if r == "si":
				plancia(p).poteri = int(plancia(p).poteri) - 1
				s.poteri_centro = int(s.poteri_centro) + 1
				neutri.append("verde")
				t["verde"] = t.verde_chiave
				_diario("%s usa il segnalino potere verde." % nome_plancia(p))
			elif r == "no":
				t["verde"] = ""
		var n := dadi_disponibili()
		if potere(p, "verde_0") or t.get("verde", "") == "verde_0":
			n += 1
		if ha_artefatto(p, "spada") and n > 0:
			t["facce"] = _tira_tao(n - 1) + ["bianco"]
			_diario("La Spada Divina fissa un dado sul bianco.")
		else:
			t["facce"] = _tira_tao(n)
		s.dadi = {"facce": t.facce, "p": p}
		_evento({"e": "dadi", "f": t.facce, "p": p})
		_diario("%s tira %d dad%s: %s." % [nome_plancia(p), n, "o" if n == 1 else "i", _testo_facce(t.facce)])
		if (potere(p, "verde_1") or t.get("verde", "") == "verde_1") and not t.get("ritirato", false):
			var inutili := _dadi_inutili(t.facce, bers)
			var o := [{"id": "tieni", "t": "Tieni i dadi"}]
			if inutili.size() > 0:
				o.append({"id": "ritira_inutili", "t": "Ritira i dadi che non servono (%d)" % inutili.size()})
			o.append({"id": "ritira_tutti", "t": "Ritira tutti i dadi"})
			_chiedi(t, p, "ritira", "Prediletto degli Dei: puoi ritirare i dadi una volta.", o)
			return
	if r.begins_with("ritira"):
		t["ritirato"] = true
		var idx := []
		if r == "ritira_tutti":
			for i in t.facce.size():
				idx.append(i)
		else:
			idx = _dadi_inutili(t.facce, bers)
		for i in idx:
			t.facce[i] = Dati.FACCE_TAO[rng_int(6)]
		s.dadi = {"facce": t.facce, "p": p}
		_evento({"e": "dadi", "f": t.facce, "p": p})
		_diario("Nuovo tiro: %s." % _testo_facce(t.facce))
	if r.begins_with("x:"):
		_applica_esorcismo(t, r)
		return
	if r == "fallisce":
		_diario("L'esorcismo fallisce.")
		_artiglio(p, bers)
		return
	var o := opzioni_esito(p, t.facce, bers)
	if o.size() == 1 and (o[0].id == "fallisce" or int(o[0].get("costo", 0)) == 0):
		if o[0].id == "fallisce":
			_diario("L'esorcismo fallisce.")
			_evento({"e": "fallito", "p": p})
			_artiglio(p, bers)
			return
		_applica_esorcismo(t, o[0].id)
		return
	_chiedi(t, p, "esito", "Dadi: %s. Come concludi l'esorcismo?" % _testo_facce(t.facce), o)
	s.domanda["facce"] = t.facce

func _testo_facce(f: Array) -> String:
	var o := []
	for x in f:
		o.append(Dati.NOMI_COLORE[x])
	return ", ".join(o)

func _dadi_inutili(facce: Array, bers: Array) -> Array:
	var servono := {}
	for x in bers:
		if Dati.ha(int(spazio(x[0], x[1]).c), "permanente", "immune"):
			continue
		for c in requisito(x[0], x[1]):
			servono[c] = true
	var o := []
	for i in facce.size():
		var f: String = facce[i]
		if f == "bianco" and not bianco_nullo():
			continue
		if not servono.has(f):
			o.append(i)
	return o

## Le possibili conclusioni dell'esorcismo dati i dadi (con o senza segnalini)
func opzioni_esito(p: int, facce: Array, bers: Array) -> Array:
	var disp := tao_disponibili(p)
	var insiemi := []
	for x in bers:
		insiemi.append([x])
	if bers.size() == 2:
		insiemi.append(bers)
	var fatt := []
	var solo_dadi := []
	for ins in insiemi:
		var c := costo(ins, facce, disp)
		if c.get("_ok", false):
			fatt.append({"ins": ins, "c": c})
			if int(c._tot) == 0:
				solo_dadi.append(ins)
	var massimi := []
	for d in solo_dadi:
		var massimo := true
		for e in solo_dadi:
			if e.size() > d.size():
				massimo = false
		if massimo:
			massimi.append(d)
	var o := []
	for f in fatt:
		var ok := massimi.is_empty()
		for m in massimi:
			var contiene := true
			for x in m:
				if not x in f.ins:
					contiene = false
			if contiene:
				ok = true
		if not ok:
			continue
		var nomi := []
		var chiavi := []
		for x in f.ins:
			nomi.append(Dati.nome(int(spazio(x[0], x[1]).c)))
			chiavi.append("%d.%d" % [x[0], x[1]])
		var spesa := []
		for c in Dati.COLORI_TAO:
			if int(f.c.get(c, 0)) > 0:
				spesa.append("%d %s" % [int(f.c[c]), Dati.NOMI_COLORE[c]])
		var testo := "Esorcizza " + " e ".join(nomi)
		if not spesa.is_empty():
			testo += " (usa Tao: " + ", ".join(spesa) + ")"
		o.append({"id": "x:" + ",".join(chiavi), "t": testo, "costo": int(f.c._tot), "spazio": f.ins[0]})
	if massimi.is_empty():
		o.append({"id": "fallisce", "t": "Non usare segnalini: l'esorcismo fallisce"})
	return o

func _applica_esorcismo(t: Dictionary, id: String) -> void:
	var p := int(t.p)
	var ins := []
	for ch in id.substr(2).split(","):
		var pz := ch.split(".")
		ins.append([int(pz[0]), int(pz[1])])
	var c := costo(ins, t.facce, tao_disponibili(p))
	if not c.get("_ok", false):
		_diario("L'esorcismo fallisce.")
		return
	# paga con i segnalini: prima i propri, poi quelli dei compagni sulla stessa tessera
	for col in Dati.COLORI_TAO:
		var n := int(c.get(col, 0))
		if n <= 0:
			continue
		var chi := [p] + _altri_vivi(p)
		for q in chi:
			if not stesso_luogo(p, q):
				continue
			var usa := mini(n, int(plancia(q).tao[col]))
			if usa > 0:
				_rendi_tao(plancia(q), col, usa)
				n -= usa
				if q != p:
					_diario("%s presta %d Tao %s." % [nome_plancia(q), usa, Dati.NOMI_COLORE[col]])
	var ncr := int(c.get("cristalli", 0))
	if ncr > 0:
		for q in [p] + _altri_vivi(p):
			if not stesso_luogo(p, q):
				continue
			var usa := mini(ncr, int(plancia(q).get("cristalli", 0)))
			plancia(q).cristalli = int(plancia(q).get("cristalli", 0)) - usa
			s.cristalli = int(s.cristalli) + usa
			ncr -= usa
		_diario("Usat%s %d Cristall%s di Luna." % ["o" if int(c.cristalli) == 1 else "i", int(c.cristalli), "o" if int(c.cristalli) == 1 else "i"])
	var l := []
	for x in ins:
		l.append({"k": "scarta", "p": x[0], "s": x[1], "modo": "esorcismo", "a": p})
	_poi(l)

# ------------------------------------------------------------ aiuti del villaggio

func _t_aiuto(t: Dictionary) -> void:
	var p := int(t.p)
	var x := int(t.t)
	var b := plancia(p)
	var id: String = s.villaggio[x].id
	var r: String = t.get("r", "")
	t.erase("r")
	if r == "" and not t.has("fase"):
		_diario("%s chiede aiuto: %s." % [nome_plancia(p), nome_tessera(x)])
		_evento({"e": "aiuto", "p": p, "t": x})
	match id:
		"casa_te":
			if qi_in_riserva() > 0:
				b.qi = int(b.qi) + 1
				_evento({"e": "qi", "p": p, "d": 1})
				_diario("%s guadagna 1 Qi." % nome_plancia(p))
			_poi([{"k": "premio_tao", "a": p, "n": 1, "perche": "Casa del Tè"}, {"k": "porta_fantasma", "a": p}])
		"erborista":
			if not t.has("facce"):
				var n := mini(2, dadi_disponibili())
				t["facce"] = _tira_tao(n)
				s.dadi = {"facce": t.facce, "p": p}
				_evento({"e": "dadi", "f": t.facce, "p": p})
				_diario("L'erborista: %s." % _testo_facce(t.facce))
				t["i"] = 0
				if potere(p, "verde_1"):
					_chiedi(t, p, "ritira_erborista", "Erborista: %s. Prediletto degli Dei: ritiri i dadi? (vale il secondo tiro)" % _testo_facce(t.facce),
						[{"id": "tieni", "t": "Tieni i dadi"}, {"id": "ritira", "t": "Ritira i dadi"}])
					return
			if r == "ritira":
				t.facce = _tira_tao(t.facce.size())
				s.dadi = {"facce": t.facce, "p": p}
				_evento({"e": "dadi", "f": t.facce, "p": p})
				_diario("Nuovo tiro: %s." % _testo_facce(t.facce))
			if r.begins_with("c:"):
				_prendi_tao(b, r.substr(2))
				_diario("%s prende un Tao %s." % [nome_plancia(p), Dati.NOMI_COLORE[r.substr(2)]])
				t.i = int(t.i) + 1
			while int(t.i) < t.facce.size():
				var f: String = t.facce[int(t.i)]
				if f == "bianco" and s.get("luna", false) and int(s.cristalli) > 0:
					_dai_cristallo(p)
					t.i = int(t.i) + 1
					continue
				if f == "bianco":
					var col := colori_in_riserva()
					if col.is_empty():
						t.i = int(t.i) + 1
						continue
					_chiedi(t, p, "colore_tao", "Erborista: dado bianco, scegli il colore del Tao.", _opzioni_colore(col))
					return
				if _prendi_tao(b, f):
					_diario("%s prende un Tao %s." % [nome_plancia(p), Dati.NOMI_COLORE[f]])
				t.i = int(t.i) + 1
		"tempio":
			if int(s.buddha_tempio) > 0:
				s.buddha_tempio = int(s.buddha_tempio) - 1
				b.buddha = int(b.buddha) + 1
				_diario("%s prende un Buddha dal Tempio." % nome_plancia(p))
		"cerchio":
			if r.begins_with("c:"):
				var c := r.substr(2)
				if s.cerchio != "":
					s.riserva_tao[s.cerchio] = int(s.riserva_tao[s.cerchio]) + 1
				s.riserva_tao[c] = int(s.riserva_tao[c]) - 1
				s.cerchio = c
				_diario("Sul Cerchio di Preghiera ora c'è un Tao %s: i fantasmi %s hanno 1 di resistenza in meno." % [Dati.NOMI_COLORE[c], Dati.NOMI_COLORE[c]])
				_evento({"e": "cerchio", "c": c})
				return
			var o := []
			for c in colori_in_riserva():
				if c != s.cerchio:
					o.append({"id": "c:" + c, "t": "Tao " + Dati.NOMI_COLORE[c], "colore": c})
			_chiedi(t, p, "cerchio", "Quale colore indebolisci con il Cerchio di Preghiera?", o)
		"altare":
			_poi([{"k": "libera", "p": p, "ghost": true}])
		"stregone":
			if r.begins_with("s:"):
				var pz := r.split(":")
				_poi([{"k": "scarta", "p": int(pz[1]), "s": int(pz[2]), "modo": "stregone", "a": p}, {"k": "perdi_qi", "p": p}])
				return
			var o := []
			for g in fantasmi_in_gioco():
				var c := int(spazio(g[0], g[1]).c)
				if not Dati.e_incarnazione(c):
					o.append({"id": "s:%d:%d" % [g[0], g[1]], "t": Dati.nome(c), "spazio": g})
			_chiedi(t, p, "stregone", "Quale fantasma manda all'inferno lo Stregone? (perdi 1 Qi)", o)
		"cimitero":
			if r == "villico":
				_resuscita_villico(x)
				_poi([{"k": "maledizione", "a": p, "t": x}])
				return
			if r.begins_with("q:"):
				var q := int(r.split(":")[1])
				var bq := plancia(q)
				bq.vivo = true
				bq.qi = 2
				bq.tessera = x
				_diario("%s torna in vita sul Cimitero con 2 Qi." % nome_plancia(q))
				_evento({"e": "risorge", "p": q})
				_poi([{"k": "maledizione", "a": p, "t": x}])
				return
			var o := []
			for q in taoisti_morti():
				o.append({"id": "q:%d" % q, "t": nome_plancia(q), "plancia": q})
			if s.get("luna", false) and not s.villici_morti.is_empty() and puo_ricevere_villico(x, true):
				o.append({"id": "villico", "t": "Un villico ucciso: %s" % nome_villico(s.villici_morti[-1])})
			if o.size() == 1 and o[0].id == "villico":
				_resuscita_villico(x)
				_poi([{"k": "maledizione", "a": p, "t": x}])
				return
			_chiedi(t, p, "cimitero", "Chi riporti in vita?", o)
		"guardiano":
			if r.begins_with("p:"):
				var q := int(r.split(":")[1])
				for k in 3:
					if int(spazio(q, k).inf) == 1:
						spazio(q, k).inf = 0
						_evento({"e": "arretra", "p": q, "s": k})
				_diario("Il Guardiano Notturno fa arretrare gli infestatori della %s." % plancia_di(q))
				return
			var o := []
			for q in POSIZIONI:
				for k in 3:
					if int(spazio(q, k).inf) == 1:
						o.append({"id": "p:%d" % q, "t": _maiuscola(plancia_di(q)), "plancia": q})
						break
			_chiedi(t, p, "guardiano", "Su quale plancia gli infestatori tornano indietro?", o)
		"padiglione":
			_aiuto_padiglione(t, r)
		"kungfu":
			_aiuto_kungfu(t, r)
		"calligrafo":
			_aiuto_calligrafo(t, r)

func _aiuto_padiglione(t: Dictionary, r: String) -> void:
	var p := int(t.p)
	var fase: String = t.get("fase", "fantasma")
	if fase == "fantasma":
		if r.begins_with("s:"):
			var pz := r.split(":")
			t["da"] = [int(pz[1]), int(pz[2])]
			t.fase = "spazio"
			_aiuto_padiglione(t, "")
			return
		var o := []
		for g in fantasmi_in_gioco():
			o.append({"id": "s:%d:%d" % [g[0], g[1]], "t": Dati.nome(int(spazio(g[0], g[1]).c)), "spazio": g})
		var libero := false
		for q in POSIZIONI:
			if not _spazi_liberi(q).is_empty():
				libero = true
		if o.is_empty() or not libero:
			t.fase = "taoista"
			_aiuto_padiglione(t, "")
			return
		o.append({"id": "no", "t": "Non spostare fantasmi"})
		if r == "no":
			t.fase = "taoista"
			_aiuto_padiglione(t, "")
			return
		t["fase"] = "fantasma"
		_chiedi(t, p, "padiglione_fantasma", "Padiglione dei Venti Celesti: quale fantasma sposti?", o)
		return
	if fase == "spazio":
		if r.begins_with("s:"):
			var pz := r.split(":")
			_sposta_fantasma(t.da[0], t.da[1], int(pz[1]), int(pz[2]))
			t.fase = "taoista"
			_aiuto_padiglione(t, "")
			return
		var o := []
		for q in POSIZIONI:
			for x in _spazi_liberi(q):
				o.append({"id": "s:%d:%d" % [x[0], x[1]], "t": "%s, spazio %d%s" % [_maiuscola(plancia_di(x[0])), x[1] + 1, " (Buddha)" if spazio(x[0], x[1]).buddha else ""], "spazio": x})
		_chiedi(t, p, "padiglione_spazio", "Su quale spazio libero va %s?" % Dati.nome(int(spazio(t.da[0], t.da[1]).c)), o)
		return
	if fase == "taoista":
		if r == "no":
			return
		if r.begins_with("q:"):
			t["q"] = int(r.split(":")[1])
			t.fase = "dove"
			_aiuto_padiglione(t, "")
			return
		var o := []
		var chi := _altri_vivi(p) if int(s.n_taoisti) > 1 else [p]
		for q in chi:
			o.append({"id": "q:%d" % q, "t": nome_plancia(q), "plancia": q, "tessera": int(plancia(q).tessera)})
		if o.is_empty():
			return
		o.append({"id": "no", "t": "Non spostare Taoisti"})
		_chiedi(t, p, "padiglione_taoista", "Padiglione: quale Taoista sposti su una tessera qualunque?", o)
		return
	if fase == "dove":
		if r.begins_with("t:"):
			var x := int(r.split(":")[1])
			plancia(int(t.q)).tessera = x
			plancia(int(t.q)).a_terra = false
			_diario("Il vento porta %s a %s." % [nome_plancia(int(t.q)), nome_tessera(x)])
			_evento({"e": "muovi", "p": int(t.q), "t": x})
			return
		var o := []
		for x in 9:
			o.append({"id": "t:%d" % x, "t": nome_tessera(x), "tessera": x})
		_chiedi(t, p, "padiglione_dove", "Dove porta il vento %s?" % nome_plancia(int(t.q)), o)

func _sposta_fantasma(p1: int, k1: int, p2: int, k2: int) -> void:
	var a := spazio(p1, k1)
	var b := spazio(p2, k2)
	var c := int(a.c)
	var mantra := ha_mantra(p1, k1)
	b.c = c
	b.inf = a.inf
	b.dado = a.dado
	a.c = 0
	a.inf = -1
	a.dado = false
	if a.buddha and Dati.e_incarnazione(c):
		pass
	if mantra:
		s.mantra.p = p2
		s.mantra.s = k2
	_diario("Il vento sposta %s sulla %s." % [Dati.nome(c), plancia_di(p2)])
	_evento({"e": "sposta", "c": c, "da": [p1, k1], "a": [p2, k2]})
	if b.buddha:
		if not Dati.e_incarnazione(c):
			b.c = 0
			b.inf = -1
			b.dado = false
			b.buddha = false
			s.buddha_tempio = int(s.buddha_tempio) + 1
			if mantra:
				s.mantra.p = -1
				s.mantra.s = -1
			s.scarti.append(c)
			_diario("%s finisce sul Buddha ed è ricacciato all'inferno." % Dati.nome(c))
			_evento({"e": "buddha", "p": p2, "s": k2, "c": c})
		elif not Dati.ha(c, "permanente", "inafferrabile"):
			b.buddha = false
			s.buddha_tempio = int(s.buddha_tempio) + 1
	_controlla_mantra()

# ------------------------------------------------------------ fine del turno

func _t_fine_turno(t: Dictionary) -> void:
	var p := int(t.p)
	var q := (p + 1) % POSIZIONI
	var primo := -1
	for i in POSIZIONI:
		if plancia(i).taoista:
			primo = i
			break
	if q == primo:
		s.giro = int(s.giro) + 1
	_poi([{"k": "turno", "p": q}])

# ============================================================ salvataggio

func salva() -> String:
	return JSON.stringify(s)

func carica(testo: String) -> bool:
	var j = JSON.parse_string(testo)
	if not j is Dictionary or not j.has("plance"):
		return false
	s = normalizza(j)
	return true

## JSON trasforma gli interi in decimali: li riporta interi
static func normalizza(v):
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = normalizza(v[k])
		return o
	if v is Array:
		var o := []
		for x in v:
			o.append(normalizza(x))
		return o
	if v is float and v == floor(v) and absf(v) < 9.0e15:
		return int(v)
	return v

# ============================================================ White Moon (espansione)

const RICETTACOLI := [0, 2, 6, 8]

func _prepara_luna(cfg: Dictionary, posti: Array) -> void:
	s.luna = true
	s.cristalli = 4
	s.ricettacoli = [false, false, false, false]
	s.suling = {"p": -1, "k": -1, "via": false}
	s.suling_evento = false
	s.villici_morti = []
	s.villici_salvi = []
	s.barriera = false
	s.famiglie_premiate = []
	var pos_portale: String = cfg.get("portale", "centro")
	s.bonus_portale = {"centro": 0, "lato": 2, "angolo": 4}.get(pos_portale, 0)
	# 10 tessere (con la Scuola di Kung-Fu): se ne usano 9 a caso
	var tess: Array = Dati.TESSERE.duplicate() + ["kungfu"]
	_mescola(tess)
	tess = tess.slice(0, 9)
	s.villaggio = []
	for id in tess:
		s.villaggio.append({"id": id, "inf": false, "ab": []})
	var dove := 4
	if pos_portale == "lato":
		dove = [1, 3, 5, 7][rng_int(4)]
	elif pos_portale == "angolo":
		dove = RICETTACOLI[rng_int(4)]
	s.portale = dove
	s.portale_casa = dove
	# i villici: pile da 3 sulle 8 tessere senza Portale
	var vil := []
	for v in Dati.villici():
		vil.append(String(v.id))
	_mescola(vil)
	var n := int(s.n_taoisti)
	var gia: int = {1: 3, 2: 2, 3: 1, 4: 0}[n]
	for i in gia:
		s.villici_salvi.append(vil.pop_back())
	for x in 9:
		if x == dove:
			continue
		for j in 3:
			if not vil.is_empty():
				s.villaggio[x].ab.append(vil.pop_back())
	for b in s.plance:
		b.cristalli = 0
		b.artefatti = []
		b.a_terra = false

func _mazzo_luna(fantasmi: Array) -> Array:
	var wm := []
	for k in range(72, 82):
		wm.append(k)
	var tutti := fantasmi + wm
	_mescola(tutti)
	return tutti.slice(10)

func suling_su(p: int, k: int) -> bool:
	return s.get("luna", false) and int(s.suling.p) == p and int(s.suling.k) == k

func ha_artefatto(p: int, a: String) -> bool:
	if p < 0 or not s.get("luna", false):
		return false
	var b := plancia(p)
	return b.taoista and b.vivo and a in b.get("artefatti", [])

func _togli_artefatto(p: int, a: String) -> void:
	plancia(p).artefatti.erase(a)

func villico_in_cima(x: int) -> String:
	if not s.get("luna", false) or x < 0:
		return ""
	var ab: Array = s.villaggio[x].get("ab", [])
	return "" if ab.is_empty() else String(ab[-1])

func nome_villico(id: String) -> String:
	var v := Dati.villico(id)
	if v.is_empty():
		return id
	return "%s %s" % [v.ruolo, v.famiglia]

func puo_ricevere_villico(x: int, anche_infestata := false) -> bool:
	if x < 0 or x > 8:
		return false
	if s.villaggio[x].inf and not anche_infestata:
		return false
	if s.villaggio[x].inf:
		return false
	return s.villaggio[x].get("ab", []).size() < 3

func ricettacolo_di(x: int) -> int:
	return RICETTACOLI.find(x)

func _dai_cristallo(p: int) -> void:
	if int(s.get("cristalli", 0)) <= 0:
		return
	s.cristalli = int(s.cristalli) - 1
	plancia(p).cristalli = int(plancia(p).get("cristalli", 0)) + 1
	_diario("%s prende un Cristallo di Luna." % nome_plancia(p))
	_evento({"e": "cristallo", "p": p})

func _sposta_villico(da: int, a: int) -> void:
	var v: String = s.villaggio[da].ab.pop_back()
	s.villaggio[a].ab.append(v)
	_diario("%s accompagna %s a %s." % [nome_plancia(int(s.turno_di)), nome_villico(v), nome_tessera(a)])
	_evento({"e": "villico", "v": v, "da": da, "a": a})

func villici_visibili() -> Array:
	var o := []
	if not s.get("luna", false):
		return o
	for x in 9:
		if villico_in_cima(x) != "":
			o.append(x)
	return o

## Un villico muore: maledizione della sua famiglia
func _uccidi_villico(x: int, chi: int) -> void:
	var v: String = s.villaggio[x].ab.pop_back()
	s.villici_morti.append(v)
	s.suling_evento = true
	_diario("Muore %s (%d villici morti)." % [nome_villico(v), s.villici_morti.size()])
	_evento({"e": "uccidi", "v": v, "t": x})
	if s.villici_morti.size() >= 12:
		_sconfitta("Dodici villici sono morti: il villaggio è perduto.")
		return
	_maledizione_famiglia(v, x, chi)

func _maledizione_famiglia(v: String, x: int, chi: int) -> void:
	var fam: String = Dati.villico(v).get("famiglia", "")
	var f := Dati.famiglia(fam)
	var a := decisore(chi)
	match String(f.get("m", "")):
		"tao_verde", "tao_rosso", "tao_giallo", "tao_blu", "tao_nero":
			var col := String(f.m).substr(4)
			if int(s.riserva_tao[col]) > 0:
				s.riserva_tao[col] = int(s.riserva_tao[col]) - 1
				_diario("Maledizione %s: un Tao %s esce dal gioco." % [fam, Dati.NOMI_COLORE[col]])
		"incarnazione":
			var libere := []
			for k in range(56, 66):
				libere.append(k)
			for k in range(82, 88):
				libere.append(k)
			for g in fantasmi_in_gioco():
				libere.erase(int(spazio(g[0], g[1]).c))
			for k in s.mazzo:
				libere.erase(int(k))
			for k in s.scarti:
				libere.erase(int(k))
			if not libere.is_empty() and a >= 0:
				var c: int = libere[rng_int(libere.size())]
				s.inc_totali = int(s.inc_totali) + 1
				_diario("Maledizione Wu: un'altra incarnazione di Wu-Feng entra in gioco.")
				s.mazzo.push_front(c)
				_poi([{"k": "porta_fantasma", "a": a}])
		"villico":
			_poi([{"k": "uccidi_scelto", "a": chi, "perche": "Maledizione Xiang"}])
		"infesta":
			_diario("Maledizione Sheng: la tessera %s viene infestata." % nome_tessera(x))
			_poi([{"k": "infesta", "t": x}])
		"fantasma":
			_diario("Maledizione Sun: entra in gioco un fantasma.")
			if a >= 0:
				_poi([{"k": "porta_fantasma", "a": a}])
		"ultima":
			if s.mazzo.size() > 1:
				s.mazzo.pop_back()
				_diario("Maledizione Li: l'ultima carta del mazzo esce dal gioco.")
		"qi":
			_diario("Maledizione Zhou: qualcuno perde 1 Qi.")
			_poi([{"k": "perdi_qi_scelto", "a": a}])
		"a_terra":
			var q := int(s.turno_di)
			if plancia(q).taoista and plancia(q).vivo:
				plancia(q).a_terra = true
				_diario("Maledizione Hua: %s finisce a terra." % nome_plancia(q))

## Un villico arriva al Portale: se la famiglia è completa, la ricompensa
func _t_salva_villico(t: Dictionary) -> void:
	var x := int(t.t)
	var v := villico_in_cima(x)
	if v == "":
		return
	s.villaggio[x].ab.pop_back()
	s.villici_salvi.append(v)
	var fam: String = Dati.villico(v).get("famiglia", "")
	_diario("%s è in salvo nel rifugio." % nome_villico(v))
	_evento({"e": "salva", "v": v, "t": x})
	var f := Dati.famiglia(fam)
	var salvi := 0
	for w in s.villici_salvi:
		if Dati.villico(String(w)).get("famiglia", "") == fam:
			salvi += 1
	if salvi >= int(f.get("membri", 1)) and not fam in s.famiglie_premiate:
		s.famiglie_premiate.append(fam)
		_diario("La famiglia %s è al completo in salvo: %s" % [fam, f.get("ricompensa", "")])
		_premio_famiglia(String(f.get("r", "")), int(t.a))

func _premio_famiglia(r: String, a: int) -> void:
	match r:
		"pozione", "polvere", "pergamena", "fuoco", "artiglio", "armatura", "scudo", "spada":
			_poi([{"k": "dai_artefatto", "a": a, "art": r}])
		"buddha":
			for g in POSIZIONI:
				for k in 3:
					var sp := spazio(g, k)
					if int(s.buddha_tempio) > 0 and int(sp.c) == 0 and not sp.buddha:
						sp.buddha = true
						s.buddha_tempio = int(s.buddha_tempio) - 1
						_evento({"e": "buddha_posa", "p": g, "s": k})
		"cinque_tao":
			for c in Dati.COLORI_TAO:
				_poi([{"k": "premio_tao_colore", "a": a, "c": c}])
		"tre_qi":
			for i in 3:
				_poi([{"k": "premio_incarnazione", "a": a, "fase": "solo_qi"}])
		"barriera":
			s.barriera = true
			_diario("La Barriera Mistica si attiverà alla fine del turno.")

func _t_dai_artefatto(t: Dictionary) -> void:
	var vivi := taoisti_vivi()
	if vivi.is_empty():
		return
	var art: String = t.art
	if t.has("r"):
		var q := int(String(t.r).split(":")[1])
		plancia(q).artefatti.append(art)
		_diario("%s riceve l'artefatto %s." % [nome_plancia(q), Dati.artefatto(art).get("nome", art)])
		_evento({"e": "artefatto", "p": q, "a": art})
		return
	if vivi.size() == 1:
		t["r"] = "q:%d" % vivi[0]
		_t_dai_artefatto(t)
		return
	var o := []
	for q in vivi:
		o.append({"id": "q:%d" % q, "t": nome_plancia(q), "plancia": q})
	_chiedi(t, decisore(int(t.a)), "artefatto", "Chi prende l'artefatto %s?" % Dati.artefatto(art).get("nome", art), o)

func _t_premio_tao_colore(t: Dictionary) -> void:
	var c: String = t.c
	if int(s.riserva_tao[c]) <= 0:
		return
	var vivi := taoisti_vivi()
	if vivi.is_empty():
		return
	if t.has("r"):
		var q := int(String(t.r).split(":")[1])
		_prendi_tao(plancia(q), c)
		_diario("%s riceve un Tao %s." % [nome_plancia(q), Dati.NOMI_COLORE[c]])
		return
	if vivi.size() == 1:
		t["r"] = "q:%d" % vivi[0]
		_t_premio_tao_colore(t)
		return
	var o := []
	for q in vivi:
		o.append({"id": "q:%d" % q, "t": nome_plancia(q), "plancia": q})
	_chiedi(t, decisore(int(t.a)), "premio_gruppo", "Chi riceve il Tao %s?" % Dati.NOMI_COLORE[c], o)

func _t_eredita(t: Dictionary) -> void:
	var da := int(t.da)
	var arts: Array = plancia(da).get("artefatti", [])
	if arts.is_empty():
		return
	var eredi := taoisti_vivi()
	if eredi.is_empty():
		return
	if t.has("r"):
		var q := int(String(t.r).split(":")[1])
		for a in arts:
			plancia(q).artefatti.append(a)
		plancia(da).artefatti = []
		_diario("%s eredita gli artefatti di %s." % [nome_plancia(q), nome_plancia(da)])
		return
	if eredi.size() == 1:
		t["r"] = "q:%d" % eredi[0]
		_t_eredita(t)
		return
	var o := []
	for q in eredi:
		o.append({"id": "q:%d" % q, "t": nome_plancia(q), "plancia": q})
	_chiedi(t, eredi[0], "artefatto", "Chi eredita gli artefatti di %s?" % nome_plancia(da), o)

func _t_perdi_qi_scelto(t: Dictionary) -> void:
	if t.has("r"):
		_poi([{"k": "perdi_qi", "p": int(String(t.r).split(":")[1])}])
		return
	var o := []
	for b in s.plance:
		if int(b.qi) > 0 and (b.vivo or not b.taoista):
			o.append({"id": "q:%d" % int(b.pos), "t": "%s (%d Qi)" % [nome_plancia(int(b.pos)), int(b.qi)], "plancia": int(b.pos)})
	if o.is_empty():
		return
	_chiedi(t, decisore(int(t.a)), "perdi_qi", "Chi perde 1 Qi?", o)

## Il fantasma avanza: il villico in cima davanti a lui scappa di una tessera
func _t_fuga(t: Dictionary) -> void:
	var l := linea(int(t.p), int(t.s))
	var i := 0
	while i < l.size() and villico_in_cima(l[i]) == "":
		i += 1
	if i >= l.size():
		return
	var x: int = l[i]
	var dopo: int = l[i + 1] if i + 1 < l.size() else -1
	if dopo < 0 or s.villaggio[dopo].ab.size() >= 3:
		_diario("%s non trova scampo." % nome_villico(villico_in_cima(x)))
		_uccidi_villico(x, int(t.p))
		return
	var v: String = s.villaggio[x].ab.pop_back()
	s.villaggio[dopo].ab.append(v)
	_diario("%s fugge a %s." % [nome_villico(v), nome_tessera(dopo)])
	_evento({"e": "villico", "v": v, "da": x, "a": dopo})

func _t_strage(t: Dictionary) -> void:
	var x := int(t.t)
	while villico_in_cima(x) != "" and not finita():
		_uccidi_villico(x, int(s.turno_di))

## Divoratori: il villico davanti, altrimenti uno a scelta, altrimenti 1 Qi
func _t_divora(t: Dictionary) -> void:
	var p := int(t.p)
	for x in linea(p, int(t.s)):
		if villico_in_cima(x) != "":
			_diario("%s divora un villico." % Dati.nome(int(t.c)))
			_uccidi_villico(x, p)
			return
	if villici_visibili().is_empty():
		_diario("%s non trova villici: la %s perde 1 Qi." % [Dati.nome(int(t.c)), plancia_di(p)])
		_poi([{"k": "perdi_qi", "p": p}])
		return
	_poi([{"k": "uccidi_scelto", "a": p, "perche": Dati.nome(int(t.c))}])

func _t_uccidi_scelto(t: Dictionary) -> void:
	var vis := villici_visibili()
	if vis.is_empty():
		return
	if t.has("r"):
		_uccidi_villico(int(String(t.r).split(":")[1]), int(t.a))
		return
	if vis.size() == 1:
		_uccidi_villico(vis[0], int(t.a))
		return
	var o := []
	for x in vis:
		o.append({"id": "t:%d" % x, "t": "%s (%s)" % [nome_villico(villico_in_cima(x)), nome_tessera(x)], "tessera": x})
	_chiedi(t, decisore(int(t.a)), "uccidi_villico", "%s: quale villico muore?" % t.get("perche", "Un villico deve morire"), o)

func _resuscita_villico(x: int) -> void:
	var v: String = s.villici_morti.pop_back()
	s.villaggio[x].ab.append(v)
	_diario("%s torna in vita sul Cimitero." % nome_villico(v))
	_evento({"e": "villico", "v": v, "da": -1, "a": x})

## La Mutaforma cambia plancia: va sullo spazio libero della plancia successiva
func _t_muta(t: Dictionary) -> void:
	var p := int(t.p)
	for i in range(1, 4):
		var q := (p + i) % POSIZIONI
		var lib := _spazi_liberi(q)
		for x in lib:
			if not spazio(x[0], x[1]).buddha:
				_sposta_fantasma(p, int(t.s), x[0], x[1])
				_diario("La Mutaforma cambia forma e passa sulla %s." % plancia_di(q))
				return

## Su-Ling: dopo un evento negativo si può mettere o spostare su un'icona dei fantasmi
func _t_suling(t: Dictionary) -> void:
	if not s.suling_evento or s.suling.via or finita():
		return
	var a := decisore(int(t.a))
	if a < 0:
		return
	if t.has("r"):
		var r: String = t.r
		if r == "no":
			return
		var pz := r.split(":")
		var p := int(pz[1])
		var k := int(pz[2])
		s.suling.p = p
		s.suling.k = k
		s.suling_evento = false
		_diario("Su-Ling si posa davanti alla %s, spazio %d." % [plancia_di(p), k + 1])
		_evento({"e": "suling", "p": p, "s": k})
		# vicino a un ricettacolo vuoto mette un cristallo della riserva
		var x: int = linea(p, k)[0]
		var ri := ricettacolo_di(x)
		if ri >= 0 and not s.ricettacoli[ri] and int(s.cristalli) > 0:
			s.cristalli = int(s.cristalli) - 1
			s.ricettacoli[ri] = true
			_diario("Su-Ling mette un Cristallo di Luna nel ricettacolo.")
			_evento({"e": "ricettacolo", "i": ri})
			_controlla_barriera()
		return
	var o := []
	for p in POSIZIONI:
		for k in 3:
			if suling_su(p, k):
				continue
			var c := int(spazio(p, k).c)
			if c > 0 and Dati.e_incarnazione(c):
				continue
			var nome := Dati.nome(c) if c > 0 else "vuoto"
			var x: int = linea(p, k)[0]
			var ri := ricettacolo_di(x)
			var extra := " (ricettacolo)" if ri >= 0 and not s.ricettacoli[ri] and int(s.cristalli) > 0 else ""
			o.append({"id": "s:%d:%d" % [p, k], "t": "%s, spazio %d: %s%s" % [_maiuscola(plancia_di(p)), k + 1, nome, extra], "spazio": [p, k]})
	o.append({"id": "no", "t": "Lascia Su-Ling dov'è"})
	_chiedi(t, a, "suling", "Su-Ling può intervenire: dove la metti?", o)

func _controlla_barriera() -> void:
	for x in s.ricettacoli:
		if not x:
			return
	if not s.barriera:
		s.barriera = true
		_diario("Quattro cristalli nei ricettacoli: la Barriera Mistica si alzerà alla fine del turno!")
		_evento({"e": "barriera"})

## Barriera Mistica: ogni plancia salva un villico o tira 4 dadi contro i suoi fantasmi
func _t_barriera(t: Dictionary) -> void:
	if not s.barriera or finita():
		return
	var i := int(t.i)
	if i >= POSIZIONI:
		s.barriera = false
		s.ricettacoli = [false, false, false, false]
		var tot := 0
		for b in s.plance:
			tot += int(b.get("cristalli", 0))
			b.cristalli = 0
		s.cristalli = 4
		s.suling.p = -1
		s.suling.k = -1
		_diario("La Barriera Mistica si spegne: i cristalli e Su-Ling tornano nella riserva.")
		return
	var p := (int(t.a) + 1 + i) % POSIZIONI
	var a := decisore(int(t.a))
	var r: String = t.get("r", "")
	if r == "":
		var o := []
		var con_cr := _chi_ha_cristalli()
		if con_cr >= 0 and not villici_visibili().is_empty():
			o.append({"id": "salva", "t": "Spendi un cristallo e salva un villico"})
		var bers := _bersagli_barriera(p)
		if not bers.is_empty():
			o.append({"id": "dadi", "t": "Tira 4 dadi contro i fantasmi della %s" % plancia_di(p)})
		if o.is_empty():
			t.i = i + 1
			s.pila.append(t)
			return
		o.append({"id": "nulla", "t": "Niente"})
		_chiedi(t, a, "barriera", "Barriera Mistica sulla %s: che cosa fai?" % plancia_di(p), o)
		return
	t.erase("r")
	t.i = i + 1
	s.pila.append(t)
	match r:
		"salva":
			var q := _chi_ha_cristalli()
			plancia(q).cristalli = int(plancia(q).cristalli) - 1
			s.cristalli = int(s.cristalli) + 1
			var x := int(s.portale)
			if villico_in_cima(x) == "" or x < 0:
				x = villici_visibili()[0]
			_poi([{"k": "salva_villico", "t": x, "a": a}])
		"dadi":
			var facce := _tira_tao(4)
			_evento({"e": "dadi", "f": facce, "p": p})
			_diario("La Barriera tira: %s." % _testo_facce(facce))
			var disp := {"cristalli": 0}
			for c in Dati.COLORI_TAO:
				disp[c] = 0
			var q := _chi_ha_cristalli()
			disp.cristalli = 0 if q < 0 else _tutti_cristalli()
			var presi := _gruppo_massimo(_bersagli_barriera(p), facce, disp)
			if presi.is_empty():
				_diario("La Barriera non scaccia nessun fantasma.")
				return
			var cst := costo(presi, facce, disp)
			_spendi_cristalli(int(cst.get("cristalli", 0)))
			for x in presi:
				_poi([{"k": "scarta", "p": x[0], "s": x[1], "modo": "barriera", "a": a}])

func _chi_ha_cristalli() -> int:
	for q in taoisti_vivi():
		if int(plancia(q).get("cristalli", 0)) > 0:
			return q
	return -1

func _tutti_cristalli() -> int:
	var n := 0
	for q in taoisti_vivi():
		n += int(plancia(q).get("cristalli", 0))
	return n

func _spendi_cristalli(n: int) -> void:
	for q in taoisti_vivi():
		var usa := mini(n, int(plancia(q).get("cristalli", 0)))
		plancia(q).cristalli = int(plancia(q).cristalli) - usa
		s.cristalli = int(s.cristalli) + usa
		n -= usa

func _bersagli_barriera(p: int) -> Array:
	var o := []
	for k in 3:
		var c := int(spazio(p, k).c)
		if c > 0 and not Dati.e_incarnazione(c) and esorcizzabile(p, k):
			o.append([p, k])
	return o

## Il sottoinsieme più numeroso di bersagli che si riesce a pagare
func _gruppo_massimo(bers: Array, facce: Array, disp: Dictionary) -> Array:
	var migliore := []
	var n := bers.size()
	for m in range(1, 1 << n):
		var g := []
		for j in n:
			if m & (1 << j):
				g.append(bers[j])
		if g.size() > migliore.size() and costo(g, facce, disp).get("_ok", false):
			migliore = g
	return migliore

func _artiglio(p: int, bers: Array) -> void:
	if not ha_artefatto(p, "artiglio") or s.get("artiglio_giro", -1) == int(s.n_evento) or bers.is_empty():
		return
	for x in bers:
		var c := int(spazio(x[0], x[1]).c)
		for col in requisito(x[0], x[1]):
			if _prendi_tao(plancia(p), col):
				_diario("L'Artiglio Vendicativo dà a %s un Tao %s." % [nome_plancia(p), Dati.NOMI_COLORE[col]])
				return

func _t_pozione(t: Dictionary) -> void:
	var a := int(t.a)
	if t.has("r"):
		var r: String = t.r
		if r == "villico":
			var cim := indice_tessera("cimitero")
			_resuscita_villico(cim if cim >= 0 else 4)
			return
		var q := int(r.split(":")[1])
		var b := plancia(q)
		if not b.vivo:
			b.vivo = true
			b.qi = 1
			var cim := indice_tessera("cimitero")
			b.tessera = cim if cim >= 0 else 4
			_diario("%s torna in vita con 1 Qi." % nome_plancia(q))
			_evento({"e": "risorge", "p": q})
		elif qi_in_riserva() > 0:
			b.qi = int(b.qi) + 1
			_evento({"e": "qi", "p": q, "d": 1})
			_diario("%s guadagna 1 Qi dalla Pozione della Vita." % nome_plancia(q))
		return
	var o := []
	for q in taoisti_vivi():
		o.append({"id": "q:%d" % q, "t": "%s: +1 Qi" % nome_plancia(q), "plancia": q})
	for q in taoisti_morti():
		o.append({"id": "q:%d" % q, "t": "%s torna in vita" % nome_plancia(q), "plancia": q})
	if not s.villici_morti.is_empty():
		o.append({"id": "villico", "t": "Un villico torna in vita: %s" % nome_villico(s.villici_morti[-1])})
	_chiedi(t, a, "pozione", "Pozione della Vita: a chi?", o)

func _t_premio_cristallo(t: Dictionary) -> void:
	var vivi := taoisti_vivi()
	if vivi.is_empty() or int(s.get("cristalli", 0)) <= 0:
		return
	var a := int(t.a)
	if a >= 0 and plancia(a).taoista and plancia(a).vivo:
		_dai_cristallo(a)
	else:
		_dai_cristallo(vivi[0])

## Scuola di Kung-Fu: esorcismo solitario contro tutti i fantasmi di un colore
func _bersagli_kungfu(p: int, modo: String) -> Array:
	var col: String = plancia(p).colore if modo == "plancia" else "nero"
	var o := []
	for x in fantasmi_in_gioco():
		var c := int(spazio(x[0], x[1]).c)
		if Dati.e_incarnazione(c) or not esorcizzabile(x[0], x[1]):
			continue
		if Dati.carta(c).get("colore", "") == col:
			o.append(x)
	return o

func _aiuto_kungfu(t: Dictionary, r: String) -> void:
	var p := int(t.p)
	var b := plancia(p)
	if r == "":
		var o := []
		if not _bersagli_kungfu(p, "plancia").is_empty():
			o.append({"id": "k:plancia", "t": "Tutti i fantasmi %s" % Dati.NOMI_COLORE[b.colore]})
		if not _bersagli_kungfu(p, "nero").is_empty():
			o.append({"id": "k:nero", "t": "Tutti i fantasmi neri"})
		if o.size() == 1:
			r = o[0].id
		else:
			_chiedi(t, p, "kungfu", "Scuola di Kung-Fu: contro chi combatti da solo?", o)
			return
	var bers := _bersagli_kungfu(p, r.substr(2))
	var facce := _tira_tao(dadi_disponibili())
	s.dadi = {"facce": facce, "p": p}
	_evento({"e": "dadi", "f": facce, "p": p})
	_diario("Kung-Fu: %s." % _testo_facce(facce))
	var disp := {"cristalli": int(b.get("cristalli", 0))}
	for c in Dati.COLORI_TAO:
		disp[c] = 0 if tao_bloccati() else int(b.tao[c])
	var cst := costo(bers, facce, disp)
	if not cst.get("_ok", false):
		_diario("Il colpo di Kung-Fu non basta: nessun fantasma scacciato.")
		_evento({"e": "fallito", "p": p})
		return
	for c in Dati.COLORI_TAO:
		_rendi_tao(b, c, int(cst.get(c, 0)))
	b.cristalli = int(b.cristalli) - int(cst.get("cristalli", 0))
	s.cristalli = int(s.cristalli) + int(cst.get("cristalli", 0))
	for x in bers:
		_poi([{"k": "scarta", "p": x[0], "s": x[1], "modo": "kungfu", "a": p}])

# ============================================================ Black Secret (espansione): Wu-Feng giocato da qualcuno

const WU := 4                       # il "posto" di chi gioca Wu-Feng
const SLOT_PIRAMIDE := [4, 3, 2, 1]
const MANO_MALEDIZIONI := [5, 4, 3, 2]
const DEMONI := ["cercatore", "scavatore", "becchino"]

func segreto() -> bool:
	return s.get("segreto", false)

func _prepara_segreto(livello: String, n: int, base: Array) -> Array:
	s.segreto = true
	var cat := Dati.catacombe()
	s.cata = []
	for i in 9:
		s.cata.append({"col": cat.colori[i], "pila": [], "scala": true})
	for liv in n:
		var strato: Array = cat.strati[liv].duplicate()
		_mescola(strato)
		for i in 9:
			s.cata[i].pila.append(strato[i])
	s.demoni = {"cercatore": -1, "scavatore": -1, "becchino": -1}
	s.ombra = -1
	s.ombra_sotto = false
	s.urne = 0
	s.scheletri = 3
	# maledizioni: si pescano 5/4/3/2 segnalini per rango, il rango 1 è scoperto
	s.mal_pool = {}
	s.mal_mano = {}
	for r in [1, 2, 3, 4]:
		s.mal_pool[str(r)] = []
		s.mal_mano[str(r)] = []
	for m in Dati.maledizioni():
		if m.get("luna", false) and not s.get("luna", false):
			continue
		s.mal_pool[str(int(m.rango))].append(String(m.id))
	s.piramide = [0, 0, 0, 0]
	s.pir_id = [[], [], [], []]
	_pesca_maledizioni()
	# Mantra di Sangue: 3 da 2 Qi, 2 da 3 Qi, 1 da 4 Qi
	s.ms_pool = {"2": [], "3": [], "4": []}
	for m in Dati.tutti_mantra_sangue():
		if m.get("luna", false) and not s.get("luna", false):
			continue
		s.ms_pool[str(int(m.livello))].append(String(m.id))
	for k in s.ms_pool:
		_mescola(s.ms_pool[k])
	s.ms = []
	for liv in [2, 2, 2, 3, 3, 4]:
		s.ms.append({"id": s.ms_pool[str(liv)].pop_back(), "liv": liv, "qi": 0})
	# incarnazioni: un mazzo a parte in mano a Wu-Feng
	var inc := []
	for k in range(56, 66):
		inc.append(k)
	for k in range(100, 105):
		inc.append(k)
	if s.get("luna", false):
		for k in range(82, 88):
			inc.append(k)
	_mescola(inc)
	s.inc_mazzo = inc
	s.inc_mano = []
	for b in s.plance:
		b.sotto = false
		b.a_terra = b.get("a_terra", false)
	# il Calligrafo nel villaggio
	if indice_tessera("calligrafo") < 0:
		var x := rng_int(9)
		if s.get("luna", false) and x == int(s.portale):
			x = (x + 1) % 9
		s.villaggio[x].id = "calligrafo"
	# il mazzo: base + 10 nuovi fantasmi, 50/45/40/35 carte
	var tutti := base.duplicate()
	for k in range(90, 100):
		tutti.append(k)
	_mescola(tutti)
	return tutti.slice(0, {4: 50, 3: 45, 2: 40, 1: 35}[n])

func _pesca_maledizioni() -> void:
	for r in [1, 2, 3, 4]:
		var pool: Array = s.mal_pool[str(r)]
		for m in s.mal_mano[str(r)]:
			pool.append(m)
		s.mal_mano[str(r)] = []
		_mescola(pool)
		for i in MANO_MALEDIZIONI[r - 1]:
			if not pool.is_empty():
				s.mal_mano[str(r)].append(pool.pop_back())

func nome_cata(i: int) -> String:
	return "catacomba %s" % ["in alto a sinistra", "in alto", "in alto a destra", "a sinistra", "centrale", "a destra", "in basso a sinistra", "in basso", "in basso a destra"][i]

func nome_luogo(p: int) -> String:
	var b := plancia(p)
	return nome_cata(int(b.tessera)) if b.get("sotto", false) else nome_tessera(int(b.tessera))

func sotto(p: int) -> bool:
	return segreto() and plancia(p).get("sotto", false)

func stesso_luogo(p: int, q: int) -> bool:
	return int(plancia(p).tessera) == int(plancia(q).tessera) and sotto(p) == sotto(q)

func fratello(p: int) -> bool:
	var b := plancia(p)
	return segreto() and b.taoista and b.vivo and int(b.qi) == 1

func ombra_su_tessera(t: int) -> bool:
	return segreto() and int(s.ombra) == t and not s.ombra_sotto

func demoni_in(i: int) -> Array:
	var o := []
	if not segreto():
		return o
	for d in DEMONI:
		if int(s.demoni[d]) == i:
			o.append(d)
	return o

func taoisti_sotto(i: int) -> Array:
	var o := []
	for q in taoisti_vivi():
		if sotto(q) and int(plancia(q).tessera) == i:
			o.append(q)
	return o

func qi_sui_mantra() -> int:
	var n := 0
	if segreto():
		for m in s.ms:
			n += int(m.qi)
	return n

func _maledizioni_libere() -> bool:
	return effetto_in_gioco("permanente", "maledizioni_libere")

func yinyang_bloccati() -> bool:
	return segreto() and effetto_in_gioco("permanente", "no_yinyang")

# ------------------------------------------------------------ Wu-Feng pesca una carta: a) villaggio b) demone c) maledizione

func _t_wf_carta(t: Dictionary) -> void:
	var c := int(t.c)
	var a := int(t.a)
	if c == 300:
		_diario("Wu-Feng pesca un'Evocazione.")
		_pesca_incarnazione()
		_poi([{"k": "wf_gioca_inc", "a": a, "evocata": true}])
		return
	if t.has("r"):
		var r: String = t.r
		if r == "a":
			_poi([{"k": "scegli_spazio", "a": a, "c": c, "chi": WU}])
		elif r.begins_with("b:"):
			s.scarti.append(c)
			_poi([{"k": "evoca_demone", "d": r.substr(2)}])
		elif r.begins_with("m:"):
			s.scarti.append(c)
			_poi([{"k": "lancia_maledizione", "m": r.substr(2), "a": a}])
		return
	var o := [{"id": "a", "t": "Mettilo nel villaggio", "carta": c}]
	var res := 0
	for v in Dati.resistenza(c).values():
		res += int(v)
	if int(s.ombra) < 0:
		for d in DEMONI:
			if int(s.demoni[d]) == -1 and int(Dati.demone(d).costo) <= res:
				o.append({"id": "b:" + d, "t": "Evoca il %s nelle catacombe (costo %d)" % [Dati.demone(d).nome, int(Dati.demone(d).costo)]})
	for m in maledizioni_lanciabili(String(Dati.carta(c).get("colore", "nero"))):
		var md := Dati.maledizione(m)
		o.append({"id": "m:" + m, "t": "Maledizione di rango %d: %s" % [int(md.rango), md.desc], "maledizione": m})
	if o.size() == 1:
		_poi([{"k": "scegli_spazio", "a": a, "c": c, "chi": WU}])
		return
	_chiedi(t, WU, "wf_carta", "Wu-Feng ha pescato %s: che cosa ne fa?" % Dati.nome(c), o)
	s.domanda["carta"] = c

func maledizioni_lanciabili(col: String) -> Array:
	var o := []
	var libero := col == "nero" or col == "qualunque" or _maledizioni_libere()
	for r in [1, 2, 3, 4]:
		if not rango_libero(r):
			continue
		for m in s.mal_mano[str(r)]:
			if libero or String(Dati.maledizione(m).colore) == col:
				o.append(m)
	return o

func rango_libero(r: int) -> bool:
	var n: Array = s.piramide
	if int(n[r - 1]) >= SLOT_PIRAMIDE[r - 1]:
		return false
	return r == 1 or int(n[r - 2]) >= int(n[r - 1]) + 2

func _pesca_incarnazione() -> void:
	if s.inc_mazzo.is_empty():
		return
	var c := int(s.inc_mazzo.pop_back())
	s.inc_mano.append(c)
	_diario("Wu-Feng prende in mano un'incarnazione.")
	_evento({"e": "wf_mano"})

func _t_wf_gioca_inc(t: Dictionary) -> void:
	if s.inc_mano.is_empty():
		return
	if t.has("r"):
		var c := int(String(t.r).substr(2))
		s.inc_mano.erase(c)
		if not t.get("evocata", false):
			s.inc_totali = int(s.inc_totali) + 1
		_diario("Wu-Feng scatena %s!" % Dati.nome(c))
		_poi([{"k": "scegli_spazio", "a": int(t.a), "c": c, "chi": WU}])
		return
	if s.inc_mano.size() == 1:
		t["r"] = "i:%d" % int(s.inc_mano[0])
		_t_wf_gioca_inc(t)
		return
	var o := []
	for c in s.inc_mano:
		o.append({"id": "i:%d" % int(c), "t": Dati.nome(int(c)), "carta": int(c)})
	_chiedi(t, WU, "wf_incarnazione", "Quale incarnazione mette in gioco Wu-Feng?", o)

func _t_evoca_demone(t: Dictionary) -> void:
	var d: String = t.d
	if t.has("r"):
		var i := int(String(t.r).substr(2))
		s.demoni[d] = i
		_diario("Wu-Feng evoca il %s nella %s." % [Dati.demone(d).nome, nome_cata(i)])
		_evento({"e": "demone", "d": d, "i": i})
		return
	var o := []
	for i in Dati.catacombe().ingressi:
		o.append({"id": "c:%d" % int(i), "t": "Ingresso: " + nome_cata(int(i)), "cata": int(i)})
	_chiedi(t, WU, "wf_ingresso", "Da quale ingresso entra il %s?" % Dati.demone(d).nome, o)

# ------------------------------------------------------------ maledizioni

func _t_lancia_maledizione(t: Dictionary) -> void:
	var m: String = t.m
	var md := Dati.maledizione(m)
	var r := int(md.rango)
	s.mal_mano[str(r)].erase(m)
	s.mal_pool[str(r)].append(m)
	s.piramide[r - 1] = int(s.piramide[r - 1]) + 1
	s.pir_id[r - 1].append(m)
	_diario("Wu-Feng lancia una maledizione: %s" % md.desc)
	_evento({"e": "wf_maledizione", "m": m})
	var l := [{"k": "effetto_wf", "e": String(md.e), "a": int(t.get("a", s.turno_di))}]
	if r == 4:
		l.append({"k": "rinnova_maledizioni"})
	_poi(l)

func _t_rinnova_maledizioni(_t: Dictionary) -> void:
	s.piramide = [0, 0, 0, 0]
	s.pir_id = [[], [], [], []]
	_pesca_maledizioni()
	_diario("La piramide delle maledizioni è completa: Wu-Feng pesca nuove maledizioni.")

## Gli effetti decisi da Wu-Feng (maledizioni, segnalini delle catacombe, carte)
func _t_effetto_wf(t: Dictionary) -> void:
	var e: String = t.e
	var a := int(t.get("a", s.turno_di))
	var r: String = t.get("r", "")
	var vivi := taoisti_vivi()
	if vivi.is_empty():
		return
	match e:
		"tao1", "tao2":
			var con := []
			for q in vivi:
				if _tot_tao(q) > 0:
					con.append(q)
			if con.is_empty():
				return
			if r == "":
				_chiedi_taoista(t, con, "Quale Taoista scarta i Tao?")
				return
			var q := int(r.substr(2))
			for i in (1 if e == "tao1" else 2):
				var mx := ""
				for c in Dati.COLORI_TAO:
					if int(plancia(q).tao[c]) > 0 and (mx == "" or int(plancia(q).tao[c]) > int(plancia(q).tao[mx])):
						mx = c
				if mx != "":
					_rendi_tao(plancia(q), mx)
			_diario("%s perde dei segnalini Tao." % nome_plancia(q))
		"qi1":
			if r == "":
				_chiedi_taoista(t, vivi, "Quale Taoista perde 1 Qi?")
				return
			_poi([{"k": "perdi_qi", "p": int(r.substr(2))}])
		"a_terra":
			if r == "":
				_chiedi_taoista(t, vivi, "Quale Taoista finisce a terra?")
				return
			plancia(int(r.substr(2))).a_terra = true
			_diario("%s finisce a terra." % nome_plancia(int(r.substr(2))))
		"via_yinyang":
			var con := []
			for q in vivi:
				if plancia(q).yinyang:
					con.append(q)
			if con.is_empty():
				return
			if r == "":
				_chiedi_taoista(t, con, "Quale Taoista perde lo Yin-Yang?")
				return
			plancia(int(r.substr(2))).yinyang = false
			_diario("%s perde lo Yin-Yang." % nome_plancia(int(r.substr(2))))
		"dado1", "dado2":
			if r == "":
				_chiedi_taoista(t, vivi, "Contro quale Taoista si tira il dado della maledizione?")
				return
			var q := int(r.substr(2))
			var tt := int(plancia(q).tessera)
			for i in (1 if e == "dado1" else 2):
				_poi([{"k": "maledizione", "a": q, "t": tt}])
		"mantra_qi1", "mantra_tutti", "mantra_via":
			var o := []
			for i in s.ms.size():
				if e == "mantra_via" or int(s.ms[i].qi) > 0:
					o.append({"id": "ms:%d" % i, "t": "%s (%d/%d Qi)" % [Dati.mantra_sangue(s.ms[i].id).desc, int(s.ms[i].qi), int(s.ms[i].liv)], "mantra": i})
			if o.is_empty():
				return
			if r == "":
				_chiedi(t, WU, "wf_bersaglio", "Quale Mantra di Sangue colpisce Wu-Feng?", o)
				return
			var i := int(r.substr(3))
			if e == "mantra_qi1":
				s.ms[i].qi = int(s.ms[i].qi) - 1
			elif e == "mantra_tutti":
				s.ms[i].qi = 0
			else:
				_sostituisci_mantra(i)
			_diario("Wu-Feng indebolisce i Mantra di Sangue.")
		"scala1", "scala2":
			var o := []
			for i in 9:
				if s.cata[i].scala:
					o.append({"id": "c:%d" % i, "t": "Scala della " + nome_cata(i), "cata": i})
			if o.is_empty():
				return
			if r == "":
				_chiedi(t, WU, "wf_bersaglio", "Quale scala toglie Wu-Feng?", o)
				return
			s.cata[int(r.substr(2))].scala = false
			s.cata[int(r.substr(2))]["tolta"] = true
			_diario("Wu-Feng toglie la scala della %s." % nome_cata(int(r.substr(2))))
			_evento({"e": "scala", "i": int(r.substr(2))})
			if e == "scala2":
				_poi([{"k": "effetto_wf", "e": "scala1", "a": a}])
		"scheletri1", "ossa":
			_poi([{"k": "piazza_scheletro", "n": 1}])
		"scheletri2":
			_poi([{"k": "piazza_scheletro", "n": 2}])
		"scheletri3":
			_poi([{"k": "piazza_scheletro", "n": 3}])
		"fantasma":
			_poi([{"k": "porta_fantasma", "a": int(s.turno_di)}])
		"incarnazione_mano":
			_pesca_incarnazione()
		"incarnazione_gioca":
			_pesca_incarnazione()
			_poi([{"k": "wf_gioca_inc", "a": int(s.turno_di)}])
		"via_ultima", "via_due":
			for i in (1 if e == "via_ultima" else 2):
				if s.mazzo.size() > 1 and int(s.mazzo[-1]) != 300:
					s.mazzo.pop_back()
			_diario("Wu-Feng toglie carte dal fondo del mazzo.")
		"attiva_demone":
			_poi([{"k": "azione_demone", "d": "?", "da": "effetto"}])
		"tutti_demoni":
			if int(s.ombra) >= 0:
				return
			var ing: Array = Dati.catacombe().ingressi
			var j := 0
			for d in DEMONI:
				if int(s.demoni[d]) == -1:
					s.demoni[d] = int(ing[j % ing.size()])
					j += 1
					_evento({"e": "demone", "d": d, "i": int(s.demoni[d])})
			_diario("Wu-Feng evoca tutti i suoi demoni.")
		"in_catacombe":
			if r == "":
				_chiedi_taoista(t, vivi, "Quale Taoista trascina Wu-Feng nelle catacombe?")
				return
			if not t.has("q"):
				t["q"] = int(r.substr(2))
				t.erase("r")
				var o := []
				for i in 9:
					o.append({"id": "c:%d" % i, "t": nome_cata(i), "cata": i})
				_chiedi(t, WU, "wf_bersaglio", "In quale catacomba?", o)
				return
			var q := int(t.q)
			plancia(q).tessera = int(r.substr(2))
			plancia(q).sotto = true
			_diario("%s è trascinato nella %s." % [nome_plancia(q), nome_cata(int(r.substr(2)))])
			_evento({"e": "muovi", "p": q, "t": int(r.substr(2))})
		"sposta_fantasma":
			var g := fantasmi_in_gioco()
			var lib := []
			for q in POSIZIONI:
				lib += _spazi_liberi(q)
			if g.is_empty() or lib.is_empty():
				return
			if r == "":
				var o := []
				for x in g:
					o.append({"id": "s:%d:%d" % [x[0], x[1]], "t": Dati.nome(int(spazio(x[0], x[1]).c)), "spazio": x})
				_chiedi(t, WU, "wf_bersaglio", "Quale fantasma sposta Wu-Feng?", o)
				return
			if not t.has("da"):
				t["da"] = r
				t.erase("r")
				var o := []
				for x in lib:
					o.append({"id": "s:%d:%d" % [x[0], x[1]], "t": "%s, spazio %d" % [_maiuscola(plancia_di(x[0])), x[1] + 1], "spazio": x})
				_chiedi(t, WU, "wf_bersaglio", "Dove lo sposta?", o)
				return
			var da := String(t.da).split(":")
			var aa := r.split(":")
			_sposta_fantasma(int(da[1]), int(da[2]), int(aa[1]), int(aa[2]))
		"dagli_scarti":
			var o := []
			for c in s.scarti:
				if not Dati.e_incarnazione(int(c)) and int(c) != 300:
					o.append({"id": "g:%d" % int(c), "t": Dati.nome(int(c)), "carta": int(c)})
			if o.is_empty():
				return
			if r == "":
				_chiedi(t, WU, "wf_bersaglio", "Quale fantasma degli scarti torna nel villaggio?", o)
				return
			var c := int(r.substr(2))
			s.scarti.erase(c)
			_poi([{"k": "scegli_spazio", "a": int(s.turno_di), "c": c, "chi": WU}])
		"scava_pila":
			var o := []
			for i in 9:
				if not s.cata[i].pila.is_empty():
					o.append({"id": "c:%d" % i, "t": "Pila della %s (%d)" % [nome_cata(i), s.cata[i].pila.size()], "cata": i})
			if o.is_empty():
				return
			if r == "":
				_chiedi(t, WU, "wf_bersaglio", "Quale pila delle catacombe svuota Wu-Feng?", o)
				return
			var i := int(r.substr(2))
			var pila: Array = s.cata[i].pila
			var urne := pila.count("urna")
			s.cata[i].pila = []
			_diario("Wu-Feng svuota la pila della %s." % nome_cata(i))
			_evento({"e": "scava", "i": i, "s": "terra"})
			for j in urne:
				_poi([{"k": "segnalino_cata", "s": "urna", "i": i, "d": ""}])
		"infesta_qi":
			if r == "":
				var o := []
				for x in 9:
					if not s.villaggio[x].inf:
						o.append({"id": "t:%d" % x, "t": nome_tessera(x), "tessera": x})
				if o.is_empty():
					return
				_chiedi(t, WU, "wf_bersaglio", "Quale tessera infesta Wu-Feng?", o)
				return
			_poi([{"k": "infesta", "t": int(r.substr(2))}, {"k": "effetto_wf", "e": "qi1", "a": a}])
		"maledizione_libera", "tavoletta":
			var lan := maledizioni_lanciabili("qualunque")
			if lan.is_empty():
				return
			if r == "":
				var o := []
				for m in lan:
					var md := Dati.maledizione(m)
					o.append({"id": "m:" + m, "t": "Rango %d: %s" % [int(md.rango), md.desc], "maledizione": m})
				o.append({"id": "no", "t": "Nessuna maledizione"})
				_chiedi(t, WU, "wf_maledizione", "Wu-Feng può lanciare una maledizione di qualunque colore.", o)
				return
			if r != "no":
				_poi([{"k": "lancia_maledizione", "m": r.substr(2), "a": a}])
		"luna_villico":
			if s.get("luna", false) and not villici_visibili().is_empty():
				var x: int = villici_visibili()[0]
				for y in adiacenti(x):
					if puo_ricevere_villico(y):
						_sposta_villico(x, y)
						break
		"luna_cristallo":
			if s.get("luna", false):
				for i in 4:
					if s.ricettacoli[i]:
						s.ricettacoli[i] = false
						s.cristalli = int(s.cristalli) + 1
						_diario("Wu-Feng toglie un cristallo da un ricettacolo.")
						break
		"luna_uccidi":
			if s.get("luna", false):
				_poi([{"k": "uccidi_scelto", "a": WU, "perche": "Maledizione di Wu-Feng"}])
		"luna_portale":
			if s.get("luna", false) and int(s.portale) >= 0:
				s.portale = rng_int(9)
				_diario("Wu-Feng sposta il Portale su %s." % nome_tessera(int(s.portale)))

func _chiedi_taoista(t: Dictionary, chi: Array, testo: String) -> void:
	if chi.size() == 1:
		t["r"] = "q:%d" % int(chi[0])
		s.pila.append(t)
		return
	var o := []
	for q in chi:
		o.append({"id": "q:%d" % int(q), "t": "%s (%d Qi)" % [nome_plancia(int(q)), int(plancia(int(q)).qi)], "plancia": int(q)})
	_chiedi(t, WU, "wf_bersaglio", testo, o)

func _tot_tao(q: int) -> int:
	var n := 0
	for c in Dati.COLORI_TAO:
		n += int(plancia(q).tao[c])
	return n

func _t_piazza_scheletro(t: Dictionary) -> void:
	var n := int(t.n)
	if n <= 0 or int(s.scheletri) <= 0:
		return
	var lib := []
	for q in POSIZIONI:
		for k in 3:
			if int(spazio(q, k).c) == 0:
				lib.append([q, k])
	if lib.is_empty():
		_diario("Non c'è posto per lo scheletro: il Taoista di turno perde 1 Qi.")
		_poi([{"k": "perdi_qi", "p": int(s.turno_di)}])
		return
	if t.has("r"):
		var pz := String(t.r).split(":")
		var p := int(pz[1])
		var k := int(pz[2])
		s.scheletri = int(s.scheletri) - 1
		t.erase("r")
		t.n = n - 1
		s.pila.append(t)
		var sp := spazio(p, k)
		if sp.buddha:
			sp.buddha = false
			s.buddha_tempio = int(s.buddha_tempio) + 1
			s.scheletri = int(s.scheletri) + 1
			_diario("Lo scheletro finisce su un Buddha e va in polvere.")
			return
		sp.c = 200
		sp.inf = -1
		sp.dado = false
		_diario("Uno scheletro si alza davanti alla %s." % plancia_di(p))
		_evento({"e": "piazza", "c": 200, "p": p, "s": k})
		return
	var o := []
	for x in lib:
		o.append({"id": "s:%d:%d" % [x[0], x[1]], "t": "%s, spazio %d%s" % [_maiuscola(plancia_di(x[0])), x[1] + 1, " (Buddha)" if spazio(x[0], x[1]).buddha else ""], "spazio": x})
	_chiedi(t, WU, "wf_scheletro", "Dove mette lo scheletro Wu-Feng?", o)

# ------------------------------------------------------------ fase dei demoni

func _t_fase_demoni(t: Dictionary) -> void:
	var l := []
	if int(s.ombra) >= 0:
		l.append({"k": "azione_demone", "d": "ombra"})
	else:
		for d in DEMONI:
			if int(s.demoni[d]) >= 0:
				l.append({"k": "azione_demone", "d": d})
	_poi(l)

func _t_azione_demone(t: Dictionary) -> void:
	var d: String = t.d
	if d == "?":
		var o := []
		if int(s.ombra) >= 0:
			t.d = "ombra"
		else:
			for x in DEMONI:
				if int(s.demoni[x]) >= 0:
					o.append({"id": "d:" + x, "t": Dati.demone(x).nome})
			if o.is_empty():
				return
			if not t.has("r"):
				if o.size() == 1:
					t.d = o[0].id.substr(2)
				else:
					_chiedi(t, WU, "wf_demone", "Quale demone attiva Wu-Feng?", o)
					return
			else:
				t.d = String(t.r).substr(2)
				t.erase("r")
		d = t.d
	if d == "ombra":
		_azione_ombra(t)
		return
	var i := int(s.demoni[d])
	if i < 0:
		return
	if t.has("r"):
		var r: String = t.r
		if r == "scava":
			var tok: String = s.cata[i].pila.pop_back()
			_evento({"e": "scava", "i": i, "s": tok})
			_diario("Il %s scava nella %s e trova: %s." % [Dati.demone(d).nome, nome_cata(i), Dati.catacombe().segnalini[tok].nome])
			_poi([{"k": "segnalino_cata", "s": tok, "i": i, "d": d}])
		elif r.begins_with("c:"):
			s.demoni[d] = int(r.substr(2))
			_diario("Il %s si sposta nella %s." % [Dati.demone(d).nome, nome_cata(int(r.substr(2)))])
			_evento({"e": "demone", "d": d, "i": int(r.substr(2))})
		return
	var o := []
	if not s.cata[i].pila.is_empty() and (taoisti_sotto(i).is_empty() or d == "scavatore"):
		o.append({"id": "scava", "t": "Scava (%d segnalini)" % s.cata[i].pila.size(), "cata": i})
	for x in adiacenti(i):
		o.append({"id": "c:%d" % x, "t": "Vai nella " + nome_cata(x), "cata": x})
	o.append({"id": "c:%d" % i, "t": "Resta fermo"})
	_chiedi(t, WU, "wf_demone_azione", "Che cosa fa il %s?" % Dati.demone(d).nome, o)
	s.domanda["demone"] = d

func _azione_ombra(t: Dictionary) -> void:
	var x := int(s.ombra)
	var giu: bool = s.ombra_sotto
	var qui := []
	for q in taoisti_vivi():
		if int(plancia(q).tessera) == x and sotto(q) == giu:
			qui.append(q)
	if t.has("r"):
		var r: String = t.r
		if r == "attacca":
			var f := _tira_tao(3)
			_evento({"e": "dadi", "f": f, "p": -1})
			var neri := f.count("nero")
			_diario("L'Ombra di Wu-Feng attacca: %s." % _testo_facce(f))
			for j in neri:
				var bersaglio: int = qui[j % qui.size()]
				_poi([{"k": "perdi_qi", "p": bersaglio}])
		elif r == "tessera":
			_diario("L'Ombra di Wu-Feng maledice la tessera %s." % nome_tessera(x))
			_poi([{"k": "maledizione", "a": int(s.turno_di), "t": x}])
		elif r.begins_with("v:") or r.begins_with("c:"):
			s.ombra = int(r.substr(2))
			s.ombra_sotto = r.begins_with("c:")
			_diario("L'Ombra di Wu-Feng si sposta: %s." % (nome_cata(int(s.ombra)) if s.ombra_sotto else nome_tessera(int(s.ombra))))
			_evento({"e": "ombra", "i": int(s.ombra), "sotto": s.ombra_sotto})
		return
	var o := []
	if not qui.is_empty():
		o.append({"id": "attacca", "t": "Attacca i Taoisti qui (3 dadi, ogni nero toglie 1 Qi)"})
	elif not giu:
		o.append({"id": "tessera", "t": "Maledici la tessera (dado della maledizione)"})
	for y in 9:
		if y != x or giu:
			o.append({"id": "v:%d" % y, "t": "Vai su " + nome_tessera(y), "tessera": y})
		if y != x or not giu:
			o.append({"id": "c:%d" % y, "t": "Vai nella " + nome_cata(y), "cata": y})
	_chiedi(t, WU, "wf_ombra", "Che cosa fa l'Ombra di Wu-Feng?", o)

func _t_segnalino_cata(t: Dictionary) -> void:
	var tok: String = t.s
	var d: String = t.d
	var a := int(s.turno_di)
	match tok:
		"buddha":
			if d != "" and d != "ombra":
				s.demoni[d] = -1
				_diario("Il Buddha scaccia il %s." % Dati.demone(d).nome)
				_evento({"e": "demone", "d": d, "i": -1})
		"sangue_suling":
			_poi([{"k": "ms_scegli", "modo": "attiva", "a": a}])
		"sangue_giusto":
			if qi_in_riserva() > 0:
				_poi([{"k": "ms_scegli", "modo": "qi", "a": a}])
		"tavoletta":
			_poi([{"k": "effetto_wf", "e": "tavoletta", "a": a}])
		"ossa":
			_poi([{"k": "piazza_scheletro", "n": 1}])
		"urna":
			s.urne = int(s.urne) + 1
			_diario("Wu-Feng trova un'urna con le sue ceneri (%d su 3)." % int(s.urne))
			_evento({"e": "urna", "n": int(s.urne)})
			_pesca_incarnazione()
			if int(s.urne) >= 3 and int(s.ombra) < 0:
				s.ombra = int(t.i)
				s.ombra_sotto = true
				for x in DEMONI:
					s.demoni[x] = -2
				_diario("LE TRE URNE SONO RIUNITE: l'Ombra di Wu-Feng entra in gioco, invincibile!")
				_evento({"e": "ombra", "i": int(t.i), "sotto": true, "nasce": true})

# ------------------------------------------------------------ Mantra di Sangue

func _sostituisci_mantra(i: int) -> void:
	var liv := int(s.ms[i].liv)
	var pool: Array = s.ms_pool[str(liv)]
	s.ms[i].qi = 0
	if pool.is_empty():
		return
	s.ms[i].id = pool.pop_back()

## Il Qi perso finisce su un Mantra di Sangue a scelta di chi lo perde
func _t_ms_scegli(t: Dictionary) -> void:
	var modo: String = t.modo
	var chi := decisore(int(t.get("a", -1)))
	if t.has("r"):
		var i := int(String(t.r).substr(3))
		if modo == "attiva":
			_attiva_mantra(i, chi)
			return
		s.ms[i].qi = int(s.ms[i].qi) + 1
		_evento({"e": "ms", "i": i})
		if int(s.ms[i].qi) >= int(s.ms[i].liv):
			_attiva_mantra(i, chi)
		return
	var o := []
	for i in s.ms.size():
		var m := Dati.mantra_sangue(s.ms[i].id)
		o.append({"id": "ms:%d" % i, "t": "[%d/%d] %s" % [int(s.ms[i].qi), int(s.ms[i].liv), m.desc], "mantra": i})
	var testo := "Su quale Mantra di Sangue va il Qi?" if modo != "attiva" else "Sangue di Su-Ling: quale Mantra di Sangue attivi?"
	_chiedi(t, chi, "ms_qi" if modo != "attiva" else "ms_attiva", testo, o)

func _attiva_mantra(i: int, chi: int) -> void:
	var id: String = s.ms[i].id
	_diario("Si attiva il Mantra di Sangue: %s" % Dati.mantra_sangue(id).desc)
	_evento({"e": "ms_attiva", "i": i})
	_sostituisci_mantra(i)
	_poi([{"k": "effetto_ms", "e": id, "a": chi}])

func _t_effetto_ms(t: Dictionary) -> void:
	var e: String = t.e
	var a := int(t.a)
	var r: String = t.get("r", "")
	var vivi := taoisti_vivi()
	match e:
		"scale2":
			var n := 0
			for i in 9:
				if n < 2 and not s.cata[i].scala and s.cata[i].get("tolta", false) and not s.villaggio[i].inf:
					s.cata[i].scala = true
					s.cata[i].tolta = false
					n += 1
					_evento({"e": "scala", "i": i})
			_diario("Tornano %d scale nelle catacombe." % n)
		"fondo":
			if not s.mazzo.is_empty():
				s.mazzo.append(s.mazzo.pop_front())
				_diario("La carta in cima al mazzo scivola in fondo.")
		"qi1":
			if r == "":
				_chiedi_tao(t, a, vivi, "Chi guadagna 1 Qi?")
				return
			if qi_in_riserva() > 0:
				var q := int(r.substr(2))
				plancia(q).qi = int(plancia(q).qi) + 1
				_evento({"e": "qi", "p": q, "d": 1})
				_diario("%s guadagna 1 Qi." % nome_plancia(q))
		"tao_mantra", "tao2_mantra":
			if r == "":
				_chiedi_tao(t, a, vivi, "Chi prende i Tao?")
				return
			var q := int(r.substr(2))
			_poi([{"k": "premio_tao", "a": q, "n": 1 if e == "tao_mantra" else 2}, {"k": "mantra", "p": q}])
		"scarta1", "scarta2":
			var g := []
			for x in fantasmi_in_gioco():
				if not Dati.e_incarnazione(int(spazio(x[0], x[1]).c)):
					g.append(x)
			if g.is_empty():
				return
			if r == "":
				var o := []
				for x in g:
					o.append({"id": "s:%d:%d" % [x[0], x[1]], "t": Dati.nome(int(spazio(x[0], x[1]).c)), "spazio": x})
				_chiedi(t, a, "ms_bersaglio", "Quale fantasma va negli scarti?", o)
				return
			var pz := r.split(":")
			_poi([{"k": "scarta", "p": int(pz[1]), "s": int(pz[2]), "modo": "mantra", "a": a}])
			if e == "scarta2":
				_poi([{"k": "effetto_ms", "e": "scarta1", "a": a}])
		"via_maledizione":
			for liv in [4, 3, 2, 1]:
				if int(s.piramide[liv - 1]) > 0 and (liv == 4 or int(s.piramide[liv]) == 0 or int(s.piramide[liv - 1]) > int(s.piramide[liv]) + 1):
					s.piramide[liv - 1] = int(s.piramide[liv - 1]) - 1
					if not s.pir_id[liv - 1].is_empty():
						s.pir_id[liv - 1].pop_back()
					_diario("Una maledizione di rango %d lascia la piramide di Wu-Feng." % liv)
					return
		"teletrasporto", "sposta2":
			if r == "":
				_chiedi_tao(t, a, vivi, "Quale Taoista si sposta?")
				return
			if not t.has("q"):
				t["q"] = int(r.substr(2))
				t.erase("r")
				var o := []
				for y in 9:
					o.append({"id": "v:%d" % y, "t": nome_tessera(y), "tessera": y})
					o.append({"id": "c:%d" % y, "t": _maiuscola(nome_cata(y)), "cata": y})
				_chiedi(t, a, "ms_bersaglio", "Dove va?", o)
				return
			var q := int(t.q)
			plancia(q).tessera = int(r.substr(2))
			plancia(q).sotto = r.begins_with("c:")
			plancia(q).a_terra = false
			_diario("%s si sposta: %s." % [nome_plancia(q), nome_luogo(q)])
			_evento({"e": "muovi", "p": q, "t": int(r.substr(2))})
			if e == "sposta2" and not fantasmi_in_gioco().is_empty():
				_poi([{"k": "sposta_fantasma_ms", "a": a}])
		"scheletri_via":
			for q in POSIZIONI:
				for k in 3:
					if int(spazio(q, k).c) == 200:
						spazio(q, k).c = 0
						s.scheletri = int(s.scheletri) + 1
						_evento({"e": "esorcizza", "c": 200, "p": q, "s": k, "modo": "mantra"})
			_diario("Tutti gli scheletri tornano polvere.")
		"yinyang":
			for q in vivi:
				if not plancia(q).yinyang:
					plancia(q).yinyang = true
					_diario("%s riprende lo Yin-Yang." % nome_plancia(q))
					return
		"demone_via", "demoni_via":
			for d in DEMONI:
				if int(s.demoni[d]) >= 0:
					s.demoni[d] = -1
					_evento({"e": "demone", "d": d, "i": -1})
					_diario("Il %s torna sulla plancia di Wu-Feng." % Dati.demone(d).nome)
					if e == "demone_via":
						return
		"buddha2":
			var n := 0
			for q in POSIZIONI:
				for k in 3:
					var sp := spazio(q, k)
					if n < 2 and int(s.buddha_tempio) > 0 and int(sp.c) == 0 and not sp.buddha:
						sp.buddha = true
						s.buddha_tempio = int(s.buddha_tempio) - 1
						n += 1
						_evento({"e": "buddha_posa", "p": q, "s": k})
		"disinfesta":
			for x in 9:
				if s.villaggio[x].inf:
					s.villaggio[x].inf = false
					_evento({"e": "libera", "t": x})
			_diario("Tutte le tessere del villaggio tornano attive.")
		"condividi":
			for q in vivi:
				if not plancia(q).yinyang:
					plancia(q).yinyang = true
					break
			var ord := vivi.duplicate()
			ord.sort_custom(func(x, y): return int(plancia(x).qi) < int(plancia(y).qi))
			for i in 2:
				if qi_in_riserva() > 0 and not ord.is_empty():
					var q: int = ord[i % ord.size()]
					plancia(q).qi = int(plancia(q).qi) + 1
			_diario("I Taoisti si dividono uno Yin-Yang e 2 Qi.")
		"riciclo":
			var g := []
			for c in s.scarti:
				if not Dati.e_incarnazione(int(c)) and int(c) != 300:
					g.append(int(c))
			g.sort_custom(func(x, y): return Dati.forza(x) < Dati.forza(y))
			for i in mini(4, g.size()):
				s.scarti.erase(g[i])
				s.mazzo.append(g[i])
			_diario("Quattro fantasmi degli scarti tornano in fondo al mazzo.")
		"luna_salva1", "luna_salva1b", "luna_salva2":
			if s.get("luna", false):
				for i in (2 if e == "luna_salva2" else 1):
					var x := int(s.portale)
					if x < 0 or villico_in_cima(x) == "":
						var vis := villici_visibili()
						if vis.is_empty():
							break
						x = vis[0]
					_poi([{"k": "salva_villico", "t": x, "a": a}])

func _chiedi_tao(t: Dictionary, a: int, chi: Array, testo: String) -> void:
	if chi.is_empty():
		return
	if chi.size() == 1:
		t["r"] = "q:%d" % int(chi[0])
		s.pila.append(t)
		return
	var o := []
	for q in chi:
		o.append({"id": "q:%d" % int(q), "t": "%s (%d Qi)" % [nome_plancia(int(q)), int(plancia(int(q)).qi)], "plancia": int(q)})
	_chiedi(t, decisore(a), "ms_bersaglio", testo, o)

func _t_sposta_fantasma_ms(t: Dictionary) -> void:
	var r: String = t.get("r", "")
	var lib := []
	for q in POSIZIONI:
		lib += _spazi_liberi(q)
	if lib.is_empty():
		return
	if r == "":
		var o := []
		for x in fantasmi_in_gioco():
			o.append({"id": "s:%d:%d" % [x[0], x[1]], "t": Dati.nome(int(spazio(x[0], x[1]).c)), "spazio": x})
		_chiedi(t, decisore(int(t.a)), "ms_bersaglio", "Quale fantasma sposti?", o)
		return
	if not t.has("da"):
		t["da"] = r
		t.erase("r")
		var o := []
		for x in lib:
			o.append({"id": "s:%d:%d" % [x[0], x[1]], "t": "%s, spazio %d" % [_maiuscola(plancia_di(x[0])), x[1] + 1], "spazio": x})
		_chiedi(t, decisore(int(t.a)), "ms_bersaglio", "Dove lo metti?", o)
		return
	var da := String(t.da).split(":")
	var aa := r.split(":")
	_sposta_fantasma(int(da[1]), int(da[2]), int(aa[1]), int(aa[2]))

# ------------------------------------------------------------ Taoisti nelle catacombe

func scala_qui(p: int) -> bool:
	var x := int(plancia(p).tessera)
	return segreto() and s.cata[x].scala

func demoni_esorcizzabili(p: int) -> Array:
	if not sotto(p):
		return []
	return demoni_in(int(plancia(p).tessera))

func requisito_demone(d: String, i: int) -> Dictionary:
	var r := {}
	r[String(s.cata[i].col)] = int(Dati.demone(d).resistenza)
	return r

## Esorcismo nelle catacombe: si tirano i dadi, poi si sceglie il demone
func _t_esorcizza_demone(t: Dictionary) -> void:
	var p := int(t.p)
	var i := int(plancia(p).tessera)
	if not t.has("facce"):
		var n := dadi_disponibili()
		t["facce"] = _tira_tao(n)
		s.dadi = {"facce": t.facce, "p": p}
		_evento({"e": "dadi", "f": t.facce, "p": p})
		_diario("%s tira %d dadi nelle catacombe: %s." % [nome_plancia(p), n, _testo_facce(t.facce)])
	if t.has("r"):
		var r: String = t.r
		if r == "fallisce":
			_diario("Il demone resiste.")
			_evento({"e": "fallito", "p": p})
			return
		var d := r.substr(2)
		var cst := _costo_demone(p, d, i, t.facce)
		for q in [p] + _altri_vivi(p):
			if not stesso_luogo(p, q):
				continue
			for c in Dati.COLORI_TAO:
				var usa := mini(int(cst.get(c, 0)), int(plancia(q).tao[c]))
				_rendi_tao(plancia(q), c, usa)
				cst[c] = int(cst.get(c, 0)) - usa
		s.demoni[d] = -1
		_diario("%s esorcizza il %s!" % [nome_plancia(p), Dati.demone(d).nome])
		_evento({"e": "demone", "d": d, "i": -1, "esorcizzato": true, "da": i})
		if d == "becchino":
			_poi([{"k": "maledizione", "a": p, "t": i}])
		return
	var o := []
	for d in demoni_in(i):
		if _costo_demone(p, d, i, t.facce).get("_ok", false):
			o.append({"id": "d:" + d, "t": "Esorcizza il %s" % Dati.demone(d).nome, "cata": i})
	o.append({"id": "fallisce", "t": "Nessun demone" if o.is_empty() else "Rinuncia"})
	_chiedi(t, p, "esorcismo_demone", "Quale demone esorcizzi?", o)

func _costo_demone(p: int, d: String, i: int, facce: Array) -> Dictionary:
	var col: String = s.cata[i].col
	var serve := int(Dati.demone(d).resistenza)
	var buoni := 0
	for f in facce:
		if f == col or f == "bianco":
			buoni += 1
	var manca := maxi(0, serve - buoni)
	if manca == 0:
		return {"_ok": true}
	if d == "cercatore":
		return {"_ok": false}
	var ha := 0
	for q in [p] + _altri_vivi(p):
		if stesso_luogo(p, q) and not tao_bloccati():
			ha += int(plancia(q).tao[col])
	var o := {"_ok": ha >= manca}
	o[col] = manca
	return o

## Calligrafo: cambia un Mantra di Sangue e/o mette 1 Qi della riserva su uno
func _aiuto_calligrafo(t: Dictionary, r: String) -> void:
	var p := int(t.p)
	t["fase"] = "c"
	var fatti: Array = t.get("fatti", [])
	if r.begins_with("cm:"):
		_sostituisci_mantra(int(r.substr(3)))
		_diario("Il Calligrafo riscrive un Mantra di Sangue.")
		fatti.append("cambia")
	elif r.begins_with("qm:"):
		var i := int(r.substr(3))
		fatti.append("qi")
		t["fatti"] = fatti
		t.erase("r")
		s.pila.append(t)
		s.ms[i].qi = int(s.ms[i].qi) + 1
		_evento({"e": "ms", "i": i})
		if int(s.ms[i].qi) >= int(s.ms[i].liv):
			_attiva_mantra(i, p)
		return
	elif r == "basta":
		return
	t["fatti"] = fatti
	var o := []
	for i in s.ms.size():
		var m := Dati.mantra_sangue(s.ms[i].id)
		if not "qi" in fatti and qi_in_riserva() > 0:
			o.append({"id": "qm:%d" % i, "t": "1 Qi su: [%d/%d] %s" % [int(s.ms[i].qi), int(s.ms[i].liv), m.desc], "mantra": i})
		if not "cambia" in fatti:
			o.append({"id": "cm:%d" % i, "t": "Cambia: %s" % m.desc, "mantra": i})
	if o.is_empty():
		return
	o.append({"id": "basta", "t": "Basta così"})
	t.erase("r")
	_chiedi(t, p, "calligrafo", "Calligrafo: che cosa fai con i Mantra di Sangue?", o)
