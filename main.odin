package fast

import "core:c/libc"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

Projects :: distinct map[string]string

Command :: enum {
	Help,
	Load,
	Save,
	Delete,
	View,
	Open,
	Edit,
	Reset,
}

STORE_PATH := filepath.join({os.get_env("HOME"), ".fstore"})
NO_PROJECTS_ERROR :: "No saved projects found"

/* Main */

main :: proc() {
	context.allocator = context.temp_allocator
	projects := read_projects()

	switch command, query := parse_args(); command {
	case .Help:
		print_help()
	case .Load:
		load_project(query, &projects)
	case .Save:
		save_project(query, &projects)
	case .Delete:
		delete_project(query, &projects)
	case .View:
		view_project(query, &projects)
	case .Open:
		open_project(query, &projects)
	case .Edit:
		edit_project(query, &projects)
	case .Reset:
		reset_projects(&projects)
	}

	free_all(context.allocator)
}

parse_args :: proc() -> (command: Command, query: string) {
	args := os.args

	if len(args) > 3 {
		error_exit("Error: Too many arguments provided")
	} else if len(args) == 1 {
		// No arguments provided - default to load project
		command = .Load
	} else if args[1][0] == '-' {
		// First argument is a flag
		switch args[1] {
		case "-h", "--help":
			command = .Help
		case "-s", "--save":
			command = .Save
		case "-d", "--delete":
			command = .Delete
		case "-v", "--view":
			command = .View
		case "-o", "--open":
			command = .Open
		case "-e", "--edit":
			command = .Edit
		case "--reset":
			command = .Reset
		case:
			error_exit("Error: Unrecognized argument provided: ", args[1])
		}

		// Second argument may or not be provided
		if len(args) == 3 do query = args[2]
	} else {
		// First argument is project query, expecting no other arguments
		if len(args) > 2 {
			error_exit("Error: Unexpected argument", args[2])
		}

		command = .Load
		query = args[1]
	}

	return
}

/* Persistence */

read_projects :: proc() -> Projects {
	// No file exists, return empty map
	if !os.exists(STORE_PATH) do return {}

	data, ok := os.read_entire_file_from_filename(STORE_PATH)
	if !ok do error_exit("Error: Failed to read data file", code = 2)
	defer delete(data)

	projects: Projects
	json.unmarshal(data, &projects)
	return projects
}

write_projects :: proc(projects: ^Projects) {
	data, err := json.marshal(projects^)
	if err != nil do error_exit("Error: Failed to marshal JSON")
	defer delete(data)

	ok := os.write_entire_file(STORE_PATH, data)
	if !ok do error_exit("Error: Failed to write data file", code = 2)
}

/* Commands */

load_project :: proc(query: string, projects: ^Projects) {
	project, path := select_project(query, projects, "Which project should be loaded?")

	if path == os.get_current_directory() {
		fmt.println("Already in project directory")
	} else {
		fmt.printf("Switching to \"%v\"\n", project)
 
		// Print to custom file descriptor used by shell wrapper
		fmt.fprint(3, path)
	}
}

save_project :: proc(query: string, projects: ^Projects) {
	project := query != "" ? query : read_user_input("Enter new project name: ")

	if project in projects &&
	   !confirm("Project named \"", project, "\" already exists. Overwrite") {
		return
	}

	projects[project] = os.get_current_directory()
	write_projects(projects)

	fmt.printf("Saved project \"%v\"\n", project)
}

delete_project :: proc(query: string, projects: ^Projects) {
	project, _ := select_project(query, projects, "Which project should be deleted?")

	if confirm("Delete \"", project, "\"") {
		delete_key(projects, project)
		write_projects(projects)

		fmt.printf("Deleted project \"%v\"\n", project)
	}
}

view_project :: proc(query: string, projects: ^Projects) {
	project, path := select_project(
		query,
		projects,
		"Which project should open in the file explorer?",
	)

	if ODIN_OS == .Darwin {
		fmt.printf("Opening \"%v\" in Finder...\n", project)
		system("open", path)
	} else if ODIN_OS == .Linux {
		fmt.printf("Opening \"%v\" in file explorer...\n", project)
		system("xdg-open", path)
	}
}

open_project :: proc(query: string, projects: ^Projects) {
	project, path := select_project(query, projects)

	if os.is_file(filepath.join({path, "start"})) {
		fmt.printf("Starting \"%v\"...\n", project)
		change_directory(path)

		system("./start")
		return
	}

	// Xcode workspace
	xcworkspace_glob := filepath.join({path, "*.xcworkspace"})
	if xcworkspaces, _ := filepath.glob(xcworkspace_glob); xcworkspaces != nil {
		fmt.printf("Opening \"%v\" in Xcode...\n", project)
		system("open", xcworkspaces[0])
		return
	}

	// Xcode project
	xcodeproj_glob := filepath.join({path, "*.xcodeproj"})
	if xcodeprojs, _ := filepath.glob(xcodeproj_glob); xcodeprojs != nil {
		fmt.printf("Opening \"%v\" in Xcode...\n", project)
		system("open", xcodeprojs[0])
		return
	}

	edit_project(project, projects)
}

edit_project :: proc(query: string, projects: ^Projects) {
	editor := os.get_env("EDITOR")

	if editor == "" do error_exit("No editor configured. Please set the $EDITOR environment variable")

	_, path := select_project(
		query,
		projects,
		fmt.tprintf("Which project should be opened with %v?", editor),
	)

	change_directory(path)
	system(editor, path)
}

reset_projects :: proc(projects: ^Projects) {
	if len(projects) == 0 do error_exit(NO_PROJECTS_ERROR)

	if confirm("Remove ", len(projects), " saved projects") {
		os.remove(STORE_PATH)
		fmt.println("Removed all saved projects")
	}
}

/* Utilities */

select_project :: proc(
	query: string,
	projects: ^Projects,
	prompt: string = "",
) -> (
	string,
	string,
) {
	if len(projects) == 0 do error_exit(NO_PROJECTS_ERROR)

	// Request user query if none provided
	if query == "" {
		print_projects(projects, prompt)
		input := read_user_input("\nEnter project: ")
		return select_project(input, projects)
	}

	// Return exact match if found
	if query in projects do return query, projects[query]

	// Filter projects containing substring name
	matches: Projects
	for project, path in projects {
		if strings.contains(project, query) {
			matches[project] = path
		}
	}
	defer delete(matches)

	switch len(matches) {
	case 0:
		error_exit("Error: No matching project found")
	case 1:
		entries, _ := slice.map_entries(matches)
		return entries[0].key, entries[0].value
	}

	// Disambiguate if multiple matches
	print_projects(&matches, prompt)
	input := read_user_input("\nEnter project: ")
	return select_project(input, &matches)
}

print_projects :: proc(projects: ^Projects, prompt: string = "") {
	if prompt == "" {
		fmt.printf("%v project%v found\n\n", len(projects), len(projects) != 1 ? "s" : "")
	} else {
		fmt.printf("%v\n\n", prompt)
	}

	max_len := 0
	keys, _ := slice.map_keys(projects^)
	for project in keys {
		if len(project) > max_len do max_len = len(project)
	}

	slice.sort(keys)
	for project in keys {
		padded_project := strings.left_justify(project, max_len + 2, " ")
		fmt.printf("\033[1m%v\033[0m%v\n", padded_project, projects[project])
	}
}

print_help :: proc(stderr: bool = false) {
	usage := []string{
		"Quickly open and interact with project directories.",
		"",
		"Usage:",
		"  f [flags] [project]",
		"",
		"Arguments:",
		"  project        Project name (allowing partial match)",
		"",
		"Flags:",
		"  -h, --help     Show this help message and exit",
		"  -s, --save     Save current directory as project",
		"  -d, --delete   Delete project with name",
		"  -v, --view     View project in system file explorer",
		"  -o, --open     Open project environment or IDE",
		"  -e, --edit     Open project in $EDITOR",
		"  --reset        Reset list of projects",
	}

	message := strings.join(usage, "\n")
	_ = stderr ? fmt.eprintln(message) : fmt.println(message)

	os.exit(0)
}

read_user_input :: proc(prompt: string) -> string {
	fmt.print(prompt)

	buffer: [256]byte
	n, err := os.read(os.stdin, buffer[:])
	if err != os.ERROR_NONE do error_exit("Failed to read user input")

	return strings.clone(string(buffer[:n - 1])) // Ignore last newline character
}

confirm :: proc(prompt: ..any) -> bool {
	joined_prompt := fmt.tprint(..prompt, sep = "")
	return "y" == read_user_input(fmt.tprintf("%v (y/N)? ", joined_prompt))
}

system :: proc(command: ..any) {
	libc.system(strings.clone_to_cstring(fmt.tprint(..command)))
}

change_directory :: proc(path: string) {
	error := os.set_current_directory(path)
	if error != os.ERROR_NONE {
		error_exit("Failed to switch to project directory", code = int(error))
	}
}

error_exit :: proc(args: ..any, code: int = 1) {
	fmt.eprintln(..args)
	os.exit(code)
}
