extends Node

signal line_ready(text)
signal choices_ready(choices)
signal scene_finished(next_scene)

@export var variables = {}
@export var scenes = {}
@export var current_scene = ""

var scene_lines: Array[String] = []
var current_index: int = 0
var current_choices: Array = []

func _ready() -> void:
	parse_file("res://dialogue_api_client/dialogue_test.txt")
	line_ready.connect(_on_line_ready)
	choices_ready.connect(_on_choices_ready)
	scene_finished.connect(_on_scene_finished)
	run_scene("intro")

# ---------------------------
# Dialogue file parsing
# ---------------------------
func parse_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open dialogue file: %s" % path)
		return
	var lines := file.get_as_text().split("\n")
	var current_block := ""
	for raw_line in lines:
		var line := raw_line.strip_edges()
		if line.begins_with("VAR "):
			var parts := line.substr(4).split("=", false)
			if parts.size() < 2:
				continue
			var name := parts[0].strip_edges()
			var value := parts[1].strip_edges()
			if value.begins_with("\"") and value.ends_with("\""):
				value = value.substr(1, value.length() - 2)
			variables[name] = parse_value(value)
		elif line.begins_with("===") and line.ends_with("==="):
			current_block = line.substr(3, line.length() - 6).strip_edges()
			scenes[current_block] = []
		elif current_block != "":
			scenes[current_block].append(line)

func parse_value(value: String):
	if value.is_valid_float():
		return float(value)
	return value

# ---------------------------
# Scene execution
# ---------------------------
func run_scene(scene_name: String) -> void:
	if not scenes.has(scene_name):
		push_error("Scene '%s' not found in dialogue." % scene_name)
		return
	current_scene = scene_name
	scene_lines = scenes[scene_name]
	current_index = 0
	advance_scene()

func advance_scene() -> void:
	while current_index < scene_lines.size():
		var line := scene_lines[current_index]
		if line.begins_with("* ["):
			_gather_choices()
			return  # Wait for player choice
		elif line.begins_with("~"):
			process_line(line)
			current_index += 1
		elif line.begins_with("->"):
			var next := line.substr(2).strip_edges()
			emit_signal("scene_finished", next)
			return
		else:
			emit_signal("line_ready", interpolate_text(line))
			current_index += 1
			return  # Wait for player input

func _gather_choices() -> void:
	current_choices.clear()
	while current_index < scene_lines.size() and scene_lines[current_index].begins_with("* ["):
		var choice_text := scene_lines[current_index].get_slice("[", 1).get_slice("]", 0)
		current_index += 1
		var option_lines := []
		while current_index < scene_lines.size() and !scene_lines[current_index].begins_with("* [") and !scene_lines[current_index].begins_with("->"):
			option_lines.append(scene_lines[current_index])
			current_index += 1
		var next_scene := ""
		if current_index < scene_lines.size() and scene_lines[current_index].begins_with("->"):
			next_scene = scene_lines[current_index].substr(2).strip_edges()
			current_index += 1
		current_choices.append({
			"text": choice_text,
			"lines": option_lines,
			"next": next_scene
		})
	emit_signal("choices_ready", current_choices)

# ---------------------------
# Helpers
# ---------------------------
func process_line(line: String) -> void:
	var expr := line.substr(1).strip_edges()
	var parts := expr.split("=", false)
	if parts.size() != 2:
		return
	var var_name := parts[0].strip_edges()
	var rhs := parts[1].strip_edges()
	variables[var_name] = evaluate_expression(rhs)

func evaluate_expression(expr: String):
	var tokens := expr.split(" ")
	if tokens.size() == 3:
		var left := tokens[0]
		var op := tokens[1]
		var right := tokens[2]
		var left_val := variables.get(left, 0)
		var right_val := parse_value(right)
		match op:
			"+":
				return left_val + right_val
			"-":
				return left_val - right_val
			"*":
				return left_val * right_val
			"/":
				return left_val / right_val
	return parse_value(expr)

func interpolate_text(text: String) -> String:
	for key in variables.keys():
		text = text.replace("{" + key + "}", str(variables[key]))
	return text

func choose(index: int) -> void:
	if index < 0 or index >= current_choices.size():
		return
	for action in current_choices[index]["lines"]:
		process_line(action)
	var next_scene := current_choices[index]["next"]
	if next_scene != "":
		run_scene(next_scene)
	else:
		advance_scene()

# ---------------------------
# Signal handlers — *deferred* to avoid deep recursion
# ---------------------------
func _on_line_ready(text: String) -> void:
	print("[LINE] %s" % text)
	# In production you'd wait for the player's click here.
	call_deferred("advance_scene")

func _on_choices_ready(choices: Array) -> void:
	print("[CHOICES]")
	for i in range(choices.size()):
		print("%d. %s" % [i + 1, choices[i]["text"]])
	# Auto‑select first choice for testing
	call_deferred("choose", 0)

func _on_scene_finished(next_scene: String) -> void:
	print("[SCENE FINISHED] Going to: %s" % next_scene)
	call_deferred("run_scene", next_scene)
