# ui_sound.gd
# Autoload singleton (register as "UISound"). Gives the WHOLE UI a click sound with
# zero per-button wiring: it watches the scene tree and connects every BaseButton's
# `pressed` signal to a click, so any menu button — now or added later — plays a sound
# when pressed. Runs always (works while the game is paused, e.g. the pause menu).
extends Node

const VOLUME_DB: float = -6.0

var click_sounds: Array[AudioStream] = [
	preload("res://assets/audio/ui/click_a.ogg"),
	preload("res://assets/audio/ui/click_b.ogg"),
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Hook up buttons that already exist, then everything added afterwards.
	get_tree().node_added.connect(_on_node_added)
	_connect_existing(get_tree().root)

func _connect_existing(node: Node) -> void:
	if node is BaseButton:
		_hook(node)
	for c in node.get_children():
		_connect_existing(c)

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_hook(node)

func _hook(button: BaseButton) -> void:
	if not button.pressed.is_connected(_play_click):
		button.pressed.connect(_play_click)

func _play_click() -> void:
	if click_sounds.is_empty():
		return
	var stream: AudioStream = click_sounds[randi() % click_sounds.size()]
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = VOLUME_DB
	if AudioServer.get_bus_index(&"SFX") != -1:
		p.bus = &"SFX"
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
