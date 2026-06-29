# skill.gd
# A single node in the combat skill tree, defined as a data-driven Resource (.tres).
#
# Like Quest and Item, a Skill is a pure TEMPLATE: it holds NO runtime state (which
# rank you currently have lives in the Progression autoload, keyed by `id`). You author
# one .tres per skill in res://global/progression/skills/ and Progression scans that
# folder at startup into a database keyed by `id`. Drop a new Skill .tres in and it
# "just works" — no code edits, exactly like the quest loader.
#
# A skill belongs to one of three playstyle BRANCHES (Melee / Ranged / Survival). It can
# be a multi-rank passive STAT boost (most skills) or a one-rank unlockable PERK. Every
# rank costs `cost` skill points; you can buy it once the player reaches `required_level`
# and (if set) the `prerequisite` skill is at least `prerequisite_rank`.
#
# --- The stat-key vocabulary (keys of stat_per_rank) ------------------------------
# The float you put in stat_per_rank is added PER rank you own. Progression sums these
# across every allocated skill and exposes typed getters used by combat:
#
#   &"melee_damage_mult"        -> +X to the melee damage multiplier (getter returns 1.0 + sum)
#   &"ranged_damage_mult"       -> +X to the ranged damage multiplier (getter returns 1.0 + sum)
#   &"ranged_cooldown_reduction"-> fraction (0..1) shaved off ranged weapon cooldown
#   &"crit_chance"              -> +X to crit chance (0..1)
#   &"max_health"               -> +X FLAT to PlayerStats.max_health
#   &"max_stamina"              -> +X FLAT to PlayerStats.max_stamina
#   &"melee_lifesteal"          -> +X fraction (0..1) of melee damage healed back (Lifesteal)
#   &"damage_reduction"         -> +X fraction (0..0.9) of incoming damage ignored (Thick Skin)
#
# Perks (is_perk = true) usually carry no stat_per_rank; they flip a behaviour flag that
# combat code reads via Progression.has_perk(&"id"). Document any new key you add here.
#
# To create one: right-click in the FileSystem -> New Resource... -> Skill.

class_name Skill
extends Resource

## The playstyle branches / use-based skills the tree is organised into. APPEND-ONLY:
## existing .tres store this as an int, so never reorder or remove values. MAGIC (3) was
## added for the use-based rework (D1) — wand-casting levels its own skill.
enum Branch { MELEE, RANGED, SURVIVAL, MAGIC }

## Unique, stable string id used as the dictionary key in Progression and in save files.
## NEVER change this once a save references it. Example: "heavy_hands".
@export var id: StringName

## Human-friendly name shown in the skill tree UI. Safe to change anytime.
@export var display_name: String = "Untitled Skill"

## Flavor / what the skill does, shown under the name in the UI.
@export_multiline var description: String = ""

## Which playstyle column this skill lives in.
@export var branch: Branch = Branch.MELEE

## How many times this skill can be ranked up. 1 for a single unlock (typical for perks),
## higher for a scaling passive (e.g. 5 ranks of +12% damage).
@export var max_rank: int = 1

## Skill points spent PER rank purchased.
@export var cost: int = 1

## Minimum player level before this skill can be allocated at all.
@export var required_level: int = 1

## Another skill's id that must be owned first, or &"" for no prerequisite.
@export var prerequisite: StringName = &""

## The rank the prerequisite skill must be at before this one unlocks.
@export var prerequisite_rank: int = 1

## True for special unlockable abilities (cleave, piercing shot, second wind...) as
## opposed to plain stat passives. Combat code checks ownership via Progression.has_perk().
@export var is_perk: bool = false

## stat-key (StringName) -> float added PER rank. See the header for the recognised keys.
## Example: {&"melee_damage_mult": 0.12}.
@export var stat_per_rank: Dictionary = {}
