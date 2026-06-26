# npc_definition.gd
# THE single place to author one custom NPC. Bundle everything a character needs
# — identity, look, how it moves, what it does all day, and which conversation it
# opens with — into one .tres data file, then drop the plain npc.tscn into a scene
# and assign this definition. No per-NPC scripts, no editing the scene's nodes.
#
# ─────────────────────────── HOW TO MAKE A NEW NPC ───────────────────────────
# 1. In FileSystem: Right-click -> New -> Resource -> NPCDefinition. Save it as
#    e.g. res://global/npc/definitions/baker.tres.
# 2. Fill it in:
#      - id            : a unique StringName, e.g. &"baker" (also its Reputation
#                        and NPCMoods key — keep it stable, it's saved against).
#      - display_name  : the name shown in the talk prompt / dialogue box.
#      - model_scene   : a Kenney rigged character .fbx (see npc_animator.gd).
#      - skin_texture  : optional recolor skin (one of the kit's Skins/*.png).
#      - target_height : metres tall (default 1.8).
#      - move_speed / turn_speed_degrees : how it walks and pivots.
#      - default_behavior : IDLE, WANDER, or SCHEDULE.
#      - schedule + home_location_id : a daily routine (only used in SCHEDULE mode,
#                        or by WorldLocation home anchoring).
#      - default_mood  : starting mood registered into NPCMoods (default &"neutral").
#      - dialogue      : the compiled .dialogue file this NPC talks from. All the
#                        branching that used to be a list of ConditionalDialogues —
#                        greet differently by mood / time of day / quest / reputation —
#                        now lives INSIDE that file as `if` conditions and cue jumps
#                        (see entities/npc/dialogue/*.dialogue). One file per character.
#      - dialogue_title : which cue in that file to open on (default "start").
# 3. Drop res://entities/npc/npc.tscn into your scene and set its `definition`
#    export to your .tres. Add WorldLocation markers if it has a schedule. Done —
#    the NPC self-configures (look, speed, schedule, mood) on _ready.
#
# Everything here is OPTIONAL/back-compatible: an npc.tscn with no definition keeps
# behaving exactly as before, using its own @export fields.

class_name NPCDefinition
extends Resource

## How the NPC behaves when not in a conversation.
enum Behavior {
	IDLE,      # stand at the spawn point
	WANDER,    # roam near the spawn point
	SCHEDULE,  # follow `schedule`, walking to WorldLocations by the Clock
}

@export_group("Identity")
## Stable unique id. Also this NPC's Reputation and NPCMoods key (e.g. &"baker").
@export var id: StringName = &""
## Name shown in the interaction prompt and as the default speaker name.
@export var display_name: String = "Villager"

@export_group("Visuals")
## Base rigged character mesh (a Kenney kit .fbx). Drives the animated body.
@export var model_scene: PackedScene
## Optional recolor skin applied to the body's albedo (kit Skins/*.png).
@export var skin_texture: Texture2D
## The model is uniformly scaled so it stands this many metres tall.
@export var target_height: float = 1.8

@export_group("Movement")
## Walking speed used both for schedule travel and wandering (m/s).
@export var move_speed: float = 2.2
## How fast the body pivots toward its heading (degrees/second).
@export var turn_speed_degrees: float = 480.0

@export_group("Behavior")
## What the NPC does when idle (no open conversation).
@export var default_behavior: Behavior = Behavior.IDLE
## Daily routine, used when default_behavior == SCHEDULE.
@export var schedule: NPCSchedule
## WorldLocation id this NPC calls home (its wander/anchor point).
@export var home_location_id: StringName = &""
## Mood this NPC starts in, registered into NPCMoods under `id`. (&"neutral" etc.)
@export var default_mood: StringName = &"neutral"

@export_group("Dialogue")
## The compiled .dialogue file this NPC talks from. Mood / time / quest / reputation
## branching lives inside the file as `if` conditions and cue jumps — one file per
## character (see entities/npc/dialogue/*.dialogue).
@export var dialogue: DialogueResource
## Which cue in `dialogue` to open on. Blank uses the file's first cue (conventionally
## `~ start`).
@export var dialogue_title: String = "start"
