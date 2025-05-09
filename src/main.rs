use anyhow::{Context, Result, anyhow, bail};
use itertools::Itertools;
use std::env::home_dir;

use std::collections::{HashMap, HashSet};
use std::env::{self, current_dir, set_current_dir};
use std::fs;
use std::io::Write;
use std::io::{stdin, stdout};
use std::path::{Path, PathBuf};

enum Command {
    Load,
    Save,
    Delete,
    View,
    Open,
    Edit,
    Reset,
    Help,
}

type Projects = HashMap<String, PathBuf>;

const NO_PROJECTS_ERROR: &str = "No saved projects found";

/* Main */

fn main() -> Result<()> {
    let (command, query) = parse_args()?;
    let mut projects = read_projects()?;

    match command {
        Command::Load => load_project(&query, &projects),
        Command::Save => save_project(&query, &mut projects),
        Command::Delete => delete_project(&query, &mut projects),
        Command::View => view_project(&query, &projects),
        Command::Open => open_project(&query, &projects),
        Command::Edit => edit_project(&query, &projects),
        Command::Reset => reset_projects(&projects),
        Command::Help => {
            print_help();
            Ok(())
        }
    }
}

fn parse_args() -> Result<(Command, String)> {
    let args: Vec<String> = env::args().collect();

    if args.len() > 3 {
        bail!("Too many arguments provided");
    }

    let has_flag = args.len() > 1 && args[1].starts_with('-');
    let command = if has_flag {
        // Parse first argument as a flag, second argument as query
        match args[1].as_ref() {
            "-h" | "--help" => Command::Help,
            "-s" | "--save" => Command::Save,
            "-d" | "--delete" => Command::Delete,
            "-v" | "--view" => Command::View,
            "-o" | "--open" => Command::Open,
            "-e" | "--edit" => Command::Edit,
            "--reset" => Command::Reset,
            _ => {
                bail!("Unrecognized argument provided: {}", args[1]);
            }
        }
    } else {
        // Parse first argument as query
        Command::Load
    };

    // Query may or may not be provided
    let query_index = if has_flag { 2 } else { 1 };
    let query = args
        .get(query_index)
        .map_or_else(String::new, String::to_owned);

    Ok((command, query))
}

/* Store */

fn read_projects() -> Result<Projects> {
    let store = get_store_path()?;
    if !store.exists() {
        // Return empty map if file does not exist
        Ok(Projects::new())
    } else {
        let serialized = fs::read_to_string(store)?;
        serde_json::from_str(&serialized).context("Failed to read projects from disk")
    }
}

fn write_projects(projects: &Projects) -> Result<()> {
    let store = get_store_path()?;
    let serialized = serde_json::to_string(projects)?;
    fs::write(store, serialized).context("Failed to write projects to disk")
}

/* Commands */

fn load_project(query: &str, projects: &Projects) -> Result<()> {
    let (project, path) = select_project(query, projects, "Which project should be loaded?")?;

    if *path == current_dir()? {
        bail!("Already in project directory");
    }

    println!("Switching to \"{project}\"");
    send_to_shell("cd", path)?;
    Ok(())
}

fn save_project(query: &str, projects: &mut Projects) -> Result<()> {
    let project = if query.is_empty() {
        user_input("Enter new project name: ")?
    } else {
        query.to_string()
    };

    let message = format!("Project named \"{}\" already exists. Overwrite", project);
    if !projects.contains_key(&project) || user_confirms(message)? {
        println!("Saved project \"{project}\"");

        projects.insert(project, current_dir()?);
        write_projects(projects)
    } else {
        Ok(())
    }
}

fn delete_project(query: &str, projects: &mut Projects) -> Result<()> {
    let (project, _) = select_project(query, projects, "Which project should be deleted?")?;

    let message = format!("Delete \"{project}\"");
    if user_confirms(message)? {
        println!("Deleted project \"{project}\"");

        projects.remove(&project.clone());
        write_projects(projects)?
    }

    Ok(())
}

fn view_project(query: &str, projects: &Projects) -> Result<()> {
    let (project, path) = select_project(
        query,
        projects,
        "Which project should open in the file explorer?",
    )?;

    println!("Opening \"{project}\" in file explorer...");
    open_native(path)
}

fn open_project(query: &str, projects: &Projects) -> Result<()> {
    let (project, path) = select_project(query, projects, "Which project would you like to open?")?;
    let path = PathBuf::from(path);

    if path.join("start").is_file() {
        // Start script
        println!("Starting \"{project}\"...");
        set_current_dir(&path)?;

        std::process::Command::new("./start")
            .spawn()?
            .wait()
            .map(|_| ())
            .map_err(|e| anyhow!("Failed to execute start script: {}", e))
    } else if let Some(xcworkspace) = get_file_with_extension("xcworkspace", &path) {
        // Xcode workspace
        println!("Opening \"{project}\" in Xcode...");
        open_native(&xcworkspace)
    } else if let Some(xcodeproj) = get_file_with_extension("xcodeproj", &path) {
        // Xcode project
        println!("Opening \"{project}\" in Xcode...");
        open_native(&xcodeproj)
    } else {
        bail!(
            "No environment or system app to open for project: {}",
            project
        );
    }
}

fn edit_project(query: &str, projects: &Projects) -> Result<()> {
    let editor = env::var("EDITOR")
        .context("No editor configured. Please set the $EDITOR environment variable")?;

    let message = format!("Which project should be opened with {}?", editor);
    let (_, path) = select_project(query, projects, &message)?;

    send_to_shell(&editor, path)
}

fn reset_projects(projects: &Projects) -> Result<()> {
    if projects.is_empty() {
        bail!(NO_PROJECTS_ERROR);
    }

    let message = format!("Remove {} saved projects", projects.len());
    if user_confirms(message)? {
        let store = get_store_path()?;
        fs::remove_file(store)?;
        println!("Remove all saved projects");
    }

    Ok(())
}

/* Utilities */

type Selection<'a> = Result<(&'a String, &'a PathBuf)>;

/// Selects a project from projects based on query, requesting user for additional input if ambiguous
/// The lifetime of the returned (project, path) key-value pair is tied to the `projects` map it is retrieved from
fn select_project<'a>(query: &str, projects: &'a Projects, prompt: &str) -> Selection<'a> {
    // Helper method to request user for query
    fn query_user<'a>(projects: &'a Projects, prompt: &str) -> Selection<'a> {
        print_projects(projects, prompt)?;
        let input = user_input("\nEnter project: ")?;
        select_project(&input, projects, prompt)
    }

    if projects.is_empty() {
        bail!(NO_PROJECTS_ERROR);
    }

    // Query user if none provided
    if query.is_empty() {
        return query_user(projects, prompt);
    }

    // Return exact match if found
    if let Some((project, path)) = projects.get_key_value(query) {
        return Ok((project, path));
    }

    // Filter project keys containing substring
    let matches: HashSet<_> = projects
        .keys()
        .filter(|project| project.contains(query))
        .collect();

    match matches.len() {
        0 => {
            bail!("No matching project found");
        }
        1 => {
            // Retrieve first (and only) project in matches and corresponding path
            let project = *matches.iter().next().unwrap();
            let path = projects.get(project).unwrap();

            Ok((project, path))
        }
        _ => {
            // Clone projects and disambiguate from matches
            let mut subset = projects.clone();
            subset.retain(|key, _| matches.contains(key));
            let (key, _) = query_user(&subset, "")?;

            // Return original key-value pair
            Ok(projects.get_key_value(key).unwrap())
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

fn print_projects(projects: &Projects, prompt: &str) -> Result<()> {
    if prompt.is_empty() {
        let count = projects.len();
        let suffix = if count != 1 { "s" } else { "" };
        println!("{count} project{suffix} found\n");
    } else {
        println!("{prompt}\n");
    }

    // Print two columns with project name on left in bold and path on right
    // Determine whitespace between columns using the maximum project length
    let padding = projects.keys().map(String::len).max().unwrap() + 2;
    let pairs = projects.iter().sorted();
    for (project, path) in pairs {
        println!(
            "\x1b[1m{: <width$}\x1b[0m{}",
            project,
            tilde_path(path)?,
            width = padding
        );
    }

    Ok(())
}

/* User Input */

fn user_input(prompt: &str) -> Result<String> {
    print!("{prompt}");
    stdout().flush()?; // Explicit flush for line-buffered stdout

    let mut buffer = String::new();
    stdin().read_line(&mut buffer)?;

    Ok(buffer.trim_end().into())
}

fn user_confirms(prompt: String) -> Result<bool> {
    let prompt = format!("{} (y/N)? ", prompt);
    Ok(user_input(&prompt)? == "y")
}

/* Files & Directories */

/// Open path using operating system
fn open_native(arg: &PathBuf) -> Result<()> {
    let command = if cfg!(target_os = "macos") {
        "open"
    } else if cfg!(target_os = "linux") {
        "xdg-open"
    } else {
        bail!("Unsupported OS");
    };

    std::process::Command::new(command).arg(arg).spawn()?;
    Ok(())
}

/// Get path to data store in user's home directory
fn get_store_path() -> Result<PathBuf> {
    let home = home_dir().context("Failed to retrieve data store path")?;
    Ok(home.join(".fstore"))
}

/// Returns a path string replacing user's home directory with ~
fn tilde_path(path: &Path) -> Result<String> {
    let home = home_dir()
        .context("Failed to retrieve home directory")?
        .to_string_lossy()
        .to_string();

    Ok(path.display().to_string().replacen(&home, "~", 1))
}

/// Get first file matching extension in directory
fn get_file_with_extension(ext: &str, dir: &Path) -> Option<PathBuf> {
    let entries = fs::read_dir(dir).ok()?;
    for entry in entries {
        let path = entry.ok()?.path();
        if let Some(extension) = path.extension() {
            if ext == extension {
                return Some(path);
            }
        }
    }

    None
}

/// Writes a shell command to temporary file to communicate with shell wrapper
fn send_to_shell(command: &str, path: &Path) -> Result<()> {
    let contents = format!("{} '{}'", command, path.display());
    fs::write("/tmp/fast_cmd", contents).context("Failed to communicate with shell")
}
