class_name Dati
extends RefCounted
## Dati fissi del gioco: carte fantasma, incarnazioni, tessere del villaggio, poteri dei Taoisti.

const COLORI_TAO := ["giallo", "verde", "rosso", "blu", "nero"]
const COLORI_PLANCIA := ["giallo", "verde", "rosso", "blu"]
const FACCE_TAO := ["giallo", "verde", "rosso", "blu", "nero", "bianco"]
const FACCE_MALEDIZIONE := ["nulla", "nulla", "infesta", "fantasma", "tao", "qi"]
const TESSERE := ["casa_te", "erborista", "padiglione", "altare", "tempio", "cerchio", "stregone", "cimitero", "guardiano"]
const NOMI_COLORE := {"giallo": "giallo", "verde": "verde", "rosso": "rosso", "blu": "blu", "nero": "nero", "bianco": "bianco"}
const NOMI_POSIZIONE := ["Sud", "Ovest", "Nord", "Est"]
const LIVELLI := ["iniziazione", "normale", "incubo", "inferno"]
const NOMI_LIVELLO := {"iniziazione": "Iniziazione", "normale": "Normale", "incubo": "Incubo", "inferno": "Inferno"}
const COLORE_RGB := {
	"giallo": Color("f2b51c"), "verde": Color("3fb24a"), "rosso": Color("e0392f"),
	"blu": Color("2c74c9"), "nero": Color("2a2a30"), "bianco": Color("f4f1e8"),
}

static var _d := {}

static func tutto() -> Dictionary:
	if _d.is_empty():
		var f := FileAccess.open("res://assets/dati/fantasmi.json", FileAccess.READ)
		var j = JSON.parse_string(f.get_as_text())
		var carte := {}
		for g in j["fantasmi"]:
			carte[int(g["n"])] = g
		for g in j["incarnazioni"]:
			carte[int(g["n"])] = g
		_d = {"carte": carte, "villaggio": j["villaggio"], "poteri": j["poteri"], "villici": j.get("villici", []), "famiglie": j.get("famiglie", {}), "artefatti": j.get("artefatti", {}), "demoni": j.get("demoni", {}), "catacombe": j.get("catacombe", {}), "maledizioni": j.get("maledizioni", []), "mantra_sangue": j.get("mantra_sangue", [])}
	return _d

static func carta(n: int) -> Dictionary:
	return tutto()["carte"].get(n, {})

static func tessera(id: String) -> Dictionary:
	return tutto()["villaggio"].get(id, {})

## Resistenza totale di una carta (somma dei colori)
static func forza(n: int) -> int:
	var t := 0
	for v in resistenza(n).values():
		t += int(v)
	return t

static func demone(id: String) -> Dictionary:
	return tutto().get("demoni", {}).get(id, {})

static func catacombe() -> Dictionary:
	return tutto().get("catacombe", {})

static func maledizione(id: String) -> Dictionary:
	for m in tutto().get("maledizioni", []):
		if String(m.id) == id:
			return m
	return {}

static func maledizioni() -> Array:
	return tutto().get("maledizioni", [])

static func mantra_sangue(id: String) -> Dictionary:
	for m in tutto().get("mantra_sangue", []):
		if String(m.id) == id:
			return m
	return {}

static func tutti_mantra_sangue() -> Array:
	return tutto().get("mantra_sangue", [])

static func villici() -> Array:
	return tutto().get("villici", [])

static func villico(id: String) -> Dictionary:
	for v in villici():
		if String(v.id) == id:
			return v
	return {}

static func famiglia(nome: String) -> Dictionary:
	return tutto().get("famiglie", {}).get(nome, {})

static func artefatto(id: String) -> Dictionary:
	return tutto().get("artefatti", {}).get(id, {})

static func potere(chiave: String) -> Dictionary:
	return tutto()["poteri"].get(chiave, {})

static func e_incarnazione(n: int) -> bool:
	return (n >= 56 and n <= 65) or (n >= 82 and n <= 87) or (n >= 100 and n <= 104)

## Resistenza come dizionario colore -> quantità
static func resistenza(n: int) -> Dictionary:
	var c := carta(n)
	var r = c.get("resistenza", 1)
	if r is Dictionary:
		var o := {}
		for k in r:
			o[k] = int(r[k])
		return o
	return {c.get("colore", "nero"): int(r)}

static func ha(n: int, gruppo: String, eff: String) -> bool:
	return eff in carta(n).get(gruppo, [])

static func nome(n: int) -> String:
	return carta(n).get("nome", "?")
