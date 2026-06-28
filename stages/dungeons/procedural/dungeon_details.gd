# dungeon_details.gd
# COSMETIC, COLLISION-FREE detail scatter for the procedural dungeon. This is deliberately a tiny,
# stateless HELPER with a single static entry point (scatter), loaded BY PATH from
# dungeon_generator.gd (never given a class_name, never instanced in the hot path) so the generator
# carries no hard type dependency on it and a missing/renamed file degrades to a clean no-op.
#
# WHY a SEPARATE pass from _scatter_clutter?
# _scatter_clutter places the chunky, eye-level props (barrels, logs, big rocks) off the MAIN
# generation rng's sibling seed. This pass instead lays a FINE carpet of ground detail — rubble,
# ore veins, pebbles, fungus — to make floors read as lived-in decay. Keeping it separate means the
# user can tune/disable each independently, and (critically) we run off our OWN seed offset
# (seed * 71 + 13) so toggling details NEVER shifts any other random draw: geometry, loot and the
# enemy army stay byte-identical for a given seed.
#
# COLLISION SAFETY: we add the imported glTF scenes as plain visual meshes (no StaticBody/colliders
# of our own). The dungeon navmesh is baked from the box COLLIDERS only, so these meshes can never
# block pathing — they are purely decorative and safe to scatter densely.

extends RefCounted

# Asset roots (same kits the clutter pass draws from, so no new art dependency is introduced).
const _NAT: String = "res://assets/models/nature/stylized-megakit/"
const _RES: String = "res://assets/models/props/kaykit_resources/"


# Scatter cosmetic ground detail across every room. Pure/static: all state arrives as arguments.
#   parent      - the DungeonGenerator (Node3D) to parent a "Details" holder under
#   rooms        - Array of Rect2i room rectangles in TILE coordinates
#   level_seed   - this floor's seed; we derive our own offset so we never perturb the main rng
#   density      - rough detail count per room tile (clamped per-room below)
#   theme_name   - the floor theme name, used to flavour the detail pool
#   tile_size    - metres per tile (DungeonGenerator.TILE_SIZE) for tile->world conversion
static func scatter(parent: Node3D, rooms: Array, level_seed: int, density: float, theme_name: String, tile_size: float) -> void:
	if parent == null or rooms.is_empty() or density <= 0.0:
		return
	var pool: Array = _detail_pool(theme_name)
	if pool.is_empty():
		return

	# Dedicated rng with an offset distinct from clutter's (seed*31+17) and rare nodes' (seed*53+91),
	# so none of the cosmetic passes share a stream or disturb the main generation rng.
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed * 71 + 13

	var holder := Node3D.new()
	holder.name = "Details"
	parent.add_child(holder)

	for room in rooms:
		var rect: Rect2i = room
		var tiles: int = rect.size.x * rect.size.y
		# Per-room budget from density, clamped so a huge room can't drown the scene in detail.
		var n: int = clampi(int(round(float(tiles) * density)), 0, 40)
		for k in range(n):
			var tx: int = rect.position.x + rng.randi_range(0, rect.size.x - 1)
			var tz: int = rect.position.y + rng.randi_range(0, rect.size.y - 1)
			var ps: PackedScene = pool[rng.randi() % pool.size()]
			if ps == null:
				continue
			var inst: Node3D = ps.instantiate() as Node3D
			if inst == null:
				continue
			holder.add_child(inst)
			# Random offset within the tile, flat on the floor plane, small + randomly rotated so
			# the carpet of detail never looks gridded.
			var cx: float = float(tx) * tile_size + rng.randf_range(-1.6, 1.6)
			var cz: float = float(tz) * tile_size + rng.randf_range(-1.6, 1.6)
			inst.position = Vector3(cx, 0.0, cz)
			inst.rotation.y = rng.randf() * TAU
			inst.scale = Vector3.ONE * rng.randf_range(0.35, 0.85)


# The detail model set for a theme: a shared rubble/pebble base plus theme-specific flavour. We
# reuse existing kit pieces (no stalactite/bone art ships with the project), reading nuggets as
# "ore veins" and stone chunks as "rubble piles" to evoke the requested decay without new assets.
static func _detail_pool(theme_name: String) -> Array:
	var pool: Array = []
	# Shared fine ground detail everywhere: pebbles + small rubble.
	pool += _load(_NAT, ["Pebble_Round_1.gltf", "Pebble_Round_2.gltf", "Pebble_Round_3.gltf",
		"Pebble_Square_1.gltf", "Pebble_Square_2.gltf",
		"RockPath_Round_Small_1.gltf", "RockPath_Square_Small_1.gltf"])
	pool += _load(_RES, ["Stone_Chunks_Small.gltf"])
	match theme_name:
		"Bog", "Sewer":
			# Damp decay: fungus + scattered small rock.
			pool += _load(_NAT, ["Mushroom_Common.gltf", "Mushroom_Laetiporus.gltf", "Rock_Medium_1.gltf"])
		"Frost", "Cave":
			# "Crystal veins" stand in as ore nuggets glinting in the rock.
			pool += _load(_RES, ["Iron_Nugget_Medium.gltf", "Copper_Nugget_Large.gltf"])
			pool += _load(_NAT, ["Rock_Medium_2.gltf"])
		"Mine", "PowerPlant":
			# Mined-out rubble + ore.
			pool += _load(_RES, ["Iron_Nugget_Medium.gltf", "Iron_Nugget_Large.gltf", "Stone_Chunks_Large.gltf"])
		_:
			# Stone / Ember and any future themes: extra rubble.
			pool += _load(_NAT, ["Rock_Medium_1.gltf", "Rock_Medium_3.gltf"])
			pool += _load(_RES, ["Stone_Chunks_Large.gltf"])
	return pool


# Load a set of glTF scenes from a directory, skipping anything that fails to resolve to a
# PackedScene (cold-cache safe). Returns only the scenes that actually loaded.
static func _load(dir: String, names: Array) -> Array:
	var out: Array = []
	for n in names:
		var r: Resource = load(dir + String(n))
		if r is PackedScene:
			out.append(r)
	return out
