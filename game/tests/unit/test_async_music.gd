extends TestCase
## Background music loading: a prefetched world track is loaded off the main
## thread and picked up by the bank without a blocking load.


func test_prefetched_music_comes_from_the_background_loader() -> void:
	var bank: SoundBank = SoundBank.from_file()
	var entry: Dictionary = bank.music("molten_grid")
	assert_false(entry.is_empty(), "world track exists")
	assert_eq(bank.prefetch_music("molten_grid"), 3, "base, intensity and boss loops requested")
	var path: String = str(entry["base"])
	var waited: int = 0
	while not bank.loader.is_ready(path) and waited < 600:
		await wait_frames(1)
		waited += 1
	assert_true(bank.loader.is_ready(path), "loaded in the background")
	assert_true(bank.stream_at(path) != null, "the bank takes the prefetched stream")
	assert_eq(bank.prefetch_music("molten_grid"), 2, "already-held loops are not requested again")
