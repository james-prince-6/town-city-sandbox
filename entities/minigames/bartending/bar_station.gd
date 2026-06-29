# bar_station.gd
# A tiny duck-typed interactable used for the bartending job's fixtures (M-D). It owns no logic —
# it just forwards the player's aim/E to the BartendingShift controller, which holds all the job
# state. The shift attaches this behaviour AT RUNTIME to the bar's scene props (the glass / bottle
# / trash-can models in barinside.tscn): glasses become &"grab" targets, the four bottles become
# &"pour" sources (one per drink), and the trash can becomes a &"trash" tip-out. Mess spots the
# shift spawns mid-shift are &"clean".
#
# Pour SOURCES (&"pour") are filled by HOLDING interact (the controller polls that each frame); the
# press still fires interact() once, which the controller treats as a no-op for sources.
extends StaticBody3D

## What this station is: &"grab" (pick up a glass), &"pour" (a bottle that pours one drink),
## &"trash" (tip a bad/wrong pour out), or &"clean" (a mess to wipe up).
var kind: StringName = &""
## For a &"pour" bottle, which drink it pours (Bartending.Drink). -1 otherwise.
var drink: int = -1
## For a &"grab" glass, which glass it hands out (Bartending.Glass). -1 otherwise.
var glass: int = -1
## The shift controller this station reports to. While null the station is inert (no prompt).
var shift: Node = null
## Prompt text shown when aimed at (used for &"clean" messes; the rest build it from kind).
var prompt: String = "Use"

func get_interaction_prompt() -> String:
	if shift == null:
		return ""
	match kind:
		&"grab":
			return "Grab a %s glass" % String(Bartending.GLASS_NAMES.get(glass, "?"))
		&"pour":
			return "Hold [E]: pour %s" % String(Bartending.DRINK_NAMES.get(drink, "?"))
		&"trash":
			return "Tip the glass out in the trash"
		_:
			return prompt

func interact(player) -> void:
	if shift != null and shift.has_method("station_interact"):
		shift.station_interact(self, player)

## True for the pour sources the controller fills while interact is held.
func is_pour_source() -> bool:
	return kind == &"pour"
