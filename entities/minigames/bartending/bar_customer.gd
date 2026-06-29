# bar_customer.gd
# A bartending CUSTOMER — now a real NPC (extends NPC) so it has a PSX, Mixamo-animated body
# built from an NPCDefinition the shift hands it (random miner / townsfolk from Bartending's
# patron pool). The NPC base gives us the body + walk/idle animation + facing; this subclass
# overrides _physics_process to drive simple point-to-point movement directly (so we don't have
# to wrangle the schedule/state machine), and runs the bartending BRAIN:
#
#   APPROACHING    walk from the door to a counter spot
#   AWAITING_ORDER stand at the counter; the player must TALK to take the order (aim + E). The
#                  customer says a little line and reveals what they want. Patience ticks here too.
#   AWAITING_DRINK wait for the matching drink; aim + E with the right glass serves them.
#   DRINKING       served! step aside to a drinking spot and nurse the drink a few seconds…
#   LEAVING        …then walk to the exit and despawn.
#
# Patience (Bartending.patience_seconds — generous, easy for new bartenders) drains while waiting;
# if it empties they leave unhappy (patience_ran_out -> the shift dings satisfaction).
extends NPC

signal patience_ran_out(customer)

enum Phase { APPROACHING, AWAITING_ORDER, AWAITING_DRINK, DRINKING, LEAVING }

# Set by the shift via setup_customer() BEFORE add_child (so NPC._ready sees `definition`).
var drink: int = 0
var counter_spot: Vector3 = Vector3.ZERO
var drink_spot: Vector3 = Vector3.ZERO
var exit_spot: Vector3 = Vector3.ZERO
var _patience_secs: float = 32.0
var _salt: int = 0

var _shift: Node = null
var _phase: int = Phase.APPROACHING
var patience: float = 1.0
var _drink_timer: float = 0.0
var _move_target: Vector3 = Vector3.ZERO
var _moving: bool = false

# Floating UI built above the head once the body exists.
var _order_label: Label3D
var _patience_mesh: MeshInstance3D
var _patience_mat: StandardMaterial3D
var _speech_label: Label3D
var _speech_t: float = 0.0

func setup_customer(shift: Node, def: Resource, drink_type: int, counter: Vector3, drink_pos: Vector3, exit_pos: Vector3, patience_secs: float, salt: int) -> void:
	_shift = shift
	definition = def
	drink = drink_type
	counter_spot = counter
	drink_spot = drink_pos
	exit_spot = exit_pos
	_patience_secs = patience_secs
	_salt = salt

func _ready() -> void:
	super._ready()  # NPC: build the PSX/Mixamo body from `definition`, state machine, idle
	_build_customer_ui()
	patience = 1.0
	_phase = Phase.APPROACHING
	_move_to(counter_spot)

# Drive movement ourselves (point-to-point) so we don't fight the NPC schedule/state machine,
# but route it through the NPC's nav_step() so we PATH the bar's navmesh — walking AROUND tables
# and chairs instead of shoving into them (it falls back to a straight line if no navmesh exists).
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	if _moving:
		# nav_step sets our horizontal velocity toward the next path point (and faces it), and
		# returns true once we've arrived at the destination.
		if nav_step(delta, walk_speed):
			_moving = false
			stop()
			play_anim(&"idle")
			_on_arrived()
		else:
			play_anim(&"walk")
	else:
		stop()
	_apply_turn(delta)
	move_and_slide()

func _process(delta: float) -> void:
	if _speech_t > 0.0:
		_speech_t -= delta
		if _speech_t <= 0.0 and _speech_label != null:
			_speech_label.visible = false
	match _phase:
		Phase.AWAITING_ORDER, Phase.AWAITING_DRINK:
			patience -= delta / maxf(0.1, _patience_secs)
			_update_patience_visual()
			if patience <= 0.0:
				patience = 0.0
				_leave_angry()
		Phase.DRINKING:
			_drink_timer -= delta
			if _drink_timer <= 0.0:
				_start_leaving()

func _move_to(pos: Vector3) -> void:
	_move_target = pos
	set_destination(pos)   # feed the NavigationAgent so nav_step() can path the navmesh
	_moving = true

func _on_arrived() -> void:
	match _phase:
		Phase.APPROACHING:
			_phase = Phase.AWAITING_ORDER
			_face_toward(global_position + Vector3(1.0, 0.0, 0.0))  # face the bar (+X)
			_order_label.text = "?"
			_order_label.visible = true
			_patience_mesh.visible = true
		Phase.DRINKING:
			_face_toward(global_position + Vector3(0.0, 0.0, 1.0))  # face out into the room
		Phase.LEAVING:
			queue_free()

func is_waiting() -> bool:
	return _phase == Phase.AWAITING_DRINK

# --- Interaction (duck-typed; overrides the NPC's dialogue interaction) -----

func get_interaction_prompt() -> String:
	match _phase:
		Phase.AWAITING_ORDER:
			return "Take %s's order" % npc_name
		Phase.AWAITING_DRINK:
			return "Serve %s" % Bartending.order_text(drink)
		_:
			return ""

func interact(player) -> void:
	match _phase:
		Phase.AWAITING_ORDER:
			if player is Node3D:
				_face_toward((player as Node3D).global_position)
			_take_order()
		Phase.AWAITING_DRINK:
			if _shift != null and _shift.has_method("try_serve_customer"):
				_shift.try_serve_customer(self)
		_:
			pass

func _take_order() -> void:
	_phase = Phase.AWAITING_DRINK
	_order_label.text = Bartending.order_text(drink)
	_order_label.visible = true
	_say(Bartending.order_line(drink, _salt))

## Called by the shift on a successful serve — thank the player, step aside, drink, then leave.
func served() -> void:
	_say("Thanks, barkeep.")
	_phase = Phase.DRINKING
	_drink_timer = Bartending.drink_seconds()
	_order_label.visible = false
	_patience_mesh.visible = false
	_move_to(drink_spot)

func _leave_angry() -> void:
	if _phase == Phase.LEAVING:
		return
	_say("Forget it.")
	patience_ran_out.emit(self)
	_start_leaving()

func _start_leaving() -> void:
	_phase = Phase.LEAVING
	if _order_label != null:
		_order_label.visible = false
	if _patience_mesh != null:
		_patience_mesh.visible = false
	_move_to(exit_spot)

# --- Floating UI -----------------------------------------------------------

func _build_customer_ui() -> void:
	var head_h: float = (definition.target_height if definition != null else 1.8)
	_order_label = Label3D.new()
	_order_label.font_size = 48
	_order_label.pixel_size = 0.006
	_order_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_order_label.position = Vector3(0.0, head_h + 0.55, 0.0)
	_order_label.modulate = Color(1.0, 0.95, 0.6)
	_order_label.outline_size = 8
	_order_label.visible = false
	add_child(_order_label)

	_patience_mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.1)
	_patience_mesh.mesh = q
	_patience_mat = StandardMaterial3D.new()
	_patience_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_patience_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_patience_mat.albedo_color = Color(0.3, 0.9, 0.3)
	_patience_mesh.material_override = _patience_mat
	_patience_mesh.position = Vector3(0.0, head_h + 0.3, 0.0)
	_patience_mesh.visible = false
	add_child(_patience_mesh)

	_speech_label = Label3D.new()
	_speech_label.font_size = 32
	_speech_label.pixel_size = 0.005
	_speech_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speech_label.position = Vector3(0.0, head_h + 0.85, 0.0)
	_speech_label.modulate = Color(0.95, 0.95, 1.0)
	_speech_label.outline_size = 6
	_speech_label.visible = false
	add_child(_speech_label)

func _update_patience_visual() -> void:
	if _patience_mesh == null:
		return
	_patience_mesh.scale.x = maxf(0.02, patience)
	_patience_mat.albedo_color = Color(0.9, 0.3, 0.3).lerp(Color(0.3, 0.9, 0.3), patience)

func _say(text: String) -> void:
	if _speech_label == null:
		return
	_speech_label.text = text
	_speech_label.visible = true
	_speech_t = 3.0
