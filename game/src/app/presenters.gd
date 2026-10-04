class_name Presenters
extends RefCounted
## Builds screen payloads from real system state. Screens stay dumb views and
## every number they show comes from here — nothing is invented for display.

const BONUS_CHEST_FLAG: String = "bonus_chest_day"
const CATEGORY_ORDER: PackedStringArray = [
	"core_skin",
	"trail",
	"particle",
	"effect",
	"background",
	"theme",
	"frame",
	"avatar",
	"badge",
]
const MODE_ORDER: Array[StringName] = [
	&"classic",
	&"endless",
	&"time_attack",
	&"daily",
	&"perfect_run",
	&"zen",
	&"hard",
	&"boss_rush",
]


static func t(key: String) -> String:
	return TranslationServer.translate(key)


## Localised world name ("world.<id>.name"), falling back to the data name.
static func world_name(world: Dictionary) -> String:
	var key: String = "world.%s.name" % str(world.get("id", ""))
	var text: String = t(key)
	return str(world.get("name", "")) if text == key or text.is_empty() else text


static func main_menu(s: AppServices) -> Dictionary:
	var p: PlayerProfile = s.profile
	# XP inside the current level (profile.xp is the lifetime total).
	var xp_state: Dictionary = s.progression.xp_progress()
	var need: int = maxi(1, int(xp_state.get("needed", 1)))
	var next_id: String = s.progression.next_level_to_play()
	var loc: Dictionary = WorldCatalog.parse_level_id(next_id)
	var world: Dictionary = s.catalog.world_at(int(loc.get("world_index", 1)))
	var hint: Dictionary = s.progression.next_unlock_hint()
	var unlock: Dictionary = {}
	if not hint.is_empty():
		unlock = {
			"title": _hint_title(s, hint),
			"progress": int(hint.get("progress", 0)),
			"target": int(hint.get("target", 1))
		}
	var daily: Dictionary = s.daily.status()
	var claimable: int = s.missions.claimable_count()
	var badge: String = ""
	var daily_open: bool = (
		s.modes.is_unlocked(&"daily", s.mode_progress()) and s.remote_config.get_bool("daily.enabled", true)
	)
	if daily_open and not bool(daily.get("completed", false)):
		badge = t("menu.daily_new")
	elif claimable > 0:
		badge = str(claimable)
	return {
		"coins": s.economy.balance(EconomyService.COINS),
		"gems": s.economy.balance(EconomyService.GEMS),
		"player_level": p.player_level,
		"xp_progress": float(int(xp_state.get("into_level", 0))) / float(need),
		"next_level_label":
		t("menu.next_level").format({"world": world_name(world), "n": int(loc.get("local_index", 1))}),
		"unlock": unlock,
		"daily_badge": badge,
		"emblem": emblem(s),
	}


## The equipped avatar, frame and badge (the badge only when one beyond the
## starter badge is worn, so the default emblem stays quiet).
static func emblem(s: AppServices) -> Dictionary:
	return {
		"avatar": s.cosmetics.avatar_params(),
		"frame": s.cosmetics.frame_params(),
		"badge": worn(s, CosmeticCatalog.BADGE),
	}


## Params of the item worn in [param category], or {} while the default item
## is worn (the art direction's own palette applies, no override).
static func worn(s: AppServices, category: String) -> Dictionary:
	var c: CosmeticService = s.cosmetics
	var id: String = c.equipped(category)
	if id == c.catalog.default_for(category):
		return {}
	return c.catalog.typed_params(id)


## Reveal extras for the skins and trails a granted [param bundle] contains:
## {"item_names": {item id: localised name}, "cosmetic": {"category",
## "params"} (preview of the first one)}; {} when it holds none.
static func reward_items(s: AppServices, bundle: RewardBundle) -> Dictionary:
	if bundle == null:
		return {}
	var names: Dictionary[String, String] = {}
	var preview: Dictionary = {}
	for item: Dictionary in bundle.items:
		var type: StringName = StringName(str(item.get("type", "")))
		if type != RewardBundle.TYPE_SKIN and type != RewardBundle.TYPE_TRAIL:
			continue
		var id: String = str(item.get("id", ""))
		var def: Dictionary = s.cosmetics_catalog.item(id)
		names[id] = t(str(def.get("name_key", id)))
		if preview.is_empty() and not def.is_empty():
			preview = {"category": str(def.get("category", "")), "params": def.get("params", {})}
	if names.is_empty():
		return {}
	return {"item_names": names, "cosmetic": preview}


static func _hint_title(s: AppServices, hint: Dictionary) -> String:
	match str(hint.get("type", "")):
		"world":
			var w: Dictionary = s.catalog.world(str(hint.get("id", "")))
			return t("menu.hint.world").format({"name": world_name(w)})
		"level":
			return t("menu.hint.level")
		"player_level":
			return t("menu.hint.player_level").format({"n": int(hint.get("target", 0))})
	return ""


## The run HUD: a tutorial level also gets its stored solution (tap hints).
static func hud(level: Dictionary) -> Dictionary:
	return {
		"tutorial": bool(level.get("tutorial", false)),
		"solution_taps": (level.get("solution", {}) as Dictionary).get("taps", [])
	}


static func worlds(s: AppServices) -> Dictionary:
	var rows: Array = []
	for w: Variant in s.progression.progress_summary().get("worlds", []) as Array:
		var row: Dictionary = (w as Dictionary).duplicate()
		var world: Dictionary = s.catalog.world(str(row.get("id", "")))
		var art: Dictionary = world.get("art", {}) as Dictionary
		row["name"] = world_name(world)
		row["story"] = str(art.get("story", ""))
		row["sink"] = Color(str(art.get("sink", "#46e6f0")))
		if not bool(row.get("unlocked", false)):
			row["requirement"] = t("worlds.requirement").format(
				{
					"stars": s.progression.stars_needed_for(str(row.get("id", ""))),
					"prev": world_name(s.catalog.world_at(maxi(1, int(row.get("index", 1)) - 1)))
				}
			)
		rows.append(row)
	return {"worlds": rows}


static func level_grid(s: AppServices, world_id: String) -> Dictionary:
	var world: Dictionary = s.catalog.world(world_id)
	var index: int = int(world.get("index", 1))
	var count: int = s.catalog.levels_in(index)
	var levels: Array = []
	var stars: int = 0
	for local: int in range(1, count + 1):
		var id: String = WorldCatalog.level_id(index, local)
		var r: Dictionary = s.profile.level_result(id)
		stars += int(r.get("stars", 0))
		var kind: String = "boss" if local == count else ("challenge" if local == count / 2 else "normal")
		levels.append(
			{
				"id": id,
				"local": local,
				"stars": int(r.get("stars", 0)),
				"unlocked": s.progression.is_level_unlocked(id),
				"cleared": s.profile.is_cleared(id),
				"kind": kind,
				"perfect": bool(r.get("perfect", false))
			}
		)
	return {
		"world_name": world_name(world),
		"summary": t("levels.summary").format({"stars": stars, "max": count * 3}),
		"levels": levels
	}


static func modes(s: AppServices) -> Dictionary:
	var progress: Dictionary = s.mode_progress()
	var raw_bests: Variant = s.profile.flags.get(RunController.MODE_BEST_FLAG, {})
	var bests: Dictionary = raw_bests as Dictionary if typeof(raw_bests) == TYPE_DICTIONARY else {}
	var rows: Array = []
	for id: StringName in MODE_ORDER:
		if not s.modes.has(id):
			continue
		var m: Dictionary = s.modes.mode(id)
		var req: Dictionary = s.modes.requirement(id)
		var best: String = ""
		if bests.has(String(id)):
			var v: int = int(bests[String(id)])
			best = (
				(UiKit.format_int(v) + " m")
				if str(m.get("best_metric", "score")) == "distance"
				else UiKit.format_int(v)
			)
		rows.append(
			{
				"id": String(id),
				"name": t(str(m.get("name_key", ""))),
				"desc": t(str(m.get("desc_key", ""))),
				"best": best,
				"unlocked": s.modes.is_unlocked(id, progress),
				"requirement": t(str(req["key"])).format(req["args"] as Dictionary)
			}
		)
	return {"modes": rows}


static func daily(s: AppServices) -> Dictionary:
	var status: Dictionary = s.daily.status()
	var level: Dictionary = s.daily.today_level()
	var world: Dictionary = s.catalog.world(str(level.get("world", "")))
	var rank: Dictionary = s.daily.rank_text_local(int(status.get("best_score", 0)))
	var missions: Dictionary[String, Array] = {}
	for kind: String in ["daily", "weekly"]:
		var list: Array = []
		for m: Dictionary in s.missions.active(kind):
			list.append(m)
		missions[kind] = list
	var req: Dictionary = s.modes.requirement(&"daily")
	return {
		# Remotely paused (daily.enabled false): missions stay, the challenge waits.
		"unlocked": s.modes.is_unlocked(&"daily", s.mode_progress()) and s.remote_config.get_bool("daily.enabled", true),
		"requirement":
		(
			t(str(req["key"])).format(req["args"] as Dictionary)
			if s.remote_config.get_bool("daily.enabled", true)
			else t("daily.paused")
		),
		"date_label": t("daily.date").format({"date": str(status.get("date_key", ""))}),
		"world_name": world_name(world),
		"status": status,
		"rank": rank,
		"missions": missions,
		"reset": {"daily": s.missions.time_left_seconds("daily"), "weekly": s.missions.time_left_seconds("weekly")},
		"bonus_chest": bonus_chest_offered(s),
	}


## The optional bonus chest: once per UTC day, only while a rewarded ad can
## really play (never an empty or broken offer).
static func bonus_chest_offered(s: AppServices) -> bool:
	var opened: Variant = s.profile.flags.get(BONUS_CHEST_FLAG, -1)
	var today: bool = typeof(opened) == TYPE_INT and int(opened) == s.clock.day_number()
	return not today and s.ads.is_rewarded_available(&"bonus_chest")


## The result card for [param result] from its [param outcome]
## ([method RunController.finish], or [method RunController.preview] while a
## revive is on offer): the complete card for a cleared run, else the fail card.
static func result_card(s: AppServices, result: RunResult, outcome: Dictionary, mode_id: StringName) -> Dictionary:
	var card: Dictionary = {"result": result, "best": int(outcome.get("best", 0))}
	if not result.completed:
		card["progress"] = float(outcome.get("progress", 0.0))
		card["can_revive"] = bool(outcome.get("can_revive", false))
		return card
	card["new_best"] = bool(outcome.get("new_best", false))
	card["reward"] = outcome.get("reward")
	card["can_double"] = bool(outcome.get("can_double", false))
	card["has_next"] = bool(outcome.get("has_next", false))
	# A daily run names its rank among the player's own daily scores (local:
	# no global board without a backend).
	card["rank_text"] = ""
	if mode_id == &"daily":
		var rank: Dictionary = s.daily.rank_text_local(result.score)
		card["rank_text"] = t(str(rank.get("key", ""))).format(rank.get("params", {}) as Dictionary)
	return card


static func progress(s: AppServices, tab: String, board: Dictionary) -> Dictionary:
	var p: PlayerProfile = s.profile
	var summary: Dictionary = s.progression.progress_summary()
	var worlds_rows: Array = []
	var perfect_count: int = 0
	for w: Variant in summary.get("worlds", []) as Array:
		var row: Dictionary = (w as Dictionary).duplicate()
		row["name"] = world_name(s.catalog.world(str(row.get("id", ""))))
		worlds_rows.append(row)
	var achievements: Array = []
	for a: Dictionary in s.achievements.list(false):
		var id: String = str(a.get("id", ""))
		var prog: Dictionary = s.achievements.progress(id)
		achievements.append(
			{
				"name": t(str(a.get("name_key", id))),
				"desc":
				t(str(a.get("desc_key", ""))).format(
					{"target": int(prog.get("target", 0)), "n": int(prog.get("target", 0))}
				),
				"value": int(prog.get("value", 0)),
				"target": int(prog.get("target", 1)),
				"unlocked": bool(prog.get("unlocked", false)),
				"reward": a.get("reward", {})
			}
		)
	# In-progress goals first, earned ones after (stable within each group).
	var open: Array = achievements.filter(func(a: Dictionary) -> bool: return not bool(a["unlocked"]))
	var earned: Array = achievements.filter(func(a: Dictionary) -> bool: return bool(a["unlocked"]))
	achievements = open + earned
	for id2: Variant in p.levels.keys():
		if bool((p.levels[id2] as Dictionary).get("perfect", false)):
			perfect_count += 1
	return {
		"emblem": emblem(s),
		"player_level": p.player_level,
		"xp": int(s.progression.xp_progress().get("into_level", 0)),
		"xp_next": maxi(1, int(s.progression.xp_progress().get("needed", 1))),
		"stars": s.progression.campaign_stars(),
		"max_stars": s.progression.max_stars(),
		"bonus_stars": s.progression.bonus_stars(),
		"perfects": perfect_count,
		"cleared": p.stat("unique_levels_cleared"),
		"worlds": worlds_rows,
		"stats": p.stats,
		"achievements": achievements,
		"achievements_unlocked": s.achievements.unlocked_count(),
		"achievements_total": s.achievements.total_count(),
		"board_ids": board_ids(s),
		"board": board,
		"tab": tab,
	}


## Daily / classic all-time / endless weekly boards shown on the Progress screen.
static func board_ids(s: AppServices) -> PackedStringArray:
	return PackedStringArray(
		[
			LeaderboardService.daily_board(s.clock.date_key()),
			LeaderboardService.alltime_board("classic"),
			LeaderboardService.weekly_board(s.clock.week_key(), "endless"),
		]
	)


## Normalises a backend fetch into the screen's board shape (own entry flagged).
static func board_view(s: AppServices, fetched: Dictionary) -> Dictionary:
	var entries: Array = []
	var player: Dictionary = fetched.get("player", {}) as Dictionary
	for e: Variant in fetched.get("entries", []) as Array:
		var row: Dictionary = (e as Dictionary).duplicate()
		row["is_player"] = (
			bool(row.get("is_player", false))
			or (not player.is_empty() and int(row.get("rank", -1)) == int(player.get("rank", -2)))
		)
		entries.append(row)
	return {"entries": entries, "remote": bool(fetched.get("remote", false)), "online": s.network.online}


static func cosmetics(s: AppServices, mode: StringName) -> Dictionary:
	var categories: Array = []
	for c: String in CATEGORY_ORDER:
		if s.cosmetics_catalog.categories().has(c) and not (mode == &"shop" and c == "badge"):
			categories.append({"id": c, "label": t("cos.category." + c)})
	var items: Array = []
	for c2: Dictionary in categories:
		for item: Dictionary in s.cosmetics_catalog.in_category(str(c2["id"])):
			var id: String = str(item.get("id", ""))
			var status: Dictionary = s.cosmetics.unlock_status(id)
			# The service reports {"currency", "amount"}; the screen shows {"coins": n} / {"gems": n}.
			var raw_price: Dictionary = status.get("price", {}) as Dictionary
			var price: Dictionary[String, int] = {}
			var affordable: bool = true
			if raw_price.has("currency") and int(raw_price.get("amount", 0)) > 0:
				var cur: String = str(raw_price["currency"])
				price[cur] = int(raw_price["amount"])
				affordable = s.economy.can_afford(StringName(cur), int(raw_price["amount"]))
			(
				items
				. append(
					{
						"id": id,
						"category": str(item.get("category", "")),
						"name": t(str(item.get("name_key", id))),
						"rarity": str(item.get("rarity", "common")),
						"owned": bool(status.get("owned", false)),
						"equipped": s.cosmetics.equipped(str(item.get("category", ""))) == id,
						"price": price,
						"affordable": affordable,
						"requirement": _requirement(status),
						"params": s.cosmetics_catalog.typed_params(id),
					}
				)
			)
	var packs: Array = []
	for listing: Dictionary in s.store.listings():
		var ids: Array = listing.get("items", []) as Array
		packs.append(
			{
				"id": str(listing.get("id", "")),
				"name": t(str(listing.get("name_key", ""))),
				"items_label": t("shop.pack_items").format({"n": ids.size()}),
				"owned": bool(listing.get("owned", false)),
				"price": str(listing.get("price", "")),
				"available": bool(listing.get("purchasable", false))
			}
		)
	return {
		"mode": String(mode),
		"coins": s.economy.balance(EconomyService.COINS),
		"gems": s.economy.balance(EconomyService.GEMS),
		"categories": categories,
		"items": items,
		"packs": packs,
		"store_available": s.store.is_available()
	}


static func _requirement(status: Dictionary) -> String:
	if bool(status.get("owned", false)):
		return ""
	var type: String = str(status.get("type", ""))
	match type:
		"coins", "gems", "default":
			return ""
		"premium":
			return t("shop.req.premium")
	return t("shop.req." + type).format({"n": int(status.get("target", 0)), "progress": int(status.get("progress", 0))})


static func settings(s: AppServices, restore_status: String) -> Dictionary:
	return {
		"settings": s.settings.snapshot(),
		"version": AppInfo.version(),
		"licenses": licenses_text(),
		"restore_status": restore_status,
		"cloud": cloud_status(s),
	}


## Cloud save row of Settings: {"enabled", "syncing", "text"}. Without a
## configured server the text says the feature is not available in this build.
static func cloud_status(s: AppServices) -> Dictionary:
	return {
		"enabled": s.cloud.is_enabled(),
		"syncing": s.cloud.is_syncing(),
		"text": t(CloudSaveService.status_text_key(s.cloud.status)),
	}


## Human-readable licence notices: the game's own assets (assets/LICENSES.json),
## then the Godot Engine MIT licence text and its third-party components, as
## the engine's licence requires them to ship with the game.
static func licenses_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for e: Variant in JsonIO.read_dict("res://assets/LICENSES.json").get("entries", []) as Array:
		var entry: Dictionary = e as Dictionary
		lines.append("%s — %s" % [str(entry.get("name", entry.get("path", ""))), str(entry.get("license", ""))])
	lines.append("")
	lines.append("Godot Engine — MIT License")
	lines.append(Engine.get_license_text())
	lines.append("Third-party components in Godot Engine:")
	for info: Dictionary in Engine.get_copyright_info():
		var licenses: PackedStringArray = PackedStringArray()
		for part: Variant in info.get("parts", []) as Array:
			var lic: String = str((part as Dictionary).get("license", ""))
			if not lic.is_empty() and not licenses.has(lic):
				licenses.append(lic)
		lines.append("%s — %s" % [str(info.get("name", "")), ", ".join(licenses)])
	return "\n".join(lines)
