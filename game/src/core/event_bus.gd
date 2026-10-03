class_name EventBus
extends RefCounted
## Typed application-wide signals. Systems publish facts here instead of
## referencing each other, which keeps the dependency graph acyclic.

# Run lifecycle
signal run_started(level_id: String, mode: StringName)
signal run_failed(result: RunResult)
signal run_completed(result: RunResult)
signal run_restarted(level_id: String)
signal run_paused(paused: bool)
signal combo_reached(combo: int)

# Progression / economy
signal currency_changed(currency: StringName, balance: int, delta: int)
signal xp_gained(amount: int, total: int)
signal player_level_up(new_level: int)
signal stars_changed(total: int)
signal level_unlocked(level_id: String)
signal world_unlocked(world_id: String)
signal reward_granted(bundle: RewardBundle)
signal cosmetic_unlocked(item_id: String)
signal cosmetic_equipped(category: StringName, item_id: String)
signal achievement_unlocked(achievement_id: String)
signal mission_completed(mission_id: String)
signal stat_changed(stat: StringName, value: int)

# Daily / online / monetisation (never gameplay-affecting)
signal daily_completed(date_key: String, score: int)
signal mission_progressed(mission_id: String, progress: int, target: int)
signal leaderboard_submitted(board: String, accepted: bool)
signal purchase_completed(product_id: String)
signal ad_finished(placement: StringName, rewarded: bool)

# Meta / platform
signal settings_changed(key: StringName, value: Variant)
signal quality_changed(preset: StringName, automatic: bool)
signal locale_changed(locale: String)
signal save_recovered(source: String)
signal toast_requested(text: String, icon: StringName)
signal network_state_changed(online: bool)
