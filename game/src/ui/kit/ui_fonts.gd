class_name UiFonts
extends RefCounted
## One font family (Outfit, SIL OFL 1.1) in three weights, each with a
## Latin-Extended fallback so Turkish glyphs (ğ ş ı İ) render in the same face.

const DIR: String = "res://assets/fonts/"
const WEIGHTS: Array[int] = [400, 600, 800]

static var _fonts: Dictionary[int, Font] = {}
static var _variations: Dictionary[String, Font] = {}


static func get_font(weight: int) -> Font:
	var w: int = _nearest(weight)
	if _fonts.has(w):
		return _fonts[w]
	var base: FontFile = load(DIR + "outfit-latin-%d-normal.woff2" % w) as FontFile
	var ext: FontFile = load(DIR + "outfit-latin-ext-%d-normal.woff2" % w) as FontFile
	if base == null:
		GameLog.error("ui", "missing font weight %d" % w)
		return ThemeDB.fallback_font
	if ext != null:
		base.fallbacks = [ext]
	_fonts[w] = base
	return base


## A tracked (letter-spaced) variation of a weight, cached.
static func tracked(weight: int, tracking: int) -> Font:
	var key: String = "%d:%d" % [weight, tracking]
	if _variations.has(key):
		return _variations[key]
	var v: FontVariation = FontVariation.new()
	v.base_font = get_font(weight)
	v.spacing_glyph = tracking
	_variations[key] = v
	return v


static func _nearest(weight: int) -> int:
	var best: int = WEIGHTS[0]
	for w: int in WEIGHTS:
		if absi(w - weight) < absi(best - weight):
			best = w
	return best
