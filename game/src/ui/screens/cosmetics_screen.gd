class_name CosmeticsScreen
extends UiScreen
## Shop and Collection share one layout (one design system):
## - live 3D preview of the selected core skin (the in-game CoreView itself),
## - category tabs, item grid, a single context action (Buy / Equip / locked).
## Shop mode additionally lists cosmetic-only premium packs. Prices and unlock
## requirements are stated plainly; nothing is time-limited.

signal buy_requested(item_id: String)
signal equip_requested(item_id: String)
signal pack_requested(product_id: String)
signal back_requested

const TILE: int = 144
const COLUMNS: int = 4
const RARITY_KEYS: Dictionary = {
	"common": "rarity.common",
	"rare": "rarity.rare",
	"epic": "rarity.epic",
	"legendary": "rarity.legendary",
}

var mode: StringName = &"shop"
var _header: ScreenHeader
var _tabs: UiSegmented
var _grid: GridContainer
var _detail_name: Label
var _detail_info: Label
var _action: UiButton
var _packs: VBoxContainer
var _preview_swatch: CosmeticSwatch
var _payload: Dictionary = {}
var _category: String = "core_skin"
var _selected: String = ""
var _coins: Label
var _gems: Label


func build() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root: SafeAreaContainer = make_safe_root()
	var col: VBoxContainer = UiKit.vbox()
	root.add_child(col)
	_header = ScreenHeader.new()
	_header.setup("")
	_header.back_pressed.connect(func() -> void: back_requested.emit())
	var coins: HBoxContainer = UiKit.stat_chip(&"coin", "0", Palette.ACCENT)
	_coins = coins.get_node("Value") as Label
	_header.trailing.add_child(coins)
	var gems: HBoxContainer = UiKit.stat_chip(&"gem", "0", Palette.SECONDARY)
	_gems = gems.get_node("Value") as Label
	_header.trailing.add_child(gems)
	col.add_child(_header)
	col.add_child(_build_preview())
	var detail: HBoxContainer = UiKit.hbox()
	var info: VBoxContainer = UiKit.vbox(UiTokens.UNIT / 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_name = UiKit.text("", &"h3")
	info.add_child(_detail_name)
	_detail_info = UiKit.text("", &"caption", UiTokens.TEXT_MUTED)
	_detail_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_detail_info)
	detail.add_child(info)
	_action = UiKit.button("", UiKit.ButtonRole.PRIMARY)
	_action.custom_minimum_size = Vector2(UiTokens.u(22), UiTokens.BUTTON_HEIGHT)
	_action.pressed.connect(_on_action)
	detail.add_child(_action)
	col.add_child(detail)
	# Nine categories never fit one row: the tab strip scrolls sideways
	# instead of stretching the whole screen wider than the device.
	var tab_scroll: ScrollContainer = ScrollContainer.new()
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	tab_scroll.custom_minimum_size = Vector2(0, UiTokens.BUTTON_HEIGHT)
	col.add_child(tab_scroll)
	_tabs = UiSegmented.new()
	_tabs.compact = true
	tab_scroll.add_child(_tabs)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var body: VBoxContainer = UiKit.vbox()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", UiTokens.GUTTER)
	_grid.add_theme_constant_override("v_separation", UiTokens.GUTTER)
	var center: CenterContainer = CenterContainer.new()
	center.add_child(_grid)
	body.add_child(center)
	_packs = UiKit.vbox(UiTokens.GUTTER)
	body.add_child(_packs)


func _build_preview() -> Control:
	# One quiet "stage" card with the large flat preview. Colours are drawn
	# exactly as the item defines them (a 3D sub-viewport would shift them
	# through a second colour-space conversion and misrepresent the purchase).
	var stage: PanelContainer = UiKit.card()
	stage.custom_minimum_size = Vector2(0, UiTokens.u(24))
	_preview_swatch = CosmeticSwatch.new()
	_preview_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_preview_swatch)
	return stage


## payload: {"mode": "shop"|"collection", "coins", "gems", "categories": [{id, label}],
##   "items": [{id, category, name, rarity, owned, equipped, price: {"coins": n}|{"gems": n},
##              affordable, requirement (String), params (Dictionary)}],
##   "packs": [{id, name, items_label, available}], "store_available": bool}
func enter(payload: Dictionary) -> void:
	_payload = payload
	mode = StringName(str(payload.get("mode", "shop")))
	_header.title_label.text = tr("menu.shop") if mode == &"shop" else tr("menu.collection")
	_coins.text = UiKit.format_int(int(payload.get("coins", 0)))
	_gems.text = UiKit.format_int(int(payload.get("gems", 0)))
	for c: Node in _tabs.get_children():
		c.queue_free()
	if _tabs.selected.is_connected(_on_tab):
		_tabs.selected.disconnect(_on_tab)
	var ids: PackedStringArray = PackedStringArray()
	var labels: PackedStringArray = PackedStringArray()
	for raw: Variant in payload.get("categories", []) as Array:
		var c2: Dictionary = raw as Dictionary
		ids.append(str(c2["id"]))
		labels.append(str(c2["label"]))
	if not ids.has(_category) and not ids.is_empty():
		_category = ids[0]
	_tabs.setup(ids, labels, _category)
	_tabs.selected.connect(_on_tab)
	_refresh()


func _on_tab(id: String) -> void:
	_category = id
	_selected = ""
	_refresh()


func _items_in_category() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in _payload.get("items", []) as Array:
		var it: Dictionary = raw as Dictionary
		if str(it.get("category", "")) != _category:
			continue
		if mode == &"shop" and (bool(it.get("owned", false)) or not (it.get("price", {}) as Dictionary).size() > 0):
			continue
		out.append(it)
	return out


func _refresh() -> void:
	for c: Node in _grid.get_children():
		c.queue_free()
	var items: Array[Dictionary] = _items_in_category()
	if _selected.is_empty() and not items.is_empty():
		_selected = str(items[0]["id"])
		for it: Dictionary in items:
			if bool(it.get("equipped", false)):
				_selected = str(it["id"])
	for it2: Dictionary in items:
		_grid.add_child(_tile(it2))
	_update_detail()
	for c3: Node in _packs.get_children():
		c3.queue_free()
	if mode == &"shop":
		_build_packs()


func _tile(it: Dictionary) -> Control:
	var id: String = str(it["id"])
	var b: Button = Button.new()
	b.theme_type_variation = &"ChoiceButton"
	b.custom_minimum_size = Vector2(TILE, TILE)
	if id == _selected:
		var sb: StyleBoxFlat = (
			(UiTheme.get_theme().get_stylebox("normal", &"ChoiceButton") as StyleBoxFlat).duplicate() as StyleBoxFlat
		)
		sb.border_color = Palette.PRIMARY
		sb.set_border_width_all(UiTokens.STROKE)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
	b.pressed.connect(
		func() -> void:
			UiKit.play_feedback(&"ui_click")
			_selected = id
			_refresh()
	)
	var swatch: CosmeticSwatch = CosmeticSwatch.new()
	swatch.setup(str(it.get("category", "")), it.get("params", {}) as Dictionary, bool(it.get("owned", false)))
	swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(swatch)
	if bool(it.get("equipped", false)):
		var check: IconGlyph = UiKit.icon(&"check", 22, Palette.SUCCESS)
		check.position = Vector2(TILE - 30, 8)
		b.add_child(check)
	return b


func _selected_item() -> Dictionary:
	for raw: Variant in _payload.get("items", []) as Array:
		var it: Dictionary = raw as Dictionary
		if str(it["id"]) == _selected:
			return it
	return {}


func _update_detail() -> void:
	var it: Dictionary = _selected_item()
	_action.visible = not it.is_empty()
	if it.is_empty():
		_detail_name.text = tr("shop.empty") if mode == &"shop" else ""
		_detail_info.text = ""
		return
	_detail_name.text = str(it.get("name", ""))
	var rarity: String = tr(str(RARITY_KEYS.get(str(it.get("rarity", "common")), "rarity.common")))
	var owned: bool = bool(it.get("owned", false))
	var price: Dictionary = it.get("price", {}) as Dictionary
	if owned:
		_detail_info.text = rarity
		_action.text = tr("shop.equipped") if bool(it.get("equipped", false)) else tr("shop.equip")
		_action.disabled = bool(it.get("equipped", false))
	elif not price.is_empty():
		var currency: String = "coins" if price.has("coins") else "gems"
		_detail_info.text = rarity
		_action.text = tr("shop.buy").format({"price": UiKit.format_int(int(price[currency]))})
		_action.set_glyph_color(UiTokens.TEXT_ON_PRIMARY)
		_action.disabled = not bool(it.get("affordable", false))
	else:
		_detail_info.text = rarity + "  ·  " + str(it.get("requirement", ""))
		_action.text = tr("shop.locked")
		_action.disabled = true
	_preview_swatch.setup(str(it.get("category", "")), it.get("params", {}) as Dictionary, true)


func _on_action() -> void:
	var it: Dictionary = _selected_item()
	if it.is_empty():
		return
	if bool(it.get("owned", false)):
		equip_requested.emit(str(it["id"]))
	else:
		buy_requested.emit(str(it["id"]))


func _build_packs() -> void:
	var packs: Array = _payload.get("packs", []) as Array
	if packs.is_empty():
		return
	_packs.add_child(UiKit.text(tr("shop.packs"), &"caption", UiTokens.TEXT_MUTED))
	var store_ok: bool = bool(_payload.get("store_available", false))
	for raw: Variant in packs:
		var p: Dictionary = raw as Dictionary
		var card: PanelContainer = UiKit.card()
		var row: HBoxContainer = UiKit.hbox()
		card.add_child(row)
		var info: VBoxContainer = UiKit.vbox(UiTokens.UNIT / 2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UiKit.text(str(p.get("name", "")), &"h3"))
		var desc: Label = UiKit.text(str(p.get("items_label", "")), &"caption", UiTokens.TEXT_MUTED)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc)
		row.add_child(info)
		var owned: bool = bool(p.get("owned", false))
		# Short state on the button; the honest "store unavailable" sentence is
		# shown once under the list instead of truncated on every row.
		var b: UiButton = UiKit.button(
			tr("shop.owned") if owned else (tr("shop.view_store") if store_ok else tr("shop.unavailable_short")),
			UiKit.ButtonRole.SECONDARY
		)
		b.disabled = owned or not store_ok
		var pid: String = str(p.get("id", ""))
		b.pressed.connect(func() -> void: pack_requested.emit(pid))
		row.add_child(b)
		_packs.add_child(card)
	if not store_ok:
		var unavailable: Label = UiKit.text(tr("shop.store_unavailable"), &"caption", UiTokens.TEXT_MUTED)
		unavailable.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_packs.add_child(unavailable)
	var note: Label = UiKit.text(tr("shop.cosmetic_only_note"), &"caption", UiTokens.TEXT_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_packs.add_child(note)


static func _color(p: Dictionary, key: String, fallback: Color) -> Color:
	var v: Variant = p.get(key, null)
	if typeof(v) == TYPE_COLOR:
		return v as Color
	if typeof(v) == TYPE_STRING and Color.html_is_valid(str(v)):
		return Color(str(v))
	return fallback


func handle_back() -> bool:
	back_requested.emit()
	return true
