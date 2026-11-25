extends SceneTree
## Partite automatiche: l'IA gioca tutti i Taoisti a ogni livello e numero di giocatori.
## Uso: godot --headless --script tests/partite.gd -- [partite per configurazione]

func _init() -> void:
	var n := 20
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		n = int(args[0])
	var errori := 0
	for livello in Dati.LIVELLI:
		for tao in [1, 2, 3, 4]:
			var vinte := 0
			var turni := 0
			var motivi := {}
			for i in n:
				var m := Motore.new()
				m.nuova_partita({"livello": livello, "taoisti": tao, "seme": 1000 + i * 7 + tao})
				var ia := IA.new(m)
				var passi := 0
				while not m.finita():
					if not m.in_attesa():
						push_error("bloccato senza domanda: pila %d" % m.s.pila.size())
						errori += 1
						break
					var id := ia.scegli()
					# ogni tanto ricarica dal salvataggio per provare la serializzazione
					if passi % 37 == 0:
						var testo := m.salva()
						m = Motore.new()
						m.carica(testo)
						ia = IA.new(m)
					if not m.rispondi(id):
						push_error("risposta rifiutata %s a %s" % [id, m.s.domanda.tipo])
						errori += 1
						break
					passi += 1
					if passi > 20000:
						push_error("partita troppo lunga")
						errori += 1
						break
				if m.s.esito == "vittoria":
					vinte += 1
				else:
					motivi[m.s.motivo.substr(0, 40)] = int(motivi.get(m.s.motivo.substr(0, 40), 0)) + 1
				turni += int(m.s.giro)
			print("%-12s %d taoisti: vinte %2d/%d  giri medi %.1f  %s" % [livello, tao, vinte, n, float(turni) / n, str(motivi)])
	print("ERRORI: ", errori)
	quit(1 if errori > 0 else 0)
