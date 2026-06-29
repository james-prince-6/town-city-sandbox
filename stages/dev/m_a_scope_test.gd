# m_a_scope_test.gd
# Headless verification for Milestone M-A (scope lock & onboarding). Follows the project's
# _ready()-assertion pattern (docs/ARCHITECTURE.md §11): asserts in _ready(), writes PASS/FAIL
# lines to user://_test_result.txt (stdout capture is unreliable for Godot here), then quits
# with code 0 (all pass) or 1 (any failure). Run with:
#   Godot --headless --path <project> res://stages/dev/m_a_scope_test.tscn --quit-after 30
#
# Asserts the M-A acceptance facts:
#   1. New game arms the player: hotbar slots 0-3 = pickaxe/hatchet/iron_sword/bow AND the bag
#      owns all four after the real MainMenu._grant_starting_tools() grant.
#   2 + 3. Scope is locked in town_template: only the Whispering Woods wild gate + the procedural
#      DungeonEntrance are live; Meadow/Hills/Barrens + the Sewer are parked (locked=true); and
#      the procedural dungeon is pinned to one theme (forced_theme_name == "Mine"). Read straight
#      off each scene's SceneState so we never instance the heavy town/dungeon (no _ready side
#      effects, fast, deterministic).
#   4. The dungeon's convenience starter-kit is a no-op when the dungeon isn't the current scene
#      (exactly the overworld-entry case) — so entering from town never disturbs the hotbar.
extends Node

const TOWN := "res://stages/overworld/town_template.tscn"
const DUNGEON := "res://stages/dungeons/procedural/generated_dungeon.tscn"
const DUNGEON_SCRIPT := "res://stages/dungeons/procedural/dungeon_generator.gd"

func _ready() -> void:
	# One frame so all autoloads have finished their own _ready() before we poke them.
	await get_tree().process_frame
	var lines: Array[String] = []
	var ok := true

	# --- 1. Starter tools (the real New Game grant path) -----------------------
	# Reset the one-shot latch so we exercise the grant fresh, then run the real autoload method.
	GameState.set_flag(&"starting_tools_granted", false)
	MainMenu._grant_starting_tools()
	var want: Array[StringName] = [&"pickaxe", &"hatchet", &"iron_sword", &"bow"]
	for i in want.size():
		var slot_id: StringName = Hotbar.slots[i]
		if slot_id == want[i]:
			lines.append("PASS hotbar slot %d = %s" % [i, slot_id])
		else:
			ok = false
			lines.append("FAIL hotbar slot %d = %s, expected %s" % [i, slot_id, want[i]])
		if Inventory.count_of(want[i]) < 1:
			ok = false
			lines.append("FAIL bag missing %s after grant" % want[i])

	# --- 2 + 3. Scope lock, read off the authored SceneState -------------------
	var town_state: SceneState = (load(TOWN) as PackedScene).get_state()
	# Live (false) gates must NOT carry a true 'locked'; parked (true) gates MUST.
	var expect_locked := {
		"GateWoods": false, "DungeonEntrance": false,
		"GateMeadow": true, "GateHills": true, "GateBarrens": true, "GateSewer": true,
	}
	var seen := {}
	for n in expect_locked:
		seen[n] = false
	for ni in town_state.get_node_count():
		var nm := String(town_state.get_node_name(ni))
		if not expect_locked.has(nm):
			continue
		seen[nm] = true
		var locked_val: bool = bool(_state_prop(town_state, ni, &"locked", false))
		if locked_val == bool(expect_locked[nm]):
			lines.append("PASS %s locked = %s" % [nm, locked_val])
		else:
			ok = false
			lines.append("FAIL %s locked = %s, expected %s" % [nm, locked_val, expect_locked[nm]])
	for n in seen:
		if not seen[n]:
			ok = false
			lines.append("FAIL gate node not found in town: %s" % n)

	# Procedural dungeon pinned to the Mine theme.
	var dgn_state: SceneState = (load(DUNGEON) as PackedScene).get_state()
	var theme_name := ""
	for ni in dgn_state.get_node_count():
		if String(dgn_state.get_node_name(ni)) == "GeneratedDungeon":
			theme_name = String(_state_prop(dgn_state, ni, &"forced_theme_name", ""))
	if theme_name == "Mine":
		lines.append("PASS dungeon forced_theme_name = Mine")
	else:
		ok = false
		lines.append("FAIL dungeon forced_theme_name = '%s', expected 'Mine'" % theme_name)

	# --- 4. Dungeon convenience kit is a no-op outside direct-play -------------
	# The grant guards on `get_tree().current_scene == self`. Entering from town puts the dungeon
	# under the world SubViewport (never current_scene), so the grant must do nothing. Build a
	# bare generator (script only — NOT the full scene, so no floor is generated), parent it so
	# get_tree() resolves, and confirm the armed hotbar is untouched.
	var before: Array[StringName] = Hotbar.slots.duplicate()
	var gen: Node = load(DUNGEON_SCRIPT).new()
	add_child(gen)
	if gen.has_method("_grant_starter_kit_if_unarmed"):
		gen._grant_starter_kit_if_unarmed()
	gen.queue_free()
	if Hotbar.slots == before:
		lines.append("PASS dungeon starter-kit left the hotbar untouched")
	else:
		ok = false
		lines.append("FAIL hotbar changed by dungeon starter-kit: %s -> %s" % [before, Hotbar.slots])

	# --- Write result + quit ---------------------------------------------------
	lines.push_front("M-A SCOPE TEST: " + ("ALL PASS" if ok else "FAILURES"))
	var f := FileAccess.open("user://_test_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines))
		f.close()
	get_tree().quit(0 if ok else 1)

# Read an authored property value for node `ni` from a SceneState, or `def` if the property
# wasn't authored (i.e. it keeps the script's export default). Avoids instancing the scene.
func _state_prop(state: SceneState, ni: int, prop: StringName, def: Variant) -> Variant:
	for pi in state.get_node_property_count(ni):
		if state.get_node_property_name(ni, pi) == prop:
			return state.get_node_property_value(ni, pi)
	return def
