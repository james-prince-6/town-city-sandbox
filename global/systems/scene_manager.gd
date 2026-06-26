# scene_manager.gd
# Autoload singleton (registered as "SceneManager").
#
# Why this exists:
# Godot's built-in `get_tree().change_scene_to_file()` destroys the ENTIRE old
# scene and builds the new one. For a town-and-buildings RPG that's fine for the
# environment, but two things need care:
#   1. Persistent state (money, inventory, day) must NOT live in scenes — that's
#      what the GameState and Inventory autoloads are for. They already survive.
#   2. When you enter a building, the player should appear at the right doorway,
#      not at the world origin. That's what "spawn points" solve here.
#
# GLOBAL PIXEL-ART VIEWPORT:
# This autoload also owns ONE persistent SubViewport that every gameplay scene is
# rendered into, downscaled then nearest-neighbour-upscaled for a crisp pixel-art
# look — without each scene needing its own SubViewport. The UI autoloads (HUD,
# menus, prompts) live on their own CanvasLayers OUTSIDE this viewport, so they stay
# sharp on top. To make this work, `change_scene` parents new scenes UNDER the world
# SubViewport instead of the tree root; `tree.current_scene` still points at the
# active scene, so all the `get_tree().current_scene` spawn code keeps working and
# spawns into the correct (pixelated) world.
#
# Boot order: the project's main scene is a tiny `boot.tscn` whose only job is to call
# change_scene() for the real first scene, so even the first level goes through the
# viewport.
#
# How to use from a door/trigger:
#   SceneManager.change_scene("res://stages/.../bar-inside/barinside.tscn", "from_door")
#
# Each destination scene should contain a Marker3D named to match the spawn id
# (e.g. a Marker3D named "from_door"). The player is moved onto that marker after
# the new scene loads. If no spawn id is given, the player keeps the position the
# scene placed them at.

extends Node

## Emitted right after a new scene has loaded and the player has been placed.
signal scene_loaded(scene_path: String)

## Pixel-art downscale factor: the world renders at (window size / PIXEL_SHRINK) then is
## upscaled with nearest-neighbour filtering for crisp, chunky pixels. Set to 1 to
## effectively disable the effect (full-resolution render).
const PIXEL_SHRINK: int = 3

# Set just before a transition; consumed once the new scene is ready.
var _pending_spawn: StringName = &""

# The active gameplay scene. We track it ourselves because it lives UNDER the world
# SubViewport, and Godot refuses to set `tree.current_scene` to a node that isn't a
# direct child of root. Gameplay code should use current_world() instead of
# get_tree().current_scene to find "the level" to spawn things into.
var _current_world: Node = null

# The persistent pixel-art world plumbing (built once in _ready).
var _world_layer: CanvasLayer
var _world_container: SubViewportContainer
var _world_viewport: SubViewport

func _ready() -> void:
	_build_world_viewport()

# Build the one SubViewport that every gameplay scene renders into. It sits on a
# CanvasLayer far behind the UI layers so HUD/menus draw crisply on top of the
# upscaled world.
func _build_world_viewport() -> void:
	_world_layer = CanvasLayer.new()
	_world_layer.layer = -100
	add_child(_world_layer)

	_world_container = SubViewportContainer.new()
	_world_container.stretch = true
	_world_container.stretch_shrink = PIXEL_SHRINK
	_world_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Nearest-neighbour so the upscaled low-res image stays crisp (no blur).
	_world_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_world_layer.add_child(_world_container)

	_world_viewport = SubViewport.new()
	# Let input flow from the container into the viewport (FPS controls live inside).
	_world_viewport.handle_input_locally = false
	_world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# 3D audio should be heard from the in-world camera that lives in this viewport.
	_world_viewport.audio_listener_enable_3d = true
	# Transparent when nothing is rendered into it, so a dev scene run directly (F6) —
	# which loads under root, not this viewport — isn't hidden behind a blank fill.
	_world_viewport.transparent_bg = true
	_world_container.add_child(_world_viewport)

## The world SubViewport every gameplay scene is parented under. Exposed for any system
## that needs the active 3D world (e.g. to add world-space effects).
func world_viewport() -> SubViewport:
	return _world_viewport

## The active gameplay scene ("the level") that things should be spawned into. Use this
## instead of get_tree().current_scene: scenes loaded through change_scene live under the
## world SubViewport, where current_scene can't point. Falls back to current_scene so a
## dev scene run directly (F6) — which loads under root normally — still works.
func current_world() -> Node:
	if is_instance_valid(_current_world):
		return _current_world
	return get_tree().current_scene

## Change to a new scene, optionally placing the player on a named spawn Marker3D.
func change_scene(scene_path: String, spawn_point: StringName = &"") -> void:
	_pending_spawn = spawn_point
	# Defer so we never tear down a scene mid-frame (e.g. while its input or
	# physics callback is still running — that's a classic crash source).
	_change_scene_deferred.call_deferred(scene_path)

func _change_scene_deferred(scene_path: String) -> void:
	var tree := get_tree()

	# Tear down the active world we're tracking (it lives under the viewport)...
	if is_instance_valid(_current_world):
		_current_world.free()
		_current_world = null
	# ...and, on first boot, the tiny boot scene Godot loaded directly under root.
	if tree.current_scene:
		tree.current_scene.free()

	# Build and install the new one.
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("SceneManager: could not load scene at %s" % scene_path)
		return
	var next_scene := packed.instantiate()
	# Parent gameplay scenes under the world SubViewport so they render pixel-art; fall
	# back to root only if the viewport somehow isn't ready.
	var host: Node = _world_viewport if _world_viewport != null else tree.root
	host.add_child(next_scene)
	_current_world = next_scene

	# Children have run _ready() by now, so the player is in the "player" group.
	_place_player(next_scene)
	scene_loaded.emit(scene_path)

func _place_player(scene_root: Node) -> void:
	if _pending_spawn == &"":
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player is Node3D:
		push_warning("SceneManager: no player found to place at spawn '%s'." % _pending_spawn)
		return
	# Find the matching Marker3D anywhere under the new scene.
	var spawn := scene_root.find_child(String(_pending_spawn), true, false)
	if spawn is Node3D:
		player.global_transform = spawn.global_transform
	else:
		push_warning("SceneManager: spawn point '%s' not found in %s." % [_pending_spawn, scene_root.name])
	_pending_spawn = &""
