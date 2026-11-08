class_name UiTheme
extends RefCounted
## Shared look for DUSHANBE-X menus: dark translucent panels with Tajik flag accents.

const RED := Color("#CC0000")
const WHITE := Color(1, 1, 1)
const GREEN := Color("#006600")
const GOLD := Color("#F8C300")
const PANEL := Color(0.05, 0.06, 0.09, 0.80)
const PANEL_LIGHT := Color(0.12, 0.14, 0.19, 0.92)
const TEXT := Color(0.95, 0.96, 0.98)
const TEXT_DIM := Color(0.7, 0.74, 0.8)

static var _theme: Theme


static func box(bg: Color, radius := 14, border := Color(0, 0, 0, 0), bw := 0, pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.anti_aliasing = true
	return s


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 26
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 4)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 18, Color(1, 1, 1, 0.08), 1, 18))
	t.set_stylebox("panel", "Panel", box(PANEL, 18))
	# buttons
	t.set_stylebox("normal", "Button", box(PANEL_LIGHT, 12, Color(1, 1, 1, 0.12), 2, 20))
	t.set_stylebox("hover", "Button", box(Color(0.2, 0.22, 0.28, 0.95), 12, GOLD, 2, 20))
	t.set_stylebox("pressed", "Button", box(RED.darkened(0.15), 12, GOLD, 2, 20))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 12, GOLD, 2, 20))
	t.set_stylebox("disabled", "Button", box(Color(0.1, 0.1, 0.12, 0.6), 12))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", WHITE)
	t.set_font_size("font_size", "Button", 28)
	# check / option
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_font_size("font_size", "CheckButton", 26)
	t.set_stylebox("normal", "OptionButton", box(PANEL_LIGHT, 12, Color(1, 1, 1, 0.12), 2, 18))
	t.set_stylebox("hover", "OptionButton", box(Color(0.2, 0.22, 0.28, 0.95), 12, GOLD, 2, 18))
	t.set_stylebox("pressed", "OptionButton", box(RED.darkened(0.15), 12, GOLD, 2, 18))
	# sliders: thick and finger friendly
	var track := box(Color(1, 1, 1, 0.18), 6, Color(0, 0, 0, 0), 0, 0)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", track)
	var fill := box(GOLD, 6, Color(0, 0, 0, 0), 0, 0)
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _circle_tex(34, WHITE))
	t.set_icon("grabber_highlight", "HSlider", _circle_tex(38, GOLD))
	t.set_stylebox("panel", "PopupMenu", box(PANEL_LIGHT, 10))
	t.set_font_size("font_size", "PopupMenu", 28)
	t.set_stylebox("panel", "TabContainer", box(PANEL, 14))
	t.set_stylebox("tab_selected", "TabContainer", box(RED, 10, Color(0, 0, 0, 0), 0, 18))
	t.set_stylebox("tab_unselected", "TabContainer", box(PANEL_LIGHT, 10, Color(0, 0, 0, 0), 0, 18))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(0.25, 0.25, 0.3), 10, Color(0, 0, 0, 0), 0, 18))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	_theme = t
	return t


static func _circle_tex(d: int, c: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := d * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)


## Big title label with gold underline used by menu screens.
static func title(text: String, size := 40) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## Thin tricolour stripe (red / white / green) used as a decorative accent.
static func flag_stripe(height := 6.0) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	hb.custom_minimum_size.y = height
	for c in [RED, WHITE, GREEN]:
		var r := ColorRect.new()
		r.color = c
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.custom_minimum_size.y = height
		hb.add_child(r)
	return hb
