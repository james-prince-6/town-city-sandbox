# bake_navmeshes.gd  — project tool, run via tools/bake_navmeshes.tscn
#
# Re-bakes the navigation meshes for the hand-authored levels and saves each as a
# .res next to its scene. The level scenes reference those .res files from their
# NavigationRegion3D, so after editing a level's geometry, run this tool to refresh
# its navmesh. (We bake offline into a resource rather than relying on the editor's
# in-place bake because the level geometry isn't parented under the NavigationRegion3D
# — this tool parses the whole scene, strips dynamic actors, and bakes.)
#
# Run headless:
#   Godot --headless --path <project> res://tools/bake_navmeshes.tscn --quit-after 600
# then check the report at user://_bake_report.txt. Add a CONFIG entry per level.

extends Node

const CONFIGS := [
	{
		"name": "town_square",
		"scene": "res://stages/overworld/townsquare/town_square.tscn",
		"parse_root": ".",
		"aabb_pos": Vector3(-24, -2, -14),
		"aabb_size": Vector3(52, 12, 40),
		"out": "res://stages/overworld/townsquare/town_square_nav.res",
	},
	{
		"name": "shop_interior",
		"scene": "res://stages/overworld/shop-interior/shop-interior.tscn",
		"parse_root": ".",
		"aabb_pos": Vector3(-8, -3, -13),
		"aabb_size": Vector3(16, 8, 20),
		"out": "res://stages/overworld/shop-interior/shop_interior_nav.res",
	},
	{
		"name": "bar_inside",
		# The bar is now a flat BarInside root (it used to render in its own SubViewport); parse
		# the whole scene so the bake carves around the furniture (tables/stools) + bar fixtures.
		"scene": "res://stages/overworld/bar-inside/barinside.tscn",
		"parse_root": ".",
		"aabb_pos": Vector3.ZERO,  # auto-computed from geometry below
		"aabb_size": Vector3.ZERO,
		"out": "res://stages/overworld/bar-inside/barinside_nav.res",
	},
]

var _report: Array = []

func _ready() -> void:
	for cfg in CONFIGS:
		await _bake_one(cfg)
	var f := FileAccess.open("user://_bake_report.txt", FileAccess.WRITE)
	f.store_string("\n".join(_report))
	f.close()
	print("\n".join(_report))
	get_tree().quit()

func _bake_one(cfg: Dictionary) -> void:
	_report.append("=== %s ===" % cfg["name"])
	var ps := load(cfg["scene"]) as PackedScene
	if ps == null:
		_report.append("  LOAD FAILED")
		return
	var scene := ps.instantiate()
	add_child(scene)
	await get_tree().physics_frame  # let _ready run so groups populate

	# Strip dynamic actors so the bake only sees static level geometry.
	for grp in ["player", "npc", "world_item", "critter"]:
		for n in get_tree().get_nodes_in_group(grp):
			n.free()

	var parse_root: Node = scene
	if cfg["parse_root"] != ".":
		parse_root = scene.get_node(cfg["parse_root"])
	if parse_root == null:
		_report.append("  parse_root not found: %s" % cfg["parse_root"])
		scene.free()
		return

	var nav := NavigationMesh.new()
	nav.cell_size = 0.2
	nav.cell_height = 0.1
	nav.agent_height = 1.7
	nav.agent_radius = 0.4
	nav.agent_max_climb = 0.4
	nav.agent_max_slope = 45.0
	nav.region_min_size = 4.0  # cull tiny islands (tabletops, etc.)
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_BOTH
	nav.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN

	var aabb_size: Vector3 = cfg["aabb_size"]
	if aabb_size == Vector3.ZERO:
		var auto := _combined_mesh_aabb(parse_root).grow(1.0)
		nav.filter_baking_aabb = auto
		_report.append("  auto aabb pos=%s size=%s" % [str(auto.position), str(auto.size)])
	else:
		nav.filter_baking_aabb = AABB(cfg["aabb_pos"], aabb_size)

	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav, source, parse_root)
	NavigationServer3D.bake_from_source_geometry_data(nav, source)

	var polys: int = nav.get_polygon_count()
	_report.append("  vertices=%d polygons=%d" % [nav.vertices.size(), polys])
	if polys > 0:
		var err := ResourceSaver.save(nav, cfg["out"])
		_report.append("  saved=%s err=%d" % [cfg["out"], err])
	else:
		_report.append("  NOT SAVED (no polygons baked)")

	scene.free()

func _combined_mesh_aabb(root: Node) -> AABB:
	var result := AABB()
	var found := false
	for vi in _find_meshes(root):
		var box: AABB = vi.global_transform * vi.get_aabb()
		if not found:
			result = box
			found = true
		else:
			result = result.merge(box)
	return result

func _find_meshes(node: Node) -> Array:
	var out: Array = []
	if node is VisualInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_meshes(c))
	return out
