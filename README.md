# fast

A minimal command-line tool for quickly opening and interacting with projects.

## Installation

**fast** requires an [Odin](https://odin-lang.org/) installation in order to build.

1. Run `make release` in the project directory.
2. Move or link the binary to make it available from your `$PATH` (e.g., `/usr/local/bin`).
3. Configure the wrapper shell script:
    - `fish`: Move or link `f.fish` to `~/.config/fish/functions`

## Usage

Save the current directory as a project (**fast** data is stored at `~/.fstore`):

```
$ f -s project1
```

Switch to a saved project directory from anywhere:

```
$ f project1
```

Enter a substring and **fast** will prompt to disambiguate as needed:

```
$ f -s project2
Saved project "project2"

$ f proj
Which project should be loaded?

project1  /Users/me/Documents/MyApp
project2  /Users/me/Developer/secret_project

Enter project: 2
Switching to "project2"
```
