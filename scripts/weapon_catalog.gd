class_name WeaponCatalog
extends RefCounted
## CS2 prices/capacities/base damage from Valve game-data snapshot 2026-09-13.
## Spread, bloom, reload duration and weight are authored for this overhead game.

const ALIASES: Dictionary = {
	"m4a4": "m4a1", "m4a1s": "m4a1_silencer", "usp": "usp_silencer",
	"usps": "usp_silencer", "scout": "ssg08", "galil": "galilar",
	"sg553": "sg556", "p2000": "hkp2000", "dualberettas": "elite",
	"five_seven": "fiveseven", "mp5": "mp5sd", "he": "hegrenade",
	"smoke": "smokegrenade", "flash": "flashbang", "incendiary": "incgrenade",
	"defuse": "kit", "defuser": "kit", "kevlar": "armor", "assaultsuit": "helmet",
	"ak": "ak47"
}
static var _catalog: Dictionary = {}

static func canonical(id: String) -> String:
	var key: String = id.to_lower().replace("weapon_", "")
	return str(ALIASES.get(key, key))

static func _ensure_loaded() -> void:
	if not _catalog.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/catalog.json"))
	if parsed is Array:
		for row: Dictionary in parsed:
			_catalog[str(row.id)] = row

static func data(id: String) -> Dictionary:
	_ensure_loaded()
	var key: String = canonical(id)
	if not _catalog.has(key):
		push_warning("Unknown weapon ID: " + id)
		key = "ak47"
	return (_catalog[key] as Dictionary).duplicate(true)

static func all() -> Array:
	_ensure_loaded()
	var result: Array = []
	for row: Dictionary in _catalog.values():
		result.append(row.duplicate(true))
	return result

static func for_team(team: String, category: String = "") -> Array:
	var result: Array = []
	for row: Dictionary in all():
		if row.team in [team.to_upper(), "ANY"] and (category.is_empty() or row.category == category):
			result.append(row)
	return result

static func model_path(id: String) -> String:
	return "res://assets/weapons/%s.tscn" % canonical(id)
