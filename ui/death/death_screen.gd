# death_screen.gd
# Autoload singleton (registered as "DeathScreen"). The "You Died" overlay that
# owns the whole death/respawn flow.
#
# Built entirely in code (no .tscn), mirroring pause_menu.gd. When PlayerStats
# reports the player's health hit zero it FULLY pauses the game (get_tree().paused
# = true freezes pausable nodes, plus Clock.pause() since the Clock runs with
# PROCESS_MODE_ALWAYS and wouldn't stop on its own), frees the mouse, and shows a
# centred overlay with Respawn / Quit to Desktop.
#
# It sits on CanvasLayer layer 21 — ABOVE the pause menu (20) and dialogue (11) —
# with process_mode = ALWAYS so its buttons still respond while the tree is paused.
#
# Respawn picks its destination in this order:
#   1. The nearest node in group "respawn_point" in the current scene (dungeons
#      drop Marker3D nodes into that group), measured from the player's position.
#   2. Otherwise the player's recorded START transform (player.gd records its
#      global_transform in _ready and exposes get_spawn_transform()).

extends CanvasLayer

# Dying inside a procedural dungeon kicks the player back to the OVERWORLD instead of
# respawning them among the monsters (dungeons drop local respawn_point markers, which would
# otherwise drop them right back in). Overworld deaths still respawn locally as before.
const DUNGEON_DEATH_SCENE: String = "res://stages/overworld/town_template.tscn"
const DUNGEON_DEATH_SPAWN: StringName = &"from_dungeon"

var is_open: bool = false

var _root: Control
var _respawn_btn: Button

func _ready() -> void:
	# Above the pause menu (20) so a death that lands while paused still wins, and
	# always processing so its buttons work while the tree is paused.
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide()
	# Death handling now lives here, not in player.gd. This fires exactly once per
	# death (PlayerStats guards the signal), so we don't need our own guard.
	PlayerStats.died.connect(_on_player_died)

# --- Death / respawn flow --------------------------------------------------

func _on_player_died() -> void:
	if is_open:
		return
	is_open = true
	show()
	get_tree().paused = true
	# Clock runs with PROCESS_MODE_ALWAYS, so the tree pause won't stop it — do it explicitly.
	if Clock:
		Clock.pause()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Put controller focus on Respawn so A works without a mouse.
	if _respawn_btn != null:
		_respawn_btn.grab_focus.call_deferred()

func _on_respawn_pressed() -> void:
	if not is_open:
		return
	# Bring the player back to full health/stamina and clear the death guard.
	PlayerStats.reset()
	# Dying in a dungeon sends you back to the overworld; otherwise respawn locally. The scene
	# change is deferred inside SceneManager, so we still run the teardown below this frame and
	# SceneManager places the player on the town's "from_dungeon" marker once it loads.
	if _current_scene_is_dungeon():
		SceneManager.change_scene(DUNGEON_DEATH_SCENE, DUNGEON_DEATH_SPAWN)
	else:
		# Move the body to wherever it should reappear, then hand control back.
		_move_player_to_spawn()
	is_open = false
	hide()
	get_tree().paused = false
	if Clock:
		Clock.resume()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_quit_pressed() -> void:
	get_tree().quit()

# --- Respawn destination ---------------------------------------------------

# True when the active gameplay scene is a procedural dungeon, so death should boot the player
# back to the overworld rather than to a local respawn_point. Detected robustly: either the
# world node carries the DungeonGenerator script, or its scene path mentions "dungeon".
func _current_scene_is_dungeon() -> bool:
	var world: Node = SceneManager.current_world()
	if world == null:
		return false
	if world is DungeonGenerator:
		return true
	var path: String = world.scene_file_path
	return path.to_lower().contains("dungeon")

# Teleports the player (group "player") to the nearest respawn_point Marker if the
# current scene has any, otherwise back to its recorded start transform. Does
# nothing gracefully if there's no player (e.g. on a menu scene).
func _move_player_to_spawn() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not (player is Node3D):
		return
	var body := player as Node3D

	# Untyped: _nearest_respawn_transform returns Variant (a Transform3D or null).
	var target = _nearest_respawn_transform(body.global_transform.origin)
	if target == null:
		# No respawn points in this scene — fall back to where the player started.
		if body.has_method("get_spawn_transform"):
			target = body.get_spawn_transform()
	if target == null:
		return # Nothing to move to; leave the player where it is.

	var xform: Transform3D = target
	# Zero out any leftover velocity so the body doesn't keep sliding after the move.
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = Vector3.ZERO
	body.global_transform = xform

# Returns the global_transform of the closest node in group "respawn_point" to
# `from`, or null if the scene has none. Variant return so callers can null-check.
func _nearest_respawn_transform(from: Vector3) -> Variant:
	var points := get_tree().get_nodes_in_group(&"respawn_point")
	var best: Node3D = null
	var best_dist: float = INF
	for point in points:
		if not (point is Node3D):
			continue
		var p := point as Node3D
		var d: float = from.distance_squared_to(p.global_transform.origin)
		if d < best_dist:
			best_dist = d
			best = p
	if best == null:
		return null
	return best.global_transform

# --- UI construction (all in code) -----------------------------------------

func _build_ui() -> void:
	# Dark red-tinted backdrop that also eats clicks behind the overlay.
	var dim := ColorRect.new()
	dim.color = Color(0.15, 0.0, 0.0, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_root = dim

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(320, 0)
	vbox.add_theme_constant_override("separation", 18)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "You Died"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.85, 0.1, 0.1))
	vbox.add_child(title)

	var respawn_btn := Button.new()
	respawn_btn.text = "Respawn"
	respawn_btn.custom_minimum_size = Vector2(0, 52)
	respawn_btn.pressed.connect(_on_respawn_pressed)
	vbox.add_child(respawn_btn)
	_respawn_btn = respawn_btn

	var quit_btn := Button.new()
	quit_btn.text = "Quit to Desktop"
	quit_btn.custom_minimum_size = Vector2(0, 52)
	quit_btn.pressed.connect(_on_quit_pressed)
	vbox.add_child(quit_btn)
