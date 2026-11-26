extends SceneTree
## Partite con scelte a caso (per tutti, Wu-Feng compreso): cerca errori nei rami poco battuti.
## Uso: godot --headless --script tests/caos.gd -- <partite> [luna]

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var n := int(a[0]) if a.size() > 0 else 20
	var luna := a.size() > 1 and a[1] == "luna"
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var esiti := {}
	var tipi := {}
	for i in n:
		var m := Motore.new()
		m.nuova_partita({"livello": Dati.LIVELLI[i % 4], "taoisti": 1 + i % 4, "seme": 9000 + i, "segreto_nero": true, "luna_bianca": luna})
		var ia := IA.new(m)
		ia.cerca = false
		var passi := 0
		while not m.finita() and passi < 20000:
			var d: Dictionary = m.s.domanda
			if d.is_empty():
				break
			tipi[d.tipo] = int(tipi.get(d.tipo, 0)) + 1
			var id: String
			if rng.randf() < 0.5:
				id = d.opzioni[rng.randi() % d.opzioni.size()].id
			else:
				id = ia.scegli()
			if not m.rispondi(id):
				print("RISPOSTA RIFIUTATA ", d.tipo, " ", id)
				break
			passi += 1
		# il salvataggio deve sopravvivere al giro in JSON
		var j = JSON.parse_string(JSON.stringify(m.s))
		var m2 := Motore.new()
		m2.s = Motore.normalizza(j)
		esiti[m.s.esito + ": " + String(m.s.motivo).substr(0, 40)] = int(esiti.get(m.s.esito + ": " + String(m.s.motivo).substr(0, 40), 0)) + 1
	print(esiti)
	print(tipi)
	quit()
