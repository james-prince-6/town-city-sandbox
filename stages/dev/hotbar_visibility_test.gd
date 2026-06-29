# hotbar_visibility_test.gd
# Headless check for the job/minigame hotbar-hide feature + the bartending shift's integration
# (hotbar suppressed on shift start, restored on end) and Barry's hand-off (frozen + restored).
extends Node

const SHIFT := "res://entities/minigames/bartending/bartending_shift.gd"

var _lines: Array = []
var _ok := true

func _ready() -> void:
	await get_tree().process_frame
	var hud := get_node_or_null("/root/HUD")
	if hud == null:
		_fail("HUD autoload missing (parse error?)"); _write(); get_tree().quit(1); return

	# 1. Baseline visible.
	hud.set_hotbar_suppressed(false)
	_check(hud.hotbar_strip.visible == true, "hotbar visible by default")
	# 2. Suppress hides it.
	hud.set_hotbar_suppressed(true)
	_check(hud.hotbar_strip.visible == false, "set_hotbar_suppressed(true) hides the hotbar")
	# 3. Opening the menu/bag reveals it again (the override).
	hud._on_menu_opened_hud()
	_check(hud.hotbar_strip.visible == true, "opening the bag reveals the hotbar while suppressed")
	# 4. Closing the menu re-hides it (still suppressed).
	hud._on_menu_closed_hud()
	_check(hud.hotbar_strip.visible == false, "closing the bag re-hides it while still suppressed")
	# 5. Un-suppressing shows it.
	hud.set_hotbar_suppressed(false)
	_check(hud.hotbar_strip.visible == true, "un-suppressing shows the hotbar")

	# 6. Bartending shift integration + Barry hand-off.
	var player := Node3D.new()
	player.add_to_group("player")
	add_child(player)
	var barry := CharacterBody3D.new()
	barry.name = "Barry"   # the shift finds Barry as a sibling via get_parent().get_node("Barry")
	add_child(barry)
	var shift: Node = load(SHIFT).new()
	add_child(shift)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(hud.hotbar_strip.visible == false, "starting a shift suppresses the hotbar")
	_check(barry.process_mode == Node.PROCESS_MODE_DISABLED, "Barry is frozen for the hand-off")

	shift.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(hud.hotbar_strip.visible == true, "ending the shift restores the hotbar")
	_check(is_instance_valid(barry) and barry.visible and barry.process_mode == Node.PROCESS_MODE_INHERIT,
		"Barry is restored to his post after the shift")

	_write()
	get_tree().quit(0 if _ok else 1)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_lines.append("PASS " + msg)
	else:
		_ok = false
		_lines.append("FAIL " + msg)

func _fail(msg: String) -> void:
	_ok = false
	_lines.append("FAIL " + msg)

func _write() -> void:
	var f := FileAccess.open("user://_test_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(("HOTBAR VISIBILITY TEST: " + ("ALL PASS" if _ok else "FAILURES")) + "\n" + "\n".join(_lines))
		f.close()
