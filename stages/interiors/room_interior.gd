# room_interior.gd
# The reusable BASE every building interior is built on — the player's house, a shop's
# back room, a guild hall, a cosy cottage. It code-builds the empty shell that the old
# brewery_inside.tscn hand-authored: a floor, four perimeter walls, an optional ceiling, a
# WorldEnvironment with flat ambient light, a couple of lamps, the player, a "from_town"
# entry marker, and a "Leave" door that teleports back to town. Content agents then only
# write a thin subclass that sets a few members and overrides _furnish() to drop furniture
# and NPCs — they never touch geometry, lighting, the player, or the door wiring.
#
# HOW TO MAKE AN INTERIOR (the whole job for a content agent):
#   1. New script:  extends "res://stages/interiors/room_interior.gd"
#      (extend by PATH, not by `RoomInterior`, so it resolves in a cold headless cache.)
#   2. Set members. Either in _init():
#          func _init() -> void:
#              room_size = Vector2(20, 14)
#              floor_color = Color(0.4, 0.3, 0.22)
#              leave_target_spawn = &"from_house"
#              sign_text = "Home"
#      ...or override _ready(), set them, then call super() to run the build.
#   3. Override _furnish() and place things:
#          func _furnish() -> void:
#              place("res://assets/models/furniture/furniture-kit/bedSingle.fbx", Vector3(-7, 0, -5), 90.0)
#              place_npc("res://global/npc/defs/granny.tres", Vector3(4, 0, 2), 180.0)
#   4. Make a thin .tscn whose root carries the subclass script. Point a town-side
#      teleport's Target Scene Path at that .tscn, and add a Marker3D in town named to
#      match `leave_target_spawn` so leaving lands the player back at the door.
#
# SceneManager CONTRACT: the destination scene must contain its own Player AND a Marker3D
# named exactly "from_town" by the time the root _ready() returns. This base creates BOTH
# during _ready (before _furnish), so subclasses satisfy the contract for free.

class_name RoomInterior
extends Node3D

const PLAYER_SCENE := "res://entities/player/player.tscn"
const NPC_SCENE := "res://entities/npc/npc.tscn"
const DRESSER_SCRIPT := "res://entities/props/furniture_dresser.gd"
const TELEPORT_SCRIPT := "res://global/teleport area/teleport_raycast.gd"
const TOWN_SCENE := "res://stages/overworld/town_template.tscn"

## Interior floor footprint in metres (width = X, depth = Z). Walls sit on this perimeter.
@export var room_size: Vector2 = Vector2(16.0, 16.0)
## Height of the perimeter walls (and where the ceiling sits) in metres.
@export var wall_height: float = 4.0
## Floor albedo.
@export var floor_color: Color = Color(0.32, 0.27, 0.22, 1.0)
## Wall albedo.
@export var wall_color: Color = Color(0.46, 0.42, 0.38, 1.0)
## Build a ceiling slab at wall_height. Off for open-roof / skylit rooms.
@export var ceiling: bool = true
## Flat ambient light colour filling the room (no sky indoors).
@export var ambient_color: Color = Color(0.5, 0.5, 0.52, 1.0)
## Brightness of the room's lamp(s).
@export var light_energy: float = 2.5

# --- Environment quality preset (warm-intimate by default; safe no-op overrides) ---
# Read in _build_environment. Defaults keep the existing filmic interior look; glow/SSAO are
# opt-in so the base render is unchanged unless a subclass dials them. Each is a plain
# tunable, so an unset member just uses the default.

## Tonemap operator (see Environment.TONE_MAPPER_*). FILMIC by default — cosy, natural indoor
## colour. This preserves the previous hard-coded interior tonemap.
@export var tonemap_mode: int = Environment.TONE_MAPPER_FILMIC
## Tonemap exposure. <1 darkens for an intimate gloom; >1 lifts. 1.0 = neutral.
@export var tonemap_exposure: float = 1.0
## Enable bloom on bright pixels (lamp flares, emissive props). Off by default.
@export var glow_enabled: bool = false
## Glow strength when glow_enabled.
@export var glow_intensity: float = 0.6
## Enable screen-space ambient occlusion (soft contact shadows in corners). Off (perf).
@export var ssao_enabled: bool = false

# --- Lamp mood overrides ----------------------------------------------------

## Scales the WHOLE time-of-day lamp energy curve. >1 = a brighter room at every hour,
## <1 = dimmer/moodier. 1.0 = the base curve unchanged. Lets a subclass set overall mood
## without redefining keyframes.
@export var mood_brightness: float = 1.0
## Pushes the lamp colour warmer (>1, ruddier candlelight) or cooler (<1, bluer) at every
## hour. 1.0 = the base curve's hue unchanged. Subtle; stacks on top of the curve tint.
@export var mood_warmth: float = 1.0
## Town-side return marker the Leave door drops the player on (e.g. &"from_house").
@export var leave_target_spawn: StringName = &"from_town"
## Scene the Leave door teleports back to. Defaults to town; interiors that are reached from
## somewhere OTHER than town (e.g. a cabin tucked in a wild area) override this so leaving
## returns the player to where they came from, not the town hub.
@export var leave_target_scene: String = "res://stages/overworld/town_template.tscn"
## Optional label shown over the Leave door (e.g. "Home", "Exit"). Blank shows just "Leave".
@export var sign_text: String = ""
## Optional area name faded in on the entry title-card when this interior loads
## (e.g. "The Brewery"). Blank = no card (silent). Cosmetic; no gameplay effect.
@export var area_title: String = ""
## Optional one-line tagline shown under area_title on the title-card. Blank = title only.
@export var area_tagline: String = ""

# Set in _build_entry() so _furnish()/subclasses can reference the entry point if needed.
var _from_town_marker: Marker3D
var _dresser: FurnitureDresser

# The room lamp + its configured base energy, kept so dynamic mood lighting can
# re-blend colour/energy each minute from the UNTINTED base (never compounding).
var _lamp: OmniLight3D
var _base_lamp_energy: float = 0.0

# Interior mood keyframes [hour:float, tint:Color, energy_scale:float]. The lamp's
# base white * tint and base energy * scale give: cool-dim night, warm-bright
# morning, neutral day, warm-dim evening — so interiors feel time-aware. Wraps 24->0.
const _LAMP_KEYS := [
	[0.0, Color(0.58, 0.64, 0.86), 0.45],   # cool dim night
	[6.0, Color(1.04, 0.86, 0.70), 0.80],   # warm rising dawn
	[9.0, Color(1.04, 0.92, 0.80), 1.00],   # warm-bright morning
	[12.0, Color(1.0, 1.0, 1.0), 1.00],     # neutral day
	[17.0, Color(1.04, 0.88, 0.72), 0.88],  # warm late afternoon
	[20.0, Color(1.02, 0.78, 0.60), 0.62],  # warm-dim evening
	[23.0, Color(0.60, 0.66, 0.88), 0.45],  # cool dim night
	[24.0, Color(0.58, 0.64, 0.86), 0.45],  # wrap back to midnight
]

func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_walls()
	if ceiling:
		_build_ceiling()
	_build_lights()
	_build_entry()      # from_town marker + player (satisfies the SceneManager contract)
	_build_leave_door() # teleport back to town + sign
	_furnish()          # subclass hook — furniture / NPCs / stations
	# Fade the interior's name in over the scene crossfade (guarded, silent if blank).
	_announce_area()

# --- Virtual hook ----------------------------------------------------------

## Override in a subclass to place furniture, NPCs and stations. Empty in the base.
func _furnish() -> void:
	pass

# --- Authoring helpers (call these from _furnish) --------------------------

## Lazily create (once) and return the shared FurnitureDresser parented in this room.
func dresser() -> FurnitureDresser:
	if _dresser == null or not is_instance_valid(_dresser):
		var d: Node3D = load(DRESSER_SCRIPT).new()
		add_child(d)
		_dresser = d
	return _dresser

## Place a furniture model. Thin pass-through to the dresser (see furniture_dresser.gd).
## The Kenney furniture-kit is sized to real-world metres via nodes/root_scale=0.2 in each
## .fbx.import, so positions are authored for true sizes and scale=1.0 is correct; any scale
## arg here is a relative multiplier on that already-correct base.
func place(model_path: String, local_pos: Vector3, yaw_degrees: float = 0.0, scale: float = 1.0, collision: bool = true) -> Node3D:
	return dresser().place(model_path, local_pos, yaw_degrees, scale, collision)

## Instance an NPC from npc.tscn, assign its NPCDefinition (.tres) and drop it in the room.
## def_path : res:// path to an NPCDefinition .tres (the NPC self-configures from it).
## pos      : floor position (y is where the NPC's feet go; usually 0).
## yaw      : facing in degrees about Y.
## Returns the NPC node.
func place_npc(def_path: String, pos: Vector3, yaw: float = 0.0) -> Node3D:
	var packed := load(NPC_SCENE) as PackedScene
	if packed == null:
		push_warning("RoomInterior: could not load npc.tscn.")
		return null
	var npc: Node3D = packed.instantiate()
	var def: Resource = load(def_path)
	if def == null:
		push_warning("RoomInterior: could not load NPCDefinition '%s'." % def_path)
	else:
		npc.set("definition", def)
	add_child(npc)
	npc.global_position = pos
	npc.rotation_degrees = Vector3(0.0, yaw, 0.0)
	return npc

# --- Shell construction ----------------------------------------------------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = floor_color.darkened(0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_color
	env.ambient_light_energy = 1.0
	# Per-room quality preset (tonemap always; glow/SSAO opt-in so the base cost is unchanged).
	env.tonemap_mode = tonemap_mode
	env.tonemap_exposure = tonemap_exposure
	if glow_enabled:
		env.glow_enabled = true
		env.glow_intensity = glow_intensity
	if ssao_enabled:
		env.ssao_enabled = true
	we.environment = env
	add_child(we)

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	add_child(body)
	# Box is 1m thick; sink it so its TOP surface is at y = 0.
	var size := Vector3(room_size.x, 1.0, room_size.y)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Thick COLLIDER (top face still at y=0) so the player can't tunnel through on spawn
	# before the freshly-added body registers; the visible mesh below stays 1m.
	box.size = Vector3(room_size.x, 12.0, room_size.y)
	col.shape = box
	col.position = Vector3(0.0, -6.0, 0.0)
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.position = Vector3(0.0, -0.5, 0.0)
	mesh.material_override = _flat_material(floor_color, 0.9)
	body.add_child(mesh)

func _build_walls() -> void:
	var hw := room_size.x * 0.5
	var hd := room_size.y * 0.5
	var t := 0.5
	var cy := wall_height * 0.5
	# Long walls span X (full width); side walls span Z (full depth, overlapping corners).
	_add_wall("WallNorth", Vector3(0.0, cy, -hd), Vector3(room_size.x, wall_height, t))
	_add_wall("WallSouth", Vector3(0.0, cy, hd), Vector3(room_size.x, wall_height, t))
	_add_wall("WallEast", Vector3(hw, cy, 0.0), Vector3(t, wall_height, room_size.y))
	_add_wall("WallWest", Vector3(-hw, cy, 0.0), Vector3(t, wall_height, room_size.y))

func _add_wall(wall_name: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = wall_name
	add_child(body)
	body.position = center
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = _flat_material(wall_color, 1.0)
	body.add_child(mesh)

func _build_ceiling() -> void:
	var body := StaticBody3D.new()
	body.name = "Ceiling"
	add_child(body)
	body.position = Vector3(0.0, wall_height, 0.0)
	var size := Vector3(room_size.x, 0.5, room_size.y)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = _flat_material(wall_color.darkened(0.2), 1.0)
	body.add_child(mesh)

func _build_lights() -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "RoomLight"
	lamp.position = Vector3(0.0, wall_height - 0.6, 0.0)
	lamp.light_energy = light_energy
	# Reach the far corners of the room.
	lamp.omni_range = maxf(room_size.x, room_size.y) * 1.5
	lamp.shadow_enabled = true
	add_child(lamp)
	# Stash for dynamic mood lighting, then tint for the current hour + track time.
	_lamp = lamp
	_base_lamp_energy = light_energy
	_apply_mood_lighting()
	_connect_mood_lighting()

# --- Dynamic interior mood lighting -----------------------------------------

# Re-blend the room lamp's colour + energy from the configured base toward the
# current hour's mood (cool-dim night ... warm-bright morning ... warm-dim
# evening). Fully guarded: no lamp or no Clock = silent no-op (static lighting).
func _apply_mood_lighting() -> void:
	if _lamp == null or not is_instance_valid(_lamp):
		return
	var clock: Node = get_node_or_null("/root/Clock")
	var hour_f: float = 12.0
	if clock != null and clock.has_method("get_time_fraction"):
		var frac: float = clock.get_time_fraction()
		hour_f = frac * 24.0
	var sample: Array = _sample_lamp(hour_f)
	var tint: Color = sample[0]
	var scale: float = sample[1]
	# Apply the per-room mood overrides on top of the curve: warmth nudges the hue (boost red,
	# trim blue) and brightness scales the energy. Both default to 1.0 (no change).
	if not is_equal_approx(mood_warmth, 1.0):
		tint = Color(
			clampf(tint.r * mood_warmth, 0.0, 2.0),
			tint.g,
			clampf(tint.b / maxf(0.01, mood_warmth), 0.0, 2.0),
			tint.a)
	_lamp.light_color = tint
	_lamp.light_energy = _base_lamp_energy * scale * mood_brightness

# Connect once so the lamp drifts as in-game time advances. Guarded: if Clock is
# missing or signal-less, the room just keeps the load-time mood (still correct).
func _connect_mood_lighting() -> void:
	var clock: Node = get_node_or_null("/root/Clock")
	if clock == null or not clock.has_signal("time_changed"):
		return
	if not clock.time_changed.is_connected(_on_clock_time_changed):
		clock.time_changed.connect(_on_clock_time_changed)

func _on_clock_time_changed(_hour: int, _minute: int) -> void:
	_apply_mood_lighting()

# Override hook: return the [hour, tint, energy_scale] keyframe table this room samples its
# lamp mood from. The base returns the shared _LAMP_KEYS curve; a subclass can return its own
# table (e.g. a perpetual-night cellar or a sun-flooded conservatory) to fully reshape the
# day. MUST be ascending in hour and span 0..24. Falling back to the base curve is automatic
# if a subclass doesn't override.
func _lamp_curve() -> Array:
	return _LAMP_KEYS

# Interpolate [tint:Color, energy_scale:float] from the active lamp curve for a 0..24 hour,
# smoothstep-eased across each segment so the room brightens/dims smoothly.
func _sample_lamp(hour_f: float) -> Array:
	var keys: Array = _lamp_curve()
	if keys.is_empty():
		# Defensive: a subclass returned nothing — neutral white at full base energy.
		return [Color(1.0, 1.0, 1.0), 1.0]
	var h: float = clampf(hour_f, 0.0, 24.0)
	for i in range(keys.size() - 1):
		var lo: Array = keys[i]
		var hi: Array = keys[i + 1]
		var lo_h: float = lo[0]
		var hi_h: float = hi[0]
		if h >= lo_h and h <= hi_h:
			var span: float = maxf(0.0001, hi_h - lo_h)
			var t: float = smoothstep(0.0, 1.0, (h - lo_h) / span)
			var lo_c: Color = lo[1]
			var hi_c: Color = hi[1]
			var lo_s: float = lo[2]
			var hi_s: float = hi[2]
			return [lo_c.lerp(hi_c, t), lerpf(lo_s, hi_s, t)]
	var last: Array = keys[keys.size() - 1]
	var last_c: Color = last[1]
	var last_s: float = last[2]
	return [last_c, last_s]

# --- Area title-card announce -----------------------------------------------

# Fade the interior's name (+ optional tagline) in over the scene crossfade via
# the AreaTitleCard autoload. Reached defensively; silent when area_title is blank.
func _announce_area() -> void:
	if area_title.strip_edges() == "":
		return
	var card: Node = get_node_or_null("/root/AreaTitleCard")
	if card != null and card.has_method("show_card"):
		card.show_card(area_title, area_tagline)

func _build_entry() -> void:
	var hd := room_size.y * 0.5
	# Entry/exit live on the -Z (north) wall. Marker sits just inside it.
	var marker := Marker3D.new()
	marker.name = "from_town"
	add_child(marker)
	marker.position = Vector3(0.0, 1.0, -hd + 2.0)
	_from_town_marker = marker

	# The destination scene MUST own a Player by the end of _ready — build it now.
	var player: Node3D = (load(PLAYER_SCENE) as PackedScene).instantiate()
	add_child(player)
	player.global_position = marker.global_position

func _build_leave_door() -> void:
	var hd := room_size.y * 0.5
	# A teleport StaticBody flush against the entry wall, on layer 1 so the player can aim+E it.
	var gate := StaticBody3D.new()
	gate.name = "Leave"
	gate.set_script(load(TELEPORT_SCRIPT))
	gate.set("target_scene_path", leave_target_scene)
	gate.set("prompt_text", "Leave")
	gate.set("target_spawn_point", leave_target_spawn)
	add_child(gate)
	gate.position = Vector3(0.0, 1.25, -hd + 0.4)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 2.5, 0.6)
	col.shape = box
	gate.add_child(col)

	# A floating sign over the door so the exit is obvious.
	var label := Label3D.new()
	label.text = sign_text if sign_text != "" else "Leave"
	label.font_size = 64
	label.pixel_size = 0.006
	label.modulate = Color(1.0, 0.95, 0.8)
	label.outline_size = 12
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = false
	add_child(label)
	label.position = Vector3(0.0, 2.7, -hd + 0.45)

# --- Small utilities -------------------------------------------------------

func _flat_material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat
