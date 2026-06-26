# shader_showcase.gd
# A dev scene (open with F6) that exercises the imported shaders so they're wired into the
# project and easy to copy from: the toon water (`assets/shaders/water/water_toon.gdshader`),
# the frosted-glass UI panel (`assets/shaders/ui/glass_panel.gdshader` + its base stylebox),
# and the stylized toon surface (`assets/shaders/stylized_toon.gdshader`). Everything is built in
# code so there's no .tscn material wiring to maintain — copy the relevant _build_* method's
# setup to use a shader elsewhere (e.g. drop the water material on a PlaneMesh over a pond).
extends Node3D

func _ready() -> void:
	_build_environment()
	_build_water()
	_build_toon_object()
	_build_glass_ui()

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -40.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 6.0, 12.0)
	cam.rotation_degrees = Vector3(-24.0, 0.0, 0.0)
	add_child(cam)

# Toon water on a subdivided plane, sitting over a sunken basin so it reads as having depth.
func _build_water() -> void:
	var basin := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(24.0, 4.0, 24.0)
	basin.mesh = bmesh
	basin.position = Vector3(0.0, -2.2, 0.0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.16, 0.13, 0.1)
	basin.material_override = bmat
	add_child(basin)

	var water := MeshInstance3D.new()
	var pmesh := PlaneMesh.new()
	pmesh.size = Vector2(20.0, 20.0)
	pmesh.subdivide_width = 64
	pmesh.subdivide_depth = 64
	water.mesh = pmesh
	water.position = Vector3(0.0, -0.2, 0.0)
	var shader: Shader = load("res://assets/shaders/water/water_toon.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	# The water_toon shader needs wave / normal / foam maps; procedural noise works well.
	mat.set_shader_parameter("wave_texture", _noise_tex(1, false))
	mat.set_shader_parameter("wave_normal_texture", _noise_tex(2, true))
	mat.set_shader_parameter("foam_texture", _noise_tex(3, false))
	water.material_override = mat
	add_child(water)

func _noise_tex(noise_seed: int, as_normal: bool) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.seed = noise_seed
	fn.frequency = 0.02
	nt.noise = fn
	nt.seamless = true
	nt.as_normal_map = as_normal
	return nt

# A sphere shaded by the stylized toon surface shader.
func _build_toon_object() -> void:
	var s := MeshInstance3D.new()
	s.mesh = SphereMesh.new()
	var shader: Shader = load("res://assets/shaders/stylized_toon.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	s.material_override = mat
	s.position = Vector3(0.0, 1.2, 3.5)
	add_child(s)

# A frosted-glass UI panel. The glass shader reads the screen behind the panel and refracts/
# blurs it; the panel's stylebox alpha drives the edge highlight (that's why we use the kit's
# border-blend stylebox). Some bright text sits behind it so the effect is visible.
func _build_glass_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var behind := Label.new()
	behind.text = "GLASS  UI  SHADER"
	behind.add_theme_font_size_override("font_size", 48)
	behind.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
	behind.position = Vector2(110.0, 150.0)
	layer.add_child(behind)

	var panel := Panel.new()
	panel.position = Vector2(80.0, 90.0)
	panel.size = Vector2(420.0, 240.0)
	var stylebox: StyleBox = load("res://assets/shaders/ui/glass_base_stylebox.tres")
	if stylebox != null:
		panel.add_theme_stylebox_override("panel", stylebox)
	var gshader: Shader = load("res://assets/shaders/ui/glass_panel.gdshader")
	var gmat := ShaderMaterial.new()
	gmat.shader = gshader
	panel.material = gmat
	layer.add_child(panel)
