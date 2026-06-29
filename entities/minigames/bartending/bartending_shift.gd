# bartending_shift.gd
# The in-world BARTENDING SHIFT controller (M-D — the headline v1 mini-game). NOT a CanvasLayer
# overlay — an in-world first-person "job mode": the player works the bar with the normal aim + E
# interaction. BarJobStation spawns one of these into the bar when a shift starts; it tears itself
# down when the timer runs out.
#
# EACH SHIFT:
#  - WIRES the bar's real PROPS as interaction targets (bar_station.gd behaviour, duck-typed,
#    attached at runtime — see _wire_targets): the three GLASS models become grab targets, the
#    four BOTTLE models become pour sources (one drink each), and the TRASH CAN tips bad pours
#    out. Nothing greybox is spawned — the player aims at the actual models on the bar.
#  - Spawns a paced queue of CUSTOMERS — real NPCs (bar_customer.gd, PSX/Mixamo bodies from the
#    Bartending patron pool: miners + townsfolk). Each walks to the counter; the player must TALK
#    to take the order (they say a line), then pour + serve; served customers step aside, drink,
#    and leave.
#  - SERVE = right DRINK in the right GLASS: grab the correct glass, pour the matching bottle to
#    the line, serve. A HELD CUP shows in hand and fills as you hold E at the bottle; overfill
#    spills. The fill gauge sits where the hotbar normally is (the hotbar is hidden during the shift).
#  - PAY: cash + skill-scaled tip; trains the Bartending skill. CLEAN messes (Bus Tub auto-helps).
#  - ENDS when you CLOCK OUT at the register, or on the timer backstop: base wage, Barry
#    reputation, autosave, teardown.
extends Node3D

# --- Tunables (shift shape; balance later) ---------------------------------
const SHIFT_SECONDS: float = 120.0
const ARRIVAL_INTERVAL: float = 8.0             # gap between customer arrivals (eased a touch)
const MESS_SAT_PENALTY_PER_SEC: float = 0.015   # satisfaction drained per uncleaned mess / sec
const BUS_TUB_CLEAR_INTERVAL: float = 14.0      # Bus Tub upgrade: clears the oldest mess this often
const BARRY_REP_PER_SHIFT: int = 4

# Where customers stand at the counter (patron side, x < bartop). Up to 4 (the v1 ceiling).
const COUNTER_SPOTS: Array[Vector3] = [
	Vector3(2.6, 0.0, -3.0), Vector3(2.6, 0.0, 0.0), Vector3(2.6, 0.0, 3.0), Vector3(2.6, 0.0, 5.5),
]
# Where served customers go to nurse their drink (away from the counter, freeing the spot).
const DRINK_SPOTS: Array[Vector3] = [
	Vector3(-2.0, 0.0, -3.5), Vector3(-3.0, 0.0, 3.0), Vector3(0.0, 0.0, 5.0), Vector3(-5.0, 0.0, -1.0),
]
const SPAWN_POS: Vector3 = Vector3(-4.0, 0.0, 6.5)
const EXIT_POS: Vector3 = Vector3(-5.5, 0.0, 7.5)

const CUSTOMER_SCENE := "res://entities/minigames/bartending/bar_customer.tscn"
const STATION_SCRIPT := "res://entities/minigames/bartending/bar_station.gd"
const HELD_CUP_SCRIPT := "res://entities/minigames/bartending/bar_held_cup.gd"
const NPC_DEFINITION_SCRIPT := "res://global/npc/npc_definition.gd"

# The bar's prop models (children of the "Bar equiptment" node in barinside.tscn) we wire as
# interaction targets at shift start. Keyed by node name -> what they become.
const EQUIPMENT_NODE := "Bar equiptment"
const BOTTLE_DRINKS := {            # bottle model name -> Bartending.Drink it pours
	"wine-red": Bartending.Drink.RED_WINE,
	"wine-white": Bartending.Drink.WHITE_WINE,
	"whiskey-bottle": Bartending.Drink.WHISKEY,
	"bottle-Gin": Bartending.Drink.GIN,
}
const GLASS_KINDS := {              # glass model name -> Bartending.Glass it hands out
	"glass-tall": Bartending.Glass.TALL,
	"glass-short": Bartending.Glass.SHORT,
	"glass-wine": Bartending.Glass.WINE,
}
const TRASH_NODE := "trashcan"

# --- Runtime state ----------------------------------------------------------
var _player: Node = null
var _time_left: float = SHIFT_SECONDS
var _arrival_timer: float = 2.0
var _bus_timer: float = BUS_TUB_CLEAR_INTERVAL
var _earned: int = 0
var _satisfaction: float = 1.0
var _running: bool = true
var _salt: int = 0   # increments per customer for order-line variety + spot rotation

# The single glass the player is holding: {} = empty hands, else {has, glass:int, drink:int,
# fill:float}. A freshly-grabbed glass has drink == -1 (empty) until poured from a bottle.
var _held: Dictionary = {}

var _customers: Array = []     # active BarCustomer NPCs
var _messes: Array = []        # active mess BarStation nodes
var _occupied: Dictionary = {} # counter-spot index -> true while a customer holds it

# Scene props we wired as interaction targets, so we can un-wire them on teardown.
var _wired_glasses: Array = []  # glass StaticBody3D nodes we attached a script to
var _proxies: Array = []        # proxy bodies we built for the fbx bottle / trash props

# First-person held cup viewmodel + the player's combat viewmodel we hide during the shift.
var _held_cup: Node3D = null
var _viewmodel: Node = null

# HUD (code-built CanvasLayer, at the tree root — see _build_hud).
var _hud: CanvasLayer
var _time_label: Label
var _money_label: Label
var _hold_label: Label
var _fill_bar: ProgressBar
var _skill_label: Label
var _flash_label: Label
var _flash_t: float = 0.0
var _intro_label: Label

# Barry hand-off: he leaves when the shift starts and returns to his post when it ends.
var _barry: Node3D = null
var _barry_home: Transform3D
var _barry_layer: int = 1

func _ready() -> void:
	add_to_group("bartending_shift")  # so the job station won't start a second concurrent shift
	_player = get_tree().get_first_node_in_group("player")
	# Step the player behind the bar so the fixtures are reachable no matter the bar's pathing.
	if _player != null and _player is Node3D:
		(_player as Node3D).global_position = Vector3(4.2, 0.2, -1.0)
	# The job is played in-world (first person), not in a menu — keep the mouse captured for look.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Hide the combat hotbar while on shift (it reappears if the player opens their bag).
	if HUD != null and HUD.has_method("set_hotbar_suppressed"):
		HUD.set_hotbar_suppressed(true)
	# Put the combat held-item away for the WHOLE shift, so scrolling the hotbar never flashes a
	# weapon/tool in hand (the held cup is the only thing you hold while working).
	_hide_viewmodel()
	_wire_targets()
	_build_hud()
	# Barry hands the bar over with a line, then clears out (after the HUD's intro label exists).
	_send_barry_off()
	_flash("Shift started — talk to customers, then pour their drink. Clock out at the register when done.")

# --- Per-frame loop --------------------------------------------------------

func _process(delta: float) -> void:
	if not _running:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = 0.0
		_end_shift()
		return

	_arrival_timer -= delta
	if _arrival_timer <= 0.0:
		_arrival_timer = ARRIVAL_INTERVAL
		_try_spawn_customer()

	_prune_customers()
	_poll_pour(delta)

	_prune_messes()
	if not _messes.is_empty():
		_satisfaction = maxf(0.0, _satisfaction - MESS_SAT_PENALTY_PER_SEC * float(_messes.size()) * delta)
	if Bartending.has_upgrade("bus_tub"):
		_bus_timer -= delta
		if _bus_timer <= 0.0:
			_bus_timer = BUS_TUB_CLEAR_INTERVAL
			if not _messes.is_empty():
				_remove_mess(_messes[0])

	_update_hud(delta)

# --- Customers (real NPCs from the patron pool) ----------------------------

func _try_spawn_customer() -> void:
	if _customers.size() >= Bartending.max_concurrent():
		return
	var spot_index: int = _free_counter_spot()
	if spot_index == -1:
		return
	var drink: int = randi() % Bartending.DRINK_NAMES.size()
	var def: Resource = _make_patron_def(Bartending.random_patron())
	var drink_spot: Vector3 = DRINK_SPOTS[_salt % DRINK_SPOTS.size()]
	var cust: Node = (load(CUSTOMER_SCENE) as PackedScene).instantiate()
	cust.setup_customer(self, def, drink, COUNTER_SPOTS[spot_index], drink_spot, EXIT_POS, Bartending.patience_seconds(), _salt)
	cust.set_meta("spot_index", spot_index)
	cust.patience_ran_out.connect(_on_customer_angry)
	_occupied[spot_index] = true
	add_child(cust)
	cust.global_position = SPAWN_POS
	_customers.append(cust)
	_salt += 1

# Build a lightweight NPCDefinition for a patron archetype dict ({model, skin, name}). Empty id so
# the customer is anonymous (no quest marker / mood entry). Loaded by path (cold-cache safe).
func _make_patron_def(patron: Dictionary) -> Resource:
	var def: Resource = load(NPC_DEFINITION_SCRIPT).new()
	def.id = &""
	def.display_name = String(patron.get("name", "Patron"))
	def.model_scene = load(String(patron.get("model", "")))
	def.skin_texture = load(String(patron.get("skin", "")))
	def.target_height = 1.8
	def.move_speed = 2.2
	def.default_behavior = 0  # IDLE; our subclass drives movement directly
	return def

func _free_counter_spot() -> int:
	for i in range(mini(COUNTER_SPOTS.size(), Bartending.max_concurrent())):
		if not _occupied.get(i, false):
			return i
	return -1

func _prune_customers() -> void:
	for c in _customers.duplicate():
		if not is_instance_valid(c):
			_customers.erase(c)

func _release_spot(cust: Node) -> void:
	if cust.has_meta("spot_index"):
		_occupied[int(cust.get_meta("spot_index"))] = false

func _on_customer_angry(cust) -> void:
	_release_spot(cust)
	_satisfaction = maxf(0.0, _satisfaction - 0.1)
	_spawn_mess(cust.global_position + Vector3(0.6, 0.0, 0.0))  # they leave a mess behind
	_flash("A customer left unhappy…")

## Serve attempt (from a customer's interact while AWAITING_DRINK). Scores the pour, pays cash +
## tip, trains the skill, frees the held cup, and sends the customer off to drink.
func try_serve_customer(cust) -> void:
	if not _held.get("has", false):
		_flash("Grab a glass and pour first")
		return
	if int(_held.get("drink", -1)) == -1:
		_flash("That glass is empty — pour a drink first")
		return
	if int(_held["drink"]) != int(cust.drink):
		_flash("Wrong drink — they ordered %s" % String(Bartending.DRINK_NAMES.get(int(cust.drink), "?")))
		return
	if int(_held.get("glass", -1)) != Bartending.glass_for(int(cust.drink)):
		_flash("Wrong glass — %s goes in a %s glass" % [
			String(Bartending.DRINK_NAMES.get(int(cust.drink), "?")),
			String(Bartending.GLASS_NAMES.get(Bartending.glass_for(int(cust.drink)), "?"))])
		return
	var score: float = Bartending.score_pour(float(_held["fill"]))
	var pay: int = Bartending.payout_for(int(cust.drink), score, cust.patience)
	pay = int(round(float(pay) * (0.6 + 0.4 * _satisfaction)))  # a messy bar tips worse
	GameState.add_money(pay)
	_earned += pay
	Bartending.register_pour(Bartending.serve_xp(score))
	_release_spot(cust)
	cust.served()
	_clear_held_cup()
	_held = {}
	var quality: String = "Perfect pour!" if score >= 0.95 else ("Good" if score >= 0.5 else "Sloppy")
	_flash("%s  +$%d" % [quality, pay])

# --- Pour (hold-to-fill) ---------------------------------------------------

func _poll_pour(delta: float) -> void:
	if not _held.get("has", false):
		return
	if _player == null or not is_instance_valid(_player):
		return
	var ray = _player.get("interaction_raycast")
	if ray == null:
		return
	var target = ray.get_collider() if ray.is_colliding() else null
	if target == null or not target.has_method("is_pour_source") or not target.is_pour_source():
		return
	if not Input.is_action_pressed("interact"):
		return
	var bottle_drink: int = int(target.drink)
	var held_drink: int = int(_held.get("drink", -1))
	if held_drink == -1:
		# First pour into an empty glass: this bottle sets the drink (+ any pre-stocked head start).
		_held["drink"] = bottle_drink
		_held["fill"] = float(_held["fill"]) + Bartending.starting_fill()
		if _held_cup != null and is_instance_valid(_held_cup):
			_held_cup.set_drink(bottle_drink)
	elif held_drink != bottle_drink:
		# Already holds a different drink — don't mix. Tip it out (trash) and start fresh.
		_flash("That glass already has %s — tip it out first" % String(Bartending.DRINK_NAMES.get(held_drink, "?")))
		return
	_held["fill"] = float(_held["fill"]) + Bartending.pour_speed() * delta
	if float(_held["fill"]) > 1.0 + Bartending.fill_window():
		_spill(target.global_position)

func _spill(at: Vector3) -> void:
	_flash("Overpoured — spilled!")
	_spawn_mess(at + Vector3(-0.6, -0.9, 0.0))
	_clear_held_cup()
	_held = {}

# --- Stations (grab / clean / trash; pour sources are handled by _poll_pour) -

func station_interact(station, _player_node) -> void:
	match station.kind:
		&"grab":
			# A fresh, EMPTY glass of this type — the drink is set when you pour from a bottle.
			_held = {"has": true, "glass": int(station.glass), "drink": -1, "fill": 0.0}
			_spawn_held_cup(int(station.glass))
			_flash("Grabbed a %s glass" % String(Bartending.GLASS_NAMES.get(int(station.glass), "?")))
		&"clean":
			_remove_mess(station)
			_satisfaction = minf(1.0, _satisfaction + 0.08)
			_flash("Wiped it up")
		&"trash":
			if _held.get("has", false):
				_clear_held_cup()
				_held = {}
				_flash("Tipped it out — grab a fresh glass")
			else:
				_flash("Nothing to tip out")
		_:
			pass  # bottles (&"pour"): filled by holding E (see _poll_pour)

# --- First-person held cup -------------------------------------------------

func _spawn_held_cup(glass: int) -> void:
	_clear_held_cup()
	if _player == null or not _player.has_method("get_camera"):
		return
	var cam = _player.get_camera()
	if cam == null:
		return
	_hide_viewmodel()  # keep the combat held-item hidden (idempotent; already hidden at shift start)
	_held_cup = load(HELD_CUP_SCRIPT).new()
	cam.add_child(_held_cup)
	_held_cup.position = Vector3(0.26, -0.20, -0.42)
	_held_cup.rotation_degrees = Vector3(8.0, 0.0, -6.0)
	_held_cup.set_glass(glass)   # shape of the grabbed glass; it starts empty (no drink yet)
	_held_cup.set_fill(0.0)

func _clear_held_cup() -> void:
	if _held_cup != null and is_instance_valid(_held_cup):
		_held_cup.queue_free()
	_held_cup = null

# Find + hide the player's combat held-item viewmodel (weapon/tool in hand) for the shift.
# Idempotent; caches the node so _restore_viewmodel can re-show it at the end. While it's hidden,
# scrolling the (also-hidden) hotbar can't flash a tool — its rebuilt model lives under this
# hidden node, so it never renders.
func _hide_viewmodel() -> void:
	if _player == null or not _player.has_method("get_camera"):
		return
	var cam = _player.get_camera()
	if cam == null:
		return
	if _viewmodel == null:
		_viewmodel = _find_viewmodel(cam)
	if _viewmodel != null:
		_viewmodel.visible = false

# Find the player's HeldItemDisplay under the camera (duck-typed via apply_walk_bob).
func _find_viewmodel(cam: Node) -> Node:
	for c in cam.get_children():
		if c.has_method("apply_walk_bob"):
			return c
	return null

func _restore_viewmodel() -> void:
	if _viewmodel != null and is_instance_valid(_viewmodel):
		_viewmodel.visible = true
	_viewmodel = null

# --- Messes ----------------------------------------------------------------

func _spawn_mess(pos: Vector3) -> void:
	var mess: StaticBody3D = load(STATION_SCRIPT).new()
	mess.kind = &"clean"
	mess.shift = self
	mess.prompt = "Wipe up the mess"
	var mesh := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 0.7)
	mesh.mesh = q
	mesh.rotation_degrees = Vector3(-90.0, 0.0, 0.0)  # lay flat on the floor
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.35, 0.1, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	mess.add_child(mesh)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 0.3, 0.7)
	col.shape = box
	col.position = Vector3(0.0, 0.15, 0.0)
	mess.add_child(col)
	add_child(mess)
	mess.global_position = Vector3(pos.x, 0.05, pos.z)
	_messes.append(mess)

func _remove_mess(mess) -> void:
	if is_instance_valid(mess):
		_messes.erase(mess)
		mess.queue_free()

func _prune_messes() -> void:
	for m in _messes.duplicate():
		if not is_instance_valid(m):
			_messes.erase(m)

# --- Wiring the bar's real props as interaction targets --------------------
# No greybox: we attach bar_station.gd behaviour to the actual glass / bottle / trash models the
# player placed in barinside.tscn, reusing THEIR OWN collision shapes as the aim targets. Glass
# props are already StaticBody3D, so we attach the script directly; the bottle / trash props are
# plain fbx instances, so we build a small proxy body that borrows the model's collider. All of it
# is un-wired again on teardown (_unwire_targets) so the props are inert outside a shift.

func _wire_targets() -> void:
	var equip: Node = _find_equipment()
	if equip == null:
		push_warning("BartendingShift: '%s' node not found — no bar props to wire." % EQUIPMENT_NODE)
		return
	for glass_name in GLASS_KINDS:
		_wire_grab(equip.get_node_or_null(glass_name), int(GLASS_KINDS[glass_name]))
	for bottle_name in BOTTLE_DRINKS:
		_wire_pour(equip.get_node_or_null(bottle_name), int(BOTTLE_DRINKS[bottle_name]))
	_wire_trash(equip.get_node_or_null(TRASH_NODE))

# The "Bar equiptment" node holding the props lives in the bar scene (our parent world).
func _find_equipment() -> Node:
	var world: Node = get_parent()
	if world != null:
		var e: Node = world.get_node_or_null(EQUIPMENT_NODE)
		if e != null:
			return e
	var scene: Node = get_tree().current_scene
	return scene.get_node_or_null(EQUIPMENT_NODE) if scene != null else null

# A glass prop is already a StaticBody3D with its own collider — attach the script to IT so its
# real collision shape is what the player aims at.
func _wire_grab(node: Node, glass: int) -> void:
	if node == null or not (node is StaticBody3D):
		return
	node.set_script(load(STATION_SCRIPT))
	node.kind = &"grab"
	node.glass = glass
	node.drink = -1
	node.shift = self
	_wired_glasses.append(node)

# A bottle prop is a plain fbx instance — give it a proxy bar_station body that reuses the model's
# own CollisionShape3D, so aiming at the bottle pours its drink.
func _wire_pour(node: Node, drink: int) -> void:
	var proxy: Node = _make_proxy(node, &"pour")
	if proxy != null:
		proxy.drink = drink

func _wire_trash(node: Node) -> void:
	_make_proxy(node, &"trash")

# Build (and track) a proxy StaticBody3D under an fbx prop, borrowing the prop's own collision
# shape so the prop itself becomes the aim target. Returns the proxy (a bar_station) or null.
func _make_proxy(node: Node, kind: StringName) -> Node:
	if node == null or not (node is Node3D):
		return null
	var proxy: StaticBody3D = load(STATION_SCRIPT).new()
	proxy.kind = kind
	proxy.shift = self
	var col := CollisionShape3D.new()
	var src: CollisionShape3D = _find_collision_shape(node)
	if src != null and src.shape != null:
		col.shape = src.shape
		col.transform = src.transform
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(0.35, 0.6, 0.35)
		col.shape = box
		col.position = Vector3(0.0, 0.3, 0.0)
	proxy.add_child(col)
	node.add_child(proxy)   # child of the prop: shares its space, so the borrowed collider lines up
	_proxies.append(proxy)
	return proxy

func _find_collision_shape(node: Node) -> CollisionShape3D:
	for c in node.get_children():
		if c is CollisionShape3D:
			return c
	return null

# Restore the props to inert set-dressing when the shift ends (or the scene changes).
func _unwire_targets() -> void:
	for g in _wired_glasses:
		if is_instance_valid(g):
			g.shift = null
			g.set_script(null)
	_wired_glasses.clear()
	for p in _proxies:
		if is_instance_valid(p):
			p.queue_free()
	_proxies.clear()

# --- HUD (code-built CanvasLayer at the tree ROOT) -------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 7
	# UI must live at the tree ROOT, OUTSIDE SceneManager's low-res world SubViewport, or it
	# renders downscaled+upscaled into giant text. (See the bug we fixed earlier.)
	get_tree().root.add_child(_hud)

	# Top-right status panel: time / earnings / skill / flash messages.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-280, 16)
	panel.custom_minimum_size = Vector2(260, 0)
	_hud.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	margin.add_child(v)
	var title := Label.new()
	title.text = "The Flaming Pebble — Shift"
	title.add_theme_font_size_override("font_size", 16)
	v.add_child(title)
	_time_label = _hud_label(v, 14)
	_money_label = _hud_label(v, 14)
	_skill_label = _hud_label(v, 12)
	_flash_label = _hud_label(v, 14)
	_flash_label.modulate = Color(1.0, 0.9, 0.5)
	_flash_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Bottom-CENTRE pour panel — sits where the hotbar normally is (now hidden): the held glass +
	# its fill gauge, so the pour reads at the centre of the screen near your hands.
	var bottom := CenterContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -118.0
	bottom.offset_bottom = -18.0
	_hud.add_child(bottom)
	var pour_panel := PanelContainer.new()
	pour_panel.custom_minimum_size = Vector2(340, 0)
	bottom.add_child(pour_panel)
	var pmargin := MarginContainer.new()
	pmargin.add_theme_constant_override("margin_left", 14)
	pmargin.add_theme_constant_override("margin_top", 8)
	pmargin.add_theme_constant_override("margin_right", 14)
	pmargin.add_theme_constant_override("margin_bottom", 8)
	pour_panel.add_child(pmargin)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 4)
	pmargin.add_child(pv)
	_hold_label = Label.new()
	_hold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hold_label.add_theme_font_size_override("font_size", 15)
	pv.add_child(_hold_label)
	_fill_bar = ProgressBar.new()
	_fill_bar.max_value = 120.0
	_fill_bar.show_percentage = false
	_fill_bar.custom_minimum_size = Vector2(300, 18)
	pv.add_child(_fill_bar)
	var hint := Label.new()
	hint.text = "Right glass + right bottle — hold E to pour, stop near 100%"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.75, 0.75, 0.75)
	pv.add_child(hint)

	# A big centred subtitle for Barry's hand-off line at the start (a little cutscene beat).
	_intro_label = Label.new()
	_intro_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_intro_label.offset_top = 90.0
	_intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_label.add_theme_font_size_override("font_size", 28)
	_intro_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	_intro_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_intro_label.add_theme_constant_override("outline_size", 8)
	_intro_label.visible = false
	_hud.add_child(_intro_label)

func _hud_label(parent: Node, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l

func _update_hud(delta: float) -> void:
	if _hud == null:
		return
	_time_label.text = "Time: %ds" % int(ceil(_time_left))
	_money_label.text = "Earned: $%d" % _earned
	_skill_label.text = "Bartending Lv %d   Satisfaction %d%%" % [Bartending.level, int(round(_satisfaction * 100.0))]
	if _held.get("has", false):
		var fill: float = float(_held["fill"])
		var glass_name: String = String(Bartending.GLASS_NAMES.get(int(_held.get("glass", -1)), "?"))
		if int(_held.get("drink", -1)) == -1:
			_hold_label.text = "Holding: empty %s glass — pour from a bottle" % glass_name
		else:
			_hold_label.text = "Holding: %s in a %s glass  (%d%%)" % [
				String(Bartending.DRINK_NAMES.get(int(_held["drink"]), "?")), glass_name, int(round(fill * 100.0))]
		_fill_bar.visible = true
		_fill_bar.value = fill * 100.0
		# Keep the in-hand cup's liquid in sync with the fill.
		if _held_cup != null and is_instance_valid(_held_cup):
			_held_cup.set_fill(fill)
	else:
		_hold_label.text = "No glass — grab one behind the bar"
		_fill_bar.visible = false
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash_label.visible = true
	else:
		_flash_label.visible = false

func _flash(msg: String) -> void:
	if _flash_label != null:
		_flash_label.text = msg
	_flash_t = 2.5

# --- Barry hand-off (a little cutscene beat at shift start) -----------------

func _send_barry_off() -> void:
	_show_intro_line("Barry:  Alright, I'm off — don't mess it up, kid.")
	var world: Node = get_parent()
	if world == null:
		return
	_barry = world.get_node_or_null("Barry") as Node3D
	if _barry == null:
		_barry = _find_barry(world)
	if _barry == null:
		return
	_barry_home = _barry.global_transform
	if "collision_layer" in _barry:
		_barry_layer = int(_barry.collision_layer)
	_barry.process_mode = Node.PROCESS_MODE_DISABLED  # freeze the NPC controller for the walk
	var door: Vector3 = Vector3(-5.0, _barry.global_position.y, 8.0)
	var t: Tween = create_tween()
	t.tween_property(_barry, "global_position", door, 1.8).set_trans(Tween.TRANS_SINE)
	t.tween_callback(_hide_barry)

func _hide_barry() -> void:
	if is_instance_valid(_barry):
		_barry.visible = false
		if "collision_layer" in _barry:
			_barry.collision_layer = 0

func _find_barry(world: Node) -> Node3D:
	for c in world.get_children():
		var def = c.get("definition")
		if def != null and String(def.get("id")) == "barry":
			return c as Node3D
	return null

func _restore_barry() -> void:
	if _barry == null or not is_instance_valid(_barry):
		return
	_barry.visible = true
	_barry.global_transform = _barry_home
	if "collision_layer" in _barry:
		_barry.collision_layer = _barry_layer
	_barry.process_mode = Node.PROCESS_MODE_INHERIT

func _show_intro_line(text: String) -> void:
	if _intro_label == null:
		return
	_intro_label.text = text
	_intro_label.visible = true
	_intro_label.modulate.a = 1.0
	var t: Tween = create_tween()
	t.tween_interval(3.2)
	t.tween_property(_intro_label, "modulate:a", 0.0, 1.0)
	t.tween_callback(_hide_intro)

func _hide_intro() -> void:
	if is_instance_valid(_intro_label):
		_intro_label.visible = false

# --- Shift end -------------------------------------------------------------

## Clock out at the register — ends the shift immediately (the player chose to stop). Same payout
## path as the timer backstop running out.
func clock_out() -> void:
	if not _running:
		return
	_flash("Clocking out…")
	_end_shift()

func _end_shift() -> void:
	if not _running:
		return
	_running = false
	var wage: int = Bartending.base_wage()
	GameState.add_money(wage)
	_earned += wage
	var rep := get_node_or_null("/root/Reputation")
	if rep != null and rep.has_method("add_reputation"):
		rep.add_reputation(&"barry", BARRY_REP_PER_SHIFT)
	GameState.set_flag(&"worked_bar_shift", true)
	var qs := get_node_or_null("/root/QuestSystem")
	if qs != null and qs.has_method("mark_flag"):
		qs.mark_flag(&"worked_bar_shift")
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method("save_game"):
		sm.save_game(0)
	_flash("Shift over! Total earned: $%d" % _earned)
	_teardown.call_deferred()

func _teardown() -> void:
	for c in _customers:
		if is_instance_valid(c):
			c.queue_free()
	for m in _messes:
		if is_instance_valid(m):
			m.queue_free()
	await get_tree().create_timer(3.0).timeout
	queue_free()

# The HUD + held cup live outside our subtree (root / camera), so free them whenever this shift
# leaves the tree (normal end OR a scene change mid-shift); restore the hotbar, viewmodel + Barry.
func _exit_tree() -> void:
	if is_instance_valid(_hud):
		_hud.queue_free()
	_clear_held_cup()
	_unwire_targets()
	_restore_viewmodel()
	if HUD != null and HUD.has_method("set_hotbar_suppressed"):
		HUD.set_hotbar_suppressed(false)
	_restore_barry()
