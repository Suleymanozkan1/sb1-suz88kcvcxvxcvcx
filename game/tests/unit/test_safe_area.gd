extends TestCase
## SafeAreaContainer on simulated devices: notch / Dynamic Island / home
## indicator insets become margins in canvas units, on several aspect ratios.

const DEVICES: Array[Dictionary] = [
	# Phone with a notch and a home indicator (19.5:9, physical pixels).
	{"screen": Vector2i(1179, 2556), "safe": Rect2i(0, 141, 1179, 2313), "view": Vector2i(720, 1561)},
	# Tall Android phone with a punch-hole (20:9).
	{"screen": Vector2i(1080, 2400), "safe": Rect2i(0, 96, 1080, 2304), "view": Vector2i(720, 1600)},
	# Classic 16:9 phone, no cut-out.
	{"screen": Vector2i(1080, 1920), "safe": Rect2i(0, 0, 1080, 1920), "view": Vector2i(720, 1280)},
	# 4:3 tablet in portrait.
	{"screen": Vector2i(1536, 2048), "safe": Rect2i(0, 40, 1536, 1988), "view": Vector2i(960, 1280)},
]


func _container_in(view: Vector2i, screen: Vector2i, safe: Rect2i) -> SafeAreaContainer:
	var vp: SubViewport = SubViewport.new()
	vp.size = view
	tree.root.add_child(vp)
	var c: SafeAreaContainer = SafeAreaContainer.new()
	c.debug_screen_size = screen
	c.debug_safe_rect = safe
	vp.add_child(c)
	return c


func test_insets_become_margins_on_every_device() -> void:
	for dev: Dictionary in DEVICES:
		var screen: Vector2i = dev["screen"]
		var safe: Rect2i = dev["safe"]
		var view: Vector2i = dev["view"]
		var c: SafeAreaContainer = _container_in(view, screen, safe)
		var scale: float = float(view.y) / float(screen.y)
		var top: int = c.get_theme_constant("margin_top")
		var bottom: int = c.get_theme_constant("margin_bottom")
		assert_eq(top, c.base_margin + int(ceil(float(safe.position.y) * scale)), "top inset %s" % str(screen))
		var bottom_inset: float = float(screen.y - safe.end.y) * scale
		assert_eq(bottom, c.base_margin + int(ceil(bottom_inset)), "bottom inset %s" % str(screen))
		assert_eq(c.get_theme_constant("margin_left"), c.base_margin, "no side cut-out")
		c.get_parent().queue_free()
	await wait_frames(1)


func test_notched_phone_keeps_content_clear_of_the_notch() -> void:
	var dev: Dictionary = DEVICES[0]
	var c: SafeAreaContainer = _container_in(dev["view"], dev["screen"], dev["safe"])
	var notch_canvas: float = 141.0 * float((dev["view"] as Vector2i).y) / 2556.0
	assert_gt(float(c.get_theme_constant("margin_top")), notch_canvas, "content starts below the notch")
	c.get_parent().queue_free()
	await wait_frames(1)
