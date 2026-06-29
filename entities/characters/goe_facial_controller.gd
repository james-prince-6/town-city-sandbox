# goe_facial_controller.gd
# Drives the GoE character's facial EXPRESSIONS (the `Anim*` blend shapes baked into the
# exported glTF). A single expression like "AnimHappy" lives on several meshes at once
# (body + eyebrows + teeth + tongue), so this controller indexes every blend shape across
# ALL of the character's MeshInstance3D meshes and moves the matching ones together.
#
# Usage:
#   var fc := GoeFacialController.new()
#   add_child(fc)            # or place it under the character scene
#   fc.setup(character_root) # scans the meshes
#   fc.set_emotion(&"happy") # smoothly blends to the happy face
#
# Expressions blend smoothly (lerp toward a target each frame) and an idle blink runs on
# top so the character never looks frozen. Blink owns the eyes-closed shapes; emotions
# never touch them, so the two channels don't fight.

class_name GoeFacialController
extends Node

## How fast expressions blend toward their target (per second; higher = snappier).
@export var blend_speed: float = 10.0
## Idle blink on/off, the random gap between blinks (seconds), and how long a blink takes.
@export var auto_blink: bool = true
@export var blink_interval: Vector2 = Vector2(2.5, 6.0)
@export var blink_duration: float = 0.12

## Semantic emotion -> { blend_shape_name: weight }. Each GoE `Anim*` shape is already a
## complete expression, so most are 1:1; tweak/combine here to taste. Names not present on
## a given character are silently ignored, so this map can be a superset.
const EMOTIONS := {
	&"neutral": {},
	&"happy": {&"AnimHappy": 1.0},
	&"smile": {&"AnimLightSmile": 1.0},
	&"grin": {&"AnimSmileFullFace": 1.0},
	&"sad": {&"AnimSad": 1.0},
	&"angry": {&"AnimAngry": 1.0},
	&"snarl": {&"AnimSnarlLeft": 1.0},
	&"afraid": {&"AnimAfraid": 1.0},
	&"fear": {&"AnimFear": 1.0},
	&"surprised": {&"AnimSurprise": 1.0},
	&"shock": {&"AnimShock": 1.0},
	&"disgust": {&"AnimDisgust": 1.0},
	&"confused": {&"AnimConfused": 1.0},
	&"concentrate": {&"AnimConcentrate": 1.0},
	&"excited": {&"AnimExcitement": 1.0},
	&"pain": {&"AnimPain": 1.0},
	&"scream": {&"AnimScream": 1.0},
	&"glare": {&"AnimGlare": 1.0},
	&"frown": {&"AnimFrown": 1.0},
	&"flirt": {&"AnimFlirting": 1.0},
}
## Blink shapes (owned by the blink channel, not emotions).
const BLINK_SHAPES := [&"AnimEyesClosedL", &"AnimEyesClosedR"]

# shape_name(StringName) -> Array of [MeshInstance3D, blend_shape_index]
var _registry: Dictionary = {}
# shape_name -> current / target weights (0..1) for the smooth blend.
var _current: Dictionary = {}
var _target: Dictionary = {}
var _ready_done: bool = false

# Blink state.
var _blink_timer: float = 0.0
var _blink_t: float = -1.0   # <0 = not blinking; 0..1 progress while blinking

## Scan a character subtree, indexing every blend shape on every MeshInstance3D so we can
## drive shapes by name across meshes. Safe to call again if the model is rebuilt.
func setup(root: Node) -> void:
	_registry.clear(); _current.clear(); _target.clear()
	_index_meshes(root)
	for name in _registry.keys():
		_current[name] = 0.0
		_target[name] = 0.0
	_ready_done = true
	_blink_timer = randf_range(blink_interval.x, blink_interval.y)

func _index_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.get_blend_shape_count():
				var sname: StringName = mi.mesh.get_blend_shape_name(i)
				if not _registry.has(sname):
					_registry[sname] = []
				(_registry[sname] as Array).append([mi, i])
	for c in node.get_children():
		_index_meshes(c)

# --- Public API ------------------------------------------------------------

## Blend to a semantic emotion (see EMOTIONS). `weight` scales the whole expression
## (0 = neutral, 1 = full). Clears any previous expression (blink is unaffected).
func set_emotion(emotion: StringName, weight: float = 1.0) -> void:
	for name in _target.keys():
		if name not in BLINK_SHAPES:
			_target[name] = 0.0
	var shapes: Dictionary = EMOTIONS.get(emotion, {})
	for sname in shapes.keys():
		if _target.has(sname):
			_target[sname] = clampf(float(shapes[sname]) * weight, 0.0, 1.0)

## Directly set one blend shape's target (for fine control / custom faces).
func set_shape(shape: StringName, weight: float) -> void:
	if _target.has(shape):
		_target[shape] = clampf(weight, 0.0, 1.0)

## Snap everything to neutral immediately (no blend).
func reset_immediate() -> void:
	for name in _current.keys():
		_current[name] = 0.0
		_target[name] = 0.0
	_apply()

## Trigger a single blink now.
func blink() -> void:
	if _blink_t < 0.0:
		_blink_t = 0.0

## The emotion names this character actually supports (present on its meshes).
func available_emotions() -> Array:
	var out: Array = []
	for e in EMOTIONS.keys():
		var ok := true
		var shapes: Dictionary = EMOTIONS[e]
		for s in shapes.keys():
			if not _registry.has(s): ok = false; break
		if ok and (e == &"neutral" or not shapes.is_empty()):
			out.append(e)
	return out

# --- Per-frame blend + blink ----------------------------------------------

func _process(delta: float) -> void:
	if not _ready_done:
		return
	var t: float = clampf(blend_speed * delta, 0.0, 1.0)
	for name in _current.keys():
		_current[name] = lerpf(_current[name], _target[name], t)
	_update_blink(delta)
	_apply()

func _update_blink(delta: float) -> void:
	if _blink_t >= 0.0:
		# Triangle 0->1->0 over blink_duration.
		_blink_t += delta / maxf(blink_duration, 0.01)
		if _blink_t >= 1.0:
			_blink_t = -1.0
		return
	if not auto_blink:
		return
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_t = 0.0
		_blink_timer = randf_range(blink_interval.x, blink_interval.y)

# Closed-ness for the blink shapes this frame (0..1).
func _blink_weight() -> float:
	if _blink_t < 0.0:
		return 0.0
	return 1.0 - absf(_blink_t * 2.0 - 1.0)

func _apply() -> void:
	var bw: float = _blink_weight()
	for name in _registry.keys():
		var w: float = _current.get(name, 0.0)
		if name in BLINK_SHAPES:
			w = maxf(w, bw)
		for pair in _registry[name]:
			var mi: MeshInstance3D = pair[0]
			if is_instance_valid(mi):
				mi.set_blend_shape_value(pair[1], w)
