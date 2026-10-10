class_name Terminal
extends CodeEdit

var terminal_info = "Godot Terminal [Version 1.0]
Copyright (c) Trulle123 2026 - MIT License"

var prompt

var last_valid_text = ""
var working_dir
var last_working_dir

var commands: TerminalCommands

var entered_commands = []
var last_previewd_command = ""
var command_preview_i = 0

var highlighter: TerminalHighlighter
var colors = {}

const USER_README = "GODOT TERMINAL
--------------

- To change colors edit the hex codes in colors.json

- If you want to change the font, add a TTF font to this folder and call it font.ttf


!!! Don't touch entered_commands.save unless you know what you are doing !!!
"

func _ready() -> void:
	working_dir = get_home_dir()
	last_working_dir = working_dir
	
	if not FileAccess.file_exists("user://README.txt"):
		var readme_file = FileAccess.open("user://README.txt", FileAccess.WRITE)
		readme_file.store_string(USER_README)
		
	if not DirAccess.dir_exists_absolute("user://libs"):
		DirAccess.make_dir_absolute("user://libs")
	
	if FileAccess.file_exists("user://entered_commands.save"):
		var history_file = FileAccess.open("user://entered_commands.save", FileAccess.READ)
		entered_commands = history_file.get_var()
			
		if history_file.get_error() != OK or not entered_commands is Array:
			entered_commands = []
		
		if entered_commands is Array and entered_commands.size() > 500:
			entered_commands = entered_commands.slice(-500)
	else:
		var history_file = FileAccess.open("user://entered_commands.save", FileAccess.WRITE)
		history_file.store_var(entered_commands)
	
	if FileAccess.file_exists("user://colors.json"):
		var colors_file = FileAccess.open("user://colors.json", FileAccess.READ)
		colors = JSON.parse_string(colors_file.get_as_text())
	else:
		var def_colors_file = FileAccess.open("res://colors.json", FileAccess.READ)
		var def_colors_json = def_colors_file.get_as_text()
		
		var colors_file = FileAccess.open("res://colors.json", FileAccess.WRITE)
		colors_file.store_string(def_colors_json)
		colors_file.close()
		colors = JSON.parse_string(def_colors_json)
	
	if FileAccess.file_exists("user://font.ttf"):
		var font_data: PackedByteArray = FileAccess.get_file_as_bytes("user://font.ttf")
		var new_font = FontFile.new()
		new_font.data = font_data
		
		theme.set_font("font", "CodeEdit", new_font)
		
	highlighter = TerminalHighlighter.new(colors)
	syntax_highlighter = highlighter
	
	theme.set_color("caret_color", "CodeEdit", syntax_highlighter.colors["caret"])
	theme.set_color("font_color", "CodeEdit", syntax_highlighter.colors["white"])
	theme.set_color("font_selected_color", "CodeEdit", syntax_highlighter.colors["selected"])
	theme.set_color("selection_color", "CodeEdit", syntax_highlighter.colors["selection"])
	var current_style = theme.get_stylebox("normal", "CodeEdit").duplicate()
	current_style.bg_color = Color(syntax_highlighter.colors["bg"])
	theme.set_stylebox("normal", "CodeEdit", current_style)
	
	commands = TerminalCommands.new(self)
	var libs = DirAccess.get_files_at("user://libs")
	
	for lib in libs:
		commands.gdpt(["install", "user://libs".path_join(lib)], ["-t"], null)
	
	command_preview_i = entered_commands.size()
	prompt = get_prompt()
	text = get_startup() + "\n\n" + prompt
	last_valid_text = text
	
	highlighter.set_span_color(get_line_count() - 1, 0, prompt.length(), "green")
	
# handle enter presses
func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var last_line = get_line_count() - 1
		var locked_column = prompt.length()
		
		if event.keycode == KEY_BACKSPACE:
			if get_caret_line() < last_line:
				accept_event()
				return
			if get_caret_column() <= locked_column:
				accept_event()
				return
		
		elif event.keycode == KEY_DELETE:
			if get_caret_line() < last_line:
				accept_event()
				return
			
			if get_caret_column() < locked_column:
				accept_event()
				return
	
	if event.is_action_pressed("enter"):
		accept_event()
		
		var lines = text.split("\n")
		var current_command = lines[-1].substr(prompt.length())
			
		if entered_commands.is_empty() or entered_commands[-1] != current_command:
			entered_commands.append(current_command)
		
		await commands.execute(current_command)
		
		command_preview_i = entered_commands.size()
		last_previewd_command = ""
		
		if current_command == "clear":
			text += prompt
		else:
			text += "\n" + prompt
		
		highlighter.set_span_color(get_line_count() - 1, 0, prompt.length(), "green")
		
		last_valid_text = text
		
		if get_tree():
			await get_tree().process_frame
		set_caret_to_end()
	
	elif event.is_action_pressed("tab"):
		accept_event()
		
		var parts = text.split("\n")[-1].substr(prompt.length()).split(" ")
		var input_path = parts[-1]
		var path = commands.solve_path(input_path)
		var path_part = path.get_file()
		var path_dir = path.get_base_dir()
		
		if input_path == "" or input_path.ends_with("/"):
			path_dir = path
			path_part = ""
		
		var dirs = DirAccess.get_directories_at(path_dir)
		var files = DirAccess.get_files_at(path_dir)
		var both = dirs + files
		
		var matches = []
		
		for thing in both:
			if thing.to_lower().begins_with(path_part.to_lower()):
				matches.append(thing)
		
		if matches.size() == 1:
			var completion = matches[0]
			text = text.left(text.length() - path_part.length()) + completion
			
			if completion in dirs:
				text += "/"
			else:
				text += " "
		
		last_valid_text = text
		set_caret_to_end()
		
	elif event.is_action_pressed("up_arrow"):
		accept_event()
		
		var lines = text.split("\n")
		var current_command = lines[-1].substr(prompt.length())
		
		if entered_commands.size() > 0:
			if not last_previewd_command.is_empty():
				text = text.left(text.length() - current_command.length())
				
			command_preview_i = max(command_preview_i - 1, 0)
			
			last_previewd_command = entered_commands[command_preview_i]
			text += last_previewd_command
		
		set_caret_to_end()
		
	elif event.is_action_pressed("down_arrow"):
		accept_event()
		
		var lines = text.split("\n")
		var current_command = lines[-1].substr(prompt.length())
		
		if entered_commands.size() > 0:
			if not last_previewd_command.is_empty():
				text = text.left(text.length() - current_command.length())
				
			command_preview_i += 1
			
			if command_preview_i >= entered_commands.size():
				command_preview_i = entered_commands.size()
				last_previewd_command = ""
			else:
				last_previewd_command = entered_commands[command_preview_i]
				text += last_previewd_command
		
		set_caret_to_end()
	
	elif event.is_action_pressed("zoom_in"):
		theme.set_font_size("font_size", "CodeEdit", theme.get_font_size("font_size", "CodeEdit") + 1)
		theme.set_constant("caret_width", "CodeEdit", int((theme.get_font_size("font_size", "CodeEdit") + 1) * 0.625))
		
	elif event.is_action_pressed("zoom_out"):
		theme.set_font_size("font_size", "CodeEdit", theme.get_font_size("font_size", "CodeEdit") - 1)
		theme.set_constant("caret_width", "CodeEdit", int((theme.get_font_size("font_size", "CodeEdit") - 1) * 0.625))
	
	elif event.is_action_pressed("copy"):
		if has_selection():
			DisplayServer.clipboard_set(get_selected_text())
			set_caret_to_end()
	
	elif event.is_action_pressed("paste"):
		text += DisplayServer.clipboard_get()
		set_caret_to_end()

# revert the text to last "saved state"
func revert_text():
	text_changed.disconnect(_on_text_changed)
	
	var saved_col = get_caret_column()
	
	text = last_valid_text
	await get_tree().process_frame
	
	set_caret_line(get_line_count() - 1)
	set_caret_column(saved_col)
	
	text_changed.connect(_on_text_changed)

# when text chaged stop non allowed deleation
func _on_text_changed() -> void:
	var lines = text.split("\n")
	var current_line_i = get_caret_line()
	
	if current_line_i < lines.size() - 1:
		revert_text()
		return
	
	var last_line = lines[lines.size() - 1]
	if not last_line.begins_with(prompt):
		revert_text()
		return

func _on_caret_changed() -> void:
	if has_selection():
		theme.set_color("caret_color", "CodeEdit", Color(0.0, 0.0, 0.0, 0.0))
	else:
		theme.set_color("caret_color", "CodeEdit", syntax_highlighter.colors["caret"])

# helper to put the caret at text end
func set_caret_to_end() -> void:
	var lines = text.split("\n")
	set_caret_line(lines.size() - 1)
	set_caret_column(lines[-1].length())

func get_prompt():
	var user
	if OS.has_environment("USERNAME"):
		user = OS.get_environment("USERNAME")
	elif OS.has_environment("USER"):
		user = OS.get_environment("USER")
	
	var host = OS.get_environment("HOSTNAME")
	if host.is_empty():
		host = OS.get_environment("COMPUTERNAME")
	
	var full_prompt = (host + "@" + user + ":" + working_dir + "$ ").replace(get_home_dir(), "~")
	var drive_regex = RegEx.create_from_string("([A-Za-z]):/")
	full_prompt = drive_regex.sub(full_prompt, "/$1/", true)
		
	return full_prompt

func get_startup() -> String:
	var user
	if OS.has_environment("USERNAME"):
		user = OS.get_environment("USERNAME")
	elif OS.has_environment("USER"):
		user = OS.get_environment("USER")
	
	var host = OS.get_environment("HOSTNAME")
	if host.is_empty():
		host = OS.get_environment("COMPUTERNAME")
	
	var separator = ""
	for c in user + "@" + host:
		separator += "-"
	
	var lines = [
		terminal_info,
		"",
		user + "@" + host,
		"-".repeat((user + "@" + host).length()),
		"OS: " + OS.get_name() + " " + OS.get_version_alias() + " " + Engine.get_architecture_name(),
		"Host: " + host,
		"Libraries: " + str(DirAccess.get_files_at("user://libs").size()),
		"CPU: " + OS.get_processor_name(),
	]

	return "\n".join(lines)

# get users home dr
func get_home_dir():
	if OS.has_feature("windows"):
		return OS.get_environment("USERPROFILE").replace("\\", "/")
	else:
		return OS.get_environment("HOME")

# write output to self
func write_output(output, color="white"):
	var lines = output.split("\n", false)
	
	for line in lines:
		text += "\n" + line
		highlighter.set_line_color(get_line_count() - 1, color)

# sets the current working dir
func set_working_dir(path):
	last_working_dir = working_dir
	working_dir = path
	prompt = get_prompt()
	
# clears the terminal and resets the colors
func clear_and_reset_colors():
	text = ""
	highlighter.line_colors.clear()
	highlighter.span_colors.clear()
	highlighter.clear_highlighting_cache()
