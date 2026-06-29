# m_c_venues_test.gd
# Headless verification for Milestone M-C (venues / interiors). Asserts in _ready(), writes
# PASS/FAIL to user://_test_result.txt, quits 0 (pass) / 1 (fail). Run:
#   Godot --headless --path <project> res://stages/dev/m_c_venues_test.tscn --quit-after 300
#
# For each of the five v1 venues it checks the M-C acceptance ("enterable from town, owner
# present, leave-door returns to the correct doorstep"):
#   1. town_template has the venue's gate — present, NOT locked, targeting the right scene —
#      plus its from_<venue> return marker (read off town_template's SceneState).
#   2. The interior scene instances, contains its owner NPC (by definition id or npc_id), and
#      its town-bound Leave door carries the matching from_<venue> spawn point.
extends Node

const TOWN := "res://stages/overworld/town_template.tscn"

# gate node name -> { interior scene, owner npc id, expected leave-door spawn / return marker }
const VENUES := {
	"GateStore":   {"scene": "res://stages/interiors/general_store_inside.tscn", "owner": "george",    "leave": "from_store"},
	"GateBar":     {"scene": "res://stages/overworld/bar-inside/barinside.tscn", "owner": "barry",     "leave": "from_bar"},
	"GateArcade":  {"scene": "res://stages/overworld/arcade_inside.tscn",        "owner": "kippie",    "leave": "from_arcade"},
	"GateGuild":   {"scene": "res://stages/interiors/adventurers_guild.tscn",    "owner": "sally",     "leave": "from_guild"},
	"GateFishing": {"scene": "res://stages/interiors/astros_fishing.tscn",       "owner": "droghnaut", "leave": "from_fishing"},
}

var _lines: Array[String] = []
var _ok := true

func _ready() -> void:
	await get_tree().process_frame

	# --- 1. Town gates + return markers (off town_template's SceneState) -------
	var ts: SceneState = (load(TOWN) as PackedScene).get_state()
	var gate_target := {}
	var gate_locked := {}
	var node_names := {}
	for ni in ts.get_node_count():
		var nm := String(ts.get_node_name(ni))
		node_names[nm] = true
		for pi in ts.get_node_property_count(ni):
			var pn := String(ts.get_node_property_name(ni, pi))
			if pn == "target_scene_path":
				gate_target[nm] = String(ts.get_node_property_value(ni, pi))
			elif pn == "locked":
				gate_locked[nm] = bool(ts.get_node_property_value(ni, pi))
	for gate in VENUES:
		var want_scene: String = VENUES[gate]["scene"]
		var leave: String = VENUES[gate]["leave"]
		if not gate_target.has(gate):
			_fail("town gate %s missing" % gate)
		elif gate_target[gate] != want_scene:
			_fail("%s targets '%s', expected '%s'" % [gate, gate_target[gate], want_scene])
		elif gate_locked.get(gate, false):
			_fail("%s is locked (a v1 venue should be open)" % gate)
		else:
			_pass("gate %s -> %s (open)" % [gate, want_scene.get_file()])
		if not node_names.has(leave):
			_fail("return marker '%s' missing in town" % leave)

	# Persist gate results before the heavier interior instancing below.
	_write()

	# --- 2. Each interior: owner present + leave-door returns to the doorstep --
	for gate in VENUES:
		var v: Dictionary = VENUES[gate]
		var ps := load(v["scene"]) as PackedScene
		if ps == null:
			_fail("interior failed to load: %s" % v["scene"])
			continue
		var inst: Node = ps.instantiate()
		add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame
		var label: String = String(v["scene"]).get_file()
		if _tree_has_owner(inst, v["owner"]):
			_pass("%s: owner '%s' present" % [label, v["owner"]])
		else:
			_fail("%s: owner '%s' NOT found" % [label, v["owner"]])
		var spawn := _find_town_return_spawn(inst)
		if spawn == v["leave"]:
			_pass("%s: leave-door returns to '%s'" % [label, v["leave"]])
		else:
			_fail("%s: leave-door spawn = '%s', expected '%s'" % [label, spawn, v["leave"]])
		inst.queue_free()
		await get_tree().process_frame

	_write()
	get_tree().quit(0 if _ok else 1)

# --- helpers ---------------------------------------------------------------

func _pass(msg: String) -> void:
	_lines.append("PASS " + msg)

func _fail(msg: String) -> void:
	_ok = false
	_lines.append("FAIL " + msg)

func _write() -> void:
	var f := FileAccess.open("user://_test_result.txt", FileAccess.WRITE)
	if f != null:
		var header := "M-C VENUES TEST: " + ("ALL PASS" if _ok else "FAILURES")
		f.store_string(header + "\n" + "\n".join(_lines))
		f.close()

# An owner matches by NPCDefinition id (npc.tscn + definition) OR by a direct npc_id export
# (the Shopkeeper). Walks the whole instanced subtree.
func _tree_has_owner(root: Node, owner_id: String) -> bool:
	var def = root.get("definition")
	if def != null and String(def.get("id")) == owner_id:
		return true
	var nid = root.get("npc_id")
	if nid != null and String(nid) == owner_id:
		return true
	for c in root.get_children():
		if _tree_has_owner(c, owner_id):
			return true
	return false

# Find the teleport that returns to town (ignores e.g. the guild's dungeon entrance) and report
# its target_spawn_point. Returns "__none__" if no town-bound teleport exists in the subtree.
func _find_town_return_spawn(root: Node) -> String:
	var tsp = root.get("target_scene_path")
	if tsp != null and String(tsp).find("town_template") != -1:
		var sp = root.get("target_spawn_point")
		return String(sp) if sp != null else ""
	for c in root.get_children():
		var r := _find_town_return_spawn(c)
		if r != "__none__":
			return r
	return "__none__"
