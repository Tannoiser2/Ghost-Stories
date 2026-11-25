extends SceneTree
## Confronto fra i pesi di default dell'IA e quelli tarati, su semi nuovi.
## Uso: godot --headless --script tests/convalida.gd -- <file pesi> [partite]

func _gioca(n: int) -> Array:
	var vinte := 0
	var giri := 0
	var inc := 0
	for i in n:
		var cfg := {"livello": ["iniziazione", "normale"][i % 2], "taoisti": [1, 2, 3, 4][i % 4], "seme": 70000 + i * 31}
		var m := Motore.new()
		m.nuova_partita(cfg)
		var ia := IA.new(m)
		ia.cerca = false
		var passi := 0
		while not m.finita() and passi < 6000:
			m.rispondi(ia.scegli())
			passi += 1
		if m.s.esito == "vittoria":
			vinte += 1
		giri += int(m.s.giro)
		inc += int(m.s.inc_sconfitte)
	return [vinte, float(giri) / n, inc]

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var n := int(a[1]) if a.size() > 1 else 40
	var base: Dictionary = IA.P.duplicate()
	print("default: ", _gioca(n))
	var pesi: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	IA.P = pesi
	print("tarati:  ", _gioca(n))
	IA.P = base
	quit()
