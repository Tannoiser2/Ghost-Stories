extends SceneTree
## Schermate di prova: menu, impostazioni e partita in corso a varie risoluzioni.
## Uso: xvfb-run godot --rendering-driver opengl3 --script tests/schermate.gd -- <cartella> <larghezza> <altezza>

var dir := "/tmp/schermate"
var w := 1920
var h := 1080
var luna := false
var segreto := false

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 3:
		dir = a[0]
		w = int(a[1])
		h = int(a[2])
	luna = a.size() >= 4 and "luna" in a[3]
	segreto = a.size() >= 4 and "segreto" in a[3]
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
	main.luna = luna
	main.segreto = segreto
	main._nuova()
	await _attendi(5)
	await _foto("impostazioni")
	main.ritmo = 0.0
	main._inizia()
	var p: Partita = main.partita
	p.in_3d = false
	p._imposta_vista()
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
	await _attendi(10)
	await _foto("partita2d")
	p.in_3d = true
	p._imposta_vista()
	await _attendi(40)
	await _foto("partita")
	p.vista.distanza = 7.0
	p.vista.pitch = 0.55
	p.vista.bersaglio = Vector3(0, 0, 1.0)
	await _attendi(6)
	await _foto("partita3d_vicino")
	# un turno giocato con i pulsanti, come farebbe una persona
	var ia := IA.new(p.m)
	for passo in 6:
		if not p.m.in_attesa() or int(p.m.s.domanda.chi) != 0:
			break
		var voluto := ia.scegli()
		var premuto := false
		for b in _bottoni(p.box_domanda):
			var o := _opzione_di(p, b)
			if o == voluto:
				b.pressed.emit()
				premuto = true
				break
		if not premuto:
			p._rispondi(voluto)
		await _attendi(20)
		await _foto("turno_%d" % passo)
	p._mostra_info(Testi.carta(58), Stile.carta(58))
	await _attendi(5)
	await _foto("carta")
	p.zoom_carta.visible = false
	p._mostra_regole()
	await _attendi(5)
	await _foto("regole")
	quit()

func _bottoni(n: Node) -> Array:
	var o := []
	for c in n.get_children():
		if c is Button and not c.disabled:
			o.append(c)
		o += _bottoni(c)
	return o

func _opzione_di(p: Partita, b: Button) -> String:
	for c in b.pressed.get_connections():
		var cb: Callable = c.callable
		var a := cb.get_bound_arguments()
		if a.size() > 0:
			return str(a[0])
	return ""
