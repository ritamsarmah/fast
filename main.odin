package fast

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

print :: fmt.println
eprint :: fmt.eprintln

STORE_FILENAME :: ".fstore"

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

/* Main */

main :: proc() {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)

	path := filepath.join({os.get_env("HOME"), STORE_FILENAME})
	projects := load_projects(path)
	defer save_projects(&projects, path)
	defer delete(projects)

	switch command, name := parse_args(); command {
	case .Help:
		print_help()
	case .Load:
		load_project(name, &projects)
	case .Save:
		save_project(name, &projects)
	case .Delete:
		delete_project(name, &projects)
	case .View:
		view_project(name, &projects)
	case .Open:
		open_project(name, &projects)
	case .Edit:
		edit_project(name, &projects)
	case .Reset:
		reset_projects(&projects)
	}
}

parse_args :: proc() -> (command: Command, name: string) {
	args := os.args

	if len(args) > 3 {
		eprint("Error: too many arguments provided")
		print_help(true)
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
			fmt.eprintln("Error: unrecognized argument provided: ", args[1])
			os.exit(1)
		}

		// Second argument may or not be provided
		if len(args) == 3 do name = args[2]
	} else {
		// First argument is project name, expecting no other arguments
		if len(args) > 2 {
			eprint("Error: unexpected argument", args[2])
			print_help()
		}

		command = .Load
		name = args[1]
	}

	return
}

/* Storage */

load_projects :: proc(path: string) -> map[string]string {
	// No file exists, return empty map
	if !os.exists(path) do return {}
	
	data, ok := os.read_entire_file_from_filename(path)
	if !ok {
		eprint("Error: failed to read data file")
		os.exit(2)
	}
	defer delete(data)

	projects: map[string]string
	json.unmarshal(data, &projects)
	return projects
}

save_projects :: proc(projects: ^map[string]string, path: string) {
	data, err := json.marshal(projects)
	if err != nil {
		eprint("Error: failed to marshal data to JSON")
		os.exit(2)
	}
	defer delete(data)

	ok := os.write_entire_file(path, data)
	if !ok {
		eprint("Error: failed to write data file")
		os.exit(2)
	}
}

/* Commands */

load_project :: proc(name: string, projects: ^map[string]string) {
}

save_project :: proc(name: string, projects: ^map[string]string) {
}

delete_project :: proc(name: string, projects: ^map[string]string) {
}

view_project :: proc(name: string, projects: ^map[string]string) {
}

open_project :: proc(name: string, projects: ^map[string]string) {
}

edit_project :: proc(name: string, projects: ^map[string]string) {
}

reset_projects :: proc(projects: ^map[string]string) {
}

/* Utilities */

print_help :: proc(stderr: bool = false) {
	usage := []string{
		"Quickly open and interact with project directories.",
		"",
		"USAGE:",
		"  f [FLAGS] [PROJECT]",
		"",
		"ARGUMENTS:",
		"  PROJECT        Name of project",
		"",
		"FLAGS:",
		"  -h, --help     Show this help message and exit",
		"  -s, --save     Save current directory as project",
		"  -d, --delete   Delete project with name",
		"  -v, --view     View project in system file explorer",
		"  -o, --open     Open project in system editor/IDE",
		"  -e, --edit     Open project in command-line editor",
		"  --reset        Reset list of projects",
	}

	message := strings.join(usage, "\n")

	if stderr {
		eprint(message)
	} else {
		print(message)
	}

	os.exit(0)
}
