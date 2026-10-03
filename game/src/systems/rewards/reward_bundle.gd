class_name RewardBundle
extends RefCounted
## A list of concrete reward items. The UI animates exactly what a bundle
## contains after it has been granted (never invented values).

const TYPE_COINS: StringName = &"coins"
const TYPE_GEMS: StringName = &"gems"
const TYPE_XP: StringName = &"xp"
const TYPE_STARS: StringName = &"stars"
const TYPE_COSMETIC: StringName = &"cosmetic"
const TYPE_BADGE: StringName = &"badge"

const VALID_TYPES: Array[StringName] = [
	TYPE_COINS,
	TYPE_GEMS,
	TYPE_XP,
	TYPE_STARS,
	TYPE_COSMETIC,
	TYPE_BADGE,
]

var source: String = ""
## Each item: {"type": StringName, "amount": int, "id": String}
var items: Array[Dictionary] = []


func _init(source_id: String = "") -> void:
	source = source_id


func add(type: StringName, amount: int, id: String = "") -> RewardBundle:
	if not VALID_TYPES.has(type):
		GameLog.warn("reward", "invalid reward type %s" % type)
		return self
	if amount <= 0 and id.is_empty():
		return self
	# Merge plain currency items for a clean presentation.
	if id.is_empty():
		for item: Dictionary in items:
			if item["type"] == type and str(item["id"]).is_empty():
				item["amount"] = int(item["amount"]) + amount
				return self
	items.append({"type": type, "amount": maxi(amount, 0), "id": id})
	return self


func amount_of(type: StringName) -> int:
	var total: int = 0
	for item: Dictionary in items:
		if item["type"] == type:
			total += int(item["amount"])
	return total


func is_empty() -> bool:
	return items.is_empty()


func scaled(factor: int) -> RewardBundle:
	var copy: RewardBundle = RewardBundle.new(source)
	for item: Dictionary in items:
		var t: StringName = item["type"]
		if t in [TYPE_COINS, TYPE_GEMS, TYPE_XP]:
			copy.add(t, int(item["amount"]) * factor, str(item["id"]))
		else:
			copy.items.append(item.duplicate())
	return copy


func to_dict() -> Dictionary:
	var arr: Array = []
	for item: Dictionary in items:
		arr.append({"type": String(item["type"]), "amount": item["amount"], "id": item["id"]})
	return {"source": source, "items": arr}


static func from_dict(data: Dictionary) -> RewardBundle:
	var b: RewardBundle = RewardBundle.new(str(data.get("source", "")))
	for raw: Variant in data.get("items", []) as Array:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = raw as Dictionary
		b.add(StringName(str(item.get("type", ""))), int(item.get("amount", 0)), str(item.get("id", "")))
	return b
