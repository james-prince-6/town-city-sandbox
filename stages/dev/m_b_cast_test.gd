# m_b_cast_test.gd
# Headless verification for Milestone M-B (cast migration). Same pattern as m_a_scope_test:
# asserts in _ready(), writes PASS/FAIL to user://_test_result.txt, quits 0 (pass) / 1 (fail).
# Run AFTER an import pass (the new .dialogue files must be imported first):
#   Godot --headless --editor --import --quit          # import new .dialogue + rebuild cache
#   Godot --headless --path <project> res://stages/dev/m_b_cast_test.tscn --quit-after 120
#
# Asserts the M-B acceptance facts:
#   1. The five v1 cast NPCDefinitions load, ids match, and their .dialogue + model resolve.
#   2. The Gus->George rename: shopkeeper.tscn is "George Coral" / npc_id george, and the
#      general_store's reputation_npc matches (key consistency).
#   3. The New Game quest (getting_started) was re-pointed at Orbo (objective target met_orbo).
#   4. Orbo is actually placed in the Town Hall (functional: instance it, find the NPC).
#   5. Broad sweep: every NPCDefinition + Quest resource still loads (no broken/parse-failed refs).
extends Node

const QUEST_DIR := "res://global/quests/resources/"
const DEF_DIR := "res://global/npc/definitions/"
const V1_CAST := {
	"orbo": "res://global/npc/definitions/orbo.tres",
	"barry": "res://global/npc/definitions/barry.tres",
	"kippie": "res://global/npc/definitions/kippie.tres",
	"droghnaut": "res://global/npc/definitions/droghnaut.tres",
	"sally": "res://global/npc/definitions/sally.tres",
}

var _lines: Array[String] = []
var _ok := true

func _ready() -> void:
	await get_tree().process_frame

	# --- 1. v1 cast definitions load; ids match; dialogue + model resolve ------
	for want_id in V1_CAST:
		var path: String = V1_CAST[want_id]
		var def: Resource = load(path)
		if def == null:
			_fail("could not load %s" % path)
			continue
		var got_id := String(def.get("id"))
		var dlg = def.get("dialogue")
		var model = def.get("model_scene")
		if got_id != want_id:
			_fail("%s id = '%s', expected '%s'" % [path, got_id, want_id])
		if dlg == null:
			_fail("cast '%s' has no dialogue resource (was the .dialogue imported?)" % want_id)
		if model == null:
			_fail("cast '%s' has no model_scene" % want_id)
		if got_id == want_id and dlg != null and model != null:
			_pass("cast '%s' def loads (id, dialogue, model all resolve)" % want_id)

	# --- 2. Gus -> George rename + reputation key consistency ------------------
	var keeper_state: SceneState = (load("res://entities/npc/shopkeeper.tscn") as PackedScene).get_state()
	var kname := ""
	var kid := ""
	for ni in keeper_state.get_node_count():
		for pi in keeper_state.get_node_property_count(ni):
			var pn := String(keeper_state.get_node_property_name(ni, pi))
			if pn == "npc_name":
				kname = String(keeper_state.get_node_property_value(ni, pi))
			elif pn == "npc_id":
				kid = String(keeper_state.get_node_property_value(ni, pi))
	if kname == "George Coral" and kid == "george":
		_pass("shopkeeper is George Coral (npc_id george)")
	else:
		_fail("shopkeeper npc_name='%s' npc_id='%s' (expected George Coral / george)" % [kname, kid])

	var shop: Resource = load("res://global/shop/shops/general_store.tres")
	var rep := String(shop.get("reputation_npc")) if shop != null else "<null shop>"
	if rep == "george":
		_pass("general_store reputation_npc = george (matches keeper)")
	else:
		_fail("general_store reputation_npc = '%s', expected george" % rep)

	# --- 3. New Game quest re-pointed at Orbo ----------------------------------
	var qs: Resource = load("res://global/quests/resources/getting_started.tres")
	var obj_target := ""
	if qs != null:
		var objs: Array = qs.get("objectives")
		if objs != null and objs.size() > 0 and objs[0] != null:
			obj_target = String(objs[0].get("target"))
	if obj_target == "met_orbo":
		_pass("getting_started objective targets met_orbo")
	else:
		_fail("getting_started objective target = '%s', expected met_orbo" % obj_target)

	# --- 5. Broad resource-load sweep (do before the heavy instance below) -----
	var swept := 0
	for dir_path in [DEF_DIR, QUEST_DIR]:
		for fn in _list_tres(dir_path):
			swept += 1
			if load(dir_path + fn) == null:
				_fail("resource failed to load: %s%s" % [dir_path, fn])
	_pass("swept %d definition+quest resources, all load" % swept)

	# Persist the data-layer results now so a failure in the heavy step below can't lose them.
	_write()

	# --- 4. Orbo is actually placed in the Town Hall (functional) -------------
	var th_scene := load("res://stages/interiors/town_hall.tscn") as PackedScene
	if th_scene == null:
		_fail("could not load town_hall.tscn")
	else:
		var th: Node = th_scene.instantiate()
		add_child(th)
		await get_tree().process_frame
		await get_tree().process_frame
		if _tree_has_npc_with_def_id(th, "orbo"):
			_pass("Town Hall places the Orbo NPC")
		else:
			_fail("Town Hall has no NPC with definition id 'orbo'")
		th.queue_free()

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
		var header := "M-B CAST TEST: " + ("ALL PASS" if _ok else "FAILURES")
		f.store_string(header + "\n" + "\n".join(_lines))
		f.close()

func _tree_has_npc_with_def_id(root: Node, want_id: String) -> bool:
	var def = root.get("definition")
	if def != null and String(def.get("id")) == want_id:
		return true
	for c in root.get_children():
		if _tree_has_npc_with_def_id(c, want_id):
			return true
	return false

func _list_tres(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if not d.current_is_dir() and fn.ends_with(".tres"):
			out.append(fn)
		fn = d.get_next()
	d.list_dir_end()
	return out
