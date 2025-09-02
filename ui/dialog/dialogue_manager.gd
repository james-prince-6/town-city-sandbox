# dialogue_manager.gd (v5 - Pause Fix)
# This version adds process_mode to allow input while paused.
# It also keeps the debugging print statements.

extends CanvasLayer

var current_dialogue: DialogueResource
var current_line_index: int = 0
var is_active: bool = false

# --- Define the full paths to your UI nodes here ---
# Adjust these paths if your scene tree structure is different.
const NAME_LABEL_PATH = "DialogueBox/VBoxContainer/NameLabel"
const DIALOGUE_LABEL_PATH = "DialogueBox/VBoxContainer/DialogueLabel"
const CHOICES_CONTAINER_PATH = "DialogueBox/VBoxContainer/ChoicesContainer"

func _ready():
	# This is the key fix: It allows this node to process input even when the game is paused.
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	hide()

func start_dialogue(dialogue: DialogueResource):
	print("--- Dialogue Initiated ---")
	if not dialogue:
		print("ERROR: start_dialogue was called with a null resource.")
		return
	
	print("Received dialogue resource: ", dialogue.resource_path)
	
	if dialogue.dialogue_lines.is_empty():
		print("ERROR: The 'dialogue_lines' array is empty. Cannot start dialogue.")
		end_dialogue()
		return
	
	print("Dialogue has ", dialogue.dialogue_lines.size(), " lines.")
	
	get_tree().paused = true
	is_active = true
	show()
	
	current_dialogue = dialogue
	current_line_index = 0
	_display_current_line()

func _unhandled_input(event: InputEvent):
	if not is_active: return
	
	var choices_container: VBoxContainer = get_node_or_null(CHOICES_CONTAINER_PATH)
	if not choices_container: return
	
	# The "ui_accept" action is typically Spacebar or Enter by default.
	if event.is_action_pressed("ui_accept") and choices_container.get_child_count() == 0:
		print("Advancing dialogue...")
		_advance_dialogue()

func _display_current_line():
	if not is_instance_valid(current_dialogue): return
	
	var name_label: Label = get_node_or_null(NAME_LABEL_PATH)
	var dialogue_label: RichTextLabel = get_node_or_null(DIALOGUE_LABEL_PATH)
	var choices_container: VBoxContainer = get_node_or_null(CHOICES_CONTAINER_PATH)
	
	if not name_label or not dialogue_label or not choices_container:
		push_error("DialogueManager could not find UI nodes at the specified paths. Check your scene tree and the paths in the script.")
		return

	var line_text = current_dialogue.dialogue_lines[current_line_index]
	print("Displaying line ", current_line_index, ": '", line_text, "'")
	
	if line_text.is_empty():
		print("WARNING: The current dialogue line is an empty string.")

	name_label.text = current_dialogue.speaker_name
	dialogue_label.text = line_text
	
	for child in choices_container.get_children():
		child.queue_free()
	
	if current_line_index == current_dialogue.dialogue_lines.size() - 1:
		print("Last line reached. Displaying choices (if any).")
		_display_choices()

func _advance_dialogue():
	current_line_index += 1
	if current_line_index < current_dialogue.dialogue_lines.size():
		_display_current_line()
	else:
		if not current_dialogue.player_choices or current_dialogue.player_choices.is_empty():
			end_dialogue()

func _display_choices():
	if not current_dialogue.player_choices:
		print("No choices to display.")
		return
	
	var choices_container: VBoxContainer = get_node_or_null(CHOICES_CONTAINER_PATH)
	if not choices_container: return

	print("Displaying ", current_dialogue.player_choices.size(), " choices.")
	for choice_resource in current_dialogue.player_choices:
		var new_button = Button.new()
		new_button.text = choice_resource.choice_text
		new_button.pressed.connect(_on_choice_selected.bind(choice_resource))
		choices_container.add_child(new_button)

func _on_choice_selected(choice: DialogueChoice):
	print("Player selected choice: '", choice.choice_text, "'")
	if choice.next_dialogue:
		start_dialogue(choice.next_dialogue)
	else:
		end_dialogue()

func end_dialogue():
	print("--- Dialogue Ended ---")
	
	# If dialogue is already inactive, do nothing to prevent strange loops.
	if not is_active:
		return

	# Mark as inactive first to prevent any re-entry into input functions.
	is_active = false

	# Hide the UI canvas first.
	hide()

	# Then, unpause the game.
	get_tree().paused = false

	print("Dialogue hidden. Game unpaused.")

	# Emit the finished signal for other scripts (like quests) to listen to.
	if is_instance_valid(current_dialogue):
		current_dialogue.emit_signal("finished")
		# Clear the reference to the dialogue resource to prevent memory leaks or reuse.
		current_dialogue = null
