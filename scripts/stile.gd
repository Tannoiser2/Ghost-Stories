class_name Stile
extends RefCounted
## Colori, font e piccoli aiuti grafici: notte blu, lacca rossa e oro, come le carte di Ghost Stories.

const FONDO := Color("07080f")
const NOTTE := Color("0e1226")
const PANNELLO := Color(0.05, 0.06, 0.12, 0.93)
const ORO := Color("e2bb63")
const ORO_SCURO := Color("8a6a2a")
const LACCA := Color("8e1c17")
const LACCA_CHIARA := Color("b8322a")
const GIADA := Color("4fb38a")
const TESTO := Color("efe6d2")
const TESTO_DEBOLE := Color("a99f8a")
const SPETTRO := Color("9fc4ff")
const ROSSO := Color("ff5a4e")
const VERDE := Color("6fd88f")

static var _font := {}

static func font(nome: String) -> Font:
	if not _font.has(nome):
		_font[nome] = load("res://assets/font/%s.ttf" % nome)
	return _font[nome]

static func titolo() -> Font:
	return font("KaushanScript-Regular")

static func testo() -> Font:
	return font("AlegreyaSans-Medium")

static func grassetto() -> Font:
	return font("AlegreyaSans-Bold")

static func maiuscoletto() -> Font:
	return font("AlegreyaSansSC-Bold")

static var _tex := {}

static func tex(percorso: String) -> Texture2D:
	if not _tex.has(percorso):
		_tex[percorso] = load(percorso)
	return _tex[percorso]

static func carta(n: int) -> Texture2D:
	return tex("res://assets/carte/fantasma_%02d.webp" % n)

static func colore(c: String) -> Color:
	return Dati.COLORE_RGB.get(c, Color.WHITE)

static func tema() -> Theme:
	var t := Theme.new()
	t.default_font = testo()
	t.default_font_size = 22
	t.set_color("font_color", "Label", TESTO)
	for k in ["Button", "CheckBox", "OptionButton"]:
		t.set_color("font_color", k, TESTO)
		t.set_color("font_hover_color", k, Color.WHITE)
		t.set_color("font_pressed_color", k, Color.WHITE)
		t.set_color("font_focus_color", k, TESTO)
		t.set_color("font_disabled_color", k, Color(1, 1, 1, 0.35))
		t.set_font("font", k, grassetto())
		t.set_font_size("font_size", k, 22)
	t.set_stylebox("normal", "Button", scatola(Color("2a1414"), ORO_SCURO, 8, 2))
	t.set_stylebox("hover", "Button", scatola(Color("4a1d18"), ORO, 8, 2))
	t.set_stylebox("pressed", "Button", scatola(LACCA, ORO, 8, 3))
	t.set_stylebox("disabled", "Button", scatola(Color("1a1515"), Color("3a3020"), 8, 2))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", scatola(PANNELLO, ORO_SCURO, 12, 2))
	t.set_stylebox("normal", "LineEdit", scatola(Color("0c0e1a"), ORO_SCURO, 8, 2))
	t.set_stylebox("focus", "LineEdit", scatola(Color("0c0e1a"), ORO, 8, 2))
	t.set_color("font_color", "LineEdit", TESTO)
	t.set_font_size("font_size", "LineEdit", 28)
	t.set_font("font", "LineEdit", grassetto())
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	return t

static func scatola(fondo: Color, bordo: Color, raggio := 10, spessore := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fondo
	s.border_color = bordo
	s.set_border_width_all(spessore)
	s.set_corner_radius_all(raggio)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s

static func etichetta(t: String, dim := 22, col := TESTO, f: Font = null) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", dim)
	l.add_theme_color_override("font_color", col)
	if f:
		l.add_theme_font_override("font", f)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 80
	return l

static func paragrafo(t: String, dim := 20, col := TESTO) -> Label:
	var l := etichetta(t, dim, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 160
	return l

static func bottone(t: String, dim := 22) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", dim)
	b.custom_minimum_size = Vector2(120, 44)
	b.clip_text = false
	return b

static func bottone_scelta(t: String, attivo: bool, dim := 22) -> Button:
	var b := bottone(t, dim)
	if attivo:
		b.add_theme_stylebox_override("normal", scatola(LACCA, ORO, 8, 3))
		b.add_theme_stylebox_override("hover", scatola(LACCA_CHIARA, ORO, 8, 3))
	return b

static func pannello() -> PanelContainer:
	var p := PanelContainer.new()
	return p
