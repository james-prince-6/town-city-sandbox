# player.gd
# Updated to use the new InteractionUI script for dynamic prompts.
extends CharacterBody3D

@export_group("Movement")
@export var speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export_group("Look")
@export var mouse_sensitivity: float = 0.25

# --- Node References ---
@onready var head = $Head
@onready var interaction_raycast = $Head/Camera3D/InteractionRayCast
@onready var dialogue_ui = $DialogueUI
@onready var interaction_ui = $InteractionUI # This node now has the interaction_ui.gd script

# --- State Variables ---
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_in_dialogue = false

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	dialogue_ui.hide()
	interaction_ui.hide_prompt() 

func _unhandled_input(event):
	if not is_in_dialogue and event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		head.rotate_x(deg_to_rad(-event.relative.y * mouse_sensitivity))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-90), deg_to_rad(90))

func _physics_process(delta):
	if not is_in_dialogue:
		handle_movement(delta)
	
	handle_interaction()

func handle_movement(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity
	var current_speed = sprint_speed if Input.is_action_pressed("sprint") else speed
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	move_and_slide()

func handle_interaction():
	if interaction_raycast.is_colliding():
		var collider = interaction_raycast.get_collider()
		# Check if the object has a prompt to give us
		if collider.has_method("get_interaction_prompt"):
			var prompt = collider.get_interaction_prompt()
			interaction_ui.show_prompt("[E] " + prompt)
		else:
			interaction_ui.hide_prompt()
	else:
		interaction_ui.hide_prompt()

	if Input.is_action_just_pressed("interact") and interaction_raycast.is_colliding():
		var collider = interaction_raycast.get_collider()
		if collider.has_method("interact"):
			collider.interact(self)

func on_start_dialogue(dialogue_text):
	is_in_dialogue = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	interaction_ui.hide_prompt()
	dialogue_ui.start_dialogue(dialogue_text)

func on_end_dialogue():
	is_in_dialogue = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	dialogue_ui.hide()
