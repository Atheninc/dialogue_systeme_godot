extends Node

# --------------------------------------------------
# DialogueManager.gd (Godot 4.4) — version patchée v6
# --------------------------------------------------
# • Callback différés → plus de récursion.
# • Texte + choix envoyés ensemble dans Conversation.
# • Journalisation détaillée (`debug_logs`).
# • ✅ FIX : fonctions manquantes (_on_line_ready etc.),
#            choose(), fin de fichier, `emit_signal`.
# --------------------------------------------------

# ---------------------------------------------------------------------------
#  SIGNALS
# ---------------------------------------------------------------------------
signal conversation_ready(conversation : Conversation)   # Flux principal

# Signaux legacy (toujours déclenchés pour compat)
signal line_ready(text : String)
signal choices_ready(choices : Array)
signal scene_finished(next_scene : String)

# ---------------------------------------------------------------------------
#  EXPORTS
# ---------------------------------------------------------------------------
@export var enable_auto_advance : bool       = false      # 🔄 Lecture auto (debug)
@export var debug_logs          : bool       = true       # 📣 Activer les logs détaillés
@export var variables           : Dictionary = {}
@export var scenes              : Dictionary = {}
@export var current_scene       : String     = ""
# Node qui émettra le signal "choice(int)"
@export var choice_signal_emitter : NodePath = NodePath()


@export var file_path : String
# ---------------------------------------------------------------------------
#  INTERNES
# ---------------------------------------------------------------------------
var scene_lines    : Array[String] = []    # Dialogue courant
var current_index  : int           = 0
var current_choices: Array         = []

# ---------------------------------------------------------------------------
#  OUTILS LOG ---------------------------------------------------------------
func _log(msg:String, cat:String="INFO") -> void:
	if debug_logs:
		print("[DM][%s] %s" % [cat, msg])

# ---------------------------------------------------------------------------
#  READY --------------------------------------------------------------------
func _ready() -> void:
	_log("Initialisation DialogueManager", "BOOT")

	parse_file(file_path)
	_connect_choice_signal()

	if enable_auto_advance:
		line_ready.connect(_on_line_ready)
		choices_ready.connect(_on_choices_ready)
		scene_finished.connect(_on_scene_finished)
		_log("Auto-advance activé", "BOOT")

	run_scene("intro")

func _connect_choice_signal() -> void:
	if choice_signal_emitter == NodePath():
		_log("Pas de choice_signal_emitter défini", "WARN")
		return
	var emitter := get_node(choice_signal_emitter)
	if emitter and emitter.has_signal("choice"):
		emitter.connect("choice", Callable(self, "_on_user_choice_selected"))
		_log("Connecté au signal choice de %s" % emitter.name, "BOOT")
	else:
		_log("Le nœud %s n’a pas de signal 'choice'" % emitter, "ERROR")

func _on_user_choice_selected(index : int) -> void:
	_log("Choix UI reçu → index %d" % index, "INPUT")
	choose(index)

# ---------------------------------------------------------------------------
#  PARSING ------------------------------------------------------------------
func parse_file(path : String) -> void:
	_log("Parsing du fichier %s" % path, "PARSE")
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open dialogue file: %s" % path)
		return

	var lines := file.get_as_text().split("\n")
	var current_block := ""

	for raw_line in lines:
		var line := raw_line.strip_edges()

		# ------------- ⬇️ PATCH : on saute les lignes vides
		if line == "":
			continue
		# ------------- ⬆️ PATCH

		# --------- Variable globale
		if line.begins_with("VAR "):
			var parts := line.substr(4).split("=", false)
			if parts.size() == 2:
				var name      := parts[0].strip_edges()
				var value_str := parts[1].strip_edges()
				if value_str.begins_with("\"") and value_str.ends_with("\""):
					value_str = value_str.substr(1, value_str.length() - 2)
				variables[name] = _parse_value(value_str)
				_log("VAR %s = %s" % [name, variables[name]], "PARSE")

		# --------- Nouveau bloc === scene ===
		elif line.begins_with("===") and line.ends_with("==="):
			current_block = line.substr(3, line.length() - 6).strip_edges()
			scenes[current_block] = [] as Array[String]
			_log("Scene détectée: %s" % current_block, "PARSE")

		# --------- Ligne de dialogue
		elif current_block != "":
			scenes[current_block].append(line)


func _parse_value(value : String):
	return float(value) if value.is_valid_float() else value

# ---------------------------------------------------------------------------
#  CONTRÔLE DES SCÈNES ------------------------------------------------------
func run_scene(scene_name : String) -> void:
	_log("Run scene → %s" % scene_name, "FLOW")
	current_scene  = scene_name
	scene_lines    = (scenes.get(scene_name, []) as Array[String])
	current_index  = 0
	_advance_scene()

func advance_scene() -> void:
	_advance_scene()

# ---------------------------------------------------------------------------
#  BOUCLE PRINCIPALE --------------------------------------------------------
func _advance_scene() -> void:
	_log("_advance_scene index=%d/%d" % [current_index, scene_lines.size()], "FLOW")
	while current_index < scene_lines.size():
		var line := scene_lines[current_index]
		_log("Analyse ligne: %s" % line, "FLOW")

		if line.begins_with("* ["):
			_collect_choices("")
			return
		elif line.begins_with("~"):
			_process_line(line)
			current_index += 1
			continue
		elif line.begins_with("->"):
			var next := line.substr(2).strip_edges()
			_log("Jump vers %s" % next, "FLOW")
			emit_signal("scene_finished", next)
			return
		else:
			var display_text := _interpolate_text(line)
			if current_index + 1 < scene_lines.size() and scene_lines[current_index + 1].begins_with("* ["):
				current_index += 1
				_collect_choices(display_text)
				return
			else:
				_emit_conversation(display_text, [])
				emit_signal("line_ready", display_text)
				current_index += 1
				return

# ---------------------------------------------------------------------------
#  COLLECTE DES CHOIX -------------------------------------------------------
func _collect_choices(dialogue_text : String) -> void:
	_log("Collecte des choix…", "CHOICE")
	current_choices = []

	while current_index < scene_lines.size() and scene_lines[current_index].begins_with("* ["):
		var choice_text := scene_lines[current_index].get_slice("[", 1).get_slice("]", 0)
		var option_lines : Array[String] = []
		current_index += 1

		while current_index < scene_lines.size() and (
			!scene_lines[current_index].begins_with("* [") and
			!scene_lines[current_index].begins_with("->")):
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
		_log("Ajout choix: %s → %s" % [choice_text, next_scene], "CHOICE")

	_emit_conversation(dialogue_text, current_choices)
	emit_signal("choices_ready", current_choices)

# ---------------------------------------------------------------------------
#  VARIABLES / EXPRESSIONS --------------------------------------------------
func _process_line(line : String) -> void:
	var expr := line.substr(1).strip_edges()
	var parts := expr.split("=", false)
	if parts.size() == 2:
		var var_name := parts[0].strip_edges()
		var rhs      := parts[1].strip_edges()
		variables[var_name] = _evaluate_expression(rhs)
		_log("Var set: %s = %s" % [var_name, variables[var_name]], "VAR")

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
#  EMISSION Conversation ----------------------------------------------------
func _emit_conversation(text : String, choices : Array) -> void:
	var conv := Conversation.new()
	conv.txt  = text
	conv.choix = [] as Array[Choice]

	for i in range(choices.size()):
		var c := Choice.new()
		c.id  = i
		c.txt = choices[i]["text"]
		conv.choix.append(c)

	_log("Emit Conversation: '%s' (%d choix)" % [text, conv.choix.size()], "EMIT")
	emit_signal("conversation_ready", conv)

# ---------------------------------------------------------------------------
#  CHOIX UTILISATEUR --------------------------------------------------------
func choose(index : int) -> void:
	_log("choose(%d)" % index, "INPUT")
	if index >= 0 and index < current_choices.size():
		for action in current_choices[index]["lines"]:
			_process_line(action)
		run_scene(current_choices[index]["next"])
	else:
		_log("Index choix invalide: %d" % index, "ERROR")

# ---------------------------------------------------------------------------
#  DEBUG AUTO-ADVANCE -------------------------------------------------------
func _on_line_ready(text : String) -> void:
	_log("Auto line_ready", "AUTO")
	call_deferred("_advance_scene")

func _on_choices_ready(choices : Array) -> void:
	_log("Auto choices_ready (pick 0)", "AUTO")
	call_deferred("choose", 0)

func _on_scene_finished(next_scene : String) -> void:
	pass
