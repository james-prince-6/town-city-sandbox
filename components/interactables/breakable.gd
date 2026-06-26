# breakable.gd
# A smashable crate / pot / barrel that plugs into the existing combat backbone.
# Put this on a StaticBody3D with two children:
#   - a Health node (components/health.gd)
#   - a HurtBox (components/hurt_box.gd) whose team = ENEMY, with a CollisionShape3D
# Because the HurtBox is on team ENEMY, the player's weapon HitBoxes (target_team =
# ENEMY) overlap and damage it exactly like a monster — no extra wiring per weapon.
#
# We connect HurtBox.hit -> Health.apply_damage here (the "owner connects hit"
# contract from hurt_box.gd), and Health.died -> _on_died. On death it spills a
# LootTable as physical WorldItems, plays a tiny shrink "pop", and frees itself.
#
# Optional persistence: give it a `break_id` and it remembers being smashed across
# revisits via a GameState flag, so a looted crate doesn't respawn full.
#
# Not interactable by E (you hit it with a weapon), so it deliberately does NOT
# implement get_interaction_prompt()/interact.

class_name Breakable
extends StaticBody3D

## Loot spilled on break (as WorldItems). May be null for an empty/decorative crate.
@export var loot: LootTable

## If set, remembers this crate as broken across scene reloads (GameState flag
## "breakable_broken/<break_id>"). Leave empty for crates that may respawn.
@export var break_id: StringName = &""

## Paths to the wired children. Defaults match the breakable.tscn template.
@export var health_path: NodePath = ^"Health"
@export var hurt_box_path: NodePath = ^"HurtBox"
## The visual that "pops" (shrinks) on break. Defaults to "Model".
@export var model_path: NodePath = ^"Model"

# Guards a second death from double-spilling.
var _broken: bool = false

func _ready() -> void:
	# Already smashed on a previous visit? Remove it before it's ever seen.
	if break_id != &"" and GameState.get_flag(_flag_name(), false):
		queue_free()
		return

	var hurt := get_node_or_null(hurt_box_path) as HurtBox
	var health := get_node_or_null(health_path)
	if hurt == null or health == null:
		push_warning("Breakable '%s': missing HurtBox or Health child." % name)
		return
	# Owner-connects-hit contract: route incoming damage into the Health pool.
	hurt.hit.connect(health.apply_damage)
	health.died.connect(_on_died)

func _flag_name() -> StringName:
	return StringName("breakable_broken/%s" % break_id)

# --- Death / loot ----------------------------------------------------------

func _on_died() -> void:
	if _broken:
		return
	_broken = true
	if break_id != &"":
		GameState.set_flag(_flag_name(), true)
	_spill_loot()
	_pop_and_free()

func _spill_loot() -> void:
	if loot == null:
		return
	var rolled: Dictionary = loot.roll()
	var origin: Vector3 = global_position + Vector3.UP * 0.4
	var index: int = 0
	for id: StringName in rolled.keys():
		var amount: int = rolled[id]
		if amount <= 0:
			continue
		# Spawn into the live scene so the drops outlive this freeing crate.
		WorldItem.spawn(id, amount, SceneManager.current_world(), origin, index)
		index += 1

# Quick shrink so the crate visibly "bursts" before disappearing, then free. We free
# from the tween callback rather than immediately so the pop is actually seen.
func _pop_and_free() -> void:
	# Stop taking further hits the instant it's broken.
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		col.set_deferred("disabled", true)
	var hurt := get_node_or_null(hurt_box_path) as HurtBox
	if hurt != null:
		hurt.set_deferred("monitoring", false)

	var model := get_node_or_null(model_path) as Node3D
	if model == null:
		queue_free()
		return
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(model, "scale", Vector3.ZERO, 0.18)
	tween.tween_callback(queue_free)
