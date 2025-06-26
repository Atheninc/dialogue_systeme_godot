extends CanvasLayer
class_name DialogueWindow
@export var conv_dict: Conversation
@export var ChoiceButtonScene : PackedScene
@export var choice_box: VBoxContainer
@export var text_box: RichTextLabel

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass
	if conv_dict:
		display_conversation(conv_dict)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

# 🔄 Set a new conversation (call from parent)
func set_conversation(new_conv: Conversation) -> void:
	conv_dict = new_conv
	print(new_conv)
	display_conversation(conv_dict)

# 💬 Display or update UI (to be implemented)
func display_conversation(convo: Conversation) -> void:
	print(text_box)
	# Set the main dialogue text
	text_box.text = convo.txt

	# Clear previous buttons
	clear_choice_buttons()

	print("Conversation:", convo.txt)

	for choice in convo.choix:
		var button := ChoiceButtonScene.instantiate()
		
		if button is Button:
			button.text = choice.txt
			button.set_meta("id", choice.id)
			button.pressed.connect(_on_choice_pressed.bind(choice.id))
			choice_box.add_child(button)


func clear_choice_buttons() -> void:
	for child in choice_box.get_children():
		child.queue_free()
signal choice(choice_id: int)

func _on_choice_pressed(choice_id: int) -> void:
	for choice in conv_dict.choix:
		if choice.id == choice_id:
			print("You chose option ID:", choice_id, " → ", choice.txt)
			emit_signal("choice", choice_id)
			break

	
	# You can emit a signal to the parent if needed
