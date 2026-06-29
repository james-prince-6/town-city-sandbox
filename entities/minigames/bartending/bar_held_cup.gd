# bar_held_cup.gd
# First-person held cup for the bartending job. The shift parents one of these under the player's
# camera while they're holding a glass, so the grabbed glass shows in hand — and the liquid RISES
# as you pour (set_fill), tinted to the drink (set_drink). The glass SHAPE matches which of the
# three glasses you grabbed (set_glass): a tall highball, a short tumbler, or a stemmed wine glass.
# It's a 3D viewmodel (not UI), so it lives in the world like the normal held-item display — no
# SubViewport issues. The shift hides the player's combat held-item while this is up.
extends Node3D

## Liquid colour per drink (Bartending.Drink: 0 red wine, 1 white wine, 2 whiskey, 3 gin).
const DRINK_COLORS: Dictionary = {
	0: Color(0.50, 0.05, 0.10),   # red wine — deep red
	1: Color(0.93, 0.90, 0.62),   # white wine — pale straw
	2: Color(0.60, 0.35, 0.12),   # whiskey — amber brown
	3: Color(0.85, 0.92, 0.96),   # gin — near-clear
}

# Per-glass geometry: bowl height / radii, and whether it sits on a stem (wine).
const GLASS_SHAPES: Dictionary = {
	0: {"height": 0.150, "top": 0.034, "bottom": 0.030, "stem": false},  # TALL highball
	1: {"height": 0.075, "top": 0.052, "bottom": 0.046, "stem": false},  # SHORT tumbler
	2: {"height": 0.090, "top": 0.050, "bottom": 0.028, "stem": true},   # WINE (stemmed)
}

var _glass: MeshInstance3D
var _glass_mesh: CylinderMesh
var _liquid: MeshInstance3D
var _liquid_mesh: CylinderMesh
var _liquid_mat: StandardMaterial3D
var _stem: MeshInstance3D
var _drink: int = -1
var _glass_type: int = 0
var _bowl_height: float = 0.12   # current bowl height, so set_fill scales the liquid correctly

func _ready() -> void:
	# The glass: a translucent tapered cylinder (the bowl).
	_glass = MeshInstance3D.new()
	_glass_mesh = CylinderMesh.new()
	_glass.mesh = _glass_mesh
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.8, 0.85, 0.9, 0.22)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.roughness = 0.05
	_glass.material_override = gmat
	add_child(_glass)

	# The liquid: a coloured cylinder inside the bowl, scaled in Y by the fill.
	_liquid = MeshInstance3D.new()
	_liquid_mesh = CylinderMesh.new()
	_liquid.mesh = _liquid_mesh
	_liquid_mat = StandardMaterial3D.new()
	_liquid.material_override = _liquid_mat
	add_child(_liquid)

	# The stem + foot (only shown for the wine glass): a thin cylinder below the bowl.
	_stem = MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.006
	sm.bottom_radius = 0.018
	sm.height = 0.07
	_stem.mesh = sm
	_stem.material_override = gmat
	_stem.visible = false
	add_child(_stem)

	set_glass(_glass_type)
	set_drink(_drink)
	set_fill(0.0)

## Shape the cup to the grabbed glass (Bartending.Glass).
func set_glass(glass: int) -> void:
	_glass_type = glass
	var s: Dictionary = GLASS_SHAPES.get(glass, GLASS_SHAPES[0])
	var h: float = float(s["height"])
	var top: float = float(s["top"])
	var bottom: float = float(s["bottom"])
	_bowl_height = h
	if _glass_mesh != null:
		_glass_mesh.top_radius = top * 1.04
		_glass_mesh.bottom_radius = bottom
		_glass_mesh.height = h
	if _liquid_mesh != null:
		_liquid_mesh.top_radius = top * 0.92
		_liquid_mesh.bottom_radius = bottom * 0.92
		_liquid_mesh.height = h
	# Stem: raise the bowl onto a stem for the wine glass; sit flat otherwise.
	var stemmed: bool = bool(s.get("stem", false))
	if _stem != null:
		_stem.visible = stemmed
		_stem.position.y = -h * 0.5 - 0.035
	var lift: float = (0.05 if stemmed else 0.0)
	if _glass != null:
		_glass.position.y = lift
	if _liquid != null:
		_liquid.position.y = lift

func set_drink(drink: int) -> void:
	_drink = drink
	if _liquid_mat != null:
		_liquid_mat.albedo_color = DRINK_COLORS.get(drink, Color(0.7, 0.7, 0.7, 0.5))

func set_fill(fill: float) -> void:
	if _liquid == null:
		return
	var f: float = clampf(fill, 0.0, 1.2)
	# An empty glass (no drink poured yet) shows no liquid.
	if f <= 0.001 or _drink < 0:
		_liquid.visible = false
		return
	_liquid.visible = true
	_liquid.scale.y = f
	# CylinderMesh is centred on its origin; raise the scaled liquid so its BOTTOM rests at the
	# bowl bottom (the bowl spans -h/2..+h/2 around the bowl's lift). Full liquid = bowl height.
	var lift: float = (_glass.position.y if _glass != null else 0.0)
	_liquid.position.y = lift - _bowl_height * 0.5 + (_bowl_height * f) * 0.5
