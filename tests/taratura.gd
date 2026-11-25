extends SceneTree
## Taratura dei pesi dell'IA: piccole variazioni casuali, si tiene chi fa meglio sulle stesse partite.
## Uso: godot --headless --script tests/taratura.gd -- <minuti> <file risultato>

var semi := []

func _punteggio() -> float:
	var tot := 0.0
	var vinte := 0
	for k in semi.size():
		var cfg: Dictionary = semi[k]
		var m := Motore.new()
		m.nuova_partita(cfg)
		var ia := IA.new(m)
		ia.cerca = false
		var passi := 0
		while not m.finita() and passi < 6000:
			m.rispondi(ia.scegli())
			passi += 1
		var v: bool = m.s.esito == "vittoria"
		if v:
			vinte += 1
		tot += (40.0 if v else 0.0) + float(m.s.giro) * (2.0 if int(cfg.taoisti) >= 3 else 1.0) + 8.0 * int(m.s.inc_sconfitte) - 0.5 * m.s.mazzo.size()
	return tot / semi.size() + vinte * 0.01

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var minuti := float(a[0]) if a.size() > 0 else 60.0
	var file: String = a[1] if a.size() > 1 else "/tmp/pesi.json"
	for i in 10:
		semi.append({"livello": "iniziazione", "taoisti": [1, 2, 4, 4, 3][i % 5], "seme": 50000 + i * 13})
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var migliori: Dictionary = IA.P.duplicate()
	var bp := _punteggio()
	print("partenza ", bp)
	var t0 := Time.get_ticks_msec()
	var giro := 0
	while Time.get_ticks_msec() - t0 < minuti * 60000.0:
		giro += 1
		var prova := migliori.duplicate()
		for k in prova:
			if rng.randf() < 0.35:
				prova[k] = maxf(0.0, float(prova[k]) * rng.randf_range(0.6, 1.6) + rng.randf_range(-0.5, 0.5))
		IA.P = prova
		var v := _punteggio()
		if v > bp:
			bp = v
			migliori = prova
			print("giro %d: meglio %.2f %s" % [giro, v, str(migliori)])
			var f := FileAccess.open(file, FileAccess.WRITE)
			f.store_string(JSON.stringify(migliori))
		IA.P = migliori
	print("fine dopo ", giro, " prove, punteggio ", bp)
	quit()
