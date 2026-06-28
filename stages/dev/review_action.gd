# review_action.gd
# DEV-ONLY interactable "button" for the Review Hub test bench. Aim + E to fire a debug
# action (bump reputation, skip a day, grant XP, give gear, hurt/heal the player, etc.) so
# you can exercise the systems that are otherwise slow to reach in a playtest. Each pillar
# is spawned by review_hub.gd with an `action` id + label. Not used outside the dev hub.
extends StaticBody3D

@export var action: StringName = &""
@export var label: String = ""

const NPCS := [&"marlo", &"sela", &"ember", &"gus", &"mira", &"pip"]

# Gear handed out by the "Give All Gear" button — every weapon/tool so you can test held
# viewmodels, swing/aim feel, and the new crafted tier in one go.
const GEAR := [
	&"radiant_sword", &"glow_staff", &"reinforced_pickaxe", &"glow_lamp",
	&"crystal_blade", &"obsidian_blade", &"greatsword", &"battle_axe", &"dagger",
	&"quarterstaff", &"crossbow", &"flame_wand", &"frost_wand", &"arcane_wand",
	&"war_hammer", &"round_shield", &"throwing_knife", &"fire_bomb", &"smoke_grenade",
]

func get_interaction_prompt() -> String:
	return label

func interact(_player: Node) -> void:
	match action:
		&"rep_up":
			for n in NPCS:
				Reputation.add_reputation(n, 25)
			_toast("+25 reputation to all NPCs (talk to them to see tier branches/discounts/gifts)")
		&"rep_down":
			for n in NPCS:
				Reputation.add_reputation(n, -40)
			_toast("-40 reputation to all NPCs (test HOSTILE branches)")
		&"day":
			Clock.advance_minutes(1440)
			_toast("Skipped a day (tasks expire, shop hours reset, day rollover)")
		&"time6":
			Clock.advance_minutes(360)
			_toast("+6 hours (watch the time-of-day sky tint)")
		&"xp":
			Progression.add_xp(250)
			_toast("+250 XP (level-up feedback + skill points)")
		&"gear":
			for id in GEAR:
				Inventory.add(id, 1 if not String(id).ends_with("knife") else 24)
			_toast("Granted every weapon/tool — drag onto the hotbar to test held models + feel")
		&"hurt":
			PlayerStats.take_damage(60.0)
			_toast("Took 60 damage (test healing: eat food, drink a potion, low-HP vignette)")
		&"heal":
			PlayerStats.heal(999.0)
			_toast("Fully healed")
		&"money":
			GameState.add_money(5000)
			_toast("+5000 coins")
		_:
			_toast("(unknown action)")

func _toast(text: String) -> void:
	var feed = get_node_or_null("/root/NotificationFeed")
	if feed != null and feed.has_method("notify"):
		feed.notify(text, Color(0.7, 0.9, 1.0))
	else:
		print("[review] ", text)
