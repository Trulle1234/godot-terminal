class_name TerminalCommands
extends RefCounted

const COMMAND_BLACKLIST = [
	"_init",
	"execute",
	"get_command_names",
	"parse_line",
	"handle_output",
	"solve_path",
	"handle_redirect",
	"output_to_text",
	"remove_recursive",
	"get_wc_text",
	"get_grep_text",
	"register_commands"
]

const COMMAND_INFO = {
	"pwd": "Print the current working directory",
	"cd": "Change the current working directory",
	"mkdir": "Create directory",
	"rmdir": "Remove empty directory",
	"ls": "List directory contents",
	"echo": "Output text",
	"touch": "Create empty file",
	"cat": "Print and concatenate file contents",
	"head": "Print first line of file",
	"tail": "Print last line of file",
	"wc": "Count lines, words and bytes",
	"sort": "Sort lines of text file",
	"grep": "Serch for a patter in file",
	"cp": "Copy file",
	"mv": "Move or rename file",
	"rm": "Remove file",
	"curl": "Send HTTP request to server",
	"gdpt": "Get libraries, locally or from server.",
	"uname": "Print system information",
	"whoami": "Print the current user",
	"clear": "Clear the terminal",
	"help": "Show command information",
	"history": "Show command history",
	"reset": "Resets the terminal",
	"colors": "Display all colors"
}

var terminal: Terminal

var command_registry = {}
var loaded_plugins = []

var command_info = {}

func _init(terminal_ref) -> void:
	terminal = terminal_ref
	register_commands(self, "terminal")

func execute(command_line) -> void:
	var history_file = FileAccess.open("user://entered_commands.save", FileAccess.WRITE)
	history_file.store_var(terminal.entered_commands)
	history_file.close()
	
	var lines = command_line.split(";")
	
	for line in lines:
		var pipeline = line.split("|")
		var pipe_input = null
		
		for i in range(pipeline.size()):
			var parts = parse_line(pipeline[i].strip_edges())
			if parts.is_empty():
				continue
			
			var command = parts[0]
			var args = parts.slice(1)
			
			if command not in command_registry:
				var solved_path = solve_path(command)
				var pid = -1
				
				if FileAccess.file_exists(solved_path):
					pid = OS.create_process(solved_path, args)
				
				if pid == -1:
					terminal.write_output(command + ": not found", "red")
					break
			else:
				var is_last = i == pipeline.size() - 1
				if is_last:
					await handle_output(args, command_registry[command], pipe_input)
				else:
					pipe_input =  await handle_output(args, command_registry[command], pipe_input, true)

func register_commands(instance, file_name):
	var script = instance.get_script()
	var blacklist = []
	
	if instance.has_method("get_command_blacklist"):
		blacklist = instance.get_command_blacklist()
	if instance.has_method("get_command_info"):
		command_info.merge(instance.get_command_info())
	
	for method in script.get_script_method_list():
		var name = method.name
		
		if name in blacklist or name == "get_command_blacklist" or name == "get_command_info":
			continue
		
		if name in command_registry:
			command_registry[file_name + "." + name] = Callable(instance, name)
		else:
			command_registry[name] = Callable(instance, name)
		
	terminal.highlighter.add_command_color(command_registry.keys(), "yellow")

func get_command_blacklist():
	return COMMAND_BLACKLIST

func get_command_info():
	return COMMAND_INFO

func parse_line(line):
	var regex = RegEx.create_from_string(r'"([^"]*)"|(\S+)')
	var parts = []
	
	for match in regex.search_all(line.strip_edges()):
		var quoted = match.get_string(1)
		
		if quoted != "":
			parts.append(quoted)
		else:
			parts.append(match.get_string(2))
	
	return parts

func handle_output(args, function, pipe_input=null, pipe=false):
	var options = []
	var new_args = []
	var parsing_options = true

	for arg in args:
		if parsing_options and arg == "--":
			parsing_options = false
		elif parsing_options and arg.begins_with("-"):
			options.append(arg)
		else:
			new_args.append(arg)

	args = new_args
	
	if handle_redirect(args, options, function, pipe_input):
		return
	
	var func_res = await function.call(args, options, pipe_input)
	
	if pipe:
		return output_to_text(func_res)
	
	if func_res is Array:
		if func_res.is_empty():
			return
		
		if func_res[0] is Array:
			for item in func_res:
				if item is Array and item.size() >= 2:
					terminal.write_output(item[0], item[1])
		else:
			terminal.write_output(func_res[0], func_res[1])
	elif func_res:
		terminal.write_output(func_res)
			
func handle_redirect(args, options, function, pipe_input):
	if args.size() >= 2 and (args[-2] == ">" or args[-2] == ">>"):
		var output_path = solve_path(args[-1])
		var command_args = args.slice(0, -2)
		var func_res = function.call(command_args, options, pipe_input)
		var file
		
		if args[-2] == ">":
			file = FileAccess.open(output_path, FileAccess.WRITE)
		elif args[-2] == ">>":
			if FileAccess.file_exists(output_path):
				file = FileAccess.open(output_path, FileAccess.READ_WRITE)
			else:
				file = FileAccess.open(output_path, FileAccess.WRITE)
		
		if not file:
			terminal.write_output("Cannot create file: " + args[-1], "red")
			return true
			
		if func_res:
			if args[-2] == ">>":
				file.seek_end()
		
		file.store_string(output_to_text(func_res))
			
		return true

func output_to_text(output):
	if output == null:
		return ""
	
	if output is Array:
		if output.is_empty():
			return ""
		
		if output[0] is Array:
			var text = ""
			
			for item in output:
				if item is Array and not item.is_empty():
					text += str(item[0]) + "\n"
					
			return text
		
		return str(output[0])
	
	return str(output)

func solve_path(path):
	path = path.replace("\\", "/")
	
	if path == "~":
		return terminal.get_home_dir()
	elif path.begins_with("~/"):
		return (terminal.get_home_dir() + path.substr(1)).simplify_path()
	
	if path == "-":
		return terminal.last_working_dir
	if path == "-/":
		return (terminal.last_working_dir + path.substr(1)).simplify_path()
	
	if path == "/" and OS.has_feature("windows"):
		var drive = terminal.working_dir.get_slice(":", 0)
		return drive + ":/"
	
	if not path.is_absolute_path():
		path = terminal.working_dir.path_join(path)
	
	return path.simplify_path().replace("\\", "/")

func remove_recursive(path):
	for file in DirAccess.get_files_at(path):
		var file_path = path.path_join(file)
		var err = DirAccess.remove_absolute(file_path)
		
		if err != OK:
			return err
	
	for dir in DirAccess.get_directories_at(path):
		var dir_path = path.path_join(dir)
		var err = remove_recursive(dir_path)
		
		if err != OK:
			return err
	
	return DirAccess.remove_absolute(path)

func get_wc_text(text_content, name, options):
	var lines = text_content.split("\n", false).size()
	var word_regex = RegEx.create_from_string(r"\S+")
	var words = word_regex.search_all(text_content).size()
	var bytes = text_content.to_utf8_buffer().size()
	
	var text_line = ""
	
	if "-l" in options:
		text_line += str(lines) + " "
	if "-w" in options:
		text_line += str(words) + " "
	if "-c" in options:
		text_line += str(bytes) + " "
	
	if text_line == "":
		text_line = str(lines) + " " + str(words) + " " + str(bytes) + " "
	
	return text_line + name + "\n"

func get_grep_text(text, pattern, options):
	var output = ""
	var count = 0
	var search_pattern = pattern.to_lower() if "-i" in options else pattern
	
	for line in text.split("\n", false):
		var search_line
		if "-i" in options:
			search_line = line.to_lower()
		else:
			search_line = line
		
		if search_line.contains(search_pattern) and "-v" not in options:
			count += 1
			if "-c" not in options:
				output += line + "\n"
		elif "-v" in options and not search_line.contains(search_pattern):
			count += 1
			if "-c" not in options:
				output += line + "\n"
	
	if "-c" in options:
		output += str(count) + "\n"
	
	return output

func pwd(_args, _options, _pipe_input):
	return terminal.working_dir
	
func cd(args, _options, _pipe_input):
	if args.is_empty():
		terminal.set_working_dir(terminal.get_home_dir())
		return
	
	var path = solve_path(args[0])
	
	if DirAccess.dir_exists_absolute(path):
		terminal.set_working_dir(path)
		return
	
	return ["cd: " + args[0] + ": No such directory", "red"]

func mkdir(args, options, _pipe_input):
	for arg in args:
		var path = solve_path(arg)
		
		var err
		if "-p" in options:
			err = DirAccess.make_dir_recursive_absolute(path)
		else:
			err = DirAccess.make_dir_absolute(path)
		
		if err != OK:
			return ["mkdir: cannot create directory '" + arg + "'", "red"]

func rmdir(args, _options, _pipe_input):
	for arg in args:
		var path = solve_path(arg)
		
		if DirAccess.dir_exists_absolute(path):
			var err = DirAccess.remove_absolute(path)
			
			if err != OK:
				return ["rmdir: failed to remove '" + arg + "'", "red"]
		else:
			return ["rmdir: " + arg + ": No such directory", "red"]
		
func ls(args, options, _pipe_input):
	if args.is_empty():
		args.append(terminal.working_dir)
	
	var all = []
	
	for arg in args:
		var path = solve_path(arg)
		
		if not DirAccess.dir_exists_absolute(path):
			return ["ls: " + arg + ": No such directory", "red"]
		
		var dirs = DirAccess.get_directories_at(path)
		var files = DirAccess.get_files_at(path)
		
		var all_here = []
		
		for dir in dirs:
			if not dir.begins_with(".") or "-a" in options:
				all_here.append([dir + "/", "blue"])
		for file in files:
			if not file.begins_with(".") or "-a" in options:
				all_here.append([file, "white"])
		
		all_here.sort_custom(func(a, b): return a[0] < b[0])
		
		all.append([path.get_file() + "/:", "cyan"])
		all.append_array(all_here)
		if not arg == args[args.size() - 1]:
			all.append([" ", "white"])
	
	return all

func echo(args, _options, _pipe_input):
	return " ".join(args) + "\n"

func touch(args, _options, _pipe_input):
	for arg in args:
		var path = solve_path(arg)
		
		if FileAccess.file_exists(path):
			continue
		
		var file = FileAccess.open(path, FileAccess.WRITE)
		
		if not file:
			return ["touch: cannot touch '" + arg + "'", "red"]
		
func cat(args, options, pipe_input):
	var text = ""
	
	if pipe_input:
		text += pipe_input
		
	for arg in args:
		var path = solve_path(arg)
		var file = FileAccess.open(path, FileAccess.READ)
		
		if not file:
			return ["cat: " + arg + ": No such file", "red"]
		
		text += file.get_as_text()
	
	if "-n" in options:
		var text_lines = text.split("\n")
		text = ""
		for i in text_lines.size():
			text += str(i + 1) + " " + text_lines[i] + "\n"
			
	return text

func head(args, _options, pipe_input):
	var text = ""
	
	if pipe_input:
		if args.size() > 0:
			text += "==> piped <==\n" + pipe_input.split("\n", false)[0] + "\n"
		else:
			text += pipe_input.split("\n", false)[0] + " \n \n"
		
	for arg in args:
		var path = solve_path(arg)
		var file = FileAccess.open(path, FileAccess.READ)
		
		if not file:
			return ["head: " + arg + ": No such file", "red"]
		
		if args.size() > 1:
			text += "==> " + path.get_file() + " <==\n" + file.get_line() + "\n"
			if not arg == args[args.size() - 1]:
				text += " \n"
		else:
			text = file.get_line()
			
	return text

func tail(args, _options, pipe_input):
	var text = ""
	
	if pipe_input:
		if args.size() > 0:
			text += "==> piped <==\n" + pipe_input.get_line().split("\n", false)[-1] + "\n"
		else:
			text += pipe_input.get_line().split("\n", false)[-1] + " \n \n"
			
	for arg in args:
		var path = solve_path(arg)
		var file = FileAccess.open(path, FileAccess.READ)
		
		if not file:
			return ["tail: " + arg + ": No such file", "red"]
		
		if args.size() > 1:
			text += "==> " + path.get_file() + " <==\n" + file.get_as_text().split("\n", false)[-1]  + "\n"
			if not arg == args[args.size() - 1]:
				text += " \n"
		else:
			text = file.get_as_text().split("\n", false)[-1]
			
	return text

func wc(args, options, pipe_input):
	var text = ""
	
	if pipe_input:
		text += get_wc_text(pipe_input, "piped", options)
	
	for arg in args:
		var path = solve_path(arg)
		var file = FileAccess.open(path, FileAccess.READ)
		
		if not file:
			return ["wc: " + arg + ": No such file", "red"]
		
		text += get_wc_text(file.get_as_text(), path.get_file(), options)
		
	return text

func sort(args, _options, pipe_input):
	var lines = []
	
	if pipe_input:
		for line in pipe_input.split("\n", false):
			lines.append(line)
	
	for arg in args:
		var path = solve_path(arg)
		var file = FileAccess.open(path, FileAccess.READ)
		
		if not file:
			return ["sort: " + arg + ": No such file", "red"]
				
		for line in file.get_as_text().split("\n", false):
			lines.append(line)
	
	lines.sort()
	
	var text = ""
	for line in lines:
		text += line + "\n"
	
	return text

func grep(args, options, pipe_input):
	if not args:
		return ["grep: missing pattern", "red"]
	
	var pattern = args[0]
	args.remove_at(0)
	var text = ""
	
	if pipe_input:
		text += get_grep_text(pipe_input, pattern, options)
		if args.size() > 1:
			text += "\n"
	
	for arg in args:
		var path = solve_path(arg)
		var file = FileAccess.open(path, FileAccess.READ)
		if not file:
			return ["grep: " + arg + ": No such file", "red"]
		
		if args.size() > 1:
			text += "==> " + path.get_file() + " <==\n"
		
		text += get_grep_text(file.get_as_text(), pattern, options)
		
		if args.size() > 1 and arg != args[-1]:
			text += "\n"
		
	return text

func cp(args, _options, _pipe_input):
	if args.size() < 2:
		return ["cp: missing target file or directory", "red"]
	
	var path = solve_path(args[0])
	var res_path = solve_path(args[1])
	
	if DirAccess.dir_exists_absolute(res_path):
		res_path = res_path.path_join(path.get_file())
	
	var err = DirAccess.copy_absolute(path, res_path)
	
	if err != OK:
		return ["cp: " + args[0] + ": No such file or directory", "red"]
		
func mv(args, _options, _pipe_input):
	if args.size() < 2:
		return ["mv: missing target file or directory", "red"]
	
	var old_path = solve_path(args[0])
	var new_path = solve_path(args[1])
	
	if DirAccess.dir_exists_absolute(new_path):
		new_path = new_path.path_join(old_path.get_file())
	
	var err = DirAccess.rename_absolute(old_path, new_path)
	
	if err != OK:
		return ["mv: cannot move '" + args[0] + "'", "red"]

func rm(args, options, _pipe_input):
	for arg in args:
		var path = solve_path(arg).trim_suffix("/")
		
		if FileAccess.file_exists(path):
			var err = DirAccess.remove_absolute(path)
			if err != OK:
				return ["rm: failed to remove '" + arg + "'", "red"]
		elif DirAccess.dir_exists_absolute(path):
			if "-r" not in options:
				return ["rm: cannot remove '" + arg + "': Is a directory", "red"]
			
			var err = remove_recursive(path)
			if err != OK:
				return ["rm: failed to remove '" + arg + "'", "red"]
		else:
			return ["rm: cannot remove '" + arg + "': No such file or directory", "red"]

func curl(args, _options, _pipe_input):
	if not args:
		return ["curl: no URL specified", "red"]
	
	var url = args[0]
	
	if not url.begins_with("http://") and not url.begins_with("https://"):
		url = "https://" + url
	
	var http = HTTPRequest.new()
	http.timeout = 10
	terminal.add_child(http)
	
	var error = http.request(url)
	if error != OK:
		http.queue_free()
		return ["curl: failed to start request", "red"]
		
	var response = await http.request_completed
	http.queue_free()
	
	var result = response[0]
	var body = response[3]
	
	if result != HTTPRequest.RESULT_SUCCESS:
		return ["curl: request failed (" + str(result) + ")", "red"]
	
	return body.get_string_from_utf8()

func gdpt(args, options, _pipe_input):
	if not args:
		return ["gdpt: invalid command", "red"]
	
	if args[0] == "install":
		if args.size() < 2:
			return ["gdpt: missing file", "red"]
		
		var paths = args.slice(1)
		
		for path in paths:
			var text = ""
			var name = ""
			
			if "-r" in options:
				text = await curl([path], null, null)
				
				if text is Array:
					return ["gdpt: failed to get '" + path + "'", "red"]
				else:
					if "-t" not in options:
						name = path.get_file().get_basename()
						var file =  FileAccess.open("user://libs/" + name + ".gd" , FileAccess.WRITE)
						file.store_string(text)
			
			else:
				var solved_path = solve_path(path)
				var file = FileAccess.open(solved_path, FileAccess.READ)
				if not file:
					return ["gdpt: file not found '" + path + "'", "red"]
				
				if "-t" not in options:
					var err = DirAccess.copy_absolute(solved_path, "user://libs/".path_join(solved_path.get_file()))
					if err != OK:
						return ["gdpt: failed to copy '" + path + "' to libs/", "red"]
				
				text = file.get_as_text()
				name = solved_path.get_basename().get_file()
			
			var script = GDScript.new()
			script.source_code = text
			
			if script.reload() != OK:
				return ["gdpt: failed to import '" + path + "'", "red"]
			
			var instance = script.new(terminal)
			
			loaded_plugins.append(instance)
			register_commands(instance, name)
			
		return "gdpt: installed successfully"
	
	else:
		return ["gdpt: invalid command '" + args[0] + "'", "red"]

func uname(_args, options, _pipe_input):
	if "-a" in options:
		var hostname = OS.get_environment("HOSTNAME")
		if hostname.is_empty():
			hostname = OS.get_environment("COMPUTERNAME")

		return OS.get_name() + " " + OS.get_version_alias() + " " + OS.get_version() + " " + hostname + " " + Engine.get_architecture_name() + " "
		
	var text = ""
	if "-s" in options or "-o" in options:
		text += OS.get_name() + " "
	if "-r" in options:
		text += OS.get_version_alias() + " " + OS.get_version() + " "
	if "-n" in options:
		var hostname = OS.get_environment("HOSTNAME")
		if hostname.is_empty():
			hostname = OS.get_environment("COMPUTERNAME")
		text += hostname + " "
	if "-m" in options or "-p" in options or "-i" in options:
		text += Engine.get_architecture_name() + " "
	
	if text == "":
		text = OS.get_name()
	
	return text

func whoami(_args, _options, _pipe_input):
	if OS.has_environment("USERNAME"):
		return OS.get_environment("USERNAME")
	elif OS.has_environment("USER"):
		return OS.get_environment("USER")

func clear(_args, _options, _pipe_input):
	terminal.clear_and_reset_colors()
	
func help(args, _options, _pipe_input):
	var text = ""
	
	if args:
		for arg in args:
			var description = command_info.get(arg, "")
			
			if description != "":
				text += arg + " - " + description + "\n"
			else:
				text += arg + "\n"
	
	else:
		for command in command_registry.keys():
			var description = command_info.get(command, "")
			
			if description != "":
				text += command + " - " + description + "\n"
			else:
				text += command + "\n"
	
	return text

func history(_args, _options, _pipe_input):
	var text = ""
	for i in terminal.entered_commands.size():
		text += str(i + 1) + " " + terminal.entered_commands[i] + "\n"
		
	return text

func reset(_args, _options, _pipe_input):
	if terminal.is_inside_tree():
		terminal.get_tree().call_deferred("reload_current_scene")

func colors(_args, options, _pipe_input):
	var lines = []
	if "-a" in options:
		lines.append_array([
			["bg        ████   #" + terminal.syntax_highlighter.colors["bg"].to_html().to_upper(), "bg"],
			["caret     ████   #" + terminal.syntax_highlighter.colors["caret"].to_html().to_upper(), "caret"],
			["selection ████   #" + terminal.syntax_highlighter.colors["selection"].to_html().to_upper(), "selection"],
			["selected  ████   #" + terminal.syntax_highlighter.colors["selected"].to_html().to_upper(), "selected"],
			["black     ████   #" + terminal.syntax_highlighter.colors["black"].to_html().to_upper(), "black"],
		])
	
	lines.append_array([
		["white     ████   #" + terminal.syntax_highlighter.colors["white"].to_html().to_upper(), "white"],
		["red       ████   #" + terminal.syntax_highlighter.colors["red"].to_html().to_upper(), "red"],
		["yellow    ████   #" + terminal.syntax_highlighter.colors["yellow"].to_html().to_upper(), "yellow"],
		["pink      ████   #" + terminal.syntax_highlighter.colors["pink"].to_html().to_upper(), "pink"],
		["green     ████   #" + terminal.syntax_highlighter.colors["green"].to_html().to_upper(), "green"],
		["cyan      ████   #" + terminal.syntax_highlighter.colors["cyan"].to_html().to_upper(), "cyan"],
		["blue      ████   #" + terminal.syntax_highlighter.colors["blue"].to_html().to_upper(), "blue"],
	])
		
	return lines
