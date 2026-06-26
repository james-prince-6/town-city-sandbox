# npc_playground.gd
# Dev-only driver for the NPC test scene. On load it bakes a navigation mesh from the
# floor's static collider so the wandering NPCs path naturally across the open space.
# If the bake produces nothing (or the navmesh is missing) the NPCs simply fall back
# to npc.gd's straight-line movement, so the scene still works either way. Not used
# outside this test scene.

extends Node3D

@onready var nav_region: NavigationRegion3D = get_node_or_null("NavigationRegion3D")

func _ready() -> void:
	# Wait a frame so the floor and its collider are fully in the tree before baking.
	await get_tree().process_frame
	if nav_region != null and nav_region.navigation_mesh != null:
		# Bake from the static collider geometry parented under the region. The NPCs'
		# NavigationAgent3D nodes pick this up automatically once it lands; until then
		# their straight-line fallback keeps them moving.
		nav_region.bake_navigation_mesh()
