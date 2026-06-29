# reputation_tab_test.gd
# Headless check that Reputation moved to its own player-menu tab. Asserts in _ready(),
# writes user://_test_result.txt, quits 0/1.
#   Godot --headless --path <project> res://stages/dev/reputation_tab_test.tscn --quit-after 120
extends Node

var _lines: Array = []
var _ok := true

func _ready() -> void:
	await get_tree().process_frame
	var pm = get_node_or_null("/root/PlayerMenu")
	if pm == null:
		_fail("PlayerMenu autoload missing (script parse error?)")
		_write(); get_tree().quit(1); return

	# 1. Reputation is now a top-level tab.
	var names = pm.TAB_NAMES
	if names is Array and names.has("Reputation"):
		_pass("Reputation is a tab: %s" % str(names))
	else:
		_fail("Reputation not in TAB_NAMES: %s" % str(names))

	# 2. The Reputation tab builds a populated panel with its header.
	var rep_body = pm._build_reputation()
	if rep_body != null and _has_text(rep_body, "Townsfolk Reputation"):
		_pass("Reputation tab builds its panel (header present)")
	else:
		_fail("Reputation tab empty / header missing")

	# 3. At least one cast row renders (Reputation autoload present in this run).
	if rep_body != null and _has_text(rep_body, "Mayor Orbo"):
		_pass("Reputation tab lists the v1 cast (e.g. Mayor Orbo)")
	else:
		_fail("Reputation tab shows no cast rows")

	# 4. The old in-inventory strip helper is gone (moved, not duplicated).
	if not pm.has_method("_build_reputation_strip"):
		_pass("old _build_reputation_strip() removed")
	else:
		_fail("_build_reputation_strip() still present (dead code / duplicate)")

	_write()
	get_tree().quit(0 if _ok else 1)

func _has_text(node: Node, sub: String) -> bool:
	if node is Label and String((node as Label).text).find(sub) != -1:
		return true
	for c in node.get_children():
		if _has_text(c, sub):
			return true
	return false

func _pass(m: String) -> void:
	_lines.append("PASS " + m)

func _fail(m: String) -> void:
	_ok = false
	_lines.append("FAIL " + m)

func _write() -> void:
	var f := FileAccess.open("user://_test_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(("REPUTATION TAB TEST: " + ("ALL PASS" if _ok else "FAILURES")) + "\n" + "\n".join(_lines))
		f.close()
