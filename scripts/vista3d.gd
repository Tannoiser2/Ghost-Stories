class_name Vista3D
extends SubViewportContainer
## Il tavolo in 3D: villaggio e plance con la grafica originale, le miniature dei Taoisti (dal modulo TTS),
## gli spettri sopra le loro carte, le figurine infestanti, i Buddha e le incarnazioni di Wu-Feng,
## con nebbia, lanterne, dadi che rotolano ed effetti per arrivi, esorcismi, infestazioni e maledizioni.
## Si sposta trascinando, si ingrandisce con la rotella o pizzicando, si ruota col tasto destro o con due dita.

signal toccato(cosa: Dictionary)
signal sopra(cosa: Dictionary)

const U := 0.01                     # 1 pixel del tavolo 2D = 1 cm
const COLORE_SPETTRO := {
	"giallo": Color(1.0, 0.82, 0.25), "verde": Color(0.35, 1.0, 0.45), "rosso": Color(1.0, 0.28, 0.2),
	"blu": Color(0.35, 0.6, 1.0), "nero": Color(0.68, 0.35, 1.0),
}

var tavolo: Tavolo                  # per la geometria condivisa (spazi, tessere, plance)
var s: Dictionary = {}
var evidenzia: Array = []
var etichette := {}

var vp: SubViewport
var mondo: Node3D
var cam: Camera3D
var bersaglio := Vector3.ZERO
var yaw := 0.0
var yaw_obiettivo := 0.0
var pitch := 0.9
var distanza := 15.0
var _tempo := 0.0

var _tessere := []                  # Node3D che si girano
var _plance := []
var _carte := {}                    # "p:k" -> {c, nodo, carta, spettro}
var _infestanti := {}               # "p:k" -> nodo
var _taoisti := {}                  # p -> nodo
var _buddha := {}                   # chiave -> nodo
var _buddha_tempio := []
var _evid := Node3D.new()
var _gettoni := Node3D.new()
var _etichette3d := {}
var _ultimo_evento := 0
var _mesh := {}
var _mat := {}
var _dadi := Node3D.new()
var _luna := Node3D.new()           # White Moon: Portale, ricettacoli, villici, Su-Ling
var _firma_luna := ""
var _segreto := Node3D.new()        # Black Secret: catacombe, demoni, Ombra, plancia di Wu-Feng
var _firma_segreto := ""
var _tocchi := {}
var _gesto := {}
var _premuto := false
var _trascinato := false
var _ultimo := Vector2.ZERO
var _orbita := false

# ============================================================ costruzione

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.handle_input_locally = false
	add_child(vp)
	mondo = Node3D.new()
	vp.add_child(mondo)
	_ambiente()
	cam = Camera3D.new()
	cam.fov = 45
	cam.near = 0.1
	cam.far = 200
	mondo.add_child(cam)
	_costruisci_tavolo()
	mondo.add_child(_evid)
	mondo.add_child(_gettoni)
	mondo.add_child(_dadi)
	mondo.add_child(_luna)
	mondo.add_child(_segreto)
	_aggiorna_camera()

func _ambiente() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.025, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.5, 0.7)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.95
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.1
	e.fog_enabled = true
	e.fog_light_color = Color(0.12, 0.15, 0.25)
	e.fog_density = 0.012
	we.environment = e
	mondo.add_child(we)
	# luna: luce fredda e morbida, niente bianchi bruciati
	var luna := DirectionalLight3D.new()
	luna.light_color = Color(0.72, 0.78, 1.0)
	luna.light_energy = 0.55
	luna.rotation_degrees = Vector3(-55, -30, 0)
	luna.shadow_enabled = true
	mondo.add_child(luna)
	# lanterne calde agli angoli del villaggio
	for v in [Vector3(-3.6, 1.6, -3.6), Vector3(3.6, 1.6, -3.6), Vector3(-3.6, 1.6, 3.6), Vector3(3.6, 1.6, 3.6)]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.62, 0.3)
		l.light_energy = 0.9
		l.omni_range = 6.0
		l.position = v
		l.set_meta("base", 0.9)
		l.add_to_group("lanterne")
		mondo.add_child(l)
		# lanterna di carta rossa appesa sopra l'angolo del villaggio
		var lampada := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.16
		cm.bottom_radius = 0.16
		cm.height = 0.42
		cm.radial_segments = 12
		lampada.mesh = cm
		lampada.material_override = _emissivo(Color(1.0, 0.32, 0.12), 1.6)
		lampada.position = v
		mondo.add_child(lampada)
		for dy in [0.23, -0.23]:
			var tappo := MeshInstance3D.new()
			var cc := CylinderMesh.new()
			cc.top_radius = 0.11
			cc.bottom_radius = 0.11
			cc.height = 0.05
			tappo.mesh = cc
			var mt := StandardMaterial3D.new()
			mt.albedo_color = Color(0.1, 0.07, 0.05)
			tappo.material_override = mt
			tappo.position = v + Vector3(0, dy, 0)
			mondo.add_child(tappo)

func _emissivo(c: Color, forza: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = forza
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _materiale_tex(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.9
	m.metallic_specular = 0.2
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _piano(w: float, h: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, h)
	mi.mesh = pm
	mi.material_override = mat
	return mi

func _v3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x * U, y, p.y * U)

func _costruisci_tavolo() -> void:
	# il tavolo: legno laccato scuro
	var legno := StandardMaterial3D.new()
	var nt := NoiseTexture2D.new()
	var n := FastNoiseLite.new()
	n.frequency = 0.004
	n.fractal_octaves = 3
	nt.noise = n
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	var g := Gradient.new()
	g.set_color(0, Color(0.09, 0.04, 0.03))
	g.set_color(1, Color(0.2, 0.08, 0.05))
	nt.color_ramp = g
	legno.albedo_texture = nt
	legno.uv1_scale = Vector3(3, 3, 3)
	legno.roughness = 0.45
	var piano := _piano(40, 40, legno)
	piano.position.y = -0.02
	mondo.add_child(piano)
	# nebbia bassa che scorre sul tavolo
	var neb := _piano(30, 30, _mat_nebbia())
	neb.position.y = 0.35
	neb.name = "nebbia"
	mondo.add_child(neb)

func _mat_nebbia() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform sampler2D rumore : repeat_enable;
void fragment() {
	vec2 uv = UV * 3.0;
	float a = texture(rumore, uv + vec2(TIME * 0.012, TIME * 0.007)).r;
	float b = texture(rumore, uv * 1.7 - vec2(TIME * 0.009, -TIME * 0.011)).r;
	float d = length(UV - 0.5) * 2.0;
	float bordo = smoothstep(0.25, 0.95, d) * (1.0 - smoothstep(0.95, 1.0, d));
	ALBEDO = vec3(0.32, 0.42, 0.62);
	ALPHA = pow(a * b, 1.6) * (0.12 + 0.55 * bordo);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	var nt := NoiseTexture2D.new()
	var n := FastNoiseLite.new()
	n.frequency = 0.012
	nt.noise = n
	nt.seamless = true
	m.set_shader_parameter("rumore", nt)
	return m

## Il materiale degli spettri: colore del fantasma, bordo luminoso e un velo che si dissolve
func _mat_spettro(c: Color) -> ShaderMaterial:
	if not _mat.has("spettro"):
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;
uniform vec4 colore : source_color = vec4(0.4, 0.7, 1.0, 1.0);
uniform float dissolvi = 0.0;
uniform sampler2D rumore : repeat_enable;
varying vec3 pos;
void vertex() { pos = VERTEX; }
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float onde = texture(rumore, vec2(pos.x * 0.8 + TIME * 0.05, pos.y * 1.2 - TIME * 0.12)).r;
	float scompare = texture(rumore, pos.xy * 1.7).r;
	if (scompare < dissolvi) { discard; }
	float lembo = smoothstep(dissolvi, dissolvi + 0.08, scompare);
	ALBEDO = colore.rgb * 0.25;
	ROUGHNESS = 0.3;
	EMISSION = colore.rgb * (0.35 + 1.6 * fres + 0.4 * onde) + vec3(1.0, 0.85, 0.5) * (1.0 - lembo) * 3.0;
	ALPHA = clamp(0.35 + 0.55 * fres + 0.2 * onde, 0.0, 0.95) * (1.0 - 0.6 * smoothstep(0.6, 0.0, pos.y));
}
"""
		_mat["spettro"] = sh
	var m := ShaderMaterial.new()
	m.shader = _mat["spettro"]
	m.set_shader_parameter("colore", c)
	m.set_shader_parameter("rumore", _rumore())
	return m

func _rumore() -> NoiseTexture2D:
	if not _mat.has("rumore"):
		var nt := NoiseTexture2D.new()
		var n := FastNoiseLite.new()
		n.frequency = 0.03
		nt.noise = n
		nt.seamless = true
		_mat["rumore"] = nt
	return _mat["rumore"]

## Il Taoista: la miniatura del modulo, con la veste ricolorata nel colore della sua plancia
func _mat_taoista(c: Color) -> ShaderMaterial:
	if not _mat.has("taoista"):
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 colore : source_color;
uniform float grigio = 0.0;
void fragment() {
	vec4 t = texture(tex, UV);
	float rosso = t.r - max(t.g, t.b);
	float l = dot(t.rgb, vec3(0.3, 0.59, 0.11));
	vec3 tinto = colore.rgb * (0.35 + l * 1.9);
	vec3 c = mix(t.rgb, tinto, smoothstep(0.08, 0.25, rosso));
	ALBEDO = mix(c, vec3(l * 0.8), grigio);
	ROUGHNESS = 0.6;
}
"""
		_mat["taoista"] = sh
	var m := ShaderMaterial.new()
	m.shader = _mat["taoista"]
	m.set_shader_parameter("tex", Stile.tex("res://assets/modelli/taoista.png"))
	m.set_shader_parameter("colore", c)
	return m

func _modello(nome: String) -> Mesh:
	if not _mesh.has(nome):
		_mesh[nome] = load("res://assets/modelli/%s.obj" % nome)
	return _mesh[nome]

func _miniatura(nome: String, altezza: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _modello(nome)
	mi.scale = Vector3.ONE * altezza
	mi.material_override = mat
	return mi

## Prepara tessere e plance la prima volta che arriva lo stato
func _prepara(st: Dictionary) -> void:
	for t in 9:
		var nodo := Node3D.new()
		nodo.position = _v3(tavolo.centro_tessera(t), 0.04)
		mondo.add_child(nodo)
		var id: String = st.villaggio[t].id
		var fronte := _piano(2.16, 2.16, _materiale_tex(Stile.tex("res://assets/villaggio/%s.webp" % id)))
		fronte.position.y = 0.025
		nodo.add_child(fronte)
		var retro := _piano(2.16, 2.16, _materiale_tex(Stile.tex("res://assets/villaggio/%s_infestata.webp" % id)))
		retro.position.y = -0.025
		retro.rotation.x = PI
		nodo.add_child(retro)
		var bordo := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.18, 0.045, 2.18)
		bordo.mesh = bm
		var mb := StandardMaterial3D.new()
		mb.albedo_color = Color(0.16, 0.12, 0.1)
		bordo.material_override = mb
		nodo.add_child(bordo)
		nodo.set_meta("inf", false)
		_tessere.append(nodo)
	for p in 4:
		var b: Dictionary = st.plance[p]
		var pl := _piano(1450.0 * Tavolo.SCALA_PLANCIA * U, 1066.0 * Tavolo.SCALA_PLANCIA * U, _materiale_tex(Stile.tex("res://assets/plance/%s_%d.webp" % [b.colore, int(b.lato)])))
		var cen := tavolo.xf_plancia(p) * Tavolo.CENTRO_PLANCIA
		pl.position = _v3(cen, 0.012)
		pl.rotation.y = -Tavolo.ANGOLI[p]
		mondo.add_child(pl)
		_plance.append(pl)
		var et := Label3D.new()
		et.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		et.font = Stile.grassetto()
		et.font_size = 64
		et.pixel_size = 0.006
		et.outline_size = 14
		et.modulate = Stile.colore(b.colore).lightened(0.35)
		et.position = _v3(tavolo.xf_plancia(p) * Vector2(725, 1066 + 70), 0.5)
		et.no_depth_test = true
		mondo.add_child(et)
		_etichette3d[p] = et

# ============================================================ aggiornamento dallo stato

func aggiorna(st: Dictionary) -> void:
	if st.is_empty():
		return
	var primo := s.is_empty()
	s = st
	if _tessere.is_empty():
		_prepara(st)
	for p in 4:
		if _etichette3d.has(p):
			_etichette3d[p].text = etichette.get(p, "")
	_aggiorna_tessere(primo)
	_aggiorna_fantasmi(primo)
	_aggiorna_taoisti(primo)
	_aggiorna_buddha()
	_aggiorna_gettoni()
	_aggiorna_luna()
	_aggiorna_segreto()
	_aggiorna_evidenze()
	_eventi()

func _aggiorna_tessere(subito: bool) -> void:
	for t in 9:
		var nodo: Node3D = _tessere[t]
		var inf: bool = s.villaggio[t].inf
		if nodo.get_meta("inf") == inf:
			continue
		nodo.set_meta("inf", inf)
		var fine := Vector3(PI if inf else 0.0, 0, 0)
		if subito:
			nodo.rotation = fine
			continue
		var tw := create_tween()
		tw.tween_property(nodo, "position:y", 0.9, 0.35).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(nodo, "rotation", fine, 0.7).set_trans(Tween.TRANS_BACK)
		tw.tween_property(nodo, "position:y", 0.04, 0.3).set_trans(Tween.TRANS_BOUNCE)
		if inf:
			_fumo(nodo.position, Color(0.35, 0.85, 1.0), 2.5, 140)

func _chiave(p: int, k: int) -> String:
	return "%d:%d" % [p, k]

func _aggiorna_fantasmi(subito: bool) -> void:
	var visti := {}
	for p in 4:
		for k in 3:
			var sp: Dictionary = s.plance[p].spazi[k]
			var c := int(sp.c)
			var ch := _chiave(p, k)
			var cen := tavolo.centro_spazio(p, k)
			if c > 0:
				visti[ch] = true
				if _carte.has(ch) and int(_carte[ch].c) != c:
					_togli_fantasma(ch, false)
				if not _carte.has(ch):
					_metti_fantasma(ch, p, k, c, subito)
				var nodo: Node3D = _carte[ch].nodo
				nodo.position = _v3(cen, 0.0)
				# il dado catturato
				_carte[ch].dado.visible = sp.dado
				_carte[ch].mantra.visible = int(s.mantra.p) == p and int(s.mantra.s) == k
			# figurina infestante
			var inf := int(sp.inf) if c > 0 else -1
			if inf >= 0:
				var dove := tavolo.xf_plancia(p) * (Vector2(Tavolo.SPAZI_X[k], Tavolo.ICONA_INFESTANTE_Y) if inf == 1 else Vector2(Tavolo.SPAZI_X[k], Tavolo.SPAZIO_Y + 200))
				var pos := _v3(dove, 0.03)
				if not _infestanti.has(ch):
					var fig := _figurina_infestante()
					fig.position = pos
					mondo.add_child(fig)
					_infestanti[ch] = fig
				elif _infestanti[ch].position.distance_to(pos) > 0.05:
					var fig: Node3D = _infestanti[ch]
					var tw := create_tween()
					var su := (fig.position + pos) / 2.0 + Vector3(0, 0.8, 0)
					tw.tween_property(fig, "position", su, 0.35).set_trans(Tween.TRANS_SINE)
					tw.tween_property(fig, "position", pos, 0.35).set_trans(Tween.TRANS_SINE)
				_infestanti[ch].get_node("anello").visible = inf == 1
			elif _infestanti.has(ch):
				var fig: Node3D = _infestanti[ch]
				_infestanti.erase(ch)
				var tw := create_tween()
				tw.tween_property(fig, "scale", Vector3.ZERO, 0.4)
				tw.tween_callback(fig.queue_free)
	for ch in _carte.keys():
		if not visti.has(ch):
			_togli_fantasma(ch, true)

func _figurina_infestante() -> Node3D:
	var n := Node3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.03, 0.04)
	m.metallic = 0.4
	m.roughness = 0.35
	m.rim_enabled = true
	m.rim = 0.6
	m.emission_enabled = true
	m.emission = Color(0.1, 0.25, 0.35)
	m.emission_energy_multiplier = 0.4
	var mi := _miniatura("fantasma", 1.0, m)
	n.add_child(mi)
	var anello := MeshInstance3D.new()
	anello.name = "anello"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	anello.mesh = tm
	anello.material_override = _emissivo(Color(0.35, 0.9, 1.0), 2.5)
	anello.position.y = 0.04
	n.add_child(anello)
	return n

func _metti_fantasma(ch: String, p: int, k: int, c: int, subito: bool) -> void:
	var nodo := Node3D.new()
	mondo.add_child(nodo)
	nodo.position = _v3(tavolo.centro_spazio(p, k))
	# la carta, distesa sullo spazio della plancia
	var carta := _piano(Tavolo.CARTA.x * Tavolo.SCALA_PLANCIA * U, Tavolo.CARTA.y * Tavolo.SCALA_PLANCIA * U, _materiale_tex(Stile.carta(c)))
	carta.rotation.y = -Tavolo.ANGOLI[p]
	carta.position.y = 0.03
	nodo.add_child(carta)
	var dati := Dati.carta(c)
	var inc := Dati.e_incarnazione(c)
	var col: String = dati.get("colore_banda", dati.get("colore", "nero")) if inc else dati.get("colore", "nero")
	var colore: Color = COLORE_SPETTRO.get(col, Color(0.7, 0.4, 1.0))
	var spettro: Node3D = Node3D.new()
	nodo.add_child(spettro)
	var verso := Vector3(0, 0, 1).rotated(Vector3.UP, -Tavolo.ANGOLI[p])
	var mi: MeshInstance3D
	if inc:
		# il boss: l'Ombra di Wu-Feng, grande, avvolta dal fuoco del suo colore
		mi = _miniatura("ombra_wufeng", 3.4, _mat_spettro(Color(1.0, 0.25, 0.12) if col == "nero" else colore))
		var fuoco := _particelle_fuoco(Color(1.0, 0.4, 0.1) if col == "nero" else colore)
		spettro.add_child(fuoco)
		var luce := OmniLight3D.new()
		luce.light_color = Color(1.0, 0.3, 0.12) if col == "nero" else colore
		luce.light_energy = 1.6
		luce.omni_range = 4.5
		luce.position.y = 1.4
		luce.add_to_group("fiamme")
		spettro.add_child(luce)
		var nome := Label3D.new()
		nome.text = Dati.nome(c)
		nome.font = Stile.titolo()
		nome.font_size = 72
		nome.pixel_size = 0.007
		nome.outline_size = 16
		nome.modulate = Color(1.0, 0.55, 0.4)
		nome.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		nome.position.y = 3.9
		spettro.add_child(nome)
	else:
		mi = _miniatura("fantasma", 1.9, _mat_spettro(colore))
		var veli := _particelle_veli(colore)
		spettro.add_child(veli)
	spettro.add_child(mi)
	# lo spettro guarda il villaggio
	spettro.rotation.y = atan2(-verso.x, -verso.z) + PI
	spettro.set_meta("fase", randf() * TAU)
	spettro.set_meta("boss", inc)
	# dado catturato e mantra
	var dado := _cubo_dado(Color(0.95, 0.94, 0.9), 0.32)
	dado.position = Vector3(-0.5, 0.2, 0.5).rotated(Vector3.UP, -Tavolo.ANGOLI[p])
	dado.visible = false
	nodo.add_child(dado)
	var catena := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.26
	tm.outer_radius = 0.31
	catena.mesh = tm
	catena.material_override = _emissivo(Color(0.9, 0.1, 0.1), 1.8)
	dado.add_child(catena)
	var mantra := Sprite3D.new()
	mantra.texture = Stile.tex("res://assets/segnalini/mantra.webp")
	mantra.pixel_size = 0.006
	mantra.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mantra.position = Vector3(0, 2.0 if not inc else 3.5, 0)
	mantra.visible = false
	nodo.add_child(mantra)
	_carte[ch] = {"c": c, "nodo": nodo, "spettro": spettro, "mi": mi, "dado": dado, "mantra": mantra}
	if not subito:
		# entra dalla nebbia
		spettro.scale = Vector3(0.05, 0.05, 0.05)
		spettro.position.y = -0.6
		var tw := create_tween()
		tw.tween_property(spettro, "scale", Vector3.ONE, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(spettro, "position:y", 0.0, 0.9)
		_fumo(nodo.position, colore, 1.6 if not inc else 3.0, 90 if not inc else 220)
		if inc:
			_lampo(nodo.position + Vector3(0, 1.5, 0), Color(1.0, 0.2, 0.05), 6.0, 1.4)

func _togli_fantasma(ch: String, effetto: bool) -> void:
	var d: Dictionary = _carte[ch]
	_carte.erase(ch)
	var nodo: Node3D = d.nodo
	if not effetto:
		nodo.queue_free()
		return
	# l'esorcismo: lo spettro si dissolve in luce, la carta svanisce
	var mi: MeshInstance3D = d.mi
	var m: ShaderMaterial = mi.material_override
	var tw := create_tween()
	tw.tween_method(func(v): m.set_shader_parameter("dissolvi", v), 0.0, 1.05, 1.1)
	tw.parallel().tween_property(d.spettro, "position:y", 1.2, 1.1)
	tw.tween_callback(nodo.queue_free)
	_scintille(nodo.position + Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.45))
	_lampo(nodo.position + Vector3(0, 1.2, 0), Color(1.0, 0.9, 0.6), 4.0, 0.8)

func _aggiorna_taoisti(subito: bool) -> void:
	var per_t := {}
	for p in 4:
		var b: Dictionary = s.plance[p]
		if not b.taoista:
			continue
		var t := int(b.tessera) + (10 if b.get("sotto", false) else 0)
		if not per_t.has(t):
			per_t[t] = []
		per_t[t].append(p)
	for t in per_t:
		var l: Array = per_t[t]
		for i in l.size():
			var p: int = l[i]
			var b: Dictionary = s.plance[p]
			var off := Vector3.ZERO
			if l.size() > 1:
				off = Vector3(0.68, 0, 0).rotated(Vector3.UP, TAU * i / l.size() + PI / 4)
			var pos := _v3(tavolo.centro_tessera(t) if t < 10 else tavolo.centro_cata(t - 10), 0.07) + off
			if not _taoisti.has(p):
				var n := Node3D.new()
				var mi := _miniatura("taoista", 1.7, _mat_taoista(Stile.colore(b.colore)))
				mi.name = "fig"
				n.add_child(mi)
				var base := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.33
				cm.bottom_radius = 0.36
				cm.height = 0.07
				base.mesh = cm
				var mb := StandardMaterial3D.new()
				mb.albedo_color = Stile.colore(b.colore)
				mb.metallic = 0.3
				mb.roughness = 0.4
				base.material_override = mb
				n.add_child(base)
				var alone := MeshInstance3D.new()
				alone.name = "alone"
				var tm := TorusMesh.new()
				tm.inner_radius = 0.45
				tm.outer_radius = 0.53
				alone.mesh = tm
				alone.material_override = _emissivo(Color(1.0, 0.82, 0.35), 2.0)
				n.add_child(alone)
				n.position = pos
				mondo.add_child(n)
				_taoisti[p] = n
			var n2: Node3D = _taoisti[p]
			n2.get_node("alone").visible = p == int(s.turno_di) and b.vivo
			var fig: MeshInstance3D = n2.get_node("fig")
			var m: ShaderMaterial = fig.material_override
			m.set_shader_parameter("grigio", 0.0 if b.vivo else 0.85)
			var steso := Vector3(0, 0, 0) if b.vivo else Vector3(0, 0, PI / 2.0)
			if fig.rotation != steso:
				var tw0 := create_tween()
				tw0.tween_property(fig, "rotation", steso, 0.6)
				tw0.parallel().tween_property(fig, "position:y", 0.0 if b.vivo else 0.25, 0.6)
			if n2.position.distance_to(pos) > 0.05:
				if subito:
					n2.position = pos
				else:
					var tw := create_tween()
					var su := (n2.position + pos) / 2.0 + Vector3(0, 1.0, 0)
					tw.tween_property(n2, "position", su, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
					tw.tween_property(n2, "position", pos, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
					var dir := pos - n2.position
					if dir.length() > 0.1:
						n2.rotation.y = atan2(dir.x, dir.z)

func _mat_oro() -> StandardMaterial3D:
	if not _mat.has("oro"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.86, 0.64, 0.18)
		m.metallic = 0.85
		m.roughness = 0.3
		m.emission_enabled = true
		m.emission = Color(0.5, 0.32, 0.05)
		m.emission_energy_multiplier = 0.35
		_mat["oro"] = m
	return _mat["oro"]

func _aggiorna_buddha() -> void:
	var visti := {}
	for p in 4:
		for k in 3:
			if s.plance[p].spazi[k].buddha:
				var ch := _chiave(p, k)
				visti[ch] = true
				var c := int(s.plance[p].spazi[k].c)
				var pos := _v3(tavolo.centro_spazio(p, k), 0.04)
				if c > 0:
					pos += Vector3(0.7, 0, 0.9).rotated(Vector3.UP, -Tavolo.ANGOLI[p])
				if not _buddha.has(ch):
					var b := _miniatura("buddha", 0.95, _mat_oro())
					b.position = pos
					b.rotation.y = -Tavolo.ANGOLI[p] + PI
					mondo.add_child(b)
					_buddha[ch] = b
					_colonna_luce(pos, Color(1.0, 0.8, 0.35))
				else:
					_buddha[ch].position = pos
	for ch in _buddha.keys():
		if not visti.has(ch):
			var b: Node3D = _buddha[ch]
			_buddha.erase(ch)
			var tw := create_tween()
			tw.tween_property(b, "scale", Vector3.ZERO, 0.5)
			tw.tween_callback(b.queue_free)
	# i Buddha che aspettano sul Tempio
	var n := int(s.buddha_tempio)
	while _buddha_tempio.size() < n:
		var b := _miniatura("buddha", 0.5, _mat_oro())
		mondo.add_child(b)
		_buddha_tempio.append(b)
	while _buddha_tempio.size() > n:
		_buddha_tempio.pop_back().queue_free()
	var tt := -1
	for t in 9:
		if s.villaggio[t].id == "tempio":
			tt = t
	for i in _buddha_tempio.size():
		_buddha_tempio[i].position = _v3(tavolo.centro_tessera(tt), 0.07) + Vector3(-0.6 + i * 0.45, 0, -0.65)

func _aggiorna_gettoni() -> void:
	for c in _gettoni.get_children():
		c.queue_free()
	if s.cerchio != "":
		for t in 9:
			if s.villaggio[t].id == "cerchio":
				_gettoni.add_child(_gettone("res://assets/segnalini/tao_%s.webp" % s.cerchio, _v3(tavolo.centro_tessera(t), 0.1) + Vector3(-0.6, 0, -0.6), 0.32))
	for i in int(s.poteri_centro):
		_gettoni.add_child(_gettone("res://assets/segnalini/potere.webp", _v3(tavolo.centro_tessera(4), 0.1 + i * 0.06) + Vector3(0.65, 0, -0.65), 0.3))

## White Moon: si ricostruisce solo quando cambia qualcosa
func _aggiorna_luna() -> void:
	if not s.get("luna", false):
		return
	var ab := []
	for v in s.villaggio:
		ab.append(v.get("ab", []))
	var firma := str([s.portale, s.ricettacoli, ab, s.suling, s.barriera])
	if firma == _firma_luna:
		return
	_firma_luna = firma
	for c in _luna.get_children():
		c.queue_free()
	# il Portale (porta della luna) sulla sua tessera
	var pt := int(s.get("portale", -1))
	if pt >= 0:
		var pos := _v3(tavolo.centro_tessera(pt), 0.05)
		var mp := StandardMaterial3D.new()
		mp.albedo_color = Color(0.36, 0.38, 0.46)
		mp.roughness = 0.85
		mp.emission_enabled = true
		mp.emission = Color(0.2, 0.3, 0.6)
		mp.emission_energy_multiplier = 0.12
		var porta := _miniatura("portale", 0.75, mp)
		porta.position = pos + Vector3(0, 0, -0.78)
		_luna.add_child(porta)
		var luce := OmniLight3D.new()
		luce.light_color = Color(0.55, 0.7, 1.0)
		luce.light_energy = 0.35
		luce.omni_range = 1.8
		luce.position = pos + Vector3(0, 1.0, -0.4)
		_luna.add_child(luce)
	# i ricettacoli agli angoli esterni, con il cristallo che brilla se è pieno
	var mr := StandardMaterial3D.new()
	mr.albedo_color = Color(0.32, 0.3, 0.34)
	mr.roughness = 0.85
	for i in 4:
		var t: int = [0, 2, 6, 8][i]
		var dir := Vector2(-1 if t % 3 == 0 else 1, -1 if t < 3 else 1)
		var pos := _v3(tavolo.centro_tessera(t) + dir * (Tavolo.T * 0.5 + 40), 0.0)
		var ric := _miniatura("ricettacolo", 0.45, mr)
		ric.position = pos
		_luna.add_child(ric)
		if s.ricettacoli[i]:
			var mc := StandardMaterial3D.new()
			mc.albedo_color = Color(0.55, 0.8, 1.0, 0.85)
			mc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mc.emission_enabled = true
			mc.emission = Color(0.4, 0.7, 1.0)
			mc.emission_energy_multiplier = 0.9
			var cr := _miniatura("cristallo", 0.42, mc)
			cr.position = pos + Vector3(0, 0.4, 0)
			cr.set_meta("gira", true)
			_luna.add_child(cr)
			var lc := OmniLight3D.new()
			lc.light_color = Color(0.5, 0.75, 1.0)
			lc.light_energy = 0.5
			lc.omni_range = 1.6
			lc.position = pos + Vector3(0, 0.8, 0)
			_luna.add_child(lc)
	# le pile dei villici: gettoni quadrati con il villico in cima scoperto
	for t in 9:
		var pila: Array = s.villaggio[t].get("ab", [])
		var base := _v3(tavolo.centro_tessera(t) + Vector2(Tavolo.T * 0.5 - 52, Tavolo.T * 0.5 - 52), 0.06)
		for j in pila.size():
			var scat := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.72, 0.07, 0.72)
			scat.mesh = bm
			var mb := StandardMaterial3D.new()
			mb.albedo_color = Color(0.32, 0.22, 0.14)
			scat.material_override = mb
			scat.position = base + Vector3(0, j * 0.075, 0)
			_luna.add_child(scat)
			if j == pila.size() - 1:
				var f := _piano(0.7, 0.7, _materiale_tex(Stile.tex("res://assets/villici/%s.webp" % pila[j])))
				f.position = scat.position + Vector3(0, 0.04, 0)
				_luna.add_child(f)
	# Su-Ling: una figura di luce davanti allo spazio che protegge
	if int(s.suling.p) >= 0:
		var sp := tavolo.centro_spazio(int(s.suling.p), int(s.suling.k))
		var verso := (sp - tavolo.centro_tessera(4)).normalized()
		var pos := _v3(sp - verso * 260, 0.0)
		var spr := Sprite3D.new()
		spr.texture = Stile.tex("res://assets/segnalini/suling.webp")
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.pixel_size = 0.0055
		spr.position = pos + Vector3(0, 1.1, 0)
		spr.modulate = Color(0.85, 0.92, 1.0, 0.92)
		spr.shaded = false
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		_luna.add_child(spr)
		var ls := OmniLight3D.new()
		ls.light_color = Color(0.7, 0.85, 1.0)
		ls.light_energy = 0.6
		ls.omni_range = 2.2
		ls.position = pos + Vector3(0, 1.2, 0)
		_luna.add_child(ls)
		_luna.add_child(_particelle_veli(Color(0.7, 0.85, 1.0, 0.5)))
		_luna.get_child(_luna.get_child_count() - 1).position = pos + Vector3(0, 0.8, 0)
	# la Barriera Mistica: una cupola di luce sul villaggio
	if s.barriera:
		var cup := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 4.2
		sm.height = 4.2
		sm.is_hemisphere = true
		cup.mesh = sm
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.5, 0.7, 1.0, 0.12)
		mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mm.cull_mode = BaseMaterial3D.CULL_DISABLED
		mm.emission_enabled = true
		mm.emission = Color(0.4, 0.6, 1.0)
		mm.emission_energy_multiplier = 0.3
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cup.material_override = mm
		_luna.add_child(cup)

## Black Secret: si ricostruisce solo quando cambia qualcosa
func _aggiorna_segreto() -> void:
	if not s.get("segreto", false):
		return
	var pile := []
	for c in s.cata:
		pile.append([c.pila.size(), c.scala])
	var firma := str([pile, s.demoni, s.ombra, s.ombra_sotto, s.pir_id, s.urne, s.scheletri])
	if firma == _firma_segreto:
		return
	_firma_segreto = firma
	for c in _segreto.get_children():
		c.queue_free()
	# la plancia delle catacombe e quella di Wu-Feng, appoggiate sul tavolo
	var lc := Tavolo.LATO_CATA * U
	var cat := _piano(lc, lc, _materiale_tex(Stile.tex("res://assets/bs/catacombe.webp")))
	cat.position = _v3(Tavolo.C_CATA, 0.03)
	_segreto.add_child(cat)
	var bordo := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(lc + 0.2, 0.06, lc + 0.2)
	bordo.mesh = bm
	var mbor := StandardMaterial3D.new()
	mbor.albedo_color = Color(0.16, 0.12, 0.1)
	bordo.material_override = mbor
	bordo.position = _v3(Tavolo.C_CATA, 0.0)
	_segreto.add_child(bordo)
	var lw := Tavolo.LATO_WF * U
	var wf := _piano(lw, lw, _materiale_tex(Stile.tex("res://assets/bs/wufeng.webp")))
	wf.position = _v3(Tavolo.C_WF, 0.03)
	_segreto.add_child(wf)
	var legno := StandardMaterial3D.new()
	legno.albedo_color = Color(0.42, 0.28, 0.15)
	legno.roughness = 0.9
	for i in 9:
		var c := tavolo.centro_cata(i)
		var cc: Dictionary = s.cata[i]
		if cc.scala:
			_segreto.add_child(_scala(_v3(c + Vector2(-55, -50), 0.03), legno))
		var pila: Array = cc.pila
		for j in pila.size():
			var g := MeshInstance3D.new()
			var gm := CylinderMesh.new()
			gm.top_radius = 0.24
			gm.bottom_radius = 0.24
			gm.height = 0.05
			g.mesh = gm
			var mg := StandardMaterial3D.new()
			mg.albedo_color = Color(0.36, 0.25, 0.16)
			g.material_override = mg
			g.position = _v3(c + Vector2(40, -40), 0.06 + j * 0.055)
			_segreto.add_child(g)
		if not pila.is_empty():
			var top := _piano(0.42, 0.42, _materiale_tex(Stile.tex("res://assets/bs/cat_dorso_%d.webp" % pila.size())))
			top.position = _v3(c + Vector2(40, -40), 0.09 + (pila.size() - 1) * 0.055)
			_segreto.add_child(top)
	# i demoni nelle catacombe
	var per_cata := {}
	for d in Tavolo.DEMONI:
		var i := int(s.demoni[d])
		if i >= 0:
			if not per_cata.has(i):
				per_cata[i] = []
			per_cata[i].append(d)
	for i in per_cata:
		var l: Array = per_cata[i]
		for j in l.size():
			var d: String = l[j]
			var md := StandardMaterial3D.new()
			md.albedo_color = {"cercatore": Color(0.45, 0.36, 0.22), "scavatore": Color(0.4, 0.3, 0.2), "becchino": Color(0.55, 0.25, 0.12)}[d]
			md.roughness = 0.75
			md.emission_enabled = true
			md.emission = Color(0.5, 0.08, 0.04)
			md.emission_energy_multiplier = 0.25
			var mi := _miniatura("demone_" + d, {"cercatore": 0.8, "scavatore": 1.0, "becchino": 1.2}[d], md)
			mi.position = _v3(tavolo.centro_cata(i) + Vector2(-25 + j * 45, 30), 0.06)
			mi.rotation.y = PI
			_segreto.add_child(mi)
			var luce := OmniLight3D.new()
			luce.light_color = Color(1.0, 0.3, 0.15)
			luce.light_energy = 0.35
			luce.omni_range = 1.3
			luce.position = mi.position + Vector3(0, 0.9, 0)
			_segreto.add_child(luce)
	# l'Ombra di Wu-Feng: figura alta, rossa, con fiamme
	if int(s.ombra) >= 0:
		var mo := StandardMaterial3D.new()
		mo.albedo_color = Color(0.45, 0.06, 0.05)
		mo.roughness = 0.6
		mo.emission_enabled = true
		mo.emission = Color(0.6, 0.05, 0.02)
		mo.emission_energy_multiplier = 0.45
		var om := _miniatura("ombra_wufeng", 2.6, mo)
		var dove := tavolo.centro_cata(int(s.ombra)) if s.ombra_sotto else tavolo.centro_tessera(int(s.ombra)) + Vector2(-60, -60)
		om.position = _v3(dove, 0.06)
		_segreto.add_child(om)
		var fuoco := _particelle_fuoco(Color(0.9, 0.2, 0.05, 0.7))
		fuoco.position = om.position + Vector3(0, 0.3, 0)
		_segreto.add_child(fuoco)
		var lo := OmniLight3D.new()
		lo.light_color = Color(1.0, 0.25, 0.1)
		lo.light_energy = 0.8
		lo.omni_range = 2.6
		lo.position = om.position + Vector3(0, 1.6, 0)
		_segreto.add_child(lo)
	# piramide delle maledizioni e urne trovate
	for rr in 4:
		var ids: Array = s.pir_id[rr]
		for j in ids.size():
			var g := _piano(0.5, 0.5, _materiale_tex(Stile.tex("res://assets/bs/maledizione_%s.webp" % ids[j])))
			g.position = _v3(tavolo.pos_piramide(rr, j), 0.07)
			_segreto.add_child(g)
	for j in int(s.urne):
		var g := _piano(0.55, 0.55, _materiale_tex(Stile.tex("res://assets/bs/cat_urna.webp")))
		g.position = _v3(tavolo.pos_urna(j), 0.07)
		_segreto.add_child(g)

## Una scala di legno appoggiata: due montanti e quattro pioli
func _scala(pos: Vector3, mat: Material) -> Node3D:
	var n := Node3D.new()
	for x in [-0.12, 0.12]:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.05, 0.65, 0.05)
		m.mesh = b
		m.material_override = mat
		m.position = Vector3(x, 0.32, 0)
		n.add_child(m)
	for j in 4:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.26, 0.035, 0.035)
		m.mesh = b
		m.material_override = mat
		m.position = Vector3(0, 0.12 + j * 0.14, 0)
		n.add_child(m)
	n.position = pos
	n.rotation.x = -0.35
	return n

func _gettone(tex: String, pos: Vector3, r: float) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	var cil := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.05
	cil.mesh = cm
	var mb := StandardMaterial3D.new()
	mb.albedo_color = Color(0.2, 0.14, 0.1)
	cil.material_override = mb
	n.add_child(cil)
	var faccia := _piano(r * 2, r * 2, _materiale_tex(Stile.tex(tex)))
	faccia.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	faccia.position.y = 0.03
	n.add_child(faccia)
	return n

func _aggiorna_evidenze() -> void:
	for c in _evid.get_children():
		c.queue_free()
	var fatte := {}
	for o in evidenzia:
		var pos := Vector3.ZERO
		var dim := Vector2.ZERO
		var rot := 0.0
		if o.has("spazio"):
			var x: Array = o.spazio
			var k := "s%d.%d" % [x[0], x[1]]
			if fatte.has(k):
				continue
			fatte[k] = true
			pos = _v3(tavolo.centro_spazio(int(x[0]), int(x[1])), 0.06)
			dim = Tavolo.CARTA * Tavolo.SCALA_PLANCIA * U + Vector2(0.25, 0.25)
			rot = -Tavolo.ANGOLI[int(x[0])]
		elif o.has("cata") and s.get("segreto", false):
			var k := "c%d" % int(o.cata)
			if fatte.has(k):
				continue
			fatte[k] = true
			pos = _v3(tavolo.centro_cata(int(o.cata)), 0.12)
			dim = Vector2(1.4, 1.4)
		elif o.has("tessera"):
			var k := "t%d" % int(o.tessera)
			if fatte.has(k):
				continue
			fatte[k] = true
			pos = _v3(tavolo.centro_tessera(int(o.tessera)), 0.12)
			dim = Vector2(2.1, 2.1)
		else:
			continue
		var cornice := _cornice(dim)
		cornice.position = pos
		cornice.rotation.y = rot
		_evid.add_child(cornice)

func _cornice(dim: Vector2) -> Node3D:
	var n := Node3D.new()
	var m := _emissivo(Color(1.0, 0.82, 0.3), 2.4)
	var sp := 0.07
	for lato in [[Vector3(0, 0, -dim.y / 2), Vector3(dim.x, sp, sp)], [Vector3(0, 0, dim.y / 2), Vector3(dim.x, sp, sp)],
			[Vector3(-dim.x / 2, 0, 0), Vector3(sp, sp, dim.y)], [Vector3(dim.x / 2, 0, 0), Vector3(sp, sp, dim.y)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = lato[1]
		mi.mesh = bm
		mi.material_override = m
		mi.position = lato[0]
		n.add_child(mi)
	n.add_to_group("cornici")
	return n

# ============================================================ effetti

func _particelle_veli(c: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 18
	p.lifetime = 2.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45
	p.direction = Vector3.UP
	p.spread = 25
	p.gravity = Vector3(0, 0.25, 0)
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.35
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.3
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	p.mesh = sm
	var m := _emissivo(c, 1.2)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(c.r, c.g, c.b, 0.25)
	m.vertex_color_use_as_albedo = true
	p.material_override = m
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.2, Color(1, 1, 1, 0.5))
	g.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	p.position.y = 0.4
	return p

func _particelle_fuoco(c: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 1.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_radius = 0.9
	p.emission_ring_inner_radius = 0.3
	p.emission_ring_height = 0.1
	p.emission_ring_axis = Vector3.UP
	p.direction = Vector3.UP
	p.spread = 15
	p.gravity = Vector3(0, 1.2, 0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.0
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.16
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var m := _emissivo(c, 3.0)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = m
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.9, 0.5, 1))
	g.set_color(1, Color(c.r, c.g * 0.4, c.b * 0.2, 0))
	p.color_ramp = g
	return p

## Una nuvola che si alza e svanisce (arrivo dei fantasmi, infestazioni)
func _fumo(pos: Vector3, c: Color, raggio: float, quante: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = quante
	p.lifetime = 1.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = raggio * 0.4
	p.direction = Vector3.UP
	p.spread = 70
	p.gravity = Vector3(0, 0.5, 0)
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.6
	p.scale_amount_min = 0.2
	p.scale_amount_max = 0.55
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	p.mesh = sm
	var m := _emissivo(c, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	p.material_override = m
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.55))
	g.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	p.position = pos + Vector3(0, 0.3, 0)
	mondo.add_child(p)
	p.emitting = true
	_poi_libera(p, 2.5)

func _poi_libera(n: Node, dopo: float) -> void:
	var tw := n.create_tween()
	tw.tween_interval(dopo)
	tw.tween_callback(n.queue_free)

func _scintille(pos: Vector3, c: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 120
	p.lifetime = 1.3
	p.direction = Vector3.UP
	p.spread = 60
	p.gravity = Vector3(0, -1.5, 0)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.07
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var m := _emissivo(c, 4.0)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = m
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 0.6, 0.2, 0))
	p.color_ramp = g
	p.position = pos
	mondo.add_child(p)
	p.emitting = true
	_poi_libera(p, 2.0)

func _lampo(pos: Vector3, c: Color, forza: float, durata: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = forza
	l.omni_range = 6
	l.position = pos
	mondo.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, durata)
	tw.tween_callback(l.queue_free)

## La colonna di luce dorata di un Buddha
func _colonna_luce(pos: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 0.6
	cm.height = 6
	mi.mesh = cm
	var m := _emissivo(c, 2.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(c.r, c.g, c.b, 0.4)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = m
	mi.position = pos + Vector3(0, 3, 0)
	mondo.add_child(mi)
	var tw := create_tween()
	tw.tween_method(func(a): m.albedo_color.a = a, 0.45, 0.0, 1.4)
	tw.tween_callback(mi.queue_free)

## Un anello rosso che pulsa attorno al Taoista che perde Qi
func _impulso(pos: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.5
	tm.outer_radius = 0.6
	mi.mesh = tm
	var m := _emissivo(c, 3.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.position = pos + Vector3(0, 0.15, 0)
	mondo.add_child(mi)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(3, 1, 3), 0.8)
	tw.parallel().tween_method(func(a): m.albedo_color.a = a, 1.0, 0.0, 0.8)
	tw.tween_callback(mi.queue_free)

# ------------------------------------------------------------ dadi

func _faccia_tao(col: String) -> ImageTexture:
	var chiave := "faccia_" + col
	if _mat.has(chiave):
		return _mat[chiave]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.93, 0.93, 0.9))
	var c: Color = Dati.COLORE_RGB[col]
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length()
			if d < 20:
				img.set_pixel(x, y, c)
			elif d < 22 and col == "bianco":
				img.set_pixel(x, y, Color(0.6, 0.6, 0.6))
	var t := ImageTexture.create_from_image(img)
	_mat[chiave] = t
	return t

const FACCE_CUBO := [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]

## Un dado: sei facce, con il colore (o l'immagine) che si vuole su ognuna
func _cubo(facce: Array, lato: float, corpo: Color) -> Node3D:
	var n := Node3D.new()
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * lato * 0.98
	box.mesh = bm
	var mb := StandardMaterial3D.new()
	mb.albedo_color = corpo
	mb.roughness = 0.4
	box.material_override = mb
	n.add_child(box)
	for i in 6:
		var q := _piano(lato * 0.92, lato * 0.92, _materiale_tex(facce[i]))
		var dir: Vector3 = FACCE_CUBO[i]
		q.position = dir * lato * 0.5
		# orienta il piano (che guarda in alto) verso la faccia
		if dir == Vector3.DOWN:
			q.rotation.x = PI
		elif dir == Vector3.RIGHT:
			q.rotation.z = -PI / 2
		elif dir == Vector3.LEFT:
			q.rotation.z = PI / 2
		elif dir == Vector3.BACK:
			q.rotation.x = PI / 2
		elif dir == Vector3.FORWARD:
			q.rotation.x = -PI / 2
		n.add_child(q)
	return n

func _cubo_dado(c: Color, lato: float) -> Node3D:
	var t := []
	for i in 6:
		t.append(_faccia_tao("bianco"))
	var d := _cubo(t, lato, c)
	var pip := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = lato * 0.18
	sm.height = lato * 0.36
	pip.mesh = sm
	pip.material_override = _emissivo(Color(0.85, 0.1, 0.1), 1.0)
	pip.position.y = lato * 0.5
	d.add_child(pip)
	return d

## Rotazione che porta la faccia i in alto
func _rotazione_faccia(i: int) -> Vector3:
	match i:
		1: return Vector3(PI, 0, 0)
		2: return Vector3(0, 0, PI / 2)
		3: return Vector3(0, 0, -PI / 2)
		4: return Vector3(-PI / 2, 0, 0)
		5: return Vector3(PI / 2, 0, 0)
	return Vector3.ZERO

func lancia_dadi(facce: Array, vicino: Vector3) -> void:
	for c in _dadi.get_children():
		c.queue_free()
	var ordine := ["giallo", "verde", "rosso", "blu", "nero", "bianco"]
	for i in facce.size():
		var t := []
		for f in ordine:
			t.append(_faccia_tao(f))
		var d := _cubo(t, 0.55, Color(0.93, 0.93, 0.9))
		_dadi.add_child(d)
		var arrivo := vicino + Vector3(-0.8 + i * 0.75, 0.3, 1.2)
		d.position = arrivo + Vector3(randf_range(-2, 2), 3.5, randf_range(2, 4))
		d.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var fine := _rotazione_faccia(ordine.find(facce[i]))
		fine.y = randf() * TAU
		var tw := create_tween()
		tw.tween_property(d, "position", arrivo + Vector3(0, 0.6, 0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(d, "rotation", d.rotation + Vector3(TAU * 2, TAU, TAU * 1.5), 0.45)
		tw.tween_property(d, "position", arrivo, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(d, "rotation", fine, 0.35)
	for c in _dadi.get_children():
		var tw2 := c.create_tween()
		tw2.tween_interval(5.0)
		tw2.tween_property(c, "scale", Vector3.ZERO, 0.4)
		tw2.tween_callback(c.queue_free)

func lancia_maledizione(faccia: String, vicino: Vector3) -> void:
	var nero := Image.create(8, 8, false, Image.FORMAT_RGB8)
	nero.fill(Color(0.05, 0.05, 0.06))
	var vuoto := ImageTexture.create_from_image(nero)
	var t := [vuoto, vuoto, Stile.tex("res://assets/segnalini/maledizione_infesta.webp"), Stile.tex("res://assets/segnalini/maledizione_fantasma.webp"),
		Stile.tex("res://assets/segnalini/maledizione_tao.webp"), Stile.tex("res://assets/segnalini/maledizione_qi.webp")]
	var d := _cubo(t, 0.7, Color(0.05, 0.05, 0.06))
	_dadi.add_child(d)
	var arrivo := vicino + Vector3(0.0, 0.38, -1.2)
	d.position = arrivo + Vector3(0, 4, 3)
	var i: int = {"nulla": 0, "infesta": 2, "fantasma": 3, "tao": 4, "qi": 5}.get(faccia, 0)
	var fine := _rotazione_faccia(i)
	var tw := create_tween()
	tw.tween_property(d, "position", arrivo + Vector3(0, 0.6, 0), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(d, "rotation", Vector3(TAU * 2, TAU, TAU), 0.5)
	tw.tween_property(d, "position", arrivo, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(d, "rotation", fine, 0.35)
	_fumo(arrivo, Color(0.9, 0.12, 0.08), 0.8, 40)
	var tw2 := d.create_tween()
	tw2.tween_interval(4.0)
	tw2.tween_property(d, "scale", Vector3.ZERO, 0.4)
	tw2.tween_callback(d.queue_free)

func _eventi() -> void:
	for e in s.get("eventi", []):
		var n := int(e.get("n", 0))
		if n <= _ultimo_evento:
			continue
		_ultimo_evento = n
		var vicino := Vector3.ZERO
		if e.has("p") and _taoisti.has(int(e.p)):
			vicino = _taoisti[int(e.p)].position
		match String(e.e):
			"dadi": lancia_dadi(e.f, vicino if e.has("p") else Vector3.ZERO)
			"maledizione": lancia_maledizione(e.f, _taoisti.get(int(s.turno_di), Node3D.new()).position if _taoisti.has(int(s.turno_di)) else Vector3.ZERO)
			"qi":
				if int(e.d) < 0 and _taoisti.has(int(e.p)):
					_impulso(_taoisti[int(e.p)].position, Color(1.0, 0.15, 0.1))
				elif int(e.d) > 0 and _taoisti.has(int(e.p)):
					_impulso(_taoisti[int(e.p)].position, Color(0.3, 1.0, 0.5))
			"buddha":
				var pos := _v3(tavolo.centro_spazio(int(e.p), int(e.s)))
				_colonna_luce(pos, Color(1.0, 0.85, 0.4))
				_scintille(pos + Vector3(0, 0.8, 0), Color(1.0, 0.85, 0.4))
			"libera":
				_scintille(_tessere[int(e.t)].position + Vector3(0, 0.5, 0), Color(0.6, 1.0, 0.7))
			"morte":
				if _taoisti.has(int(e.p)):
					_fumo(_taoisti[int(e.p)].position, Color(0.5, 0.5, 0.6), 1.0, 60)
			"risorge":
				if _taoisti.has(int(e.p)):
					_colonna_luce(_taoisti[int(e.p)].position, Color(0.6, 1.0, 0.8))
			"scava":
				var pc := _v3(tavolo.centro_cata(int(e.i)), 0.4)
				_fumo(pc, Color(0.4, 0.3, 0.2), 0.5, 30)
				if String(e.get("s", "")) == "urna":
					_lampo(pc + Vector3(0, 0.8, 0), Color(1.0, 0.3, 0.1), 2.0, 0.8)
			"urna":
				_impulso(_v3(Tavolo.C_WF), Color(1.0, 0.2, 0.1))
			"demone":
				if int(e.i) >= 0:
					_fumo(_v3(tavolo.centro_cata(int(e.i)), 0.3), Color(0.5, 0.1, 0.05), 0.5, 30)
				elif e.get("esorcizzato", false):
					_colonna_luce(_v3(tavolo.centro_cata(int(e.get("da", 4))), 0.1), Color(0.9, 0.8, 0.5))
			"ombra":
				var po := _v3(tavolo.centro_cata(int(e.i)) if e.sotto else tavolo.centro_tessera(int(e.i)), 0.5)
				_lampo(po + Vector3(0, 1.0, 0), Color(1.0, 0.15, 0.05), 2.5, 1.0)
				_fumo(po, Color(0.3, 0.02, 0.02), 0.8, 50)
			"wf_maledizione":
				_lampo(_v3(Tavolo.C_WF, 1.0), Color(0.8, 0.1, 0.4), 1.6, 0.7)
			"ms_attiva":
				_impulso(Vector3.ZERO, Color(0.9, 0.1, 0.1))
			"uccidi":
				var pv := _v3(tavolo.centro_tessera(int(e.t)), 0.3)
				_fumo(pv, Color(0.55, 0.1, 0.1), 0.6, 40)
				_lampo(pv + Vector3(0, 0.6, 0), Color(1.0, 0.2, 0.1), 1.2, 0.5)
			"salva":
				_colonna_luce(_v3(tavolo.centro_tessera(int(e.t)), 0.1), Color(0.55, 0.75, 1.0))
			"ricettacolo":
				var t: int = [0, 2, 6, 8][int(e.i)]
				_scintille(_v3(tavolo.centro_tessera(t), 0.6), Color(0.5, 0.8, 1.0))
			"barriera":
				_lampo(Vector3(0, 3, 0), Color(0.5, 0.7, 1.0), 3.0, 1.5)
				_impulso(Vector3.ZERO, Color(0.5, 0.75, 1.0))
			"suling":
				_scintille(_v3(tavolo.centro_spazio(int(e.p), int(e.s)), 1.0), Color(0.8, 0.9, 1.0))
			"cristallo":
				if _taoisti.has(int(e.p)):
					_scintille(_taoisti[int(e.p)].position + Vector3(0, 1.0, 0), Color(0.5, 0.8, 1.0))
			"mantra":
				var pos2 := _v3(tavolo.centro_spazio(int(e.p), int(e.s)))
				_scintille(pos2 + Vector3(0, 1.5, 0), Color(1.0, 0.95, 0.4))

# ============================================================ animazione continua

func _process(d: float) -> void:
	_tempo += d
	if absf(yaw - yaw_obiettivo) > 0.001:
		yaw = lerp_angle(yaw, yaw_obiettivo, minf(1.0, d * 4.0))
	_aggiorna_camera()
	for ch in _carte:
		var sp: Node3D = _carte[ch].spettro
		var f: float = sp.get_meta("fase", 0.0)
		var boss: bool = sp.get_meta("boss", false)
		if sp.scale.x > 0.99:
			sp.position.y = (0.25 if not boss else 0.1) + sin(_tempo * 1.3 + f) * (0.12 if not boss else 0.06)
		var mi: MeshInstance3D = _carte[ch].mi
		mi.rotation.y = sin(_tempo * 0.6 + f) * 0.25
	for l in get_tree().get_nodes_in_group("lanterne"):
		l.light_energy = float(l.get_meta("base")) * (0.88 + 0.12 * sin(_tempo * 7.0 + l.position.x) * sin(_tempo * 3.1 + l.position.z))
	for l in get_tree().get_nodes_in_group("fiamme"):
		l.light_energy = 1.3 + 0.5 * sin(_tempo * 11.0) * sin(_tempo * 4.3)
	for c in _luna.get_children():
		if c.has_meta("gira"):
			c.rotation.y = _tempo * 0.8
	var pulsa := 0.5 + 0.5 * sin(_tempo * 5.0)
	for c in _evid.get_children():
		c.position.y = 0.08 + 0.05 * pulsa
		c.scale = Vector3.ONE * (1.0 + 0.015 * pulsa)

# ============================================================ camera e tocchi

func centra() -> void:
	bersaglio = Vector3.ZERO
	distanza = 15.0
	pitch = 0.9

func ruota_verso(pos: int) -> void:
	yaw_obiettivo = -Tavolo.ANGOLI[pos]

func ruota_di(d: float) -> void:
	yaw_obiettivo += d

func _aggiorna_camera() -> void:
	if cam == null:
		return
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	cam.position = bersaglio + dir * distanza
	cam.look_at(bersaglio, Vector3.UP)

func _punto_tavolo(schermo: Vector2) -> Vector3:
	var sc := Vector2(vp.size) / size if size.x > 0 else Vector2.ONE
	var p := schermo * sc
	var o := cam.project_ray_origin(p)
	var d := cam.project_ray_normal(p)
	if absf(d.y) < 0.0001:
		return Vector3.INF
	var t := -o.y / d.y
	return o + d * t

func _cosa(schermo: Vector2) -> Dictionary:
	var w := _punto_tavolo(schermo)
	if w == Vector3.INF:
		return {}
	return tavolo.cosa_in_mondo(Vector2(w.x, w.z) / U)

func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		_tocco(e)
		accept_event()
		return
	if e is InputEventMouse and e.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			distanza = clampf(distanza / 1.1, 4.0, 40.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			distanza = clampf(distanza * 1.1, 4.0, 40.0)
		elif e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if e.pressed:
				_premuto = true
				_trascinato = false
				_ultimo = e.position
				_orbita = e.button_index == MOUSE_BUTTON_RIGHT or e.shift_pressed
			else:
				if _premuto and not _trascinato and e.button_index == MOUSE_BUTTON_LEFT:
					toccato.emit(_cosa(e.position))
				_premuto = false
		accept_event()
	elif e is InputEventMouseMotion:
		if _premuto:
			var dlt: Vector2 = e.position - _ultimo
			if dlt.length() > 3 or _trascinato:
				_trascinato = true
				if _orbita:
					yaw -= dlt.x * 0.008
					yaw_obiettivo = yaw
					pitch = clampf(pitch + dlt.y * 0.006, 0.25, 1.45)
				else:
					_sposta(dlt)
				_ultimo = e.position
		else:
			var q := _cosa(e.position)
			sopra.emit(q)

func _sposta(dlt: Vector2) -> void:
	var destra := Vector3(cos(yaw), 0, -sin(yaw))
	var avanti := Vector3(-sin(yaw), 0, -cos(yaw))
	var k := distanza * 0.0016
	bersaglio -= destra * dlt.x * k
	bersaglio -= avanti * dlt.y * k * -1.0
	bersaglio.x = clampf(bersaglio.x, -9, 9)
	bersaglio.z = clampf(bersaglio.z, -9, 9)

func _tocco(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_tocchi[e.index] = e.position
			if _tocchi.size() == 1:
				_trascinato = false
				_ultimo = e.position
		else:
			if _tocchi.size() == 1 and not _trascinato:
				toccato.emit(_cosa(e.position))
			_tocchi.erase(e.index)
			if _tocchi.size() == 1:
				_ultimo = _tocchi.values()[0]
		_inizia_gesto()
	elif e is InputEventScreenDrag:
		_tocchi[e.index] = e.position
		if _tocchi.size() == 1:
			var dlt: Vector2 = e.position - _ultimo
			if dlt.length() > 6 or _trascinato:
				_trascinato = true
				_sposta(dlt)
				_ultimo = e.position
		elif _tocchi.size() >= 2 and not _gesto.is_empty():
			_trascinato = true
			var k: Array = _tocchi.keys()
			var a: Vector2 = _tocchi[k[0]]
			var b: Vector2 = _tocchi[k[1]]
			var dist := maxf(10.0, a.distance_to(b))
			distanza = clampf(_gesto.distanza * _gesto.dist / dist, 4.0, 40.0)
			yaw = _gesto.yaw - ((b - a).angle() - _gesto.ang)
			yaw_obiettivo = yaw
			# due dita che salgono o scendono insieme inclinano la vista
			var mezzo := (a + b) / 2.0
			pitch = clampf(_gesto.pitch + (mezzo.y - _gesto.mezzo.y) * 0.004, 0.25, 1.45)

func _inizia_gesto() -> void:
	_gesto = {}
	if _tocchi.size() >= 2:
		var k: Array = _tocchi.keys()
		var a: Vector2 = _tocchi[k[0]]
		var b: Vector2 = _tocchi[k[1]]
		_gesto = {"dist": maxf(10.0, a.distance_to(b)), "ang": (b - a).angle(), "distanza": distanza, "yaw": yaw, "pitch": pitch, "mezzo": (a + b) / 2.0}
