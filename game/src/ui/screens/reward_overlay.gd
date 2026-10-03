class_name RewardOverlay
extends UiScreen
## Reward reveal for level-ups, achievements, mission claims, daily rewards and
## world completion. It animates exactly the granted RewardBundle — every value
## on screen was already applied to the profile (nothing is "pending").
## Motion (ART_DIRECTION §8): title settles, items land 120 ms apart, numbers
## count up; one action.

signal continue_requested
signal item_landed(index: int)

const ITEM_ICONS: Dictionary = {
	"coins": [&"coin", Palette.ACCENT],
	"gems": [&"gem", Palette.SECONDARY],
	"xp": [&"progress", Palette.PRIMARY],
	"stars": [&"star_filled", Palette.ACCENT],
	"cosmetic": [&"collection", Palette.PRIMARY],
	"badge": [&"trophy", Palette.ACCENT],
}

var reduce_motion: bool = false

var _eyebrow: Label
var _title: Label
var _subtitle: Label
var _items: HBoxContainer
var _preview: CosmeticSwatch
var _continue: UiButton
var _seq_tween: Tween


func build() -> void:
	is_overlay = true
	add_scrim(0.93)
	var root: SafeAreaContainer = make_safe_root()
	var col: VBoxContainer = UiKit.vbox(UiTokens.GUTTER)
	root.add_child(col)
	col.add_child(UiKit.expand())
	_eyebrow = UiKit.text("", &"caption", Palette.ACCENT)
	_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_eyebrow)
	_title = UiKit.text("", &"h2")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	_subtitle = UiKit.text("", &"body", UiTokens.TEXT_MUTED)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_subtitle)
	_preview = CosmeticSwatch.new()
	_preview.custom_minimum_size = Vector2(UiTokens.u(20), UiTokens.u(20))
	_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_preview.visible = false
	col.add_child(_preview)
	_items = UiKit.hbox(UiTokens.u(4))
	_items.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_items)
	col.add_child(UiKit.expand())
	_continue = UiKit.button(tr("ui.continue"), UiKit.ButtonRole.PRIMARY, &"check")
	_continue.pressed.connect(func() -> void: continue_requested.emit())
	col.add_child(_continue)


## payload: {"eyebrow", "title", "subtitle", "bundle": RewardBundle,
##           "cosmetic": {"category", "params"} (optional)}
func enter(payload: Dictionary) -> void:
	_eyebrow.text = str(payload.get("eyebrow", ""))
	_title.text = str(payload.get("title", ""))
	_subtitle.text = str(payload.get("subtitle", ""))
	_subtitle.visible = not _subtitle.text.is_empty()
	var cosmetic: Dictionary = payload.get("cosmetic", {}) as Dictionary
	_preview.visible = not cosmetic.is_empty()
	if _preview.visible:
		_preview.setup(str(cosmetic.get("category", "")), cosmetic.get("params", {}) as Dictionary, true)
	for c: Node in _items.get_children():
		c.queue_free()
	var bundle: RewardBundle = payload.get("bundle") as RewardBundle
	var targets: Array[int] = []
	var labels: Array[Label] = []
	var cells: Array[Control] = []
	if bundle != null:
		for raw: Variant in bundle.items:
			var item: Dictionary = raw as Dictionary
			var type: String = str(item.get("type", ""))
			if not ITEM_ICONS.has(type) or type == "cosmetic" or type == "badge":
				continue
			var spec: Array = ITEM_ICONS[type] as Array
			var cell: VBoxContainer = UiKit.vbox(UiTokens.UNIT / 2)
			cell.alignment = BoxContainer.ALIGNMENT_CENTER
			var glyph: IconGlyph = UiKit.icon(spec[0] as StringName, 40, spec[1] as Color)
			glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			cell.add_child(glyph)
			var value: Label = UiKit.text("+0", &"reward")
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.add_child(value)
			var cap: Label = UiKit.text(tr("reward.label." + type), &"caption", UiTokens.TEXT_MUTED)
			cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.add_child(cap)
			_items.add_child(cell)
			targets.append(int(item.get("amount", 0)))
			labels.append(value)
			cells.append(cell)
	_animate(cells, labels, targets)
	_continue.grab_focus.call_deferred()


func _animate(cells: Array[Control], labels: Array[Label], targets: Array[int]) -> void:
	if _seq_tween != null:
		_seq_tween.kill()
	if cells.is_empty():
		return
	if reduce_motion:
		for i: int in labels.size():
			labels[i].text = "+" + UiKit.format_int(targets[i])
		return
	_seq_tween = create_tween()
	for i: int in cells.size():
		var cell: Control = cells[i]
		var label: Label = labels[i]
		var target: int = targets[i]
		cell.modulate.a = 0.0
		var index: int = i
		_seq_tween.tween_callback(
			func() -> void:
				cell.modulate.a = 1.0
				cell.pivot_offset = cell.size * 0.5
				cell.scale = Vector2(0.8, 0.8)
				var pop: Tween = cell.create_tween()
				pop.tween_property(cell, "scale", Vector2(1.06, 1.06), 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(
					Tween.EASE_OUT
				)
				pop.tween_property(cell, "scale", Vector2.ONE, 0.1)
				item_landed.emit(index)
		)
		(
			_seq_tween
			. tween_method(
				func(v: float) -> void: label.text = "+" + UiKit.format_int(int(round(v))),
				0.0,
				float(target),
				UiTokens.COUNT_UP_TIME * 0.6
			)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_OUT)
		)
		_seq_tween.tween_interval(UiTokens.STAR_INTERVAL)


func handle_back() -> bool:
	continue_requested.emit()
	return true
