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
	fantasmi = fantasmi.slice(togli)
	var inc := []
	for k in range(56, 66):
		inc.append(k)
	_mescola(inc)
	var n_inc := 1
	if livello in ["incubo", "inferno"]:
		n_inc = 4 if n >= 3 else 3
	s.inc_totali = n_inc
	# dal fondo: 10 fantasmi, un'incarnazione, 10 fantasmi, un'incarnazione... poi il resto in cima
	var fondo := []
	for k in n_inc:
		for j in 10:
			fondo.append(fantasmi.pop_back())
		fondo.append(inc[k])
	fondo.reverse()
	s.mazzo = fantasmi + fondo  # indice 0 = la carta in cima
	_diario("Inizia la partita: livello %s, %d Taoist%s." % [Dati.NOMI_LIVELLO[livello], n, "a" if n == 1 else "i"])
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
		if c > 0 and Dati.ha(c, "arrivo", "potere"):
			return true
	return poteri_bloccati()

## Il potere della plancia del Taoista è utilizzabile da lui?
func potere(p: int, chiave: String) -> bool:
	var b := plancia(p)
	if not b.taoista or not b.vivo:
		return false
	if "%s_%d" % [b.colore, int(b.lato)] != chiave:
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
	var n := QI_TOTALI
	for b in s.plance:
		n -= int(b.qi)
	return maxi(n, 0)

## Chi decide quando la scelta è di gruppo o tocca a una plancia neutra
func decisore(p: int) -> int:
	if p >= 0 and plancia(p).taoista and plancia(p).vivo:
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
	if tao_bloccati():
		return o
	var t := int(plancia(p).tessera)
	for q in taoisti_vivi():
		if int(plancia(q).tessera) == t:
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
		var imm := Dati.ha(int(spazio(x[0], x[1]).c), "permanente", "immune")
		for c in r:
			if imm:
				solo_tao[c] = int(solo_tao.get(c, 0)) + int(r[c])
			else:
				req[c] = int(req.get(c, 0)) + int(r[c])
	var deficit := {}
	for c in req:
		deficit[c] = maxi(0, int(req[c]) - int(dadi.get(c, 0)))
	# i bianchi prima dove mancano i segnalini, poi dove fanno risparmiare
	var w := bianchi
	var token := {}
	for c in Dati.COLORI_TAO:
		token[c] = int(solo_tao.get(c, 0))
	var resto := {}
	for c in deficit:
		var manca := int(deficit[c]) + int(token[c]) - int(disp.get(c, 0))
		if manca > 0:
			if manca > w:
				return {"_ok": false}
			w -= manca
			resto[c] = int(deficit[c]) - manca
		else:
			resto[c] = int(deficit[c])
	for c in resto:
		var usa := mini(w, int(resto[c]))
		w -= usa
		resto[c] = int(resto[c]) - usa
	var tot := 0
	for c in Dati.COLORI_TAO:
		token[c] = int(token[c]) + int(resto.get(c, 0))
		if int(token[c]) > int(disp.get(c, 0)):
			return {"_ok": false}
		tot += int(token[c])
	token["_ok"] = true
	token["_tot"] = tot
	return token

## Probabilità (0-1) di esorcizzare almeno i bersagli dati tirando n dadi con i segnalini disponibili.
## Conta le combinazioni di facce (non le sequenze) e ricorda i risultati già calcolati.
static var _cache_prob := {}
static var _combinazioni := {}

func probabilita(bersagli: Array, n: int, disp: Dictionary) -> float:
	var chiave: String = str(n) + "|" + str(disp) + "|" + str(bianco_nullo()) + "|" + s.cerchio
	for x in bersagli:
		chiave += "|" + str(requisito(x[0], x[1])) + str(Dati.ha(int(spazio(x[0], x[1]).c), "permanente", "immune")) + str(ha_mantra(x[0], x[1]))
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
		_: push_error("compito sconosciuto " + str(t.k))

func _t_turno(t: Dictionary) -> void:
	var p := int(t.p)
	var b := plancia(p)
	s.turno_di = p
	s.dadi = {}
	if b.taoista and b.vivo:
		s.ultimo_taoista = p
	_diario("— Turno: %s —" % nome_plancia(p) + (" (morto)" if b.taoista and not b.vivo else ""))
	_evento({"e": "turno", "p": p})
	var l := [{"k": "yin_azioni", "p": p}]
	l.append({"k": "yin_arrivo", "p": p})
	if b.taoista and b.vivo:
		l.append({"k": "yang", "p": p, "fase": "inizio", "azioni": 0, "tipi": [], "neutri": [], "usati": []})
	l.append({"k": "fine_turno", "p": p})
	_poi(l)

func _t_yin_azioni(t: Dictionary) -> void:
	var p := int(t.p)
	var l := []
	for k in [2, 1, 0]:
		var c := int(spazio(p, k).c)
		if c <= 0:
			continue
		for eff in Dati.carta(c).get("turno", []):
			match eff:
				"infestante": l.append({"k": "infestante", "p": p, "s": k, "c": c})
				"tormento": l.append({"k": "maledizione", "a": p, "p": p, "s": k, "c": c})
				"gruppo_tao": l.append({"k": "gruppo_tao", "c": c})
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
	else:
		sp.inf = 0
		_diario("%s infesta il villaggio!" % Dati.nome(int(sp.c)))
		_poi([{"k": "infesta", "p": p, "s": k}])

func _t_infesta(t: Dictionary) -> void:
	if t.has("t"):
		_infesta_tessera(int(t.t))
		return
	var l := linea(int(t.p), int(t.s))
	for x in l:
		if not s.villaggio[x].inf:
			_infesta_tessera(x)
			return
	_sconfitta("Le tre tessere davanti a un fantasma sono già infestate.")

func _infesta_tessera(x: int) -> void:
	if s.villaggio[x].inf:
		return
	s.villaggio[x].inf = true
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
	_chiedi(t, decisore(a), "piazza", "Dove entra %s?" % Dati.nome(c), o)
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
	_evento({"e": "piazza", "c": c, "p": p, "s": k})
	if inc:
		_diario("ATTENZIONE: è arrivata un'incarnazione di Wu-Feng: %s!" % Dati.nome(c))
	_controlla_ultima()
	if finita():
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
		"maledizione":
			_poi([{"k": "maledizione", "a": a, "p": p, "s": k, "c": c}])
		"cerchio":
			if s.cerchio != "":
				s.riserva_tao[s.cerchio] = int(s.riserva_tao[s.cerchio]) + 1
				_diario("Il Senza Nome scaccia il segnalino del Cerchio di Preghiera.")
				s.cerchio = ""

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
	b.tessera = cim
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
	s.scarti.append(c)
	_evento({"e": "esorcizza", "c": c, "p": p, "s": k, "modo": t.modo})
	var a := int(t.get("a", -1))
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
	if Dati.e_incarnazione(c):
		s.inc_sconfitte = int(s.inc_sconfitte) + 1
		_diario("Un'incarnazione di Wu-Feng è sconfitta (%d su %d)." % [int(s.inc_sconfitte), int(s.inc_totali)])
		if int(s.inc_sconfitte) >= int(s.inc_totali):
			l.append({"k": "vittoria"})
		else:
			l.append({"k": "premio_incarnazione", "a": a, "fase": "qi"})
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
		else:
			plancia(q).yinyang = true
			_diario("%s riceve lo Yin-Yang dall'incarnazione sconfitta." % nome_plancia(q))
		return
	var o := []
	for q in vivi:
		if t.fase == "qi" or not plancia(q).yinyang:
			o.append({"id": "q:%d" % q, "t": "%s (%d Qi)" % [nome_plancia(q), int(plancia(q).qi)], "plancia": q})
	if o.is_empty():
		return
	if t.fase == "qi" and qi_in_riserva() <= 0:
		_poi([{"k": "premio_incarnazione", "a": t.a, "fase": "yy"}])
		return
	if o.size() == 1:
		t["r"] = o[0].id
		_t_premio_incarnazione(t)
		return
	_chiedi(t, decisore(int(t.a)), "premio_gruppo", "Chi riceve %s dell'incarnazione sconfitta?" % ("il Qi" if t.fase == "qi" else "lo Yin-Yang"), o)

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
		"fine": "Fine del turno."}[t.fase]
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
	if t.fase == "inizio":
		var vicine := adiacenti(qui)
		var vola := potere(p, "rosso_1")
		for x in 9:
			if x == qui:
				o.append({"id": "m:%d" % x, "t": "Resta su %s" % nome_tessera(x), "tessera": x})
			elif x in vicine or vola:
				o.append({"id": "m:%d" % x, "t": "Vai a %s" % nome_tessera(x), "tessera": x})
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
		var puo_e := false
		var puo_a := false
		if fatte < mx:
			if fatte == 0:
				puo_e = true
				puo_a = true
			elif potere(p, "blu_0"):
				puo_e = tipi[0] == "e"
				puo_a = tipi[0] == "a"
			elif potere(p, "blu_1"):
				puo_e = not "e" in tipi
				puo_a = not "a" in tipi
		var extra_e := false
		var extra_a := false
		if fatte >= 1 and fatte >= mx and not t.get("blu_neutro", false):
			if "blu_0" in neutri:
				extra_e = tipi[0] == "e"
				extra_a = tipi[0] == "a"
			elif "blu_1" in neutri:
				extra_e = not "e" in tipi
				extra_a = not "a" in tipi
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
		o.append({"id": "fine", "t": "Fine turno"})
	# lo Yin-Yang si può usare prima o dopo ogni passo
	if b.yinyang:
		if n_infestate() > 0:
			o.append({"id": "yy_libera", "t": "Yin-Yang: libera una tessera infestata"})
		var dist := false
		for x in 9:
			if aiuto_possibile(x, p):
				dist = true
		if dist:
			o.append({"id": "yy_aiuto", "t": "Yin-Yang: aiuto di una tessera lontana"})
	return o

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
	if s.villaggio[t].inf:
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
		"cimitero": return int(s.n_taoisti) > 1 and not taoisti_morti().is_empty()
		"guardiano":
			for x in fantasmi_in_gioco():
				if int(spazio(x[0], x[1]).inf) == 1:
					return true
			return false
	return false

func _yang_risposta(t: Dictionary, r: String) -> void:
	var p := int(t.p)
	var b := plancia(p)
	if r.begins_with("m:") or r.begins_with("mv:"):
		var x := int(r.split(":")[1])
		if r.begins_with("mv:"):
			_usa_segnalino(p, "rosso", t)
		if x != int(b.tessera):
			b.tessera = x
			_diario("%s va a %s." % [nome_plancia(p), nome_tessera(x)])
			_evento({"e": "muovi", "p": p, "t": x})
		t.fase = "azione"
		s.pila.append(t)
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
			if r.begins_with("b:"):
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
		return
	var o := opzioni_esito(p, t.facce, bers)
	if o.size() == 1 and (o[0].id == "fallisce" or int(o[0].get("costo", 0)) == 0):
		if o[0].id == "fallisce":
			_diario("L'esorcismo fallisce.")
			_evento({"e": "fallito", "p": p})
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
			if int(plancia(q).tessera) != int(plancia(p).tessera):
				continue
			var usa := mini(n, int(plancia(q).tao[col]))
			if usa > 0:
				_rendi_tao(plancia(q), col, usa)
				n -= usa
				if q != p:
					_diario("%s presta %d Tao %s." % [nome_plancia(q), usa, Dati.NOMI_COLORE[col]])
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
