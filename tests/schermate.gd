extends SceneTree
## Schermate di prova: menu, impostazioni e partita in corso a varie risoluzioni.
## Uso: xvfb-run godot --rendering-driver opengl3 --script tests/schermate.gd -- <cartella> <larghezza> <altezza>

var dir := "/tmp/schermate"
var w := 1920
var h := 1080

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 3:
		dir = a[0]
		w = int(a[1])
		h = int(a[2])
	DirAccess.make_dir_recursive_absolute(dir)
	root.size = Vector2i(w, h)
	DisplayServer.window_set_size(Vector2i(w, h))
	_vai.call_deferred()

func _foto(nome: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s_%dx%d.png" % [dir, nome, w, h])

func _attendi(n: int) -> void:
	for i in n:
		await process_frame

func _vai() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _attendi(10)
	await _foto("menu")
	main._nuova()
	await _attendi(5)
	await _foto("impostazioni")
	main.ritmo = 0.0
	main._inizia()
	var p: Partita = main.partita
	# il computer gioca qualche turno, poi tocca al primo Taoista (sul dispositivo)
	p.posti[0].tipo = "ia"
	for i in 260:
		await process_frame
		if int(p.s.get("giro", 1)) >= 4:
			break
	p.posti[0].tipo = "locale"
	for i in 400:
		await process_frame
		if p.m.in_attesa() and int(p.m.s.domanda.chi) == 0 and p.m.s.domanda.tipo == "yang":
			break
	p._versione_disegnata = -1
	p._aggiorna()
	await _attendi(30)
	await _foto("partita")
	p._mostra_info(Testi.carta(58), Stile.carta(58))
	await _attendi(5)
	await _foto("carta")
	p.zoom_carta.visible = false
	p._mostra_regole()
	await _attendi(5)
	await _foto("regole")
	quit()
