# asset_review.gd
# A dev scene (F6) for eyeballing asset SIZES. Every model from the listed folders is placed on
# the floor at its NATIVE imported scale (no normalisation), resting on the ground, with a
# floating label showing its name + measured W x H x D in metres. Next to the spawn there's a
# 1.8 m human reference and a 1 m-marked ruler so you can judge scale at a glance, and a player
# is dropped in so you can walk among them. Tell me which ones read wrong and by how much.
#
# Models are laid out in a grid, grouped by folder with a header label. Configure the folders /
# grid below. Nothing here is normalised — what you see is exactly how each model imports.
extends Node3D

## Folders to scan for models (every .gltf/.glb/.fbx is shown, at native scale).
@export var folders: PackedStringArray = [
	"res://assets/models/tools_weapons/kaykit_weapons",
	"res://assets/models/tools_weapons/kaykit_tools",
	"res://assets/models/props/kaykit_resources",
	"res://assets/models/nature/stylized-megakit",
]
## Columns per row before wrapping.
@export var columns: int = 10
## Spacing between items (metres).
@export var spacing: float = 3.5

# Pending (holder, model, name) to finish (measure + label + sit on ground) after a frame.
var _pending: Array = []

func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_scale_reference()
	_layout_assets()
	# Player so you can walk the rows.
	var player: Node3D = (load("res://entities/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(-4.0, 1.5, -4.0)
	# Measure + label once everything is in the tree (AABBs need a frame to be valid).
	call_deferred("_finish")

func _layout_assets() -> void:
	var row: int = 0
	for folder in folders:
		var files: Array = _model_files(folder)
		if files.is_empty():
			continue
		# Section header at the start of this folder's band.
		var header := Label3D.new()
		header.text = folder.get_file().to_upper()
		header.font_size = 96
		header.modulate = Color(1.0, 0.85, 0.3)
		header.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		header.no_depth_test = true
		header.position = Vector3(-spacing, 3.0, float(row) * spacing)
		add_child(header)
		var col: int = 0
		for f in files:
			var ps: Resource = load(folder.path_join(String(f)))
			if not (ps is PackedScene):
				continue
			var holder := Node3D.new()
			holder.position = Vector3(float(col) * spacing, 0.0, float(row) * spacing)
			add_child(holder)
			var model: Node3D = (ps as PackedScene).instantiate() as Node3D
			if model == null:
				continue
			holder.add_child(model)
			_pending.append({"holder": holder, "model": model, "name": String(f).get_basename()})
			col += 1
			if col >= columns:
				col = 0
				row += 1
		if col != 0:
			row += 1
		row += 1  # blank row between folders

func _finish() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	for entry in _pending:
		var holder: Node3D = entry["holder"]
		var model: Node3D = entry["model"]
		var item_name: String = entry["name"]
		var aabb := _visual_aabb(model)
		# Rest the model's base on the ground.
		model.position.y = -aabb.position.y
		# A small pad marker so each item reads as "placed".
		var label := Label3D.new()
		label.text = "%s\n%.2f x %.2f x %.2f" % [item_name, aabb.size.x, aabb.size.y, aabb.size.z]
		label.font_size = 40
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3(0.0, maxf(aabb.size.y, 0.2) + 0.4, 0.0)
		holder.add_child(label)
	_pending.clear()

# A 1.8 m human-height capsule + a 0-3 m ruler with metre marks, at the spawn corner.
func _build_scale_reference() -> void:
	var human := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.height = 1.8
	cap.radius = 0.3
	human.mesh = cap
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.2, 0.6, 1.0, 0.6)
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	human.material_override = hmat
	human.position = Vector3(-7.0, 0.9, -4.0)
	add_child(human)
	var hlabel := Label3D.new()
	hlabel.text = "1.8 m\nhuman"
	hlabel.font_size = 56
	hlabel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hlabel.no_depth_test = true
	hlabel.position = Vector3(-7.0, 2.1, -4.0)
	add_child(hlabel)
	# Ruler pole with metre marks 1..3.
	var pole := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.05, 3.0, 0.05)
	pole.mesh = pm
	pole.position = Vector3(-9.0, 1.5, -4.0)
	add_child(pole)
	for m in range(1, 4):
		var mark := Label3D.new()
		mark.text = "%d m" % m
		mark.font_size = 48
		mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mark.no_depth_test = true
		mark.position = Vector3(-9.4, float(m), -4.0)
		add_child(mark)

# --- helpers ---------------------------------------------------------------

func _model_files(folder: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	for file_name in dir.get_files():
		var fn: String = file_name.trim_suffix(".remap")
		var lower: String = fn.to_lower()
		if lower.ends_with(".gltf") or lower.ends_with(".glb") or lower.ends_with(".fbx"):
			out.append(fn)
	out.sort()
	return out

func _visual_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for vi in _find_visuals(root):
		var local: Transform3D = root.global_transform.affine_inverse() * vi.global_transform
		var box: AABB = local * vi.get_aabb()
		if not found:
			result = box
			found = true
		else:
			result = result.merge(box)
	return result

func _find_visuals(node: Node) -> Array[VisualInstance3D]:
	var out: Array[VisualInstance3D] = []
	if node is VisualInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_visuals(c))
	return out

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.2
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

func _build_ground() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 120.0)
	col.shape = box
	col.position = Vector3(40.0, -0.5, 25.0)
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120.0, 120.0)
	mesh.mesh = pm
	mesh.position = Vector3(40.0, 0.0, 25.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.27, 0.29, 0.32)
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)
