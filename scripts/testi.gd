class_name Testi
extends RefCounted
## Le descrizioni in italiano di carte, tessere e poteri, e il riassunto delle regole.

const ARRIVO := {
	"fantasma": "porta in gioco un altro fantasma",
	"potere": "spegne il potere della plancia su cui si trova finché resta in gioco",
	"dado": "cattura un dado Tao finché resta in gioco",
	"notao": "finché resta in gioco nessuno può usare i segnalini Tao",
	"gruppo_tao": "ogni Taoista scarta un segnalino Tao",
	"infesta": "infesta la prima tessera attiva di fronte a sé",
	"qi": "la plancia su cui arriva perde 1 Qi",
	"rapido": "la figurina infestante parte già sulla plancia",
	"maledizione": "si tira il dado della maledizione",
	"cerchio": "scarta il segnalino del Cerchio di Preghiera",
}
const TURNO := {
	"infestante": "infestatore: a ogni fase Yin la figurina avanza; al secondo passo infesta una tessera",
	"tormento": "tormentatore: a ogni fase Yin si tira il dado della maledizione",
	"gruppo_tao": "a ogni fase Yin ogni Taoista scarta un segnalino Tao",
}
const ESORCISMO := {
	"maledizione": "si tira il dado della maledizione",
	"qi_yy": "chi lo esorcizza riceve 1 Qi oppure riprende lo Yin-Yang",
	"tao1": "chi lo esorcizza prende 1 segnalino Tao a scelta",
	"tao2": "chi lo esorcizza prende 2 segnalini Tao a scelta",
}

static func resistenza(n: int) -> String:
	var r := Dati.resistenza(n)
	var p := []
	var tot := 0
	for c in r:
		p.append("%d %s" % [int(r[c]), "del colore della plancia" if c == "plancia" else Dati.NOMI_COLORE[c]])
		tot += int(r[c])
	if r.size() == 1:
		var col: String = Dati.carta(n).get("colore", "nero")
		return "Fantasma %s, resistenza %d" % [col, tot]
	return "Resistenza %d: %s" % [tot, ", ".join(p)]

static func carta(n: int) -> String:
	var c := Dati.carta(n)
	var righe := [resistenza(n)]
	if Dati.e_incarnazione(n):
		righe.append("Incarnazione di Wu-Feng: esorcizzarla dà al gruppo 1 Qi e uno Yin-Yang.")
		righe.append(c.get("descrizione", ""))
		return "\n".join(righe)
	var a := []
	for e in c.get("arrivo", []):
		a.append(ARRIVO.get(e, e))
	if not a.is_empty():
		righe.append("Quando entra: " + "; ".join(a) + ".")
	if "immune" in c.get("permanente", []):
		righe.append("I dadi Tao non hanno effetto: si esorcizza solo con i segnalini Tao (valgono anche Cerchio, Buddha e Stregone).")
	var t := []
	for e in c.get("turno", []):
		t.append(TURNO.get(e, e))
	if not t.is_empty():
		righe.append("Ogni turno: " + "; ".join(t) + ".")
	var x := []
	for e in c.get("esorcismo", []):
		x.append(ESORCISMO.get(e, e))
	if not x.is_empty():
		righe.append("Esorcizzato: " + "; poi ".join(x) + ".")
	return "\n".join(righe)

static func tessera(id: String) -> String:
	var t := Dati.tessera(id)
	return t.get("aiuto", "")

static func potere(chiave: String) -> String:
	var p := Dati.potere(chiave)
	return "%s: %s" % [p.get("nome", ""), p.get("desc", "")]

const REGOLE := """[b]Lo scopo[/b]
I Taoisti vincono insieme se esorcizzano l'incarnazione di Wu-Feng (nei livelli Incubo e Inferno tutte le incarnazioni). Perdono se muoiono tutti, se il villaggio ha troppe tessere infestate (4 in Iniziazione, 3 negli altri livelli) o se entra in gioco l'ultima carta del mazzo.

[b]Il turno[/b]
[b]Fase Yin (i fantasmi)[/b]: agiscono i fantasmi della plancia di turno (gli infestatori avanzano, i tormentatori fanno tirare il dado della maledizione). Se la plancia è piena il Taoista perde 1 Qi; altrimenti entra un nuovo fantasma: quelli colorati vanno sulla plancia del loro colore, i neri su quella del giocatore di turno.
[b]Fase Yang (il Taoista)[/b]: ci si muove di una tessera (anche in diagonale) o si resta, poi si sceglie UNA azione: tentare un esorcismo oppure chiedere aiuto al villaggio. Alla fine si può mettere un Buddha.

[b]L'esorcismo[/b]
Si attaccano i fantasmi davanti alla propria tessera: gli angoli ne hanno davanti due, le tessere sui lati uno, il centro nessuno. Si tirano 3 dadi Tao: ogni faccia del colore del fantasma vale 1, il bianco vale per qualunque colore. Si aggiungono i segnalini Tao del colore giusto, propri o dei compagni sulla stessa tessera. Se i dadi da soli bastano, l'esorcismo è obbligatorio.

[b]Infestatori e tessere[/b]
La figurina di un infestatore parte sulla carta, alla fase Yin dopo scende sulla plancia, a quella successiva infesta la prima tessera attiva davanti al fantasma e torna sulla carta. Una tessera infestata non dà aiuto.

[b]Yin-Yang[/b]
Una volta (finché non lo si riprende con una ricompensa) permette di chiedere aiuto a una tessera lontana oppure di liberare una tessera infestata, in più alla normale azione.

[b]Qi e morte[/b]
Il Qi è la vita del Taoista. A zero Qi il Taoista muore: la sua plancia resta e i fantasmi continuano ad agire. Il Cimitero lo riporta in vita.

[b]Giocare in meno di quattro[/b]
Le plance senza Taoista sono neutre: hanno 3 Qi, i loro fantasmi agiscono ma non ne arrivano di nuovi. I segnalini potere permettono di usare una volta il potere di una plancia neutra; usati vanno al centro del villaggio e chi finisce il turno lì li riprende.

[b]I livelli[/b]
Iniziazione: 4 Qi, un Tao nero in più, si perde con 4 tessere infestate. Normale: 3 Qi, si perde con 3 tessere infestate. Incubo: come Normale ma con 4 incarnazioni (3 in uno o due Taoisti). Inferno: come Incubo e senza Yin-Yang all'inizio.

[b]Comandi[/b]
[b]Espansione White Moon[/b] (si sceglie nella nuova partita)
Su ogni tessera, tranne quella del Portale, c'è una pila di villici. Chi sta sul Portale può usare la sua azione per metterne in salvo uno; muovendosi si può portare con sé il villico in cima alla pila di partenza (al massimo tre per tessera). Un fantasma che infesta una tessera con dei villici li uccide invece di infestarla; quando un infestatore avanza, il primo villico davanti a lui scappa di una tessera o muore. I nuovi divoratori uccidono un villico a ogni turno. Ogni villico morto applica la maledizione della sua famiglia; una famiglia salvata per intero dà la sua ricompensa (spesso un artefatto). Con dodici villici morti si perde.
Dopo un evento negativo si può mettere Su-Ling davanti a un fantasma: ne blocca le abilità della pietra centrale. I Cristalli di Luna valgono come segnalini Tao di qualunque colore; posati nei quattro ricettacoli agli angoli (dalla tessera d'angolo, a fine turno) alzano la Barriera Mistica: ogni plancia salva un villico o tira quattro dadi contro i propri fantasmi. Nel punteggio contano anche i villici salvati e la posizione del Portale.

[b]Espansione Black Secret[/b] (si sceglie nella nuova partita)
Wu-Feng diventa un giocatore: una persona, un amico online o il computer (indulgente o spietato). Ogni volta che deve entrare un fantasma è lui a pescarlo e sceglie se metterlo nel villaggio, scartarlo per evocare un demone nelle catacombe (serve una carta con resistenza almeno pari al costo del demone) oppure scartarlo per lanciare una maledizione dello stesso colore (le carte nere valgono per ogni colore). Le maledizioni si impilano a piramide: per lanciarne una di rango più alto ne servono due del rango sotto. Al posto delle incarnazioni nel mazzo ci sono le Evocazioni: Wu-Feng prende un'incarnazione in mano e ne mette in gioco una a sua scelta.
Prima della fase Yin di ogni Taoista i demoni si muovono di uno spazio o scavano: sotto ogni tessera c'è una pila di segnalini, e tra questi le tre urne con le ceneri di Wu-Feng. Alla terza urna arriva l'Ombra di Wu-Feng, che non si può esorcizzare e attacca i Taoisti o le tessere.
Dopo il movimento un Taoista può scendere o salire con la scala della sua tessera; quando una tessera viene infestata la sua scala crolla. Nelle catacombe l'unica azione è esorcizzare un demone, del colore dello spazio. Il Qi che si perde non torna nella riserva ma va su un Mantra di Sangue: quando è pieno si attiva il suo effetto. Un Taoista ridotto a 1 Qi diventa Fratello di Sangue e usa anche il potere della plancia di fronte. Il Calligrafo aiuta con i Mantra di Sangue.

Trascina per spostare il tavolo, rotella o due dita per ingrandire, tasto destro, Maiusc + trascinamento o due dita per ruotarlo. Tocca una carta per leggerla, una tessera per vedere il suo aiuto. Le scelte possibili si illuminano sul tavolo e compaiono nel pannello a destra."""
