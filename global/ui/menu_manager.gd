# menu_manager.gd
# Autoload singleton (register as "MenuManager"). Stops full-screen menus from stacking
# on top of each other. A menu opts in by joining the "exclusive_menu" group (in its
# _ready) and calling MenuManager.opening(self) right when it opens; this closes any
# OTHER exclusive menu that's currently up, so only one is ever open at a time.
extends Node

func opening(active: Node) -> void:
	for m in get_tree().get_nodes_in_group("exclusive_menu"):
		if m == active or not is_instance_valid(m):
			continue
		if not _is_open(m):
			continue
		if m.has_method("close"):
			m.close()
		elif m.has_method("hide"):
			m.hide()

func _is_open(m: Node) -> bool:
	if "is_open" in m:
		return m.is_open
	if "visible" in m:
		return m.visible
	return false
