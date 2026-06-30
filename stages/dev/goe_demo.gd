# Dev review scene for the GoE character: slowly spins the model and cycles every facial
# expression so you can eyeball the skin, rig and faces in-editor (F6).
extends Node3D
@onready var character: Node3D = $GoeCharacter
@onready var label: Label = $UI/Emotion
var _emos: Array = []
var _i: int = 0
var _t: float = 0.0
func _ready() -> void:
	$Sun.rotation_degrees = Vector3(-50, -35, 0)
	await get_tree().process_frame
	_emos = character.available_emotions()
	character.play_anim(&"walk")   # body loco (inert until the humanoid retarget reimport is done)
	if not _emos.is_empty():
		character.set_emotion(_emos[0]); _label(_emos[0])
func _process(d: float) -> void:
	character.rotate_y(d * 0.4)
	_t += d
	if _t >= 2.5 and not _emos.is_empty():
		_t = 0.0
		_i = (_i + 1) % _emos.size()
		character.set_emotion(_emos[_i]); _label(_emos[_i])
func _label(e) -> void:
	if label == null: return
	var loco: Array = character.built_clips()
	var loco_txt := ("walk/idle/run ✓" if not loco.is_empty() else "none yet — do the retarget reimport (docs §5)")
	label.text = "Expression: %s  (%d/%d)\nBody anim: %s" % [str(e), _i + 1, _emos.size(), loco_txt]
