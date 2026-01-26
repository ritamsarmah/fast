package main

import "core:encoding/json"
import "core:fmt"
import os "core:os/os2"
import "core:path/filepath"
import "core:slice"
import "core:strings"

USAGE :: `Quickly open and interact with project directories.

Usage:
  f [flags] [project]

Arguments:
  project        Project name (allowing partial match)

Flags:
  -h, --help     Show this help message and exit
  -s, --save     Save current directory as project
  -d, --delete   Delete project with name
  -e, --edit     Open project in $EDITOR
  --reset        Reset list of projects`

Command :: enum {
	Load,
	Save,
	Delete,
	Edit,
	Reset,
	Help,
}

Projects :: map[string]string

Error :: enum {
	Too_Many_Arguments,
	Unrecognized_Flag,
	Project_Already_Loaded,
	No_Editor,
	No_Projects,
	No_Project_Found,
}

Any_Error :: union #shared_nil {
	os.Error,
	json.Marshal_Error,
	json.Unmarshal_Error,
	Error,
}

/* Main */

main :: proc() {
	command, query, parse_err := parse_args()
	check_error(parse_err)

	projects, read_err := read_projects()
	defer delete(projects)
	check_error(read_err)

	err: Any_Error

	switch command {
	case .Load:
		err = load_project(query, &projects)
	case .Save:
		err = save_project(query, &projects)
	case .Delete:
		err = delete_project(query, &projects)
	case .Edit:
		err = edit_project(query, &projects)
	case .Reset:
		err = reset_projects(&projects)
	case .Help:
		fmt.println(USAGE)
	}

	check_error(err)
	free_all(context.temp_allocator)
}

check_error :: proc(err: Any_Error) {
	if err == nil do return

	message: string

	switch e in err {
	case os.Error:
		message = os.error_string(e)
	case json.Marshal_Error:
		message = "failed to marshal json"
	case json.Unmarshal_Error:
		message = "failed to unmarshal json"
	case Error:
		switch e {
		case .Too_Many_Arguments:
			message = "too many arguments provided"
		case .Unrecognized_Flag:
			message = "unrecognized flag"
		case .Project_Already_Loaded:
			message = "already in project directory"
		case .No_Projects:
			message = "no saved projects found"
		case .No_Editor:
			message = "no editor configured via $EDITOR environment variable"
		case .No_Project_Found:
			message = "no matching project found"
		}
	}

	fmt.eprintln("pair:", message)
	os.exit(1)
}

parse_args :: proc() -> (command: Command, query: string, err: Error) {
	args := os.args

	if len(args) > 3 {
		err = .Too_Many_Arguments
		return
	}

	has_flag := len(args) > 1 && args[1][0] == '-'
	if has_flag {
		// Parse first argument as a flag, second argument as query
		switch args[1] {
		case "-h", "--help":
			command = .Help
		case "-s", "--save":
			command = .Save
		case "-d", "--delete":
			command = .Delete
		case "-e", "--edit":
			command = .Edit
		case "--reset":
			command = .Reset
		case:
			err = .Unrecognized_Flag
			return
		}
	} else {
		// Parse first argument as query
		command = .Load
	}

	// Query may or may not be provided
	query_index := has_flag ? 2 : 1
	if query_index < len(args) {
		query = args[query_index]
	}

	return
}

/* Store */

read_projects :: proc() -> (projects: Projects, err: Any_Error) {
	path := get_store_path() or_return

	if os.exists(path) {
		data := os.read_entire_file(path, context.allocator) or_return
		defer delete(data)
		json.unmarshal(data, &projects) or_return
	}

	return
}

write_projects :: proc(projects: ^Projects) -> Any_Error {
	path := get_store_path() or_return
	data := json.marshal(projects^) or_return
	defer delete(data)
	return os.write_entire_file(path, data)
}

// Gets path to data store in user's home directory
get_store_path :: proc() -> (path: string, err: os.Error) {
	dir := os.user_home_dir(context.temp_allocator) or_return
	return filepath.join([]string{dir, ".fstore"}, context.temp_allocator)
}

/* Commands */

load_project :: proc(query: string, projects: ^Projects) -> Any_Error {
	name, path := select_project(query, projects, "Which project should be loaded?") or_return
	pwd := os.get_working_directory(context.temp_allocator) or_return

	if path == pwd do return .Project_Already_Loaded

	fmt.printfln("Switching to \"%v\"", name)
	return send_to_shell("cd", path)
}

save_project :: proc(name: string, projects: ^Projects) -> Any_Error {
	name := name
	for name == "" {
		name = user_input("Enter new project name: ") or_return
	}

	prompt := fmt.tprintf("Project named \"%v\" already exists. Overwrite", name)
	if !(name in projects) || (user_confirms(prompt) or_return) {
		pwd := os.get_working_directory(context.temp_allocator) or_return
		projects[name] = pwd
		fmt.printfln("Saved project \"%v\"", name)
		return write_projects(projects)
	}

	return nil
}

delete_project :: proc(query: string, projects: ^Projects) -> Any_Error {
	name, _ := select_project(query, projects, "Which project should be deleted?") or_return

	prompt := fmt.tprintf("Delete \"%v\"", name)
	if user_confirms(prompt) or_return {
		fmt.printfln("Deleted project \"%v\"", name)
		delete_key(projects, name)
		return write_projects(projects)
	}

	return nil
}

edit_project :: proc(query: string, projects: ^Projects) -> Any_Error {
	editor, found := os.lookup_env("EDITOR", context.temp_allocator)
	if !found do return .No_Editor

	prompt := fmt.tprintf("Which project should be opened with %v?", editor)
	_, path := select_project(query, projects, prompt) or_return

	return send_to_shell(editor, path)
}

reset_projects :: proc(projects: ^Projects) -> Any_Error {
	if len(projects) == 0 do return .No_Projects

	prompt := fmt.tprintf("Remove %v saved projects", len(projects))
	if user_confirms(prompt) or_return {
		store := get_store_path() or_return
		os.remove(store) or_return
		fmt.println("Removed all saved projects")
	}

	return nil
}

/* Utilities */

user_input :: proc(prompt: string) -> (input: string, err: os.Error) {
	fmt.print(prompt)
	os.flush(os.stdout) // Explicit flush for line-buffered stdout

	builder: strings.Builder
	strings.builder_init(&builder, context.temp_allocator)

	// Read input until newline entered
	buffer: [1]byte
	for {
		_, read_err := os.read_at_least(os.stdin, buffer[:], 1)
		if read_err != nil {
			if read_err == .EOF do break
			return "", read_err
		}

		if buffer == '\n' do break

		fmt.sbprint(&builder, string(buffer[:]))
	}

	input = strings.to_string(builder)
	input = strings.trim_space(input)

	return
}

user_confirms :: proc(prompt: string) -> (confirm: bool, err: os.Error) {
	prompt := fmt.tprint(prompt, "(y/N)? ")
	input := user_input(prompt) or_return

	return input == "y", nil
}

print_projects :: proc(projects: ^Projects, prompt: string) {
	if prompt != "" {
		fmt.printf("%v\n\n", prompt)
	} else {
		fmt.println()
	}

	padding := 0
	names: [dynamic]string
	defer delete(names)

	// Determine whitespace between columns using the maximum project length
	for name in projects {
		padding = max(padding, len(name))
		append(&names, name)
	}

	slice.sort(names[:])

	// Print two columns with project name on left in bold and path on right
	for name in names {
		fmt.printfln("\x1b[1m%-*s\x1b[0m%s", padding + 2, name, projects[name])
	}
}

// Selects a project from projects based on query, requesting user for additional input if ambiguous
select_project :: proc(
	query: string,
	projects: ^Projects,
	prompt: string,
) -> (
	name: string,
	path: string,
	err: Any_Error,
) {
	if len(projects) == 0 {
		err = .No_Projects
		return
	}

	query := query
	prompt := prompt

	matches: Projects
	defer delete(matches)
	for key, value in projects do matches[key] = value

	for {
		// Request user query if needed
		for query == "" {
			print_projects(&matches, prompt)
			query = user_input("\nEnter project: ") or_return
			prompt = "" // Clear prompt for next input request
		}

		// Return exact match with query if found
		if query in matches {
			name = query
			path = matches[name]
			return
		}

		// Filter project keys containing query as substring
		for key in matches {
			if !strings.contains(key, query) {
				delete_key(&matches, key)
			}
		}

		switch len(matches) {
		case 0:
			err = .No_Project_Found
			return
		case 1:
			// Retrieve first (and only) project in matches and corresponding path
			for key in matches do name = key
			path = projects[name]
			return
		case:
			// Clear query to request user to disambiguate from matches
			query = ""
		}
	}
}

// Writes a shell command to temporary file to communicate with shell wrapper
send_to_shell :: proc(command: string, path: string) -> os.Error {
	contents := fmt.tprintf("%v '%v'", command, path)
	return os.write_entire_file("/tmp/fast_cmd", contents)
}
