# bar_upgrade_station.gd
# Greybox bar-upgrades buyer behind the counter (M-D money sink). Duck-typed interactable: aim
# + E buys the CHEAPEST unowned bar upgrade (Bartending.UPGRADES) if you can afford it, spending
# money via Bartending.buy_upgrade(). The upgrades (better tap / pre-stocked rack / bus tub /
# crowd capacity) persist via the Bartending autoload's save. A fuller shop-style picker is a
# later polish pass; this proves the earn → spend → better-shifts loop. Self-builds its visuals.
extends StaticBody3D

func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 1.0, 0.6)
	mesh.mesh = bm
	mesh.position = Vector3(0.0, 0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.55, 0.75)
	mesh.material_override = mat
	add_child(mesh)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 1.0, 0.6)
	col.shape = box
	col.position = Vector3(0.0, 0.5, 0.0)
	add_child(col)
	var lbl := Label3D.new()
	lbl.text = "BAR UPGRADES"
	lbl.font_size = 36
	lbl.pixel_size = 0.006
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0.0, 1.3, 0.0)
	lbl.outline_size = 8
	add_child(lbl)

func get_interaction_prompt() -> String:
	var nxt: StringName = _next_upgrade()
	if nxt == &"":
		return "Bar upgrades — all owned"
	var u: Dictionary = Bartending.UPGRADES[nxt]
	return "Buy %s  ($%d)" % [String(u["name"]), int(u["cost"])]

func interact(_player) -> void:
	var nxt: StringName = _next_upgrade()
	if nxt == &"":
		_notify("All bar upgrades owned.")
		return
	if Bartending.buy_upgrade(nxt):
		_notify("Bought %s!" % String(Bartending.UPGRADES[nxt]["name"]))
	else:
		_notify("Not enough money for %s." % String(Bartending.UPGRADES[nxt]["name"]))

# The cheapest upgrade the player doesn't own yet (&"" when everything is owned).
func _next_upgrade() -> StringName:
	var best: StringName = &""
	var best_cost: int = 1 << 30
	for id in Bartending.UPGRADES:
		if not Bartending.has_upgrade(id) and int(Bartending.UPGRADES[id]["cost"]) < best_cost:
			best = id
			best_cost = int(Bartending.UPGRADES[id]["cost"])
	return best

func _notify(msg: String) -> void:
	var feed := get_node_or_null("/root/NotificationFeed")
	if feed != null and feed.has_method("notify"):
		feed.notify(msg)
