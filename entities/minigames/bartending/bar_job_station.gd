# bar_job_station.gd
# The CLOCK-IN / CLOCK-OUT point for the bartending job at The Flaming Pebble (M-D). It lives on
# the CASH REGISTER the player placed in barinside.tscn: on _ready it relocates itself onto the
# register prop and adopts the register's collider, so aiming at the register is what clocks you
# in and out. (The register prop is a plain fbx instance whose own CollisionShape3D is inert — its
# root isn't a physics body — so this StaticBody3D supplies the working one.)
#
#   CLOCK IN  — no shift running: spawns a bartending_shift.gd controller into the live world.
#   CLOCK OUT — shift running: tells the shift to end now (you keep what you earned + base wage).
#
# Duck-typed interactable (aim + E), same as everything else the player interacts with.
extends StaticBody3D

const SHIFT_SCRIPT := "res://entities/minigames/bartending/bartending_shift.gd"
const REGISTER_PATH := "Bar equiptment/cash-register"

func _ready() -> void:
	# Move onto the register prop and borrow its collider so the register itself is the target.
	var reg: Node3D = null
	if get_parent() != null:
		reg = get_parent().get_node_or_null(REGISTER_PATH) as Node3D
	var col := CollisionShape3D.new()
	if reg != null:
		global_transform = reg.global_transform
		var src: CollisionShape3D = _find_collision_shape(reg)
		if src != null and src.shape != null:
			col.shape = src.shape
			col.transform = src.transform
		else:
			col.shape = _default_shape()
	else:
		push_warning("BarJobStation: '%s' not found — clock station stays at its scene position." % REGISTER_PATH)
		col.shape = _default_shape()
		col.position = Vector3(0.0, 0.5, 0.0)
	add_child(col)

func get_interaction_prompt() -> String:
	if _shift_running():
		return "Clock out — end your shift"
	return "Clock in — start a bartending shift"

func interact(_player) -> void:
	if _shift_running():
		var shifts: Array = get_tree().get_nodes_in_group("bartending_shift")
		if not shifts.is_empty() and shifts[0].has_method("clock_out"):
			shifts[0].clock_out()
		return
	var shift: Node = load(SHIFT_SCRIPT).new()
	var world: Node = null
	if SceneManager != null and SceneManager.has_method("current_world"):
		world = SceneManager.current_world()
	if world == null:
		world = get_tree().current_scene
	if world == null:
		world = get_parent()
	world.add_child(shift)

func _shift_running() -> bool:
	return not get_tree().get_nodes_in_group("bartending_shift").is_empty()

func _find_collision_shape(node: Node) -> CollisionShape3D:
	for c in node.get_children():
		if c is CollisionShape3D:
			return c
	return null

func _default_shape() -> BoxShape3D:
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.5, 0.6)
	return box
