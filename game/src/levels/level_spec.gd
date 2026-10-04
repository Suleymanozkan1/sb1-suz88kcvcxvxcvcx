class_name LevelSpec
extends RefCounted
## Generator input: every tunable that shapes one level. Produced by
## [DifficultyModel] (campaign), the daily challenge and endless modes.

var id: String = ""
var number: int = 0
var world_id: String = ""
var world_index: int = 1
var local_index: int = 1
var kind: String = "normal"
var tier: String = "early"
var chapter: String = "A"
var chapter_phase: String = "mastery"
var intensity: float = 0.0
var seed: int = 1

var lanes: int = 2
var speed: float = 8.0
var spacing: float = 6.0
var spacing_jitter: float = 0.12
var slot_count: int = 10
var target_duration: float = 12.0
var duration_bounds: Vector2 = Vector2(5.0, 15.0)

## Weights by form name ("hop", "phase", "dash", "surge").
var forms: Dictionary = {"hop": 1.0}
var start_form: String = "hop"
var form_segment: int = 6
## Weights by hazard entity name.
var hazards: Dictionary = {"barrier": 1.0}

var change_prob: float = 0.4
var density: float = 0.8
var spark_density: float = 0.8
var prism_chance: float = 0.0
var shield_chance: float = 0.0
var magnet_chance: float = 0.0
var current_chance: float = 0.0
var portal_chance: float = 0.0
var cluster_chance: float = 0.0
## Mass & gravity family (0 = off; specials never inherit them from a chapter).
var gravity_chance: float = 0.0
## Gravity factors a well can take (low-g and high-g).
var gravity_values: Array[float] = [0.7, 1.4]
## A well spans this many slots (inclusive range).
var gravity_slots: Vector2i = Vector2i(3, 5)
var launch_chance: float = 0.0
var plate_chance: float = 0.0

var hop_time: float = SimConst.HOP_TIME
var speed_ramp: float = 0.0
## Distance over which speed_ramp is applied; 0 = derived from the slot plan.
var ramp_distance: float = 0.0
var forgiving: bool = false
var tutorial: bool = false
var min_window: float = 0.3
var beat_seconds: float = 0.5

var objective_type: String = "reach_end"
var objective_fraction: float = 0.0
var score_ratio: float = 0.6
var combo_ratio: float = 0.6

var intro_mechanic: String = ""
var environment: String = ""
var music: String = ""
var boss_name: String = ""
var pattern: String = ""
var unlock_requires: String = ""
var unlock_stars: int = 0
var endless: bool = false


func is_special() -> bool:
	return kind != "normal"
