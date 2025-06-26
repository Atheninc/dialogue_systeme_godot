extends Node

# --------------------------------------------------
# DialogueManager.gd (Godot 4.4) — Connexion au choix
# --------------------------------------------------
# • Émet « conversation_ready(Conversation) » pour le front
# • Se connecte à un signal externe « user_choice_selected(int) »
#   qui véhicule l’ID du choix utilisateur.
#   → Dès réception : traite le choix, met à jour les variables,
#     lance la scène suivante et renvoie immédiatement le nouveau
#     signal « conversation_ready » / « scene_finished ».
# --------------------------------------------------

signal conversation_ready(conversation : Conversation)

# Signaux d’origine (toujours dispo pour debug / rétro-compat)
signal line_ready(text : String)
signal choices_ready(choices : Array)
signal scene_finished(next_scene : String)

# ---------------------------------------------------------------------------
#  EXPORTS
# ---------------------------------------------------------------------------
@export var variables            : Dictionary = {}
@export var scenes               : Dictionary = {}
@export var current_scene        : String    = ""
# Permet de brancher dans l’éditeur le node qui émettra
# « user_choice_selected(index:int) ».
@export var choice_signal_emitter: NodePath   = NodePath()

# ---------------------------------------------------------------------------
#  INTERNES
# ---------------------------------------------------------------------------
var scene_lines    : Array[String] = []
var current_index  : int           = 0
var current_choices: Array         = []

# ---------------------------------------------------------------------------
#  READY
# ---------------------------------------------------------------------------
func _ready() -> void:
	parse_file("res://dialogue_api_client/dialogue_test.txt")

	# Connexion au signal externe de choix utilisateur
	_connect_choice_signal()

	# Debug (à retirer en production)
	line_ready.connect(_on_line_ready)
	choices_ready.connect(_on_choices_ready)
	scene_finished.connect(_on_scene_finished)

	run_scene("intro")

func _connect_choice_signal() -> void:
	if choice_signal_emitter == NodePath():
		return
	var emitter := get_node(choice_signal_emitter)
	if emitter and emitter.has_signal("user_choice_selected"):
		emitter.connect("user_choice_selected", Callable(self, "_on_user_choice_selected"))

func _on_user_choice_selected(index : int) -> void:
	choose(index)   # Wrapper qui gère tout le flux

# ---------------------------------------------------------------------------
#  Chargement du fichier Ink-like
# ---------------------------------------------------------------------------
func parse_file(path : String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	var lines := file.get_as_text().split("\n")
	var current_block := ""

	for raw_line in lines:
		var line := raw_line.strip_edges()
		if line.begins_with("VAR "):
			var parts := line.substr(4).split("=", false)
			if parts.size() == 2:
				var name      := parts[0].strip_edges()
				var value_str := parts[1].strip_edges()
				if value_str.begins_with("\"") and value_str.ends_with("\""):
					value_str = value_str.substr(1, value_str.length() - 2)
				variables[name] = _parse_value(value_str)
		elif line.begins_with("===") and line.ends_with("==="):
			current_block = line.substr(3, line.length() - 6).strip_edges()
			scenes[current_block] = []
		elif current_block != "":
			scenes[current_block].append(line)

func _parse_value(value : String):
	return float(value) if value.is_valid_float() else value

# ---------------------------------------------------------------------------
#  Contrôle des scènes
# ---------------------------------------------------------------------------
func run_scene(scene_name : String) -> void:
	current_scene  = scene_name
	scene_lines    = scenes.get(scene_name, [])
	current_index  = 0
	_advance_scene()

# API publique pour avancer sans choix (clic « suivant », etc.)
func advance_scene() -> void:
	_advance_scene()

# ---------------------------------------------------------------------------
#  Boucle principale — lit jusqu’à devoir attendre le front
# ---------------------------------------------------------------------------
func _advance_scene() -> void:
	while current_index < scene_lines.size():
		var line := scene_lines[current_index]

		# --------- Bloc de CHOIX "* [ ..."
		if line.begins_with("* ["):
			_collect_choices()
			return   # On attend le signal user_choice_selected

		# --------- Ligne code « ~ »
		elif line.begins_with("~"):
			_process_line(line)
			current_index += 1
			continue  # Pas d’affichage, on boucle

		# --------- Jump « -> scene_name »
		elif line.begins_with("->"):
			var next := line.substr(2).strip_edges()
			emit_signal("scene_finished", next)
			return

		# --------- Dialogue standard
		else:
			var display_text := _interpolate_text(line)
			_emit_conversation(display_text, [])
			emit_signal("line_ready", display_text)  # legacy
			current_index += 1
			return  # On attend confirmation front

# ---------------------------------------------------------------------------
#  Collecte des choix + signal agrégé
# ---------------------------------------------------------------------------
func _collect_choices() -> void:
	current_choices = []

	while current_index < scene_lines.size() and scene_lines[current_index].begins_with("* ["):
		var choice_text := scene_lines[current_index].get_slice("[", 1).get_slice("]", 0)
		var option_lines : Array[String] = []
		current_index += 1

		while current_index < scene_lines.size() and \
				!scene_lines[current_index].begins_with("* [") and \
				!scene_lines[current_index].begins_with("->"):
			option_lines.append(scene_lines[current_index])
			current_index += 1

		var next_scene := ""
		if current_index < scene_lines.size() and scene_lines[current_index].begins_with("->"):
			next_scene = scene_lines[current_index].substr(2).strip_edges()
			current_index += 1

		current_choices.append({
			"text"  : choice_text,
			"lines" : option_lines,
			"next"  : next_scene
		})

	_emit_conversation("", current_choices)
	emit_signal("choices_ready", current_choices)  # legacy

# ---------------------------------------------------------------------------
#  Variables / expressions / interpolation
# ---------------------------------------------------------------------------
func _process_line(line : String) -> void:
	var expr := line.substr(1).strip_edges()
	var parts := expr.split("=", false)
	if parts.size() == 2:
		var var_name := parts[0].strip_edges()
		var rhs      := parts[1].strip_edges()
		variables[var_name] = _evaluate_expression(rhs)

func _evaluate_expression(expr : String):
	var tokens := expr.split(" ")
	if tokens.size() == 3:
		var left      := tokens[0]
		var op        := tokens[1]
		var right     := tokens[2]
		var left_val  = variables.get(left, 0)
		var right_val = _parse_value(right)
		match op:
			"+": return left_val + right_val
			"-": return left_val - right_val
			"*": return left_val * right_val
			"/": return left_val / right_val
	return _parse_value(expr)

func _interpolate_text(text : String) -> String:
	for key in variables.keys():
		text = text.replace("{" + key + "}", str(variables[key]))
	return text

# ---------------------------------------------------------------------------
#  Construction / émission Conversation
# ---------------------------------------------------------------------------
func _emit_conversation(text : String, choices : Array) -> void:
	var conv := Conversation.new()
	conv.txt  = text
	conv.choix = []

	for i in range(choices.size()):
		var c := Choice.new()
		c.id  = i
		c.txt = choices[i]["text"]
		conv.choix.append(c)

	emit_signal("conversation_ready", conv)

# ---------------------------------------------------------------------------
#  Choix (interne ou via signal)
# ---------------------------------------------------------------------------
func choose(index : int) -> void:
	if index >= 0 and index < current_choices.size():
		for action in current_choices[index]["lines"]:
			_process_line(action)
		run_scene(current_choices[index]["next"])

# ---------------------------------------------------------------------------
#  DEBUG auto-advance
# ---------------------------------------------------------------------------
func _on_line_ready(text : String) -> void:
	print("[LINE] ", text)
	_advance_scene()

func _on_choices_ready(choices : Array) -> void:
	print("[CHOICES]")
	for i in range(choices.size()):
		print(str(i + 1) + ". " + choices[i]["text"])
	choose(0)

func _on_scene_finished(next_scene : String) -> void:
	print("[SCENE FINISHED] → ", next_scene)
	run_scene(next_scene)
