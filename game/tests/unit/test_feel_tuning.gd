extends TestCase
## The gameplay feel table (FeelTuning): every feedback kind the gameplay view
## emits has a named strength, each emit looks up its own kind, and the table
## lists nothing the view never emits.

const VIEW_SOURCE: String = "res://src/gameplay/view/gameplay_view.gd"


func test_every_emitted_feedback_kind_has_a_strength() -> void:
	var kind_literal: RegEx = RegEx.create_from_string('&"([a-z_]+)"')
	var kinds: PackedStringArray = PackedStringArray()
	for line: String in FileAccess.get_file_as_string(VIEW_SOURCE).split("\n"):
		if not line.contains("feedback.emit("):
			continue
		var on_line: PackedStringArray = PackedStringArray()
		for found: RegExMatch in kind_literal.search_all(line):
			if not on_line.has(found.get_string(1)):
				on_line.append(found.get_string(1))
		assert_eq(on_line.size(), 1, "one kind per emit, its strength looked up by it: %s" % line.strip_edges())
		for kind: String in on_line:
			assert_true(FeelTuning.FEEDBACK_STRENGTH.has(StringName(kind)), 'a strength for &"%s"' % kind)
			if not kinds.has(kind):
				kinds.append(kind)
	assert_gt(kinds.size(), 20, "the scan finds the view's feedback calls")
	for kind: StringName in FeelTuning.FEEDBACK_STRENGTH:
		assert_true(kinds.has(String(kind)), '&"%s" is emitted by the view' % kind)
		var strength: float = FeelTuning.strength(kind)
		assert_true(strength > 0.0 and strength <= 1.0, '&"%s" strength in (0, 1]' % kind)
	assert_eq(FeelTuning.strength(&"not_a_kind"), FeelTuning.DEFAULT_FEEDBACK_STRENGTH, "unlisted kind")
