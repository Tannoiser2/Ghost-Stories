class_name IA
extends RefCounted
## L'intelligenza dei Taoisti guidati dal computer: risponde a ogni domanda del motore.
## Valuta la minaccia di ogni fantasma, la probabilità esatta di esorcizzarlo con i dadi e i segnalini,
## il valore di ogni aiuto del villaggio e sceglie il movimento e l'azione migliori.

var m: Motore
var cerca := true          # simula le mosse possibili con il motore (falso dentro le simulazioni)
var campioni := 4          # tiri simulati per ogni mossa
var profondo := false      # simula anche i turni dei compagni fino al proprio turno successivo

func _init(motore: Motore) -> void:
	m = motore

func scegli() -> String:
	var d: Dictionary = m.s.domanda
	if d.is_empty():
		return ""
	var o: Array = d.opzioni
	var p := int(d.chi)
	var id := ""
	match String(d.tipo):
		"yang":
			id = _yang(p, o)
			if cerca and (String(id).begins_with("m:") or String(id).begins_with("mv:") or id in ["esorcizza", "n_esorcizza", "aiuto", "n_aiuto", "basta"]):
				id = _cerca(p, o, id)
		"piazza": id = _piazza(o)
		"chi_perde_qi": id = _max_qi(o)
		"premio":
			id = "yy" if not m.plancia(p).yinyang and int(m.plancia(p).qi) >= 2 else "qi"
		"colore_tao", "cerchio": id = _colore(o)
		"premio_gruppo": id = _min_qi(o)
		"ritira_maledizione": id = "ritira"
		"verde_neutro": id = "si"
		"ritira_erborista":
			var bianchi := 0
			for f in m.s.domanda.task.facce:
				if f == "bianco":
					bianchi += 1
			id = "tieni" if bianchi > 0 else "ritira"
		"ritira": id = "ritira_inutili"
		"esito": id = _esito(p, o)
		"tessera_aiuto": id = _miglior_aiuto(p, o)
		"libera": id = _libera(p, o)
		"mantra": id = _mantra(o)
		"gemelli": id = _gemelli(p, o)
		"gemelli_dove": id = _gemelli_dove(p, o)
		"stregone": id = _stregone(o)
		"cimitero": id = o[0].id
		"guardiano": id = _guardiano(o)
		"padiglione_fantasma": id = _pad_fantasma(o)
		"padiglione_spazio": id = _pad_spazio(o)
		"padiglione_taoista": id = "no"
		"padiglione_dove": id = o[0].id
	for x in o:
		if x.id == id:
			return id
	return o[0].id

# ------------------------------------------------------------ valutazioni

func minaccia(p: int, k: int) -> float:
	var sp := m.spazio(p, k)
	var c := int(sp.c)
	if c <= 0:
		return 0.0
	var v := 3.5
	var lim := m.limite_infestate()
	var inf := m.n_infestate()
	if Dati.ha(c, "turno", "infestante"):
		v += 12.0 if int(sp.inf) == 1 else 5.0
		if int(sp.inf) == 1 and inf >= lim - 2:
			v += 10.0
		if int(sp.inf) == 1 and inf >= lim - 1:
			v += 25.0
	if Dati.ha(c, "turno", "tormento"):
		v += 3.0
	if Dati.ha(c, "turno", "gruppo_tao"):
		v += 2.5
	if Dati.ha(c, "arrivo", "potere"):
		v += 2.5 if m.plancia(p).taoista else 1.5
	if Dati.ha(c, "arrivo", "notao"):
		v += 3.5
	if sp.dado:
		v += 3.0
	if Dati.ha(c, "permanente", "nopoteri"):
		v += 4.0
	if Dati.ha(c, "permanente", "bianco_nullo"):
		v += 2.0
	var pieni := 0
	for kk in 3:
		if int(m.spazio(p, kk).c) > 0:
			pieni += 1
	if pieni == 3:
		v += 6.0
	elif pieni == 2:
		v += 2.5
	for e in Dati.carta(c).get("esorcismo", []):
		match e:
			"qi_yy": v += 2.0
			"tao2": v += 1.5
			"tao1": v += 0.8
			"maledizione": v -= 1.0
	if Dati.e_incarnazione(c):
		v += 12.0
		if int(m.s.inc_sconfitte) + 1 >= int(m.s.inc_totali):
			v += 200.0
	return v

func n_dadi(p: int) -> int:
	var n := m.dadi_disponibili()
	if m.potere(p, "verde_0"):
		n += 1
	return n

## Valore atteso dell'esorcismo dalla tessera t per il Taoista p
func valore_esorcismo(p: int, t: int) -> float:
	var bers := []
	for x in Motore.fronte(t):
		if m.esorcizzabile(x[0], x[1]):
			bers.append(x)
	if bers.is_empty():
		return 0.0
	var disp := _disp_in(p, t)
	var n := n_dadi(p)
	var best := 0.0
	for x in bers:
		var pr := m.probabilita([x], n, disp)
		best = maxf(best, pr * minaccia(x[0], x[1]))
	if bers.size() == 2:
		var pr2 := m.probabilita(bers, n, disp)
		best = maxf(best, pr2 * (minaccia(bers[0][0], bers[0][1]) + minaccia(bers[1][0], bers[1][1])))
	if m.potere(p, "blu_0"):
		best *= 1.4
	return best

func _disp_in(p: int, t: int) -> Dictionary:
	var o := {}
	for c in Dati.COLORI_TAO:
		o[c] = 0
	if m.tao_bloccati():
		return o
	for q in m.taoisti_vivi():
		if q == p or int(m.plancia(q).tessera) == t:
			for c in Dati.COLORI_TAO:
				o[c] += int(m.plancia(q).tao[c])
	return o

func valore_aiuto(p: int, t: int) -> float:
	if not m.aiuto_possibile(t, p):
		return -1.0
	var b := m.plancia(p)
	var costo_fantasma := 2.5
	var lim := m.limite_infestate()
	var inf := m.n_infestate()
	match String(m.s.villaggio[t].id):
		"casa_te":
			var v := 1.2
			if int(b.qi) <= 1:
				v += 5.0
			elif int(b.qi) == 2:
				v += 2.5
			return v - costo_fantasma
		"erborista":
			return 4.0 - 0.35 * _n_tao(b)
		"padiglione":
			var bud := _spazio_buddha_libero()
			if not bud.is_empty():
				var mx := 0.0
				for x in m.fantasmi_in_gioco():
					if not Dati.e_incarnazione(int(m.spazio(x[0], x[1]).c)):
						mx = maxf(mx, minaccia(x[0], x[1]))
				return mx
			return 0.2
		"altare":
			var v := 5.0
			if inf >= lim - 1:
				v += 15.0
			return v - costo_fantasma
		"tempio":
			return 4.5 if int(b.buddha) == 0 else 1.5
		"cerchio":
			var conta := {}
			for x in m.fantasmi_in_gioco():
				var r := Dati.resistenza(int(m.spazio(x[0], x[1]).c))
				for c in r:
					conta[c] = float(conta.get(c, 0.0)) + 1.0
			var mx := 0.0
			for c in conta:
				if c != m.s.cerchio and int(m.s.riserva_tao[c]) > 0:
					mx = maxf(mx, float(conta[c]))
			var ora := float(conta.get(m.s.cerchio, 0.0)) if m.s.cerchio != "" else 0.0
			return 3.0 * (mx - ora) + 1.0
		"stregone":
			if int(b.qi) <= 1:
				return -5.0
			var mx := 0.0
			for x in m.fantasmi_in_gioco():
				if not Dati.e_incarnazione(int(m.spazio(x[0], x[1]).c)):
					mx = maxf(mx, minaccia(x[0], x[1]))
			# il Qi è la vita: lo Stregone si chiama solo nelle emergenze
			return mx - (14.0 if int(b.qi) == 2 else 9.5)
		"cimitero":
			return 8.0
		"guardiano":
			var mx := 0
			for q in Motore.POSIZIONI:
				var n := 0
				for k in 3:
					if int(m.spazio(q, k).inf) == 1:
						n += 1
				mx = maxi(mx, n)
			var v := 7.0 * mx
			if inf >= lim - 2:
				v += 8.0 * mx
			if inf >= lim - 1:
				v += 15.0 * mx
			return v
	return 0.0

func _n_tao(b: Dictionary) -> int:
	var n := 0
	for c in Dati.COLORI_TAO:
		n += int(b.tao[c])
	return n

func _spazio_buddha_libero() -> Array:
	for q in Motore.POSIZIONI:
		for k in 3:
			var sp := m.spazio(q, k)
			if int(sp.c) == 0 and sp.buddha:
				return [q, k]
	return []

func valore_tessera(p: int, t: int) -> float:
	return maxf(valore_esorcismo(p, t), valore_aiuto(p, t))

# ------------------------------------------------------------ fase Yang

func _yang(p: int, o: Array) -> String:
	var ids := {}
	for x in o:
		ids[x.id] = x
	var b := m.plancia(p)
	var lim := m.limite_infestate()
	# Yin-Yang: libera una tessera se il villaggio è sul punto di cadere
	if ids.has("yy_libera") and m.n_infestate() >= lim - 2:
		return "yy_libera"
	if ids.has("mantra") or ids.has("n_mantra"):
		var mx := 0.0
		for x in m.fantasmi_in_gioco():
			var r := Dati.resistenza(int(m.spazio(x[0], x[1]).c))
			var tot := 0
			for c in r:
				tot += int(r[c])
			if tot >= 2 and not m.ha_mantra(x[0], x[1]):
				mx = maxf(mx, minaccia(x[0], x[1]))
		if mx >= 4.0:
			return "mantra" if ids.has("mantra") else "n_mantra"
	if ids.has("tasche"):
		return "tasche"
	if ids.has("prendi_poteri"):
		return "prendi_poteri"
	for x in o:
		if String(x.id).begins_with("b:"):
			return x.id
	var mosse := []
	for x in o:
		if String(x.id).begins_with("m:") or String(x.id).begins_with("mv:"):
			mosse.append(x)
	if not mosse.is_empty():
		var best := ""
		var bv := -999.0
		for x in mosse:
			var t := int(x.tessera)
			var v := valore_tessera(p, t)
			if String(x.id).begins_with("mv:"):
				v -= 1.0
			# meglio restare vicino agli angoli e lontano dal centro se non c'è altro da fare
			if t == 4:
				v -= 0.3
			v += _posizione(p, t) * 0.12
			if v > bv:
				bv = v
				best = x.id
		# Yin-Yang per un aiuto lontano molto prezioso
		if ids.has("yy_aiuto"):
			var mx := 0.0
			for t in 9:
				mx = maxf(mx, valore_aiuto(p, t))
			if mx >= 8.0 and mx > bv + 3.0:
				return "yy_aiuto"
		return best
	if ids.has("gemelli") or ids.has("n_gemelli"):
		if _gemelli_utile(p):
			return "gemelli" if ids.has("gemelli") else "n_gemelli"
	var qui := int(b.tessera)
	var ve := valore_esorcismo(p, qui) if ids.has("esorcizza") or ids.has("n_esorcizza") else -1.0
	var va := valore_aiuto(p, qui) if ids.has("aiuto") or ids.has("n_aiuto") else -1.0
	if ids.has("n_esorcizza"):
		ve -= 0.5
	if ids.has("n_aiuto"):
		va -= 0.5
	if ve > 0.05 and ve >= va:
		return "esorcizza" if ids.has("esorcizza") else "n_esorcizza"
	if va > 0.0:
		return "aiuto" if ids.has("aiuto") else "n_aiuto"
	if ids.has("yy_aiuto"):
		var mx := 0.0
		for t in 9:
			mx = maxf(mx, valore_aiuto(p, t))
		if mx >= 8.0:
			return "yy_aiuto"
	if ids.has("basta"):
		return "basta"
	return "fine" if ids.has("fine") else o[o.size() - 1].id

## Quanto è utile la posizione per i turni dopo (fantasmi minacciosi di fronte)
func _posizione(p: int, t: int) -> float:
	var v := 0.0
	for x in Motore.fronte(t):
		v += minaccia(x[0], x[1])
	for a in Motore.adiacenti(t):
		for x in Motore.fronte(a):
			v += 0.3 * minaccia(x[0], x[1])
	return v

func _gemelli_utile(p: int) -> bool:
	for q in m.taoisti_vivi():
		if q == p:
			continue
		var t := int(m.plancia(q).tessera)
		var ora := valore_tessera(q, t)
		for a in Motore.adiacenti(t):
			if valore_tessera(q, a) > ora + 2.0:
				return true
	return false

func _gemelli(p: int, o: Array) -> String:
	var best := "no"
	var bg := 2.0
	for x in o:
		if not String(x.id).begins_with("q:"):
			continue
		var q := int(x.plancia)
		var t := int(m.plancia(q).tessera)
		var ora := valore_tessera(q, t)
		for a in Motore.adiacenti(t):
			var g := valore_tessera(q, a) - ora
			if g > bg:
				bg = g
				best = x.id
	return best

func _gemelli_dove(p: int, o: Array) -> String:
	var q := int(m.s.domanda.task.q)
	var best := "no"
	var bv := valore_tessera(q, int(m.plancia(q).tessera))
	for x in o:
		if String(x.id).begins_with("t:"):
			var v := valore_tessera(q, int(x.tessera))
			if v > bv:
				bv = v
				best = x.id
	return best

# ------------------------------------------------------------ altre scelte

func _piazza(o: Array) -> String:
	var c := int(m.s.domanda.get("carta", 0))
	var inc := Dati.e_incarnazione(c)
	var best: String = o[0].id
	var bv := -9999.0
	for x in o:
		var sp := m.spazio(x.spazio[0], x.spazio[1])
		var v := 0.0
		if sp.buddha:
			v += 100.0 if (not inc or Dati.ha(c, "permanente", "inafferrabile")) else -5.0
		# vicino a un Taoista è più facile da esorcizzare
		var fr: int = Motore.linea(x.spazio[0], x.spazio[1])[0]
		var dmin := 9
		for q in m.taoisti_vivi():
			var tq := int(m.plancia(q).tessera)
			var d := maxi(absi(tq / 3 - fr / 3), absi(tq % 3 - fr % 3))
			dmin = mini(dmin, d)
		v -= dmin
		# meglio non riempire una plancia già carica
		var pieni := 0
		for k in 3:
			if int(m.spazio(x.spazio[0], k).c) > 0:
				pieni += 1
		v -= pieni * 0.8
		# un infestatore lontano dalle tessere già infestate fa meno danni
		if Dati.ha(c, "turno", "infestante"):
			for t in Motore.linea(x.spazio[0], x.spazio[1]):
				if m.s.villaggio[t].inf:
					v -= 0.5
		if v > bv:
			bv = v
			best = x.id
	return best

func _max_qi(o: Array) -> String:
	var best: String = o[0].id
	var mx := -1
	for x in o:
		var q := int(x.plancia)
		if int(m.plancia(q).qi) > mx:
			mx = int(m.plancia(q).qi)
			best = x.id
	return best

func _min_qi(o: Array) -> String:
	var best: String = o[0].id
	var mn := 99
	for x in o:
		var q := int(x.plancia)
		if int(m.plancia(q).qi) < mn:
			mn = int(m.plancia(q).qi)
			best = x.id
	return best

## Il colore più utile: quello dei fantasmi in gioco (pesati per minaccia) che manca di più
func _colore(o: Array) -> String:
	var peso := {}
	for c in Dati.COLORI_TAO:
		peso[c] = 0.1
	for x in m.fantasmi_in_gioco():
		var r := Dati.resistenza(int(m.spazio(x[0], x[1]).c))
		for c in r:
			peso[c] = float(peso[c]) + float(r[c]) * (0.5 + 0.1 * minaccia(x[0], x[1]))
	var p := int(m.s.domanda.chi)
	var b := m.plancia(p)
	var best: String = o[0].id
	var bv := -999.0
	for x in o:
		var c: String = x.get("colore", "")
		if c == "":
			continue
		var v := float(peso[c]) - 0.8 * int(b.tao[c])
		if m.s.domanda.tipo == "cerchio":
			v = float(peso[c])
		if v > bv:
			bv = v
			best = x.id
	return best

func _esito(p: int, o: Array) -> String:
	var best: String = o[0].id
	var bv := -999.0
	for x in o:
		var v := 0.0
		if x.id != "fallisce":
			for ch in String(x.id).substr(2).split(","):
				var pz := ch.split(".")
				v += minaccia(int(pz[0]), int(pz[1]))
			v -= 0.7 * int(x.get("costo", 0))
		if v > bv:
			bv = v
			best = x.id
	return best

func _miglior_aiuto(p: int, o: Array) -> String:
	var best: String = o[0].id
	var bv := -999.0
	for x in o:
		var v := valore_aiuto(p, int(x.tessera))
		if v > bv:
			bv = v
			best = x.id
	return best

func _libera(p: int, o: Array) -> String:
	var best: String = o[0].id
	var bv := -999.0
	for x in o:
		var t := int(x.tessera)
		# vale di più una tessera con un aiuto prezioso
		var v := {"cimitero": 2.0, "altare": 3.0, "tempio": 2.0, "casa_te": 2.5, "erborista": 2.0, "cerchio": 1.5, "stregone": 1.5, "guardiano": 2.0, "padiglione": 1.0}.get(m.s.villaggio[t].id, 1.0)
		if v > bv:
			bv = v
			best = x.id
	return best

func _mantra(o: Array) -> String:
	var best: String = o[0].id
	var bv := -1.0
	for x in o:
		var v := minaccia(x.spazio[0], x.spazio[1])
		if v > bv:
			bv = v
			best = x.id
	return best

func _stregone(o: Array) -> String:
	return _mantra(o)

func _guardiano(o: Array) -> String:
	var best: String = o[0].id
	var mx := -1
	for x in o:
		var n := 0
		for k in 3:
			if int(m.spazio(int(x.plancia), k).inf) == 1:
				n += 1
		if n > mx:
			mx = n
			best = x.id
	return best

func _pad_fantasma(o: Array) -> String:
	if _spazio_buddha_libero().is_empty():
		return "no"
	var best := "no"
	var bv := 3.0
	for x in o:
		if x.id == "no":
			continue
		if Dati.e_incarnazione(int(m.spazio(x.spazio[0], x.spazio[1]).c)):
			continue
		var v := minaccia(x.spazio[0], x.spazio[1])
		if v > bv:
			bv = v
			best = x.id
	return best

func _pad_spazio(o: Array) -> String:
	for x in o:
		if m.spazio(x.spazio[0], x.spazio[1]).buddha:
			return x.id
	return o[0].id

# ------------------------------------------------------------ ricerca con il motore

## Prova davvero le mosse e le azioni possibili su copie della partita e sceglie quella che lascia
## il villaggio messo meglio (in media sui tiri dei dadi).
func _cerca(p: int, o: Array, proposta: String) -> String:
	var candidati := []
	for x in o:
		var id: String = x.id
		if id.begins_with("m:") or id.begins_with("mv:") or id in ["esorcizza", "n_esorcizza", "aiuto", "n_aiuto", "basta"]:
			candidati.append(id)
	if candidati.size() <= 1:
		return proposta
	var best := proposta
	var bv := -INF
	for id in candidati:
		var v := _valuta_mossa(p, id)
		if id == proposta:
			v += 0.5
		if v > bv:
			bv = v
			best = id
	return best

func _copia(seme: int) -> Motore:
	var c := Motore.new()
	var d: Dictionary = m.s.duplicate(true)
	d.diario = []
	d.eventi = []
	c.s = d
	c.s.rng = str(seme)
	# il computer non sbircia il mazzo: nella copia i fantasmi sono rimescolati (le incarnazioni restano al loro posto)
	var pos := []
	var carte := []
	for i in c.s.mazzo.size():
		if not Dati.e_incarnazione(int(c.s.mazzo[i])):
			pos.append(i)
			carte.append(c.s.mazzo[i])
	c._mescola(carte)
	for k in pos.size():
		c.s.mazzo[pos[k]] = carte[k]
	return c

func _valuta_mossa(p: int, id: String) -> float:
	var tot := 0.0
	var n := campioni
	for k in n:
		var c := _copia(hash(str(k) + id + str(m.s.rng)))
		var ia2 := IA.new(c)
		ia2.cerca = false
		if not c.rispondi(id):
			return -INF
		var passi := 0
		var uscito := false
		while not c.finita() and c.in_attesa() and passi < 400:
			var d: Dictionary = c.s.domanda
			if int(c.s.turno_di) != p:
				uscito = true
				if not profondo:
					break
			elif uscito:
				break
			elif d.tipo == "yang" and int(d.chi) == p and d.task.fase == "fine" and not profondo:
				break
			c.rispondi(ia2.scegli())
			passi += 1
		tot += ia2.valuta()
	return tot / n

func _ha_dadi(id: String, p: int) -> bool:
	if id.begins_with("m:") or id.begins_with("mv:"):
		return true
	if id in ["esorcizza", "n_esorcizza"]:
		return true
	if id in ["aiuto", "n_aiuto"]:
		var t := int(m.plancia(p).tessera)
		return String(m.s.villaggio[t].id) in ["erborista", "casa_te", "altare", "cimitero"]
	return false

## Quanto è buona la situazione per i Taoisti (più alto è meglio)
func valuta() -> float:
	if m.s.esito == "vittoria":
		return 100000.0
	if m.s.esito == "sconfitta":
		return -100000.0
	var v := 0.0
	var lim := m.limite_infestate()
	var inf := m.n_infestate()
	for q in Motore.POSIZIONI:
		var b := m.plancia(q)
		if b.taoista:
			if b.vivo:
				var qi := int(b.qi)
				v += 30.0 + 10.0 * mini(qi, 4) + 4.0 * maxi(qi - 4, 0)
				if qi == 1:
					v -= 8.0
				var nt := _n_tao(b)
				v += 2.4 * mini(nt, 6) + 0.6 * maxi(nt - 6, 0)
				if b.yinyang:
					v += 6.0
				v += 6.0 * int(b.buddha) + 2.0 * int(b.poteri)
			else:
				v -= 25.0
		else:
			v += 4.0 * int(b.qi)
		var pieni := 0
		for k in 3:
			var sp := m.spazio(q, k)
			var c := int(sp.c)
			if c > 0:
				pieni += 1
				v -= _peso_fantasma(q, k, inf, lim)
			elif sp.buddha:
				v += 5.0
		if pieni == 3:
			v -= 10.0
		elif pieni == 2:
			v -= 3.0
	v -= 40.0 * inf
	if inf >= lim - 1:
		v -= 60.0
	if m.s.cerchio != "":
		# il Cerchio vale per ogni fantasma del suo colore in gioco
		v += 3.0
		for x in m.fantasmi_in_gioco():
			if Dati.resistenza(int(m.spazio(x[0], x[1]).c)).has(m.s.cerchio):
				v += 4.0
	v += 6.0 * int(m.s.buddha_tempio) * 0.0
	return v

func _peso_fantasma(q: int, k: int, inf: int, lim: int) -> float:
	var sp := m.spazio(q, k)
	var c := int(sp.c)
	var w := 7.0
	var r := Dati.resistenza(c)
	for x in r:
		w += 0.8 * int(r[x])
	if Dati.ha(c, "turno", "infestante"):
		w += 12.0 if int(sp.inf) == 1 else 5.0
		if int(sp.inf) == 1 and inf >= lim - 1:
			w += 60.0
	if Dati.ha(c, "turno", "tormento"):
		w += 5.0
	if Dati.ha(c, "turno", "gruppo_tao"):
		w += 4.0
	if Dati.ha(c, "arrivo", "potere"):
		w += 3.0
	if Dati.ha(c, "arrivo", "notao"):
		w += 5.0
	if sp.dado:
		w += 4.0
	if Dati.ha(c, "permanente", "nopoteri"):
		w += 6.0
	if Dati.e_incarnazione(c):
		w += 20.0
	return w
