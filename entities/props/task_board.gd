# task_board.gd
# A town NOTICE BOARD: the impersonal counterpart to NPC task-givers. Walk up,
# press E, and it hands you the first available TASK-tier quest from the town's
# pool (odd jobs anyone can pick up — gather, deliver, clear). NPCs offer tasks
# through their dialogue; this board offers them with no conversation.
#
# Duck-typed interaction (no special-casing in player.gd): the player's interaction
# RayCast3D hits this StaticBody3D, calls get_interaction_prompt() to show
# "Read the Notice Board", and interact(player) on press, which gives a town task.
#
# Code-built (mirrors upgrade_station.gd) so the .tscn stays a thin script holder:
# _ready builds a wooden board + posts from BoxMesh and a box collider on physics
# layer 1 (so the player's interaction ray can hit it) and joins group "interactable".
#
# Autoloads are reached DEFENSIVELY (get_node_or_null) so the board is harmless in a
# scene/test where QuestSystem or NotificationFeed isn't present.

extends StaticBody3D

## TASK-tier quest ids posted on this board, tried in order. The content agent fills
## this in (the first one that is available — not active, not completed, off cooldown —
## is the one handed out). Leave empty and the board simply reports "no work".
@export var town_task_pool: Array[StringName] = []

## Friendly name shown in the interaction prompt.
@export var display_name: String = "Read the Notice Board"

func _ready() -> void:
	# Sit on the default physics layer 1 so the player's layer-1 interaction ray can
	# detect us (mirrors how every other interactable is reachable).
	collision_layer = 1
	collision_mask = 1
	add_to_group("interactable")
	_build_visual()

# --- Interaction (duck-typed by the player's RayCast3D) ---------------------

func get_interaction_prompt() -> String:
	return display_name

func interact(_player: Node) -> void:
	var quests := get_node_or_null("/root/QuestSystem")
	if quests == null:
		_feedback("No work available right now.")
		return

	# Find the first task in the pool that can be offered right now and give it.
	for task_id in town_task_pool:
		var available := true
		# A board posts specific TASK ids, so ask the per-task check
		# (is_task_available), NOT has_task_available — that one is keyed by NPC
		# giver id and would always return false for a bare task id.
		if quests.has_method("is_task_available"):
			available = quests.is_task_available(task_id)
		if not available:
			continue
		var given := true
		if quests.has_method("give_task"):
			# give_task may return whether it actually started the task.
			var result = quests.give_task(task_id)
			if result is bool:
				given = result
		if given:
			_feedback("New task: %s" % _task_title(task_id))
			return

	_feedback("No work available right now.")

# --- Feedback ---------------------------------------------------------------

# Pop a toast if the NotificationFeed autoload is present; otherwise stay silent.
func _feedback(text: String) -> void:
	var feed := get_node_or_null("/root/NotificationFeed")
	if feed != null and feed.has_method("notify"):
		feed.notify(text)

# Resolve a task id to its quest title for the toast, falling back to the id.
func _task_title(task_id: StringName) -> String:
	var quests := get_node_or_null("/root/QuestSystem")
	if quests != null and quests.has_method("get_quest"):
		var quest = quests.get_quest(task_id)
		if quest != null and quest.title != "":
			return quest.title
	return String(task_id)

# --- Visual / collider ------------------------------------------------------

# Builds a simple notice-board look — two posts and a planked board with a header —
# out of boxes plus a matching box collider. Kept in code so the scene file is a
# thin script holder (see the file header).
func _build_visual() -> void:
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.42, 0.30, 0.20)  # warm post wood
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.55, 0.40, 0.26)  # lighter plank face
	var paper_mat := StandardMaterial3D.new()
	paper_mat.albedo_color = Color(0.88, 0.85, 0.74)  # pinned cream notices

	# Two upright support posts.
	for x: float in [-0.55, 0.55]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.12, 1.8, 0.12)
		post.mesh = post_mesh
		post.position = Vector3(x, 0.9, 0.0)
		post.material_override = wood_mat
		add_child(post)

	# The planked board face the notices are pinned to.
	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(1.3, 0.85, 0.08)
	board.mesh = board_mesh
	board.position = Vector3(0.0, 1.35, 0.0)
	board.material_override = board_mat
	add_child(board)

	# A little pitched header plank across the top so it reads as a notice board.
	var header := MeshInstance3D.new()
	var header_mesh := BoxMesh.new()
	header_mesh.size = Vector3(1.45, 0.18, 0.12)
	header.mesh = header_mesh
	header.position = Vector3(0.0, 1.85, 0.0)
	header.material_override = wood_mat
	add_child(header)

	# A couple of pinned paper notices to sell the "jobs posted here" idea.
	for offset: Vector3 in [Vector3(-0.3, 1.45, 0.06), Vector3(0.32, 1.25, 0.06)]:
		var note := MeshInstance3D.new()
		var note_mesh := BoxMesh.new()
		note_mesh.size = Vector3(0.32, 0.4, 0.02)
		note.mesh = note_mesh
		note.position = offset
		note.material_override = paper_mat
		add_child(note)

	# Collider roughly enclosing the board so the player bumps into it and the ray hits.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.45, 1.9, 0.3)
	col.shape = shape
	col.position = Vector3(0.0, 0.95, 0.0)
	add_child(col)
