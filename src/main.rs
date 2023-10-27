use home::home_dir;

use itertools::Itertools;

use std::collections::{HashMap, HashSet};
use std::env;
use std::fs;
use std::io::Write;
use std::io::{stdin, stdout};
use std::path::{Path, PathBuf};
use std::process::exit;

enum Command {
    Help,
    Load,
    Save,
    Delete,
    View,
    Open,
    Edit,
    Reset,
}

type Projects = HashMap<String, PathBuf>;

const NO_PROJECTS_ERROR: &str = "No saved projects found";

/* Main */

fn main() {
    let (command, query) = parse_args();
    let mut projects = read_projects();

    match command {
        Command::Help => print_help(),
        Command::Load => load_project(&query, &projects),
        Command::Save => save_project(&query, &mut projects),
        Command::Delete => delete_project(&query, &mut projects),
        Command::View => view_project(&query, &projects),
        Command::Open => open_project(&query, &projects),
        Command::Edit => edit_project(&query, &projects),
        Command::Reset => reset_projects(&projects),
    }
}

fn parse_args() -> (Command, String) {
    let args: Vec<String> = env::args().collect();

    if args.len() > 3 {
        eprintln!("Error: Too many arguments provided");
        exit(1);
    }

    let has_flag = args.len() > 1 && args[1].starts_with('-');
    let (command, query_index) = if has_flag {
        // Parse first argument as a flag, second argument as query
        let command = match args[1].as_ref() {
            "-h" | "--help" => Command::Help,
            "-s" | "--save" => Command::Save,
            "-d" | "--delete" => Command::Delete,
            "-v" | "--view" => Command::View,
            "-o" | "--open" => Command::Open,
            "-e" | "--edit" => Command::Edit,
            "--reset" => Command::Reset,
            _ => {
                eprintln!("Error: Unrecognized argument provided: {}", args[1]);
                exit(1);
            }
        };

        (command, 2)
    } else {
        // Parse first argument as query
        (Command::Load, 1)
    };

    // Query may or may not be provided
    let query = args
        .get(query_index)
        .map_or_else(String::new, String::to_owned);

    (command, query)
}

/* Store */

fn read_projects() -> Projects {
    // Return empty map if file does not exist
    let store = get_store_path();
    if !store.exists() {
        return Projects::new();
    }

    let serialized = fs::read_to_string(store).expect("Read projects file");
    serde_json::from_str(&serialized).expect("Deserialized projects")
}

fn write_projects(projects: &Projects) {
    let store = get_store_path();
    let serialized = serde_json::to_string(projects).expect("Serialized projects");
    fs::write(store, serialized).expect("Write projects file");
}

/* Commands */

fn load_project(query: &str, projects: &Projects) {
    let (project, path) = select_project(query, projects, "Which project should be loaded?");

    if *path == current_dir() {
        eprintln!("Already in project directory");
        exit(1);
    } else {
        println!("Switching to \"{}\"", project);
        send_to_shell("cd", path);
    }
}

fn save_project(query: &str, projects: &mut Projects) {
    let project = if query.is_empty() {
        user_input("Enter new project name: ")
    } else {
        query.to_string()
    };

    if projects.contains_key(&project)
        && !user_confirms(format!(
            "Project named \"{}\" already exists. Overwrite",
            project
        ))
    {
        return;
    }

    println!("Saved project \"{}\"", &project);

    projects.insert(project, current_dir());
    write_projects(projects);
}

fn delete_project(query: &str, projects: &mut Projects) {
    let (project, _) = select_project(query, projects, "Which project should be deleted?");

    if user_confirms(format!("Delete \"{}\"", project)) {
        println!("Deleted project \"{}\"", project);

        projects.remove(&project.clone());
        write_projects(projects);
    }
}

fn view_project(query: &str, projects: &Projects) {
    let (project, path) = select_project(
        query,
        projects,
        "Which project should open in the file explorer?",
    );

    println!("Opening \"{}\" in file explorer...", project);
    open_native(path);
}

fn open_project(query: &str, projects: &Projects) {
    let (project, path) = select_project(query, projects, "Which project would you like to open?");
    let path = PathBuf::from(path);

    // Start script
    if path.join("start").is_file() {
        println!("Starting \"{}\"...", project);
        env::set_current_dir(&path).expect("Change to project directory");

        let mut child = std::process::Command::new("./start")
            .spawn()
            .expect("Run start script");

        child.wait().expect("Wait for start script to finish");

        return;
    }

    // Xcode workspace
    if let Some(xcworkspace) = get_file_with_extension("xcworkspace", &path) {
        println!("Opening \"{}\" in Xcode...", project);
        open_native(&xcworkspace);
        return;
    }

    // Xcode project
    if let Some(xcodeproj) = get_file_with_extension("xcodeproj", &path) {
        println!("Opening \"{}\" in Xcode...", project);
        open_native(&xcodeproj);
        return;
    }

    eprintln!(
        "No environment or system app to open for project: {}",
        project
    );

    exit(1);
}

fn edit_project(query: &str, projects: &Projects) {
    match env::var("EDITOR") {
        Ok(editor) => {
            let message = format!("Which project should be opened with {}?", editor);
            let (_, path) = select_project(query, projects, &message);

            send_to_shell(&editor, path);
        }
        Err(_) => {
            eprintln!("No editor configured. Please set the $EDITOR environment variable");
            exit(1);
        }
    }
}

fn reset_projects(projects: &Projects) {
    if projects.is_empty() {
        eprintln!("{}", NO_PROJECTS_ERROR);
        exit(1);
    }

    if user_confirms(format!("Remove {} saved projects", projects.len())) {
        let store = get_store_path();
        fs::remove_file(store).expect("Remove saved projects");
        println!("Remove all saved projects")
    }
}

/* Utilities */

/// Selects a project from projects based on query, requesting user for additional input if ambiguous
/// The lifetime of the returned (project, path) key-value pair is tied to the `projects` map it is retrieved from
fn select_project<'a>(
    query: &str,
    projects: &'a Projects,
    prompt: &str,
) -> (&'a String, &'a PathBuf) {
    if projects.is_empty() {
        eprintln!("{}", NO_PROJECTS_ERROR);
        exit(1);
    }

    // Request user query if none provided
    if query.is_empty() {
        print_projects(projects, prompt);
        let input = user_input("\nEnter project: ");
        return select_project(&input, projects, "");
    }

    // Return exact match if found
    if let Some((project, path)) = projects.get_key_value(query) {
        return (project, path);
    }

    // Filter project keys containing substring
    let matches: HashSet<_> = projects
        .keys()
        .filter(|project| project.contains(query))
        .collect();

    match matches.len() {
        0 => {
            eprintln!("Error: No matching project found");
            exit(1);
        }
        1 => {
            // Retrieve first (and only) project in matches and corresponding path
            let project = *matches.iter().next().unwrap();
            let path = projects.get(project).unwrap();

            (project, path)
        }
        _ => {
            // Clone projects and disambiguate from matches
            let mut subset = projects.clone();
            subset.retain(|key, _| matches.contains(key));

            print_projects(&subset, prompt);
            let input = user_input("\nEnter project: ");
            let (key, _) = select_project(&input, &subset, "");

            // Return original key-value pair
            projects.get_key_value(key).unwrap()
        }
    }
}

/* Printing */

fn print_help() {
    println!(
        "\
Quickly open and interact with project directories.

Usage:
  f [flags] [project]

Arguments:
  project        Project name (allowing partial match)

Flags:
  -h, --help     Show this help message and exit
  -s, --save     Save current directory as project
  -d, --delete   Delete project with name
  -v, --view     View project in system file explorer
  -o, --open     Open project environment or IDE
  -e, --edit     Open project in $EDITOR
  --reset        Reset list of projects"
    );
}

fn print_projects(projects: &Projects, prompt: &str) {
    if prompt.is_empty() {
        let count = projects.len();
        let suffix = if count != 1 { "s" } else { "" };
        println!("{} project{} found\n", count, suffix);
    } else {
        println!("{}\n", prompt);
    }

    // Print two columns with project name on left in bold and path on right
    // Determine whitespace between columns using the maximum project length
    let padding = projects.keys().map(String::len).max().unwrap() + 2;
    let pairs = projects.iter().sorted();
    for (project, path) in pairs {
        println!(
            "\x1b[1m{: <width$}\x1b[0m{}",
            project,
            tilde_path(path),
            width = padding
        );
    }
}

/* User Input */

fn user_input(prompt: &str) -> String {
    print!("{}", prompt);
    let _ = stdout().flush(); // Explicit flush for line-buffered stdout

    let mut buffer = String::new();
    let _ = stdin().read_line(&mut buffer).expect("Read user input");

    buffer.trim_end().into()
}

fn user_confirms(prompt: String) -> bool {
    let prompt = format!("{} (y/N)? ", prompt);
    user_input(&prompt) == "y"
}

/* Files & Directories */

/// Open path using operating system
fn open_native(arg: &PathBuf) {
    let command = if cfg!(target_os = "macos") {
        "open"
    } else if cfg!(target_os = "linux") {
        "xdg-open"
    } else {
        eprintln!("Unsupported OS");
        exit(1);
    };

    let _ = std::process::Command::new(command).arg(arg).spawn();
}

/// Get path to data store in user's home directory
fn get_store_path() -> PathBuf {
    home_dir().unwrap().join(".fstore")
}

/// Return current directory
fn current_dir() -> PathBuf {
    env::current_dir().expect("Get current directory")
}

// Returns a path string replacing user's home directory with ~
fn tilde_path(path: &Path) -> String {
    let home = home_dir().unwrap_or_default().to_string_lossy().to_string();
    path.display().to_string().replacen(&home, "~", 1)
}

/// Get first file matching extension in directory
fn get_file_with_extension(ext: &str, dir: &PathBuf) -> Option<PathBuf> {
    let entries = fs::read_dir(dir).expect("Read directory");
    for entry in entries {
        let path = entry.unwrap().path();
        let extension = path.extension().unwrap_or_default();
        if ext == extension {
            return Some(path);
        }
    }

    None
}

/// Writes a shell command to temporary file to communicate with shell wrapper
fn send_to_shell(command: &str, path: &Path) {
    let contents = format!("{} '{}'", command, path.display());
    fs::write("/tmp/fast_cmd", contents).expect("Write to temporary file for shell");
}
