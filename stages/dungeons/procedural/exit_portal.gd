# exit_portal.gd
# A big, OBVIOUS way out of a procedural dungeon, back to the overworld. DungeonGenerator
# places one in a corner of the START room. Where the old raycast teleporter was a subtle,
# unmarked volume you had to aim at, this reads as an exit from across the room: a glowing
# emissive slab, a coloured light washing the floor, and a floating "Leave Dungeon" sign.
#
# The player can leave TWO ways, so it's hard to miss:
#   1. WALK INTO IT — an Area3D child fires body_entered for the "player" group.
#   2. LOOK AT IT + press "interact" — the duck-typed get_interaction_prompt()/interact(player)
#      pattern (same as chests / the descend portal). The player's interaction RayCast3D only
#      collides with physics BODIES, which is why the root is a StaticBody3D (not a bare Area3D).
#
# Both routes funnel through _leave(), which performs the exact same SceneManager.change_scene()
# the teleport_raycast used, so persistent state survives and the player lands on the right
# spawn marker in the overworld.

class_name ExitPortal
extends StaticBody3D

## Destination scene (the overworld hub). Set by DungeonGenerator from its exit_scene_path.
var target_scene_path: String = "res://stages/overworld/town_template.tscn"
## Marker3D name to spawn at in the destination. Set from DungeonGenerator.exit_spawn_point.
var target_spawn_point: StringName = &"from_dungeon"
## Prompt shown when the player looks at the portal.
var prompt_text: String = "Leave Dungeon"

# The portal's signature glow colour (a welcoming green that reads as "exit / go", distinct
# from the descend portal's blue "deeper" glow).
const GLOW: Color = Color(0.3, 1.0, 0.45)

# Guard so a walk-in and an already-queued interact can't both fire the transition.
var _leaving: bool = false

func _ready() -> void:
	_build_visuals()
	_build_colliders()

# --- Interaction (duck-typed by the player's RayCast3D) --------------------

func get_interaction_prompt() -> String:
	return prompt_text

func interact(_player: Node) -> void:
	_leave()

# --- Walk-in trigger -------------------------------------------------------

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_leave()

# --- Transition ------------------------------------------------------------

# The single way out, shared by the walk-in trigger and the look+interact path. Mirrors how
# teleport_raycast.gd performs the transition so persistent state survives and the player is
# placed on the destination's spawn marker.
func _leave() -> void:
	if _leaving:
		return
	if target_scene_path == "":
		push_error("ExitPortal: target_scene_path is not set on %s" % name)
		return
	_leaving = true
	SceneManager.change_scene(target_scene_path, target_spawn_point)

# --- Construction ----------------------------------------------------------

# A glowing slab "doorway", a wash light, and a floating sign — all built so the exit is
# visible from across the room. Origin sits on the floor (y = 0); everything is stacked up.
func _build_visuals() -> void:
	# The portal slab: a tall, thin emissive panel that glows in the dark dungeon.
	var slab := MeshInstance3D.new()
	slab.name = "Glow"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 2.6, 0.35)
	slab.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GLOW
	mat.emission_enabled = true
	mat.emission = GLOW
	mat.emission_energy_multiplier = 3.0
	slab.material_override = mat
	slab.position = Vector3(0.0, 1.3, 0.0)
	add_child(slab)

	# A coloured light so the exit also lights up the floor and walls around it.
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = GLOW
	light.light_energy = 3.0
	light.omni_range = 9.0
	light.position = Vector3(0.0, 2.0, 0.0)
	add_child(light)

	# A floating, billboarded "Leave Dungeon" sign hovering above the slab.
	var label := Label3D.new()
	label.name = "Sign"
	label.text = "Leave Dungeon"
	label.font_size = 64
	label.modulate = GLOW
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 3.1, 0.0)
	add_child(label)

# The root StaticBody3D collider (so the interaction raycast can hit it for look+interact),
# plus an Area3D with a slightly larger volume so simply walking up to the portal triggers it.
func _build_colliders() -> void:
	# Body collider matching the slab — what the player's interaction raycast looks at.
	var body_col := CollisionShape3D.new()
	var body_box := BoxShape3D.new()
	body_box.size = Vector3(2.0, 2.6, 0.35)
	body_col.shape = body_box
	body_col.position = Vector3(0.0, 1.3, 0.0)
	add_child(body_col)

	# Walk-in trigger: a roomier box so body_entered fires as the player steps onto/into it.
	var area := Area3D.new()
	area.name = "WalkInTrigger"
	var area_col := CollisionShape3D.new()
	var area_box := BoxShape3D.new()
	area_box.size = Vector3(2.6, 2.8, 1.6)
	area_col.shape = area_box
	area_col.position = Vector3(0.0, 1.3, 0.0)
	area.add_child(area_col)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
