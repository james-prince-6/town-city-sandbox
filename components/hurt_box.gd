# hurt_box.gd
# The "you can hit me here" volume. Drop a HurtBox (an Area3D with a collision
# shape) as a child of anything that can be damaged — the player, an enemy, a
# breakable. When an attacker's HitBox overlaps it, the HitBox calls take_hit(),
# which re-emits as the `hit` signal. The OWNER connects `hit` to its Health (or
# PlayerStats) to actually lose HP. Keeping the box separate from the Health lets a
# big enemy have several hurtboxes (e.g. a weak-point) feeding one health pool.
#
# `team` keeps friendly fire out: a HitBox only damages HurtBoxes whose team matches
# the HitBox's target_team. So a player swing (target_team = ENEMY) hits enemies but
# not the player, and an enemy attack (target_team = PLAYER) hits only the player.
#
# Collision setup: HurtBoxes and HitBoxes all sit on the default area layer/mask and
# find each other via area overlap; team is checked in code (see hit_box.gd).

class_name HurtBox
extends Area3D

## Which side this belongs to. Used by HitBox.target_team to filter friendly fire.
enum Team { PLAYER, ENEMY, NEUTRAL }

## Emitted when an attack lands. The owner connects this to apply the damage to its
## Health / PlayerStats (e.g. health.apply_damage(info)).
signal hit(info: DamageInfo)

## This hurtbox's side.
@export var team: Team = Team.ENEMY

## Called by a HitBox when it overlaps and the teams match. Just forwards the info;
## what the damage actually does is up to whatever the owner connected to `hit`.
func take_hit(info: DamageInfo) -> void:
	hit.emit(info)
	# Global game-feel (purely cosmetic): a hit landing triggers hitstop / camera
	# shake / optional hit sound, scaled by which side got hit. Guarded so the game
	# runs fine even if the CombatFeel autoload isn't registered.
	var feel = get_node_or_null("/root/CombatFeel")
	if feel != null:
		feel.report_hit(info, team)
