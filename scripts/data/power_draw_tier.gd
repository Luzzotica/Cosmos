class_name PowerDrawTier
extends RefCounted
## Integer sort keys for grid power allocation: lower = served first.
## Gaps between values leave room for future per-player reorder offsets.

enum Id {
	WEAPONS = 0,
	MINING = 20,
	REPAIR = 40,
	UPGRADES = 60,
	MONOLITH = 80,
	CONSTRUCTION = 100,
}


static func effective_sort_key(id: Id, user_offset: int = 0) -> int:
	return int(id) + user_offset
